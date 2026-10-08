import SwiftData
import Foundation

nonisolated enum Side: Sendable { case front, back }

/// One typed text box on a card side. Position and size are fractions of the card
/// (`size` is the font size as a fraction of the card width), so the box looks the same
/// in the editor, thumbnails and Study mode.
nonisolated struct TextItem: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var side: Int            // 0 = front, 1 = back
    var text = ""
    var x = 0.04
    var y = 0.05
    var w = 0.6
    var size = 0.03
}

/// A photo placed on a card side. Position and width are fractions of the card;
/// `aspect` is height divided by width.
nonisolated struct ImageItem: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var side: Int            // 0 = front, 1 = back
    var file: String         // file name inside ImageStore
    var aspect: Double
    var x = 0.3
    var y = 0.2
    var w = 0.4
}

@Model final class Deck {
    var title: String
    var created: Date
    /// When the deck was moved to Recently Deleted (seconds since 1970); 0 = not deleted.
    var deletedAt = 0.0
    @Relationship(deleteRule: .cascade) var cards: [Card] = []

    init(title: String = "Untitled Deck") {
        self.title = title
        self.created = .now
    }

    /// Cards that haven't been moved to Recently Deleted.
    var liveCards: [Card] { cards.filter { $0.deletedAt == 0 } }
    var inTrash: Bool { deletedAt > 0 }

    var sortedCards: [Card] { liveCards.sorted { $0.order < $1.order } }
    var starredCards: [Card] { sortedCards.filter(\.isStarred) }

    /// Cards due for review now: most overdue first, new cards (never reviewed) included.
    var dueCards: [Card] {
        liveCards.filter(\.isDue).sorted { ($0.dueTime, $0.order) < ($1.dueTime, $1.order) }
    }
    var newCount: Int { liveCards.filter(\.isNew).count }
    var masteredCount: Int { liveCards.filter(\.isMastered).count }

    func newCard() -> Card {
        // New cards go first, right after the add tile, so existing cards shift along.
        for other in liveCards { other.order += 1 }
        let card = Card(order: 0)
        cards.append(card)
        return card
    }

    /// Re-numbers cards 0...n-1 so ordering stays contiguous after deletes and moves.
    func renumber() {
        for (index, card) in sortedCards.enumerated() { card.order = index }
    }
}

// New properties all have defaults so existing stores migrate automatically.
@Model final class Card {
    var order: Int
    var front: Data
    var back: Data
    var frontText: String = ""
    var backText: String = ""
    var frontLined: Bool = true
    var backLined: Bool = true
    // Text box layout is stored as plain numbers: adding scalar properties with
    // defaults migrates existing stores cleanly (a Codable struct property did not).
    var frontBoxX = 0.02
    var frontBoxY = 0.03
    var frontBoxW = 0.96
    var frontBoxSize = 0.03
    var backBoxX = 0.02
    var backBoxY = 0.03
    var backBoxW = 0.96
    var backBoxSize = 0.03
    var isStarred: Bool = false
    /// When the card was moved to Recently Deleted (seconds since 1970); 0 = not deleted.
    var deletedAt = 0.0
    // Spaced repetition (Leitner boxes). Plain numbers with defaults so stores migrate.
    var leitnerBox = 0            // 0 = learning ... 5 = best known
    var dueTime = 0.0             // seconds since 1970; 0 = never reviewed, due now
    var reviewCount = 0
    var correctCount = 0
    var lastReviewed = 0.0
    // All text boxes (both sides) as JSON. A plain String keeps store migration trivial.
    var textItemsJSON: String = ""
    // Photos on the card (metadata only; the image files live in ImageStore).
    var imageItemsJSON: String = ""
    // Handwriting search: text read from each side's ink, and a fingerprint of the ink it was
    // read from (so a side is only re-read after it changes).
    var frontInkText: String = ""
    var backInkText: String = ""
    var frontInkHash: String = ""
    var backInkHash: String = ""

    init(order: Int) {
        self.order = order
        self.front = Data()
        self.back = Data()
    }

    var inTrash: Bool { deletedAt > 0 }

