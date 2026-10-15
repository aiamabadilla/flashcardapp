import SwiftUI
import Combine
import UIKit

/// Stores card photos as files (they are too big for the card database, which only
/// keeps each photo's position and file name) and caches decoded images.
enum ImageStore {
    private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 60
        return c
    }()

    /// Photo files are named `<UUID>.jpg`. Names that arrive from outside (backups) must look
    /// like a plain file name, so they can never point outside the photo folder.
    static func isSafeName(_ name: String) -> Bool {
        func isASCIIAlphanumeric(_ u: Unicode.Scalar) -> Bool {
            (u >= "a" && u <= "z") || (u >= "A" && u <= "Z") || (u >= "0" && u <= "9")
        }
        let scalars = Array(name.unicodeScalars)
        guard !scalars.isEmpty, scalars.count <= 128, isASCIIAlphanumeric(scalars[0]) else { return false }
        return scalars.allSatisfy { isASCIIAlphanumeric($0) || $0 == "." || $0 == "-" || $0 == "_" }
            && !name.contains("..")
    }

    /// The photo folder (exposed for tests).
    static var storageDirectory: URL { directory }

    private static func url(for name: String) -> URL? {
        isSafeName(name) ? directory.appendingPathComponent(name) : nil
    }

    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("CardImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Downsizes (longest side 1600 px) and saves as JPEG. Returns the file name and
    /// the image's height/width ratio.
    static func save(_ image: UIImage) -> (file: String, aspect: Double)? {
        let longest = max(image.size.width, image.size.height)
        let scale = min(1, 1600 / max(longest, 1))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let data = resized.jpegData(compressionQuality: 0.85) else { return nil }
        let name = UUID().uuidString + ".jpg"
        do { try data.write(to: directory.appendingPathComponent(name)) } catch { return nil }
        cache.setObject(resized, forKey: name as NSString)
        return (name, Double(size.height / max(size.width, 1)))
    }

    /// Every stored photo file with its size in bytes.
    static func storedFiles() -> [(name: String, bytes: Int)] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return urls.map { url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            return (url.lastPathComponent, size)
        }
    }

    /// Raw bytes of a stored photo (for backups).
    static func fileData(_ file: String) -> Data? {
        guard let url = url(for: file) else { return nil }
        return try? Data(contentsOf: url)
    }

    /// Writes a photo file under a known name (for restoring backups). Existing files are kept.
    static func write(_ data: Data, as file: String) {
        guard let url = url(for: file),
              !FileManager.default.fileExists(atPath: url.path) else { return }
        try? data.write(to: url)
    }

    static func delete(_ names: [String]) {
        for name in names {
            guard let url = url(for: name) else { continue }
            try? FileManager.default.removeItem(at: url)
            cache.removeObject(forKey: name as NSString)
        }
    }

    static func image(_ file: String) -> UIImage? {
        if let hit = cache.object(forKey: file as NSString) { return hit }
        guard let url = url(for: file),
              let image = UIImage(contentsOfFile: url.path) else { return nil }
        cache.setObject(image, forKey: file as NSString)
        return image
    }
}

/// A photo placed on the card by its fractional position.
struct PlacedImage: View {
    let item: ImageItem
    let card: CGSize

    var body: some View {
        let width = item.w * card.width
        ZStack(alignment: .topLeading) {
            if let image = ImageStore.image(item.file) {
                Image(uiImage: image)
                    .resizable()
                    .frame(width: width, height: width * item.aspect)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .opacity(item.opacity ?? 1)
                    .offset(x: item.x * card.width, y: item.y * card.height)
            }
        }
        .frame(width: card.width, height: card.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}

/// All of a side's photos, back to front, tracking the canvas's zoom and pan. The photo being
/// edited is drawn from its draft (so moves and opacity show live) at its own place in the stack.
struct ZoomingImages: View {
    @ObservedObject var viewport: Viewport
    @ObservedObject var draft: ImageDraft
    let items: [ImageItem]
    let selectedID: UUID?
    let card: CGSize

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(items) { saved in
                PlacedImage(item: saved.id == selectedID ? (draft.item ?? saved) : saved, card: card)
            }
        }
        .frame(width: card.width, height: card.height, alignment: .topLeading)
        .scaleEffect(viewport.zoom, anchor: .topLeading)
        .offset(x: -viewport.offset.x, y: -viewport.offset.y)
    }
}

