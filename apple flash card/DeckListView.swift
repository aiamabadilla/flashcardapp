import SwiftUI
import SwiftData

struct DeckListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Deck.created) private var decks: [Deck]
    @State private var path: [Deck] = []

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach(decks) { deck in
                    NavigationLink(value: deck) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(deck.title.isEmpty ? "Untitled Deck" : deck.title).font(.headline)
                            Text("\(deck.cards.count) \(deck.cards.count == 1 ? "card" : "cards")")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .contextMenu {
                        Button("Delete", systemImage: "trash", role: .destructive) { Haptics.warning(); context.delete(deck) }
                    }
                }
                .onDelete { offsets in
                    Haptics.warning()
                    for i in offsets { context.delete(decks[i]) }
                }
            }
            .overlay {
                if decks.isEmpty {
                    ContentUnavailableView("No Decks", systemImage: "rectangle.stack",
                                           description: Text("Tap + to create your first deck."))
                }
            }
            .navigationTitle("Decks")
            .navigationDestination(for: Deck.self) { DeckView(deck: $0) }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { newDeck() } label: { Label("New Deck", systemImage: "plus") }
                }
            }
        }
    }

    private func newDeck() {
        let deck = Deck()
        Haptics.success()
        context.insert(deck)
        path.append(deck)
    }
}
