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

@Model final class Deck {
    var title: String
    var created: Date
    @Relationship(deleteRule: .cascade) var cards: [Card] = []

    init(title: String = "Untitled Deck") {
        self.title = title
        self.created = .now
    }

    var sortedCards: [Card] { cards.sorted { $0.order < $1.order } }
    var starredCards: [Card] { sortedCards.filter(\.isStarred) }

    func newCard() -> Card {
        let card = Card(order: (cards.map(\.order).max() ?? -1) + 1)
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
    // All text boxes (both sides) as JSON. A plain String keeps store migration trivial.
    var textItemsJSON: String = ""

    init(order: Int) {
        self.order = order
        self.front = Data()
        self.back = Data()
    }

    func drawing(_ side: Side) -> Data { side == .front ? front : back }
    func isLined(_ side: Side) -> Bool { side == .front ? frontLined : backLined }

    func toggleLines(_ side: Side) {
        if side == .front { frontLined.toggle() } else { backLined.toggle() }
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
}
