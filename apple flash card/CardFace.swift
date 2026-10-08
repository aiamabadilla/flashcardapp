import SwiftUI
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

struct CardLines: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Canvas { ctx, size in
            // Spacing scales with the card so thumbnails match the editor.
            let spacing = size.height * 32 / 570
            let margin = size.width * 0.017
            var y = spacing * 1.25
            while y < size.height {
                var line = Path()
                line.move(to: CGPoint(x: margin, y: y))
                line.addLine(to: CGPoint(x: size.width - margin, y: y))
                ctx.stroke(line, with: .color(.blue.opacity(scheme == .dark ? 0.3 : 0.18)), lineWidth: 1)
                y += spacing
            }
        }
        .allowsHitTesting(false)
    }
}
