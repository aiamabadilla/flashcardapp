import SwiftUI
import SwiftData

extension Card {
    /// A new, free-standing card with this card's content (ink, text, photos, paper) but
    /// none of its study history, so a copy starts out as a new card.
    func contentCopy(order: Int) -> Card {
        let c = Card(order: order)
        c.front = front
        c.back = back
        c.frontLined = frontLined
        c.backLined = backLined
        c.isStarred = isStarred
        c.textItemsJSON = textItemsJSON.isEmpty ? Self.json(allTextItems) : textItemsJSON
        c.imageItemsJSON = imageItemsJSON   // copies share the photo files
        c.frontInkText = frontInkText
        c.backInkText = backInkText
        c.frontInkHash = frontInkHash
        c.backInkHash = backInkHash
        return c
    }

    private static func json(_ items: [TextItem]) -> String {
        (try? JSONEncoder().encode(items)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
}

extension Deck {
    /// Duplicates a card, placing the copy right after the original.
    @MainActor func duplicate(_ card: Card, in context: ModelContext) {
        let copy = card.contentCopy(order: card.order + 1)
        for other in liveCards where other.order > card.order { other.order += 1 }
        cards.append(copy)
        try? context.save()
        UndoCenter.shared.offer("Card duplicated") { [self] in
            cards.removeAll { $0 === copy }
            context.delete(copy)
            renumber()
            try? context.save()
        }
    }

    /// Copies a card to the end of another deck.
    @MainActor func copy(_ card: Card, to target: Deck, in context: ModelContext) {
        let copy = card.contentCopy(order: (target.liveCards.map(\.order).max() ?? -1) + 1)
        target.cards.append(copy)
        try? context.save()
        UndoCenter.shared.offer("Copied to \(target.displayTitle)") {
            target.cards.removeAll { $0 === copy }
            context.delete(copy)
            target.renumber()
            try? context.save()
        }
    }

    /// Moves a card to the end of another deck.
    ///
    /// The card is detached and saved first, then attached to the new deck. Doing both in
    /// one step made SwiftData clear the new link when it processed the removal.
    @MainActor func move(_ card: Card, to target: Deck, in context: ModelContext) {
        let originalOrder = card.order
        cards.removeAll { $0 === card }
        do { try context.save() } catch { NSLog("MOVE save1 failed: %@", "\(error)") }

        card.order = (target.liveCards.map(\.order).max() ?? -1) + 1
        target.cards.append(card)
        renumber()
        do { try context.save() } catch { NSLog("MOVE save2 failed: %@", "\(error)") }

        UndoCenter.shared.offer("Moved to \(target.displayTitle)") { [self] in
            target.cards.removeAll { $0 === card }
            try? context.save()

            target.renumber()
            for other in liveCards where other.order >= originalOrder { other.order += 1 }
            card.order = originalOrder
            cards.append(card)
            try? context.save()
        }
    }

    var displayTitle: String { title.isEmpty ? "Untitled Deck" : title }
}
