import SwiftData
import Foundation

nonisolated enum Side: Sendable { case front, back }

/// Where a side's typed text sits on the card, as fractions of the card's size.
/// `size` is the font size as a fraction of the card width.
nonisolated struct TextBox: Equatable, Sendable {
    var x = 0.02
    var y = 0.03
    var w = 0.96
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

    init(order: Int) {
        self.order = order
        self.front = Data()
        self.back = Data()
    }

    func drawing(_ side: Side) -> Data { side == .front ? front : back }
    func text(_ side: Side) -> String { side == .front ? frontText : backText }
    func isLined(_ side: Side) -> Bool { side == .front ? frontLined : backLined }

    func box(_ side: Side) -> TextBox {
        side == .front
            ? TextBox(x: frontBoxX, y: frontBoxY, w: frontBoxW, size: frontBoxSize)
            : TextBox(x: backBoxX, y: backBoxY, w: backBoxW, size: backBoxSize)
    }

    func setBox(_ b: TextBox, _ side: Side) {
        if side == .front {
            frontBoxX = b.x; frontBoxY = b.y; frontBoxW = b.w; frontBoxSize = b.size
        } else {
            backBoxX = b.x; backBoxY = b.y; backBoxW = b.w; backBoxSize = b.size
        }
    }

    func setText(_ value: String, _ side: Side) {
        if side == .front { frontText = value } else { backText = value }
    }
    func toggleLines(_ side: Side) {
        if side == .front { frontLined.toggle() } else { backLined.toggle() }
    }
}
