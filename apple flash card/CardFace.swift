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

    static func image(_ data: Data, dark: Bool, scale: CGFloat = 2) -> UIImage? {
        guard !data.isEmpty else { return nil }
        let key = "\(data.count)-\(data.hashValue)-\(dark)-\(scale)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let drawing = try? PKDrawing(data: data), !drawing.bounds.isEmpty else { return nil }
        var image: UIImage?
        UITraitCollection(userInterfaceStyle: dark ? .dark : .light).performAsCurrent {
            image = drawing.image(from: drawing.bounds, scale: scale)
        }
        if let image { cache.setObject(image, forKey: key) }
        return image
    }
}

struct DrawingImage: View {
    let data: Data
    var padding: CGFloat = 12
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if let image = InkRenderer.image(data, dark: scheme == .dark) {
            Image(uiImage: image).resizable().scaledToFit().padding(padding)
        }
    }
}

/// Typed text positioned by its TextBox. The padding mirrors TextEditor's own insets
/// so text doesn't jump when leaving edit mode.
struct PlacedText: View {
    let text: String
    let box: TextBox
    let card: CGSize

    var body: some View {
        ZStack(alignment: .topLeading) {
            Text(text)
                .font(.system(size: box.size * card.width))
                .padding(.horizontal, 5).padding(.vertical, 8)
                .frame(width: box.w * card.width, alignment: .leading)
                .offset(x: box.x * card.width, y: box.y * card.height)
        }
        .frame(width: card.width, height: card.height, alignment: .topLeading)
        .allowsHitTesting(false)
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
        let text = card.text(side)
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: corner).fill(Color.paper(scheme))
                if card.isLined(side) { CardLines() }
                if !text.isEmpty {
                    PlacedText(text: text, box: card.box(side), card: geo.size)
                }
                DrawingImage(data: card.drawing(side), padding: inset)
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

/// Typed text that tracks the canvas's zoom and pan.
struct ZoomingText: View {
    @ObservedObject var viewport: Viewport
    let text: String
    let box: TextBox
    let card: CGSize

    var body: some View {
        PlacedText(text: text, box: box, card: card)
            .scaleEffect(viewport.zoom, anchor: .topLeading)
            .offset(x: -viewport.offset.x, y: -viewport.offset.y)
    }
}

/// Editable, movable, scalable text box. Drag the top-left handle to move it, the
/// bottom-right handle to scale it (box width and font size together).
struct TextBoxEditor: View {
    @Binding var text: String
    @Binding var box: TextBox
    let card: CGSize
    var focus: FocusState<Bool>.Binding
    @State private var start: TextBox?

    var body: some View {
        let fontSize = box.size * card.width
        let width = box.w * card.width

        // The hidden Text sizes the box to its content; the editor is overlaid on it.
        Text(text + " ")
            .font(.system(size: fontSize))
            .padding(.horizontal, 5).padding(.vertical, 8)
            .frame(width: width, alignment: .leading)
            .frame(minHeight: fontSize * 2.2, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
            .opacity(0)
            .overlay {
                TextEditor(text: $text)
                    .font(.system(size: fontSize))
                    .scrollContentBackground(.hidden)
                    .focused(focus)
            }
        .overlay(RoundedRectangle(cornerRadius: 6)
            .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
        .overlay(alignment: .topLeading) {
            handle("arrow.up.and.down.and.arrow.left.and.right")
                .offset(x: -18, y: -18)
                .gesture(move)
        }
        .overlay(alignment: .bottomTrailing) {
            handle("arrow.up.left.and.arrow.down.right")
                .offset(x: 18, y: 18)
                .gesture(resize)
        }
        .offset(x: box.x * card.width, y: box.y * card.height)
        .frame(width: card.width, height: card.height, alignment: .topLeading)
        .onAppear { focus.wrappedValue = true }
    }

    private func handle(_ icon: String) -> some View {
        Image(systemName: icon)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 36, height: 36)
            .background(Circle().fill(Color.accentColor))
            .contentShape(Circle())
    }

    private var move: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { drag in
                let origin = start ?? box
                start = origin
                var b = origin
                b.x = min(max(origin.x + drag.translation.width / card.width, 0), max(0, 1 - origin.w))
                b.y = min(max(origin.y + drag.translation.height / card.height, 0), 0.92)
                box = b
            }
            .onEnded { _ in start = nil }
    }

    private var resize: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { drag in
                let origin = start ?? box
                start = origin
                let startWidth = origin.w * card.width
                let newW = min(max((startWidth + drag.translation.width) / card.width, 0.1),
                               max(0.1, 1 - origin.x))
                var b = origin
                b.w = newW
                b.size = origin.size * (newW / origin.w)
                box = b
            }
            .onEnded { _ in start = nil }
    }
}
