import SwiftUI
import SwiftData

struct DeckListView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query(filter: #Predicate<Deck> { $0.deletedAt == 0 }, sort: \Deck.created) private var decks: [Deck]
    @Query(filter: #Predicate<Deck> { $0.deletedAt > 0 }) private var trashedDecks: [Deck]
    @Query(filter: #Predicate<Card> { $0.deletedAt > 0 }) private var trashedCards: [Card]
    @State private var path: [Deck] = []
    @State private var pendingDelete: Deck?
    @State private var showingStats = false
    @State private var showingTrash = false

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Button { Haptics.tap(); showingStats = true } label: { StreakBanner() }
                    .buttonStyle(.plain)

                ForEach(decks) { deck in
                    NavigationLink(value: deck) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(deck.title.isEmpty ? "Untitled Deck" : deck.title).font(.headline)
                            let due = deck.dueCards.count
                            (Text("\(deck.liveCards.count) \(deck.liveCards.count == 1 ? "card" : "cards")")
                             + (due > 0 ? Text(" · \(due) due").foregroundStyle(.orange) : Text("")))
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        // Not role: .destructive. That makes iOS start collapsing the row as if
                        // it were already deleted, then snap it back while we ask to confirm.
                        Button {
                            Haptics.tap()
                            pendingDelete = deck
                        } label: {
                            Label("Delete", systemImage: "trash").labelStyle(.iconOnly)
                        }
                        .tint(.red)
                    }
                    .contextMenu {
                        Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = deck }
                    }
                    // Attached to the row (not the whole screen) so the popup points at this deck.
                    .confirmationDialog(
                        "Move \"\(deck.title)\" and its cards to Recently Deleted?",
                        isPresented: Binding(
                            get: { pendingDelete === deck },
                            set: { if !$0, pendingDelete === deck { pendingDelete = nil } }),
                        titleVisibility: .visible
                    ) {
                        Button("Delete Deck", role: .destructive) {
                            Haptics.warning()
                            pendingDelete = nil
                            withAnimation { context.deleteDeck(deck) }
                        }
                    }
                }

                Button { Haptics.tap(); showingTrash = true } label: {
                    HStack {
                        Label("Recently Deleted", systemImage: "trash")
                        Spacer()
                        if trashCount > 0 { Text("\(trashCount)").foregroundStyle(.secondary) }
                        Image(systemName: "chevron.right").font(.footnote.bold()).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .overlay {
                if decks.isEmpty {
                    ContentUnavailableView("No Decks", systemImage: "rectangle.stack",
                                           description: Text("Tap + to create your first deck."))
                }
            }
            .sheet(isPresented: $showingStats) { StatsView() }
            .sheet(isPresented: $showingTrash) { RecentlyDeletedView() }
            .undoBanner()
            .task {
                Trash.purgeExpired(in: context)   // remove anything deleted over 30 days ago
                PhotoCleanup.run(in: context)     // then clear photo files nothing uses
            }
            .onChange(of: scenePhase) {
                if scenePhase == .background { PhotoCleanup.run(in: context) }
            }
            .navigationTitle("Decks")
            .navigationDestination(for: Deck.self) { DeckView(deck: $0) }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { Haptics.tap(); showingStats = true } label: {
                        Label("Stats", systemImage: "chart.bar.xaxis")
                    }
                    AppearanceMenu()
                    Button { newDeck() } label: { Label("New Deck", systemImage: "plus") }
                }
            }
        }
    }

    /// Items in Recently Deleted: decks, plus deleted cards whose deck still exists.
    private var trashCount: Int {
        trashedDecks.count + trashedCards.filter { card in
            decks.contains { $0.cards.contains { $0 === card } }
        }.count
    }

    private func newDeck() {
        let deck = Deck()
        Haptics.success()
        context.insert(deck)
        path.append(deck)
    }
}
