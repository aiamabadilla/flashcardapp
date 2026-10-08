import Foundation
import SwiftData

/// Recently Deleted: decks and cards stay recoverable for 30 days, then are removed.
enum Trash {
    static let retentionDays = 30

    static func daysLeft(deletedAt: Double, now: Date = .now) -> Int {
        let elapsed = now.timeIntervalSince1970 - deletedAt
        return max(0, Int((Double(retentionDays) - elapsed / 86_400).rounded(.up)))
    }

    /// Permanently removes anything that has been in Recently Deleted too long.
    @MainActor static func purgeExpired(in context: ModelContext, now: Date = .now) {
        let limit = Double(retentionDays) * 86_400
        let cutoff = now.timeIntervalSince1970 - limit
        let decks = (try? context.fetch(FetchDescriptor<Deck>())) ?? []
        for deck in decks where deck.deletedAt > 0 && deck.deletedAt < cutoff {
            context.delete(deck)
        }
        let cards = (try? context.fetch(FetchDescriptor<Card>())) ?? []
        for card in cards where card.deletedAt > 0 && card.deletedAt < cutoff {
            context.delete(card)
        }
        try? context.save()
    }

    @MainActor static func deleteForever(_ deck: Deck, in context: ModelContext) {
        context.delete(deck)
        try? context.save()
    }

    @MainActor static func deleteForever(_ card: Card, in context: ModelContext) {
        context.delete(card)
        try? context.save()
    }
}
