import SwiftUI
import SwiftData
import PencilKit
import Vision
import CryptoKit

/// Reads the handwriting on each card side with Apple's Vision framework and stores the
/// recognised text on the card, so search can find cards by what you wrote. A side is
/// only read again after its ink changes.
enum HandwritingIndex {
    private static let emptyMarker = "empty"

    /// Bump when the reading method improves, so cards are read again with the new method.
    private static let methodVersion = "v2"

    /// A short, stable fingerprint of a drawing's bytes (and of the reading method).
    static func fingerprint(_ data: Data) -> String {
        guard !data.isEmpty else { return emptyMarker }
        let digest = SHA256.hash(data: data).prefix(8).map { String(format: "%02x", $0) }.joined()
        return "\(methodVersion)-\(digest)"
    }

    /// How a drawing is prepared for reading. Real handwriting is thin and small compared to
    /// what text recognition expects, so strokes are thickened, drawn large and padded.
    private nonisolated struct Pass {
        let thicknessDivisor: CGFloat   // minimum stroke width = writing height / this
        let targetSide: CGFloat         // longest side of the image, in pixels
        let paddingFactor: CGFloat      // blank border, as a multiple of the writing height
    }

    // Two passes: the second is a fallback for words the first misses. Results are combined,
    // which suits search (a word found by either pass counts).
    private nonisolated static let passes = [Pass(thicknessDivisor: 12, targetSide: 2000, paddingFactor: 1.5),
                                 Pass(thicknessDivisor: 10, targetSide: 1600, paddingFactor: 1.0)]

    /// The same strokes with a minimum width, drawn in plain black.
    private nonisolated static func thickened(_ drawing: PKDrawing, minimumWidth: CGFloat) -> PKDrawing {
        let strokes = drawing.strokes.map { stroke -> PKStroke in
            let points = stroke.path.map { p in
                let w = max(p.size.width, minimumWidth)
                return PKStrokePoint(location: p.location, timeOffset: p.timeOffset,
                                     size: CGSize(width: w, height: w), opacity: 1,
                                     force: p.force, azimuth: p.azimuth, altitude: p.altitude)
            }
            return PKStroke(ink: PKInk(.pen, color: .black),
                            path: PKStrokePath(controlPoints: points, creationDate: stroke.path.creationDate))
        }
        return PKDrawing(strokes: strokes)
    }

    private nonisolated static func read(_ drawing: PKDrawing, pass: Pass) -> String {
        let height = max(drawing.bounds.height, 1)
        let long = max(drawing.bounds.width, height)
        let scale = min(max(pass.targetSide / long, 1), 8)
        let source = thickened(drawing, minimumWidth: max(1.5, height / pass.thicknessDivisor))
        let bounds = source.bounds.insetBy(dx: -max(24, height * pass.paddingFactor),
                                           dy: -max(24, height * pass.paddingFactor))

        // Vision reads dark text on a light background, so draw the ink on white.
        var ink: UIImage?
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            ink = source.image(from: bounds, scale: scale)
        }
        guard let ink else { return "" }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let flattened = UIGraphicsImageRenderer(size: ink.size, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: ink.size))
            ink.draw(at: .zero)
        }
        guard let cgImage = flattened.cgImage else { return "" }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["en-US"]
        try? VNImageRequestHandler(cgImage: cgImage).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
    }

    /// Reads the text in a saved drawing. Runs off the main thread.
    static func recognize(_ data: Data) async -> String {
        await Task.detached(priority: .utility) {
            guard let drawing = try? PKDrawing(data: data), !drawing.bounds.isEmpty else { return "" }
            return passes.map { read(drawing, pass: $0) }.joined(separator: " ")
        }.value
    }

    /// Sides whose ink has changed since they were last read.
    @MainActor static func pendingCount(in context: ModelContext) -> Int {
        let cards = (try? context.fetch(FetchDescriptor<Card>())) ?? []
        return cards.filter { $0.deletedAt == 0 }.reduce(0) { total, card in
            total + (card.frontInkHash != fingerprint(card.front) ? 1 : 0)
                  + (card.backInkHash != fingerprint(card.back) ? 1 : 0)
        }
    }

    /// Reads every side that is new or changed. `progress` reports how many are left.
    @MainActor static func indexAll(in context: ModelContext, progress: ((Int) -> Void)? = nil) async {
        var left = pendingCount(in: context)
        progress?(left)
        guard left > 0 else { return }
        let cards = (try? context.fetch(FetchDescriptor<Card>())) ?? []
        for card in cards where card.deletedAt == 0 {
            for side in [Side.front, .back] {
                let data = card.drawing(side)
                let hash = fingerprint(data)
                guard card.inkHash(side) != hash else { continue }
                let text = data.isEmpty ? "" : await recognize(data)
                card.setInk(text: text, hash: hash, side)
                left -= 1
                progress?(max(left, 0))
            }
        }
        try? context.save()
    }
}

