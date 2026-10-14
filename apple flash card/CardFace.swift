import SwiftUI
import Combine
import PencilKit

/// Renders saved PKDrawings to images. Rendering is slow, so results are cached
/// (keyed by the drawing's bytes and the interface style).
enum InkRenderer {
    private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 200
        return c
    }()

    /// The ink as an image. With a reference width it covers the whole card area (so ink is at
    /// its true position and size); without one it is cropped to the ink and fitted.
    static func image(_ data: Data, dark: Bool, refWidth: Double = 0, scale: CGFloat = 2) -> UIImage? {
        guard !data.isEmpty else { return nil }
        let key = "\(data.count)-\(data.hashValue)-\(dark)-\(refWidth)-\(scale)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let drawing = try? PKDrawing(data: data), !drawing.bounds.isEmpty else { return nil }
        let rect = refWidth > 0
            ? CGRect(x: 0, y: 0, width: refWidth, height: refWidth * 3 / 5)
            : drawing.bounds
        var image: UIImage?
        UITraitCollection(userInterfaceStyle: dark ? .dark : .light).performAsCurrent {
            image = drawing.image(from: rect, scale: scale)
        }
        if let image { cache.setObject(image, forKey: key) }
        return image
    }
}

struct DrawingImage: View {
    let data: Data
    var refWidth: Double = 0
    var padding: CGFloat = 12
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        // Scale so the small previews stay sharp: about 1000 px across the card.
        let scale = refWidth > 0 ? max(1, min(1000 / refWidth, 3)) : 2
        if let image = InkRenderer.image(data, dark: scheme == .dark, refWidth: refWidth, scale: scale) {
            if refWidth > 0 {
                // Covers the face exactly, so ink lines up with photos and text.
                Image(uiImage: image).resizable()
            } else {
                Image(uiImage: image).resizable().scaledToFit().padding(padding)
            }
        }
    }
}

/// A text box placed on the card by its fractional position. The padding mirrors
/// TextEditor's own insets so text doesn't jump when leaving edit mode.
struct PlacedText: View {
    let item: TextItem
    let card: CGSize
    var onTap: (() -> Void)? = nil

    var body: some View {
        ZStack(alignment: .topLeading) {
            Text(item.text)
                .font(.system(size: item.size * card.width))
                .padding(.horizontal, 5).padding(.vertical, 8)
                .frame(width: item.w * card.width, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { onTap?() }
                .offset(x: item.x * card.width, y: item.y * card.height)
        }
        .frame(width: card.width, height: card.height, alignment: .topLeading)
        .allowsHitTesting(onTap != nil)
    }
}

/// Read-only view of one side of a card: paper, optional lines, typed text, ink.
struct CardFace: View {
    let card: Card
    let side: Side
    var corner: CGFloat = 14
    var inset: CGFloat = 12
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: corner).fill(Color.paper(scheme))
                if card.isLined(side) { CardLines() }
                ForEach(card.imageItems(side)) { PlacedImage(item: $0, card: geo.size) }
                ForEach(card.textItems(side)) { PlacedText(item: $0, card: geo.size) }
                DrawingImage(data: card.drawing(side), refWidth: card.inkRefWidth > 0 ? card.inkRefWidth : Card.lastKnownCardWidth, padding: inset)
            }
        }
        .aspectRatio(5.0 / 3.0, contentMode: .fit)
    }
}

/// Shared zoom/pan state of the drawing canvas, so the lines and typed text can follow it.
@MainActor final class Viewport: ObservableObject {
    @Published var zoom: CGFloat = 1
    @Published var offset: CGPoint = .zero
    weak var scrollView: UIScrollView?
    /// How much the canvas is scaled to fit the card (card width / canvas's own width). Pan
    /// offsets and taps are reported in canvas units; this converts them to card points.
    var displayScale: CGFloat = 1

