import SwiftUI
import UIKit

/// Stores card photos as files (they are too big for the card database, which only
/// keeps each photo's position and file name) and caches decoded images.
enum ImageStore {
    private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 60
        return c
    }()

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
        try? Data(contentsOf: directory.appendingPathComponent(file))
    }

    /// Writes a photo file under a known name (for restoring backups). Existing files are kept.
    static func write(_ data: Data, as file: String) {
        let url = directory.appendingPathComponent(file)
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        try? data.write(to: url)
    }

    static func delete(_ names: [String]) {
        for name in names {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
            cache.removeObject(forKey: name as NSString)
        }
    }

    static func image(_ file: String) -> UIImage? {
        if let hit = cache.object(forKey: file as NSString) { return hit }
        guard let image = UIImage(contentsOfFile: directory.appendingPathComponent(file).path) else { return nil }
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
                    .offset(x: item.x * card.width, y: item.y * card.height)
            }
        }
        .frame(width: card.width, height: card.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}

/// Photos that track the canvas's zoom and pan.
struct ZoomingImages: View {
    @ObservedObject var viewport: Viewport
    let items: [ImageItem]
    let card: CGSize

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(items) { PlacedImage(item: $0, card: card) }
        }
        .frame(width: card.width, height: card.height, alignment: .topLeading)
        .scaleEffect(viewport.zoom, anchor: .topLeading)
        .offset(x: -viewport.offset.x, y: -viewport.offset.y)
    }
}

/// A selected photo with handles: top-left moves it, bottom-right scales it (keeping its
/// proportions), top-right deletes it.
struct ImageBoxEditor: View {
    @Binding var item: ImageItem
    let card: CGSize
    var onDelete: () -> Void
    /// Updated every frame by gestures; written back only when a gesture ends.
    @State private var draft: ImageItem
    @State private var start: ImageItem?

    init(item: Binding<ImageItem>, card: CGSize, onDelete: @escaping () -> Void) {
        _item = item
        _draft = State(initialValue: item.wrappedValue)
        self.card = card
        self.onDelete = onDelete
    }

    var body: some View {
        let width = draft.w * card.width
        let height = width * draft.aspect

        PlacedImage(item: draft, card: card)
            .overlay(alignment: .topLeading) {
                Color.clear
                    .frame(width: width, height: height)
                    .overlay(RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
                    .overlay(alignment: .topLeading) {
                        handle("arrow.up.and.down.and.arrow.left.and.right", .accentColor)
                            .offset(x: -18, y: -18).gesture(move)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        handle("arrow.up.left.and.arrow.down.right", .accentColor)
                            .offset(x: 18, y: 18).gesture(resize)
                    }
                    .overlay(alignment: .topTrailing) {
                        handle("trash", .red).offset(x: 18, y: -18).onTapGesture { onDelete() }
                    }
                    .offset(x: draft.x * card.width, y: draft.y * card.height)
            }
            .allowsHitTesting(true)
    }

    private func handle(_ icon: String, _ color: Color) -> some View {
        Image(systemName: icon)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 36, height: 36)
            .background(Circle().fill(color))
            .contentShape(Circle())
    }

    // Screen coordinates: the handles move with the photo, so measuring in their own
    // space would make the drag feed back on itself.
    private var move: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { drag in
                let origin = start ?? draft
                start = origin
                var b = origin
                let height = origin.w * origin.aspect * card.width / card.height
                b.x = min(max(origin.x + drag.translation.width / card.width, 0), max(0, 1 - origin.w))
                b.y = min(max(origin.y + drag.translation.height / card.height, 0), max(0, 1 - height))
                draft = b
            }
            .onEnded { _ in commit() }
    }

    private var resize: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { drag in
                let origin = start ?? draft
                start = origin
                var b = origin
                let maxW = min(1 - origin.x, (1 - origin.y) * card.height / (origin.aspect * card.width))
                b.w = min(max(origin.w + drag.translation.width / card.width, 0.08), max(0.08, maxW))
                draft = b
            }
            .onEnded { _ in commit() }
    }

    private func commit() {
        start = nil
        if item != draft { item = draft }
    }
}
