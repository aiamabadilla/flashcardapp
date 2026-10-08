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

struct DeckView: View {
    @Bindable var deck: Deck
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    enum Filter { case all, starred }
    @State private var filter: Filter = .all
    @State private var confirmingDelete = false

    // Covers are presented with wrapper items that have their own stable IDs, never
    // the model's identity: a new card's identity changes when SwiftData first saves
    // it, which used to make the editor close and reopen mid-writing.
    @State private var editor: EditorTarget?
    @State private var study: StudyTarget?

    private let columns = [GridItem(.flexible(), spacing: 24),
                           GridItem(.flexible(), spacing: 24)]

    var body: some View {
        let all = deck.sortedCards
        let starred = all.filter(\.isStarred)
        let due = deck.dueCards
        let visible = filter == .all ? all : starred

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
                    ForEach(visible) { card in
                        CardThumbnail(card: card)
                            .onTapGesture { Haptics.tap(); open(card) }
                            .contextMenu { menu(for: card, in: all) }
                    }
                    if filter == .all {
                        AddCardCell { addCard() }
                    }
                }

                if filter == .starred && starred.isEmpty {
                    ContentUnavailableView("No Starred Cards", systemImage: "star",
                                           description: Text("Tap Star in the card editor, or long-press a card."))
                }
            }
            .padding(32)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                AppearanceMenu()
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
        .fullScreenCover(item: $editor) { CardEditor(deck: deck, start: $0.card) }
        .fullScreenCover(item: $study) { StudyView(cards: $0.cards) }
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
        Button("Move Earlier", systemImage: "arrow.up.left") { move(card, by: -1) }
            .disabled(index == 0)
        Button("Move Later", systemImage: "arrow.down.right") { move(card, by: 1) }
            .disabled(index == cards.count - 1)
        Button("Delete", systemImage: "trash", role: .destructive) { delete(card) }
    }

    private func open(_ card: Card) {
        editor = EditorTarget(card: card)
    }

    private func startStudy(_ cards: [Card]) {
        Haptics.tap()
        study = StudyTarget(cards: cards)
    }

    private func addCard() {
        Haptics.success()
        let card = deck.newCard()
        try? context.save()
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
