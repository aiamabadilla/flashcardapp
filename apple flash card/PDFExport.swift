import SwiftUI
import UIKit

/// Exports a deck as a PDF: a landscape page for the front of each card, then one for its back,
/// in deck order. Pages are drawn the way Study shows cards (photos fully opaque) on light paper,
/// so the PDF reads well when printed whatever appearance the app is in.
enum PDFExport {
    enum PDFError: LocalizedError {
        case noCards, failed

        var errorDescription: String? {
            switch self {
            case .noCards: "This deck has no cards to export."
            case .failed: "Couldn't create the PDF."
            }
        }
    }

    /// Page size in points. Matches the 5:3 shape of a card, so a card fills its page.
    static let pageSize = CGSize(width: 720, height: 432)

    /// Builds the PDF in a temporary file and returns its URL. `progress` is told how many pages
    /// are done out of the total, so a long deck can show it.
    @MainActor static func export(_ deck: Deck, progress: ((Int, Int) -> Void)? = nil) async throws -> URL {
        let cards = deck.sortedCards
        guard !cards.isEmpty else { throw PDFError.noCards }

        let total = cards.count * 2
        var pages: [Data] = []
        pages.reserveCapacity(total)

        // Each page is drawn as an image first, with a pause between pages so the app stays
        // responsive. Keeping them as compressed JPEG data holds memory down for big decks.
        for card in cards {
            for side in [Side.front, Side.back] {
                try Task.checkCancellation()
                guard let jpeg = pageJPEG(card: card, side: side) else { throw PDFError.failed }
                pages.append(jpeg)
                progress?(pages.count, total)
                await Task.yield()
            }
        }

        let bounds = CGRect(origin: .zero, size: pageSize)
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: deck.displayTitle,
            kCGPDFContextCreator as String: "IMSTUDY",
        ]
        let data = UIGraphicsPDFRenderer(bounds: bounds, format: format).pdfData { context in
            for jpeg in pages {
                context.beginPage()
                UIImage(data: jpeg)?.draw(in: bounds)
            }
        }
        guard !data.isEmpty else { throw PDFError.failed }

        let stamp = Date.now.formatted(.iso8601.year().month().day())
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(safeFileName(deck.displayTitle)) \(stamp).pdf")
        try data.write(to: url, options: .atomic)
        return url
    }

    /// One side of one card as a JPEG page image.
    @MainActor private static func pageJPEG(card: Card, side: Side) -> Data? {
        // The card draws its ink from a cache that is normally filled in the background. An
        // ImageRenderer doesn't wait for that, so fill it first.
        InkRenderer.prewarm(card, side: side, dark: false)

        let page = CardFace(card: card, side: side, corner: 0, inset: 12, fullOpacityImages: true)
            .environment(\.colorScheme, .light)
            .frame(width: pageSize.width, height: pageSize.height)
        let renderer = ImageRenderer(content: page)
        renderer.scale = 2
        return renderer.uiImage?.jpegData(compressionQuality: 0.85)
    }

    /// A file name without characters that file systems reject.
    static func safeFileName(_ name: String) -> String {
        let cleaned = name.components(separatedBy: CharacterSet(charactersIn: "/\\:?*\"<>|")).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "IMSTUDY" : cleaned
    }
}