    func drawing(_ side: Side) -> Data { side == .front ? front : back }
    func isLined(_ side: Side) -> Bool { side == .front ? frontLined : backLined }

    func toggleLines(_ side: Side) {
        if side == .front { frontLined.toggle() } else { backLined.toggle() }
    }

    // MARK: Spaced repetition

    /// Days until the next review for each Leitner box.
    static let intervalDays: [Double] = [0, 1, 2, 4, 8, 16]

    var isDue: Bool { dueTime <= Date.now.timeIntervalSince1970 }
    var isNew: Bool { reviewCount == 0 }
    var isMastered: Bool { leitnerBox >= 4 }

    /// Records one review. Knowing a card moves it up a box (longer wait); missing it
    /// sends it back to box 0, so it is due again right away.
    func review(known: Bool, now: Date = .now) {
        reviewCount += 1
        lastReviewed = now.timeIntervalSince1970
        if known {
            correctCount += 1
            leitnerBox = min(leitnerBox + 1, Card.intervalDays.count - 1)
        } else {
            leitnerBox = 0
        }
        dueTime = now.timeIntervalSince1970 + Card.intervalDays[leitnerBox] * 86_400
    }

    // MARK: Text boxes

    private static let legacyFrontID = UUID(uuidString: "00000000-0000-0000-0000-00000000F001")!
    private static let legacyBackID = UUID(uuidString: "00000000-0000-0000-0000-00000000B001")!

    /// Every text box on the card. Text typed before multiple boxes existed (the old
    /// single frontText/backText fields) is carried over as one box per side.
    var allTextItems: [TextItem] {
        if !textItemsJSON.isEmpty,
           let data = textItemsJSON.data(using: .utf8),
           let items = try? JSONDecoder().decode([TextItem].self, from: data) {
            return items
        }
        var legacy: [TextItem] = []
        if !frontText.isEmpty {
            legacy.append(TextItem(id: Card.legacyFrontID, side: 0, text: frontText,
                                   x: frontBoxX, y: frontBoxY, w: frontBoxW, size: frontBoxSize))
        }
        if !backText.isEmpty {
            legacy.append(TextItem(id: Card.legacyBackID, side: 1, text: backText,
                                   x: backBoxX, y: backBoxY, w: backBoxW, size: backBoxSize))
        }
        return legacy
    }

    func textItems(_ side: Side) -> [TextItem] {
        allTextItems.filter { $0.side == (side == .front ? 0 : 1) }
    }

    func textItem(_ id: UUID) -> TextItem? { allTextItems.first { $0.id == id } }

    private func store(_ items: [TextItem]) {
        if let data = try? JSONEncoder().encode(items), let json = String(data: data, encoding: .utf8) {
            textItemsJSON = json
            frontText = ""   // legacy fields now live in the list
            backText = ""
        }
    }

    func updateTextItem(_ item: TextItem) {
        var items = allTextItems
        if let i = items.firstIndex(where: { $0.id == item.id }) { items[i] = item } else { items.append(item) }
        store(items)
    }

    func removeTextItem(_ id: UUID) {
        store(allTextItems.filter { $0.id != id })
    }

    // MARK: Photos

    var allImageItems: [ImageItem] {
        guard !imageItemsJSON.isEmpty, let data = imageItemsJSON.data(using: .utf8),
              let items = try? JSONDecoder().decode([ImageItem].self, from: data) else { return [] }
        return items
    }

    func imageItems(_ side: Side) -> [ImageItem] {
        allImageItems.filter { $0.side == (side == .front ? 0 : 1) }
    }

    func imageItem(_ id: UUID) -> ImageItem? { allImageItems.first { $0.id == id } }

    private func storeImages(_ items: [ImageItem]) {
        if let data = try? JSONEncoder().encode(items), let json = String(data: data, encoding: .utf8) {
            imageItemsJSON = json
        }
    }

    func updateImageItem(_ item: ImageItem) {
        var items = allImageItems
        if let i = items.firstIndex(where: { $0.id == item.id }) { items[i] = item } else { items.append(item) }
        storeImages(items)
    }

    func removeImageItem(_ id: UUID) {
        storeImages(allImageItems.filter { $0.id != id })
    }
}