    /// Back to 1x without animation (used before positioning the text box).
    func resetCanvasZoom() {
        scrollView?.setZoomScale(1, animated: false)
        scrollView?.setContentOffset(.zero, animated: false)
        reset()
    }

    func reset() {
        if zoom != 1 { zoom = 1 }
        if offset != .zero { offset = .zero }
    }
}

struct CardLines: View {
    var zoom: CGFloat = 1
    var offset: CGPoint = .zero
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Canvas { ctx, size in
            // Spacing scales with the card so thumbnails match the editor, and with
            // the zoom so the lines stay aligned with zoomed-in handwriting.
            let spacing = size.height * 32 / 570
            let margin = size.width * 0.017
            let x1 = margin * zoom - offset.x
            let x2 = (size.width - margin) * zoom - offset.x
            let color = Color.blue.opacity(scheme == .dark ? 0.3 : 0.18)
            var i = 0
            while true {
                let y = (spacing * 1.25 + CGFloat(i) * spacing) * zoom - offset.y
                if y > size.height { break }
                if y >= 0 {
                    var line = Path()
                    line.move(to: CGPoint(x: x1, y: y))
                    line.addLine(to: CGPoint(x: x2, y: y))
                    ctx.stroke(line, with: .color(color), lineWidth: 1)
                }
                i += 1
            }
        }
        .allowsHitTesting(false)
    }
}

/// Lines that track the canvas's zoom and pan. Observes the viewport itself so only
/// this small view redraws while pinching, not the whole editor.
struct ZoomingLines: View {
    @ObservedObject var viewport: Viewport
    var body: some View { CardLines(zoom: viewport.zoom, offset: viewport.offset) }
}

/// Typed text boxes that track the canvas's zoom and pan. Tapping one selects it.
struct ZoomingTexts: View {
    @ObservedObject var viewport: Viewport
    let items: [TextItem]
    let card: CGSize
    let onTap: (UUID) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(items) { item in
                PlacedText(item: item, card: card) { onTap(item.id) }
            }
        }
        .frame(width: card.width, height: card.height, alignment: .topLeading)
        .scaleEffect(viewport.zoom, anchor: .topLeading)
        .offset(x: -viewport.offset.x, y: -viewport.offset.y)
    }
}

/// Editable text box. Drag the top-left handle to move it, the bottom-right handle to
/// scale it (width and font size together), the top-right button to delete it.
struct TextBoxEditor: View {
    @Binding var item: TextItem
    let card: CGSize
    var focus: FocusState<Bool>.Binding
    var onDelete: () -> Void
    /// Local copy that gestures update every frame; it's written back to the card
    /// only when a gesture ends. Saving on every touch movement made dragging stutter.
    @State private var draft: TextItem
    @State private var start: TextItem?

    init(item: Binding<TextItem>, card: CGSize, focus: FocusState<Bool>.Binding,
         onDelete: @escaping () -> Void) {
        _item = item
        _draft = State(initialValue: item.wrappedValue)
        self.card = card
        self.focus = focus
        self.onDelete = onDelete
    }

