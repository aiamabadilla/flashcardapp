import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct DeckListView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query(filter: #Predicate<Deck> { $0.deletedAt == 0 }, sort: \Deck.created) private var decks: [Deck]
    @Query(filter: #Predicate<Deck> { $0.deletedAt > 0 }) private var trashedDecks: [Deck]
    @Query(filter: #Predicate<Card> { $0.deletedAt > 0 }) private var trashedCards: [Card]
    @State private var path: [Deck] = []
    @State private var pendingDelete: Deck?
    @State private var showingStats = false
    @ObservedObject private var saveStatus = SaveStatus.shared
    @State private var showingTrash = false
    @State private var exported: ExportedFile?
    @State private var showingImporter = false
    @State private var backupMessage: String?
    @State private var query = ""
    /// The query after a short pause in typing; searches run on this, not on every keystroke.
    @State private var settledQuery = ""
    @State private var indexingLeft = 0
    @State private var searchTarget: SearchTarget?

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
                        Button("Export Deck", systemImage: "square.and.arrow.up") {
                            export([deck], name: deck.title)
                        }
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
            .searchable(text: $query, prompt: "Search cards and handwriting")
            .overlay {
                if !settledQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                    SearchResultsView(query: settledQuery, decks: decks, indexingLeft: indexingLeft) { hit in
                        searchTarget = SearchTarget(deck: hit.deck, card: hit.card)
                    }
                    .background(Color(.systemGroupedBackground))
                }
            }
            .fullScreenCover(item: $searchTarget) { CardEditor(deck: $0.deck, start: $0.card) }
            // Read any new or changed handwriting as soon as someone searches, so results are current.
            .task(id: query) {
                // Wait for a pause in typing before searching (cancelled by the next keystroke).
                if query.isEmpty { settledQuery = ""; return }
                try? await Task.sleep(for: .milliseconds(250))
                if !Task.isCancelled { settledQuery = query }
            }
            .task(id: query.isEmpty) {
                guard !query.isEmpty else { return }
                await HandwritingIndex.indexAll(in: context) { indexingLeft = $0 }
                indexingLeft = 0
            }
            .sheet(isPresented: $showingStats) { StatsView() }
            .sheet(isPresented: $showingTrash) { RecentlyDeletedView() }
            .sheet(item: $exported) { file in
                ShareSheet(url: file.url) { completed in
                    guard completed else { return }
                    Haptics.success()
                    backupMessage = "Backup complete: \(plural(file.decks, "deck")), \(plural(file.cards, "card"))."
                }
            }
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.item]) { result in
                switch result {
                case .success(let url):
                    do {
                        let r = try Backup.importArchive(from: url, into: context)
                        Haptics.success()
                        backupMessage = "Restored \(plural(r.decks, "deck")) with \(plural(r.cards, "card"))."
                    } catch {
                        Haptics.warning()
                        backupMessage = error.localizedDescription
                    }
                case .failure(let error):
                    backupMessage = error.localizedDescription
                }
            }
            .alert("Couldn't save", isPresented: Binding(
                get: { saveStatus.failureMessage != nil },
                set: { if !$0 { saveStatus.failureMessage = nil } })) {
                Button("OK") { saveStatus.failureMessage = nil }
            } message: {
                Text(saveStatus.failureMessage ?? "")
            }
            .alert("Backup", isPresented: Binding(get: { backupMessage != nil },
                                                  set: { if !$0 { backupMessage = nil } })) {
                Button("OK") { backupMessage = nil }
            } message: {
                Text(backupMessage ?? "")
            }
            .undoBanner()
            .task {
                Trash.purgeExpired(in: context)   // remove anything deleted over 30 days ago
                PhotoCleanup.run(in: context)     // then clear photo files nothing uses
                await HandwritingIndex.indexAll(in: context)   // read new handwriting in the background
            }
            .onChange(of: scenePhase) {
                if scenePhase == .background {
                    PhotoCleanup.run(in: context)
                    Task { await HandwritingIndex.indexAll(in: context) }
                }
            }
            .navigationTitle("Decks")
            .navigationDestination(for: Deck.self) { DeckView(deck: $0) }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { Haptics.tap(); showingStats = true } label: {
                        Label("Stats", systemImage: "chart.bar.xaxis")
                    }
                    Menu {
                        Button("Back Up All Decks", systemImage: "square.and.arrow.up") {
                            export(decks, name: "IMSTUDY Backup")
                        }
                        .disabled(decks.isEmpty)
                        Button("Restore from Backup…", systemImage: "square.and.arrow.down") {
                            Haptics.tap()
                            showingImporter = true
                        }
                    } label: {
                        Label("Backup", systemImage: "externaldrive")
                    }
                    AppearanceMenu()
                    Button { newDeck() } label: { Label("New Deck", systemImage: "plus") }
                }
            }
        }
    }

    /// Items in Recently Deleted: decks, plus deleted cards whose deck still exists.
    private var trashCount: Int {
        let live = Set(decks.flatMap { $0.cards.map(\.persistentModelID) })
        return trashedDecks.count + trashedCards.filter { live.contains($0.persistentModelID) }.count
    }

    private func export(_ decks: [Deck], name: String) {
        do {
            let url = try Backup.export(decks, name: name)
            exported = ExportedFile(url: url, decks: decks.count,
                                    cards: decks.reduce(0) { $0 + $1.liveCards.count })
            Haptics.tap()
        } catch {
            backupMessage = "Couldn't create the backup: \(error.localizedDescription)"
        }
    }

    private func newDeck() {
        let deck = Deck()
        Haptics.success()
        context.insert(deck)
        path.append(deck)
    }
}
