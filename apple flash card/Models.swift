import SwiftData
import Foundation

nonisolated enum Side: Sendable { case front, back }

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
    var isStarred: Bool = false

    init(order: Int) {
        self.order = order
        self.front = Data()
        self.back = Data()
    }

    func drawing(_ side: Side) -> Data { side == .front ? front : back }
    func text(_ side: Side) -> String { side == .front ? frontText : backText }
    func isLined(_ side: Side) -> Bool { side == .front ? frontLined : backLined }

    func setText(_ value: String, _ side: Side) {
        if side == .front { frontText = value } else { backText = value }
    }
    func toggleLines(_ side: Side) {
        if side == .front { frontLined.toggle() } else { backLined.toggle() }
    }
}