    var body: some View {
        let fontSize = draft.size * card.width
        let width = draft.w * card.width

        // The hidden Text sizes the box to its content; the editor is overlaid on it.
        Text(draft.text + " ")
            .font(.system(size: fontSize))
            .padding(.horizontal, 5).padding(.vertical, 8)
            .frame(width: width, alignment: .leading)
            .frame(minHeight: fontSize * 2.2, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
            .opacity(0)
            .overlay {
                TextEditor(text: $draft.text)
                    .font(.system(size: fontSize))
                    .scrollContentBackground(.hidden)
                    .focused(focus)
            }
            .overlay(RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
            .overlay(alignment: .topLeading) {
                handle("arrow.up.and.down.and.arrow.left.and.right", .accentColor)
                    .offset(x: -18, y: -18)
                    .gesture(move)
            }
            .overlay(alignment: .bottomTrailing) {
                handle("arrow.up.left.and.arrow.down.right", .accentColor)
                    .offset(x: 18, y: 18)
                    .gesture(resize)
            }
            .overlay(alignment: .topTrailing) {
                handle("trash", .red)
                    .offset(x: 18, y: -18)
                    .onTapGesture { onDelete() }
            }
            .offset(x: draft.x * card.width, y: draft.y * card.height)
            .frame(width: card.width, height: card.height, alignment: .topLeading)
            .onAppear { focus.wrappedValue = true }
            // Typing is saved as it happens...
            .onChange(of: draft.text) {
                if item.text != draft.text {
                    var saved = item
                    saved.text = draft.text
                    item = saved
                }
            }
            // ...and changes made elsewhere (A-/A+) flow back in, except mid-gesture.
            .onChange(of: item) {
                if start == nil, draft != item { draft = item }
            }
    }

    private func handle(_ icon: String, _ color: Color) -> some View {
        Image(systemName: icon)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 36, height: 36)
            .background(Circle().fill(color))
            .contentShape(Circle())
    }

    // Gestures use screen coordinates: the handles move with the box, so measuring in
    // their own coordinate space made the drag feed back on itself and jitter.
    private var move: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { drag in
                let origin = start ?? draft
                start = origin
                var b = origin
                b.x = min(max(origin.x + drag.translation.width / card.width, 0), max(0, 1 - origin.w))
                b.y = min(max(origin.y + drag.translation.height / card.height, 0), 0.92)
                draft = b
            }
            .onEnded { _ in commit() }
    }

    private var resize: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { drag in
                let origin = start ?? draft
                start = origin
                let startWidth = origin.w * card.width
                let newW = min(max((startWidth + drag.translation.width) / card.width, 0.1),
                               max(0.1, 1 - origin.x))
                var b = origin
                b.w = newW
                b.size = origin.size * (newW / origin.w)
                draft = b
            }
            .onEnded { _ in commit() }
    }

    private func commit() {
        start = nil
        if item != draft { item = draft }
    }
}

/// A box around everything drawn on a side, with handles to move or scale it, like a photo.
/// Top-left handle moves, bottom-right scales (keeping proportions). The ink itself is
/// transformed once, when editing finishes; until then the box only previews the change.
struct InkBoxEditor: View {
    /// The ink's bounds in card coordinates, as they were when editing began.
    let bounds: CGRect
    let card: CGSize
    @Binding var scale: CGFloat
    @Binding var offset: CGSize
    @State private var startScale: CGFloat?
    @State private var startOffset: CGSize?

    var body: some View {
        let w = bounds.width * scale
        let h = bounds.height * scale

        Color.clear
            .frame(width: w, height: h)
            .overlay(RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
            .overlay(alignment: .topLeading) {
                handle("arrow.up.and.down.and.arrow.left.and.right").offset(x: -18, y: -18).gesture(move)
            }
            .overlay(alignment: .bottomTrailing) {
                handle("arrow.up.left.and.arrow.down.right").offset(x: 18, y: 18).gesture(resize)
            }
            .offset(x: bounds.minX + offset.width, y: bounds.minY + offset.height)
            .frame(width: card.width, height: card.height, alignment: .topLeading)
    }

    private func handle(_ icon: String) -> some View {
        Image(systemName: icon)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 36, height: 36)
            .background(Circle().fill(Color.accentColor))
            .contentShape(Circle())
    }

    // Screen coordinates, as for photos: the handles move with the box.
    private var move: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { drag in
                let origin = startOffset ?? offset
                startOffset = origin
                offset = CGSize(width: origin.width + drag.translation.width,
                                height: origin.height + drag.translation.height)
            }
            .onEnded { _ in startOffset = nil }
    }

    private var resize: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { drag in
                let origin = startScale ?? scale
                startScale = origin
                let width = bounds.width * origin + drag.translation.width
                scale = min(max(width / max(bounds.width, 1), 0.15), 6)
            }
            .onEnded { _ in startScale = nil }
    }
}
