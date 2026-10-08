import SwiftUI
import SwiftData

/// Decks and cards deleted in the last 30 days, with Restore and Delete Forever.
struct RecentlyDeletedView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Deck> { $0.deletedAt > 0 }, sort: \Deck.deletedAt, order: .reverse)
    private var trashedDecks: [Deck]
    @Query(filter: #Predicate<Card> { $0.deletedAt > 0 }, sort: \Card.deletedAt, order: .reverse)
    private var trashedCards: [Card]
    @Query private var allDecks: [Deck]
    @State private var confirmingEmpty = false

    /// Deleted cards whose deck still exists. (Cards of a deleted deck come back with it.)
    private var cardEntries: [(card: Card, deck: Deck)] {
        trashedCards.compactMap { card in
            guard let deck = allDecks.first(where: { $0.cards.contains { $0 === card } }),
                  !deck.inTrash else { return nil }
            return (card, deck)
        }
    }

    var body: some View {
        NavigationStack {
            let cards = cardEntries
            List {
                if !trashedDecks.isEmpty {
                    Section("Decks") {
                        ForEach(trashedDecks) { deck in
                            row(title: deck.title.isEmpty ? "Untitled Deck" : deck.title,
                                detail: plural(deck.liveCards.count, "card"),
                                deletedAt: deck.deletedAt, thumbnail: nil,
                                restore: { deck.deletedAt = 0 },
                                forever: { Trash.deleteForever(deck, in: context) })
                        }
                    }
                }
                if !cards.isEmpty {
                    Section("Cards") {
                        ForEach(cards, id: \.card.persistentModelID) { entry in
                            row(title: "Card",
                                detail: "From \(entry.deck.title.isEmpty ? "Untitled Deck" : entry.deck.title)",
                                deletedAt: entry.card.deletedAt, thumbnail: entry.card,
                                restore: { entry.deck.restoreCard(entry.card) },
                                forever: { Trash.deleteForever(entry.card, in: context) })
                        }
                    }
                }
            }
            .overlay {
                if trashedDecks.isEmpty && cards.isEmpty {
                    ContentUnavailableView("Nothing Deleted", systemImage: "trash",
                                           description: Text("Decks and cards you delete stay here for \(Trash.retentionDays) days."))
                }
            }
            .navigationTitle("Recently Deleted")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Delete All", role: .destructive) { Haptics.tap(); confirmingEmpty = true }
                        .disabled(trashedDecks.isEmpty && cards.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { Haptics.tap(); dismiss() }
                }
            }
            .confirmationDialog("Permanently delete everything in Recently Deleted?",
                                isPresented: $confirmingEmpty, titleVisibility: .visible) {
                Button("Delete All Forever", role: .destructive) {
                    Haptics.warning()
                    for deck in trashedDecks { context.delete(deck) }
                    for entry in cards { context.delete(entry.card) }
                    try? context.save()
                    PhotoCleanup.run(in: context, force: true)
                }
            } message: {
                Text("This can't be undone.")
            }
        }
    }

    private func row(title: String, detail: String, deletedAt: Double, thumbnail: Card?,
                     restore: @escaping () -> Void, forever: @escaping () -> Void) -> some View {
        HStack(spacing: 16) {
            if let card = thumbnail {
                CardFace(card: card, side: .front, corner: 8, inset: 6)
                    .frame(width: 110)
                    .shadow(radius: 2)
            } else {
                Image(systemName: "rectangle.stack.fill")
                    .font(.title2).foregroundStyle(.secondary).frame(width: 110)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
                Text("\(plural(Trash.daysLeft(deletedAt: deletedAt), "day")) left")
                    .font(.caption).foregroundStyle(.orange)
            }
            Spacer()
            Button("Restore") { Haptics.success(); restore(); try? context.save() }
                .buttonStyle(.bordered)
            Button("Delete", role: .destructive) {
                Haptics.warning(); forever()
                PhotoCleanup.run(in: context, force: true)
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
    }
}
