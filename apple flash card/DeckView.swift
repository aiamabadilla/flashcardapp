import SwiftUI
import SwiftData

struct DeckView: View {
    @Bindable var deck: Deck
    @Environment(\.modelContext) private var context
    @State private var selected: Card?
    @State private var studying = false
    private let columns = [GridItem(.flexible(), spacing: 24),
                           GridItem(.flexible(), spacing: 24)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                TextField("Deck title", text: $deck.title)
                    .font(.largeTitle.bold())

                LazyVGrid(columns: columns, spacing: 24) {
                    ForEach(deck.sortedCards) { card in
                        CardThumbnail(card: card)
                            .onTapGesture { Haptics.tap(); selected = card }
                            .contextMenu { menu(for: card) }
                    }
                    AddCardCell { addCard() }
                }
            }
            .padding(32)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { Haptics.tap(); studying = true } label: {
                    Label("Study", systemImage: "rectangle.on.rectangle.angled")
                }
                .disabled(deck.cards.isEmpty)
            }
        }
        .fullScreenCover(item: $selected) { card in
            CardEditor(deck: deck, start: card)
        }
        .fullScreenCover(isPresented: $studying) {
            StudyView(deck: deck)
        }
    }

    @ViewBuilder
    private func menu(for card: Card) -> some View {
        let cards = deck.sortedCards
        let index = cards.firstIndex(where: { $0 === card }) ?? 0
        Button("Edit", systemImage: "pencil") { selected = card }
        Button("Move Earlier", systemImage: "arrow.up.left") { move(card, by: -1) }
            .disabled(index == 0)
        Button("Move Later", systemImage: "arrow.down.right") { move(card, by: 1) }
            .disabled(index == cards.count - 1)
        Button("Delete", systemImage: "trash", role: .destructive) { delete(card) }
    }

    private func addCard() {
        Haptics.success()
        selected = deck.newCard()
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
        deck.cards.removeAll { $0 === card }
        context.delete(card)
        deck.renumber()
    }
}

struct AddCardCell: View {
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                .foregroundStyle(.secondary)
                .aspectRatio(5.0 / 3.0, contentMode: .fit)
                .overlay(Image(systemName: "plus").font(.system(size: 40)))
        }
        .buttonStyle(.plain)
    }
}

/// Front of the card, with a small preview of the back in the corner.
struct CardThumbnail: View {
    let card: Card
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 14).fill(.white).shadow(radius: 4)
            DrawingImage(data: card.front)
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(Color(white: 0.95))
                RoundedRectangle(cornerRadius: 6).strokeBorder(.secondary.opacity(0.4))
                DrawingImage(data: card.back, padding: 3)
            }
            .aspectRatio(5.0 / 3.0, contentMode: .fit)
            .frame(width: 84)
            .padding(8)
        }
        .aspectRatio(5.0 / 3.0, contentMode: .fit)
    }
}