/// The photo being edited. Shared by the picture layer (drawn under the ink and text) and the
/// handles layer (drawn on top), so gestures update both without touching the saved card.
@MainActor final class ImageDraft: ObservableObject {
    @Published var item: ImageItem?
    var start: ImageItem?
}

/// A selected photo, in two parts: the picture sits under the writing and text so they stay
/// visible (and can be lined up with it), the handles sit on top. Top-left moves, bottom-right
/// scales (keeping proportions), top-right deletes.
struct ImageBoxEditor: View {
    enum Part { case picture, handles }

    @ObservedObject var draft: ImageDraft
    let part: Part
    let card: CGSize
    var onCommit: (ImageItem) -> Void = { _ in }
    var onDelete: () -> Void = {}

    var body: some View {
        if let item = draft.item {
            switch part {
            case .picture:
                EmptyView()
            case .handles:
                let width = item.w * card.width
                let height = width * item.aspect
                Color.clear
                    .frame(width: width, height: height)
                    .overlay(RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
                    .overlay(alignment: .topLeading) {
                        handle("arrow.up.and.down.and.arrow.left.and.right", .accentColor)
                            .offset(x: -HandleStyle.inset, y: -HandleStyle.inset).gesture(move)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        handle("arrow.up.left.and.arrow.down.right", .accentColor)
                            .offset(x: HandleStyle.inset, y: HandleStyle.inset).gesture(resize)
                    }
                    .overlay(alignment: .topTrailing) {
                        handle("trash", .red).offset(x: HandleStyle.inset, y: -HandleStyle.inset).onTapGesture { onDelete() }
                    }
                    .offset(x: item.x * card.width, y: item.y * card.height)
                    .frame(width: card.width, height: card.height, alignment: .topLeading)
            }
        }
    }

    private func handle(_ icon: String, _ color: Color) -> some View {
        Image(systemName: icon)
            .font(.system(size: HandleStyle.icon, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: HandleStyle.size, height: HandleStyle.size)
            .background(Circle().fill(color))
            .contentShape(Circle())
            .accessibilityLabel(Self.handleName(icon))
    }

    private static func handleName(_ icon: String) -> String {
        if icon.contains("trash") { return "Delete" }
        if icon.contains("move") || icon.hasPrefix("arrow.up.and.down") || icon.contains("hand") { return "Move" }
        if icon.contains("resize") || icon.contains("arrow.up.left.and.arrow.down.right") || icon.contains("diagonal") { return "Resize" }
        if icon.contains("checkmark") { return "Done" }
        return "Edit handle"
    }

    // Screen coordinates: the handles move with the photo, so measuring in their own
    // space would make the drag feed back on itself.
    private var move: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { drag in
                guard let current = draft.item else { return }
                let origin = draft.start ?? current
                draft.start = origin
                var b = origin
                let height = origin.w * origin.aspect * card.width / card.height
                b.x = min(max(origin.x + drag.translation.width / card.width, 0), max(0, 1 - origin.w))
                b.y = min(max(origin.y + drag.translation.height / card.height, 0), max(0, 1 - height))
                draft.item = b
            }
            .onEnded { _ in finish() }
    }

    private var resize: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { drag in
                guard let current = draft.item else { return }
                let origin = draft.start ?? current
                draft.start = origin
                var b = origin
                let maxW = min(1 - origin.x, (1 - origin.y) * card.height / (origin.aspect * card.width))
                b.w = min(max(origin.w + drag.translation.width / card.width, 0.08), max(0.08, maxW))
                draft.item = b
            }
            .onEnded { _ in finish() }
    }

    private func finish() {
        draft.start = nil
        if let item = draft.item { onCommit(item) }
    }
}

/// The opacity slider for the selected photo. Observes the draft itself so the percentage and
/// the slider stay current without redrawing the whole editor.
struct PhotoOpacityRow: View {
    @ObservedObject var draft: ImageDraft
    let card: Card

    var body: some View {
        let value = draft.item?.opacity ?? 1
        HStack(spacing: 14) {
            Image(systemName: "circle.lefthalf.filled").foregroundStyle(.secondary)
            Slider(value: Binding(
                get: { value },
                set: { new in
                    guard var item = draft.item else { return }
                    item.opacity = new
                    draft.item = item
                    card.updateImageItem(item)
                }), in: 0.1...1)
            Text("\(Int((value * 100).rounded()))%")
                .monospacedDigit().foregroundStyle(.secondary).frame(width: 52, alignment: .trailing)
        }
    }
}
