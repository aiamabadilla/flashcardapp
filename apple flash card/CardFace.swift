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
                    Text(text)
                        .font(.system(size: geo.size.width * 0.03))
                        .padding(geo.size.width * 0.025)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
    let fontSize: CGFloat
    let padding: CGFloat

    var body: some View {
        Text(text)
            .font(.system(size: fontSize))
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .scaleEffect(viewport.zoom, anchor: .topLeading)
            .offset(x: -viewport.offset.x, y: -viewport.offset.y)
            .allowsHitTesting(false)
    }
}
