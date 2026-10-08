import SwiftUI

struct CardEditor: View {
    let deck: Deck
    @Environment(\.dismiss) private var dismiss
    @State private var card: Card
    @State private var showingFront = true
    @State private var angle = 0.0

    init(deck: Deck, start: Card) {
        self.deck = deck
        _card = State(initialValue: start)
    }

    private var cards: [Card] { deck.sortedCards }
    private var index: Int { cards.firstIndex { $0 === card } ?? 0 }
    private let buttonWidth: CGFloat = 170

    var body: some View {
        let editing = Bindable(card)

        VStack(spacing: 24) {
            // Header: equal-width side slots keep the title truly centered.
            HStack {
                Button("Done") { Haptics.tap(); dismiss() }
                    .frame(width: 80, alignment: .leading)
                Spacer()
                VStack(spacing: 2) {
                    Text(showingFront ? "Front" : "Back").font(.headline)
                    Text("Card \(index + 1) of \(cards.count)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Color.clear.frame(width: 80, height: 1)
            }
            .padding(.horizontal)

            // The placeholder fixes the card's size; the canvas is overlaid so its
            // large intrinsic size can't stretch the layout.
            Color.clear
                .aspectRatio(5.0 / 3.0, contentMode: .fit)
                .overlay {
                    ZStack {
                        RoundedRectangle(cornerRadius: 18).fill(.white).shadow(radius: 10)
                        CardLines()
                        DrawingCanvas(data: showingFront ? editing.front : editing.back)
                            .id("\(ObjectIdentifier(card).hashValue)-\(showingFront)")
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                    }
                }
                .padding(.horizontal, 40)
                .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0))

            // Row 1: previous / rotate / next, all the same width.
            HStack(spacing: 16) {
                Button { go(to: index - 1) } label: {
                    Label("Previous", systemImage: "chevron.left").frame(width: buttonWidth)
                }
                .buttonStyle(.bordered)
                .disabled(index == 0)

                Button { flip() } label: {
                    Label("Rotate", systemImage: "arrow.triangle.2.circlepath").frame(width: buttonWidth)
                }
                .buttonStyle(.borderedProminent)

                Button { go(to: index + 1) } label: {
                    Label("Next", systemImage: "chevron.right")
                        .labelStyle(TrailingIconLabelStyle()).frame(width: buttonWidth)
                }
                .buttonStyle(.bordered)
                .disabled(index >= cards.count - 1)
            }
            .controlSize(.large)

            // Row 2: one button to add the next card.
            Button { addCard() } label: {
                Label("New Card", systemImage: "plus").frame(width: buttonWidth * 3 + 32)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .controlSize(.large)

            Spacer()
        }
        .padding(.top, 24)
    }

    private func go(to newIndex: Int) {
        guard cards.indices.contains(newIndex) else { return }
        Haptics.select()
        card = cards[newIndex]
        showingFront = true
        angle = 0
    }

    private func addCard() {
        Haptics.success()
        card = deck.newCard()
        showingFront = true
        angle = 0
    }

    private func flip() {
        Haptics.flip()
        withAnimation(.easeIn(duration: 0.18)) { angle = 90 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            showingFront.toggle()
            angle = -90
            withAnimation(.easeOut(duration: 0.18)) { angle = 0 }
        }
    }
}

struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) { configuration.title; configuration.icon }
    }
}

struct CardLines: View {
    var body: some View {
        Canvas { ctx, size in
            var y: CGFloat = 40
            while y < size.height {
                var line = Path()
                line.move(to: CGPoint(x: 16, y: y))
                line.addLine(to: CGPoint(x: size.width - 16, y: y))
                ctx.stroke(line, with: .color(.blue.opacity(0.18)), lineWidth: 1)
                y += 32
            }
        }
        .allowsHitTesting(false)
    }
}
