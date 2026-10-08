import SwiftData
import Foundation

@Model final class Deck {
    var title: String
    var created: Date
    @Relationship(deleteRule: .cascade) var cards: [Card] = []

    init(title: String = "Untitled Deck") {
        self.title = title
        self.created = .now
    }

    var sortedCards: [Card] { cards.sorted { $0.order < $1.order } }

    /// Re-numbers cards 0...n-1 so ordering stays contiguous after deletes and moves.
    func newCard() -> Card {
        let card = Card(order: (cards.map(\.order).max() ?? -1) + 1)
        cards.append(card)
        return card
    }

    func renumber() {
        for (index, card) in sortedCards.enumerated() { card.order = index }
    }
}

@Model final class Card {
    var order: Int
    var front: Data
    var back: Data

    init(order: Int) {
        self.order = order
        self.front = Data()
        self.back = Data()
    }
}
