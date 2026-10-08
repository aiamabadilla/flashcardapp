import SwiftUI
import SwiftData

struct DeckListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Deck.created) private var decks: [Deck]
    @State private var path: [Deck] = []
    @State private var pendingDelete: Deck?

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach(decks) { deck in
                    NavigationLink(value: deck) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(deck.title.isEmpty ? "Untitled Deck" : deck.title).font(.headline)
                            let due = deck.dueCards.count
                            (Text("\(deck.cards.count) \(deck.cards.count == 1 ? "card" : "cards")")
                             + (due > 0 ? Text(" · \(due) due").foregroundStyle(.orange) : Text("")))
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            Haptics.tap()
                            pendingDelete = deck
                        } label: {
                            Label("Delete", systemImage: "trash").labelStyle(.iconOnly)
                        }
                    }
                    .contextMenu {
                        Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = deck }
                    }
                }
            }
            .overlay {
                if decks.isEmpty {
                    ContentUnavailableView("No Decks", systemImage: "rectangle.stack",
                                           description: Text("Tap + to create your first deck."))
                }
            }
            .confirmationDialog("Delete \"\(pendingDelete?.title ?? "")\" and all its cards?",
                                isPresented: Binding(get: { pendingDelete != nil },
                                                     set: { if !$0 { pendingDelete = nil } }),
                                titleVisibility: .visible) {
                Button("Delete Deck", role: .destructive) {
                    if let deck = pendingDelete { Haptics.warning(); context.delete(deck) }
                    pendingDelete = nil
                }
            }
            .navigationTitle("Decks")
            .navigationDestination(for: Deck.self) { DeckView(deck: $0) }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    AppearanceMenu()
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
