import SwiftUI
import SwiftData

struct EditorTarget: Identifiable {
    let id = UUID()
    let card: Card
}

struct StudyTarget: Identifiable {
    let id = UUID()
    let cards: [Card]
}

/// Which cards the grid currently has on screen. A plain class so changing it never redraws.
final class VisibleCards {
    var ids: Set<PersistentIdentifier> = []
}

/// How far along a PDF export is.
struct PDFProgress: Equatable {
    var done: Int
    var total: Int
}

struct DeckView: View {
    @Bindable var deck: Deck
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    enum Filter { case all, starred }
    @State private var filter: Filter = .all
    @State private var confirmingDelete = false
    @Query(filter: #Predicate<Deck> { $0.deletedAt == 0 }, sort: \Deck.created) private var allDecks: [Deck]

    // Covers are presented with wrapper items that have their own stable IDs, never
    // the model's identity: a new card's identity changes when SwiftData first saves
    // it, which used to make the editor close and reopen mid-writing.
    @State private var editor: EditorTarget?
    @State private var study: StudyTarget?

    // Scroll position: the card last edited, and which cards are on screen (held without
    // observation, so scrolling never re-renders the grid just to keep this list).
    @State private var lastEditedID: PersistentIdentifier?
    @State private var visibility = VisibleCards()

    // Spreadsheet import and PDF export.
    @State private var showingSheetImporter = false
    @State private var exportedPDF: ExportedFile?
    @State private var pdfProgress: PDFProgress?
    @State private var pdfTask: Task<Void, Never>?
    @State private var message: String?

    private let columns = [GridItem(.flexible(), spacing: 24),
                           GridItem(.flexible(), spacing: 24)]

    var body: some View {
        let all = deck.sortedCards
        let starred = all.filter(\.isStarred)
        let due = deck.dueCards
        let visible = filter == .all ? all : starred

        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                TextField("Deck title", text: $deck.title)
                    .font(.largeTitle.bold())

                if !all.isEmpty {
                    HStack(spacing: 10) {
                        StatChip(value: due.count, label: "due", color: .orange)
                        StatChip(value: deck.newCount, label: "new", color: .blue)
                        StatChip(value: deck.masteredCount, label: "mastered", color: .green)
                        Spacer()
                        if !due.isEmpty {
                            Button { startStudy(due) } label: {
                                Label("Study Due", systemImage: "play.fill")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }

                Picker("Show", selection: $filter) {
                    Text("All Cards (\(all.count))").tag(Filter.all)
                    Label("Starred (\(starred.count))", systemImage: "star.fill").tag(Filter.starred)
                }
                .pickerStyle(.segmented)
                .onChange(of: filter) { Haptics.select() }

                LazyVGrid(columns: columns, spacing: 24) {
                    if filter == .all {
                        // New Card tile sits first so it's always in the top-left, however many cards there are.
                        AddCardCell { addCard() }
                    }
                    ForEach(visible) { card in
                        CardThumbnail(card: card)
                            .id(card.persistentModelID)
                            .onAppear { visibility.ids.insert(card.persistentModelID) }
                            .onDisappear { visibility.ids.remove(card.persistentModelID) }
                            .onTapGesture { Haptics.tap(); open(card) }
                            .contextMenu { menu(for: card, in: all) }
                    }
                }

                if filter == .starred && starred.isEmpty {
                    ContentUnavailableView("No Starred Cards", systemImage: "star",
                                           description: Text("Tap Star in the card editor, or long-press a card."))
                }
            }
            .padding(32)
        }
        // After the editor closes, keep the grid on the card that was being edited. If that card
        // is still on screen nothing moves; if the grid lost its place, bring the card back.
        .onChange(of: editor?.id) { _, newValue in
            guard newValue == nil, let id = lastEditedID, !visibility.ids.contains(id) else { return }
            DispatchQueue.main.async { proxy.scrollTo(id, anchor: .center) }
        }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                AppearanceMenu()
                Menu {
                    Button("Import Spreadsheet…", systemImage: "tablecells") {
                        Haptics.tap()
                        showingSheetImporter = true
                    }
                    Button("Export as PDF", systemImage: "doc.richtext") { exportPDF() }
                        .disabled(all.isEmpty || pdfTask != nil)
                } label: {
                    Label("Import and Export", systemImage: "ellipsis.circle")
                }
                Button(role: .destructive) { Haptics.tap(); confirmingDelete = true } label: {
                    Label("Delete Deck", systemImage: "trash")
                }
                .tint(.red)
                Menu {
                    Button("Study Due (\(due.count))", systemImage: "clock.badge.checkmark") {
                        startStudy(due)
                    }
                    .disabled(due.isEmpty)
                    Button("Study All Cards", systemImage: "rectangle.on.rectangle.angled") {
                        startStudy(all.shuffled())
                    }
                    Button("Study Starred (\(starred.count))", systemImage: "star") {
                        startStudy(starred.shuffled())
                    }
                    .disabled(starred.isEmpty)
                } label: {
                    Label("Study", systemImage: "rectangle.on.rectangle.angled")
                }
                .disabled(all.isEmpty)
            }
        }
        .confirmationDialog("Move \"\(deck.title)\" and its cards to Recently Deleted?",
                            isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete Deck", role: .destructive) {
                Haptics.warning()
                dismiss()
                context.deleteDeck(deck)
            }
        }
        .undoBanner()
        .fullScreenCover(item: $editor) { target in
            CardEditor(deck: deck, start: target.card) { lastEditedID = $0.persistentModelID }
        }
        .fullScreenCover(item: $study) { StudyView(cards: $0.cards, deck: deck) }
        .fileImporter(isPresented: $showingSheetImporter, allowedContentTypes: SheetImport.allowedTypes) { result in
            importSheet(result)
        }
        .sheet(item: $exportedPDF) { file in
            ShareSheet(url: file.url) { completed in
                if completed { Haptics.success() }
            }
        }
        .overlay {
            if let progress = pdfProgress {
                VStack(spacing: 12) {
                    ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                        .frame(width: 220)
                    Text("Creating PDF…").font(.headline)
                    Button("Cancel", role: .cancel) { pdfTask?.cancel() }
                }
                .padding(24)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .alert("Import and Export", isPresented: Binding(get: { message != nil },
                                                          set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        } message: {
            Text(message ?? "")
        }
    }

    private func importSheet(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            do {
                let rows = try SheetImport.readRows(at: url)
                let added = SheetImport.addCards(rows, to: deck, in: context)
                SheetImport.offerUndo(added, in: deck, context: context)
                Haptics.success()
                message = "Added \(plural(added.count, "card")) from \(url.lastPathComponent)."
            } catch {
                Haptics.warning()
                message = error.localizedDescription
            }
        case .failure(let error):
            message = error.localizedDescription
        }
    }

    private func exportPDF() {
        guard pdfTask == nil else { return }
        Haptics.tap()
        pdfProgress = PDFProgress(done: 0, total: max(deck.liveCards.count * 2, 1))
        pdfTask = Task {
            defer {
                pdfTask = nil
                pdfProgress = nil
            }
            do {
                let url = try await PDFExport.export(deck) { done, total in
                    pdfProgress = PDFProgress(done: done, total: total)
                }
                exportedPDF = ExportedFile(url: url, decks: 1, cards: deck.liveCards.count)
            } catch is CancellationError {
                // Cancelled by the person; nothing to report.
            } catch {
                Haptics.warning()
                message = error.localizedDescription
            }
        }
    }

    @ViewBuilder
    private func menu(for card: Card, in cards: [Card]) -> some View {
        let index = cards.firstIndex(where: { $0 === card }) ?? 0
        Button("Edit", systemImage: "pencil") { open(card) }
        Button(card.isStarred ? "Unstar" : "Star",
               systemImage: card.isStarred ? "star.slash" : "star") {
            Haptics.tap()
            card.isStarred.toggle()
        }
        Button("Duplicate", systemImage: "plus.square.on.square") {
            Haptics.success()
            deck.duplicate(card, in: context)
        }
        let others = allDecks.filter { $0 !== deck }
        Menu("Move to…", systemImage: "folder") {
            ForEach(others) { target in
                Button(target.displayTitle) {
                    Haptics.success()
                    deck.move(card, to: target, in: context)
                }
            }
        }
        .disabled(others.isEmpty)
        Menu("Copy to…", systemImage: "doc.on.doc") {
            ForEach(others) { target in
                Button(target.displayTitle) {
                    Haptics.success()
                    deck.copy(card, to: target, in: context)
                }
            }
        }
        .disabled(others.isEmpty)
        Button("Move Earlier", systemImage: "arrow.up.left") { move(card, by: -1) }
            .disabled(index == 0)
        Button("Move Later", systemImage: "arrow.down.right") { move(card, by: 1) }
            .disabled(index == cards.count - 1)
        Button("Delete", systemImage: "trash", role: .destructive) { delete(card) }
    }

    private func open(_ card: Card) {
        lastEditedID = card.persistentModelID
        editor = EditorTarget(card: card)
    }

    private func startStudy(_ cards: [Card]) {
        Haptics.tap()
        study = StudyTarget(cards: cards)
    }

    private func addCard() {
        Haptics.success()
        let card = deck.newCard()
        context.saveReporting()
        open(card)
    }

    private func move(_ card: Card, by offset: Int) {
        var cards = deck.sortedCards
        guard let from = cards.firstIndex(where: { $0 === card }) else { return }
        let to = from + offset
        guard cards.indices.contains(to) else { return }
        Haptics.select()
        cards.swapAt(from, to)
        for (i, c) in cards.enumerated() { c.order = i }
    }

    private func delete(_ card: Card) {
        Haptics.warning()
        deck.deleteCard(card, in: context)
    }
}

/// An empty card slot: tapping anywhere inside it adds a card.
struct AddCardCell: View {
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                .foregroundStyle(.secondary)
                .background(RoundedRectangle(cornerRadius: 14).fill(.secondary.opacity(0.06)))
                .aspectRatio(5.0 / 3.0, contentMode: .fit)
                .overlay(Image(systemName: "plus").font(.system(size: 40)).foregroundStyle(.secondary))
                .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

/// Front of the card, with a small preview of the back in the corner and a star badge.
struct CardThumbnail: View {
    let card: Card
    var body: some View {
        CardFace(card: card, side: .front)
            .shadow(radius: 4)
            .overlay(alignment: .bottomTrailing) {
                CardFace(card: card, side: .back, corner: 6, inset: 3)
                    .frame(width: 84)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.secondary.opacity(0.4)))
                    .padding(8)
            }
            .overlay(alignment: .topTrailing) {
                if card.isStarred {
                    Image(systemName: "star.fill").foregroundStyle(.yellow)
                        .font(.title3).padding(10)
                }
            }
    }
}

struct StatChip: View {
    let value: Int
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Text("\(value)").font(.headline.monospacedDigit())
            Text(label).font(.subheadline)
        }
        .foregroundStyle(value > 0 ? color : .secondary)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Capsule().fill((value > 0 ? color : Color.secondary).opacity(0.15)))
    }
}
