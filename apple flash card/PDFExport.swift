import UIKit

/// Prints a deck as a PDF: US Letter pages of 2 × 4 cards. Fronts and backs alternate by page,
/// with the back page's columns mirrored so a double-sided print lines each back up behind its
/// front. Always drawn on white paper in light colours, whatever the app's appearance.
enum PDFExport {
    static let page = CGSize(width: 612, height: 792)
    static let columns = 2
    static let rows = 4
    static let margin: CGFloat = 36
    static let gap: CGFloat = 12

    static var cardSize: CGSize {
        let w = (page.width - margin * 2 - gap * CGFloat(columns - 1)) / CGFloat(columns)
        return CGSize(width: w, height: w * 3 / 5)
    }

    static func export(_ deck: Deck) throws -> URL {
        let cards = deck.sortedCards
        let name = deck.title.isEmpty ? "Deck" : deck.title
        let safe = name.map { $0.isLetter || $0.isNumber || $0 == " " ? $0 : "-" }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(String(safe).trimmingCharacters(in: .whitespaces) + ".pdf")
        try? FileManager.default.removeItem(at: url)

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: page),
                                             format: pdfFormat(title: name))
        let perPage = columns * rows
        try renderer.writePDF(to: url) { context in
            if cards.isEmpty {
                context.beginPage()
                draw("This deck has no cards.", in: CGRect(origin: .zero, size: page))
            }
            for start in stride(from: 0, to: cards.count, by: perPage) {
                let group = Array(cards[start..<min(start + perPage, cards.count)])
                for side in [Side.front, .back] {
                    context.beginPage()
                    for (i, card) in group.enumerated() {
                        drawCard(card, side: side, in: frame(slot: i, mirrored: side == .back))
                    }
                }
            }
        }
        return url
    }

    private static func pdfFormat(title: String) -> UIGraphicsPDFRendererFormat {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextTitle as String: title, kCGPDFContextCreator as String: "IMSTUDY"]
        return format
    }

    static func frame(slot: Int, mirrored: Bool) -> CGRect {
        let size = cardSize
        var column = slot % columns
        if mirrored { column = columns - 1 - column }
        let row = slot / columns
        let totalH = size.height * CGFloat(rows) + gap * CGFloat(rows - 1)
        let top = (page.height - totalH) / 2
        return CGRect(x: margin + CGFloat(column) * (size.width + gap),
                      y: top + CGFloat(row) * (size.height + gap),
                      width: size.width, height: size.height)
    }

    private static func draw(_ text: String, in rect: CGRect) {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        (text as NSString).draw(in: rect.insetBy(dx: 0, dy: rect.height / 2 - 10),
                                withAttributes: [.font: UIFont.systemFont(ofSize: 14),
                                                 .foregroundColor: UIColor.gray, .paragraphStyle: style])
    }

    /// One side of a card at `rect`, in the same stacking order as the app:
    /// paper, lines, photos (back to front), ink, then typed text.
    static func drawCard(_ card: Card, side: Side, in rect: CGRect) {
        guard let cg = UIGraphicsGetCurrentContext() else { return }
        let w = rect.width, h = rect.height
        let corner = w * 0.025

        cg.saveGState()
        let shape = UIBezierPath(roundedRect: rect, cornerRadius: corner)
        UIColor.white.setFill()
        shape.fill()
        shape.addClip()

        if card.isLined(side) {
            let spacing = h * 32 / 570
            UIColor(red: 0, green: 0.48, blue: 1, alpha: 0.18).setStroke()
            let x1 = rect.minX + w * 0.017, x2 = rect.maxX - w * 0.017
            var y = rect.minY + spacing * 1.25
            while y < rect.maxY {
                let line = UIBezierPath()
                line.move(to: CGPoint(x: x1, y: y))
                line.addLine(to: CGPoint(x: x2, y: y))
                line.lineWidth = 0.5
                line.stroke()
                y += spacing
            }
        }

        for item in card.imageItems(side) {
            guard let image = ImageStore.image(item.file) else { continue }
            let box = CGRect(x: rect.minX + item.x * w, y: rect.minY + item.y * h,
                             width: item.w * w, height: item.w * w * item.aspect)
            cg.saveGState()
            UIBezierPath(roundedRect: box, cornerRadius: w * 0.009).addClip()
            image.draw(in: box, blendMode: .normal, alpha: item.opacity ?? 1)
            cg.restoreGState()
        }

        let ref = card.effectiveInkWidth
        if let ink = InkRenderQueue.sync({ InkRenderer.render(card.drawing(side), dark: false, refWidth: ref,
                                        scale: max(1, min(1600 / max(ref, 1), 3))) }) {
            ink.draw(in: rect)
        }

        for item in card.textItems(side) where !item.text.isEmpty {
            let style = NSMutableParagraphStyle()
            style.alignment = item.centered == true ? .center : .left
            let padX = w * 0.007, padY = w * 0.011
            let box = CGRect(x: rect.minX + item.x * w + padX, y: rect.minY + item.y * h + padY,
                             width: item.w * w - padX * 2, height: rect.maxY)
            (item.text as NSString).draw(in: box, withAttributes: [
                .font: UIFont.systemFont(ofSize: item.size * w),
                .foregroundColor: UIColor.black, .paragraphStyle: style])
        }
        cg.restoreGState()

        // A hairline border doubles as the cutting guide.
        UIColor(white: 0.55, alpha: 1).setStroke()
        shape.lineWidth = 0.5
        shape.stroke()
    }
}