extension Card {
    func inkText(_ side: Side) -> String { side == .front ? frontInkText : backInkText }
    func inkHash(_ side: Side) -> String { side == .front ? frontInkHash : backInkHash }

    func setInk(text: String, hash: String, _ side: Side) {
        if side == .front { frontInkText = text; frontInkHash = hash }
        else { backInkText = text; backInkHash = hash }
    }
}

// MARK: - Searching

struct SearchHit: Identifiable {
    let card: Card
    let deck: Deck
    /// Where the words were found, e.g. "Front · handwriting".
    let matches: [String]
    var id: PersistentIdentifier { card.persistentModelID }
}

enum CardSearch {
    static func run(_ query: String, in decks: [Deck]) -> [SearchHit] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        var hits: [SearchHit] = []
        for deck in decks {
            for card in deck.sortedCards {
                var found: [String] = []
                for side in [Side.front, .back] {
                    let name = side == .front ? "Front" : "Back"
                    let typed = card.textItems(side).map(\.text).joined(separator: " ")
                    if typed.localizedStandardContains(q) { found.append("\(name) · typed text") }
                    if card.inkText(side).localizedStandardContains(q) { found.append("\(name) · handwriting") }
                }
                if !found.isEmpty { hits.append(SearchHit(card: card, deck: deck, matches: found)) }
            }
        }
        return hits
    }
}

struct SearchTarget: Identifiable {
    let id = UUID()
    let deck: Deck
    let card: Card
}

/// The results shown while the search field has text.
struct SearchResultsView: View {
    let query: String
    let decks: [Deck]
    let indexingLeft: Int
    let onOpen: (SearchHit) -> Void

    var body: some View {
        let hits = CardSearch.run(query, in: decks)
        let deckHits = decks.filter { $0.title.localizedStandardContains(query) }

        List {
            if indexingLeft > 0 {
                Label("Reading handwriting… \(indexingLeft) left", systemImage: "pencil.and.scribble")
                    .foregroundStyle(.secondary)
            }
            if !deckHits.isEmpty {
                Section("Decks") {
                    ForEach(deckHits) { deck in
                        Text(deck.displayTitle)
                    }
                }
            }
            if !hits.isEmpty {
                Section("Cards") {
                    ForEach(hits) { hit in
                        Button { Haptics.tap(); onOpen(hit) } label: {
                            HStack(spacing: 16) {
                                CardFace(card: hit.card, side: .front, corner: 8, inset: 6)
                                    .frame(width: 130)
                                    .shadow(radius: 2)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(hit.deck.displayTitle).font(.headline)
                                    ForEach(hit.matches, id: \.self) {
                                        Text($0).font(.subheadline).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.footnote.bold()).foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .overlay {
            if hits.isEmpty && deckHits.isEmpty && indexingLeft == 0 {
                ContentUnavailableView.search(text: query)
            }
        }
    }
}
