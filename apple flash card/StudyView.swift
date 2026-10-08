import SwiftUI

/// Shows each card's front; tap to flip to the back.
struct StudyView: View {
    let deck: Deck
    @Environment(\.dismiss) private var dismiss
    @State private var cards: [Card] = []
    @State private var index = 0
    @State private var showingBack = false
    @State private var angle = 0.0

    var body: some View {
        VStack(spacing: 24) {
            HStack {
                Button("Done") { dismiss() }
                Spacer()
                Text(cards.isEmpty ? "" : "\(index + 1) of \(cards.count)").font(.headline)
                Spacer()
                Button("Shuffle", systemImage: "shuffle") { cards.shuffle(); go(to: 0) }
            }
            .padding(.horizontal)

            if let card = current {
                ZStack {
                    RoundedRectangle(cornerRadius: 18).fill(.white).shadow(radius: 10)
                    CardLines()
                    DrawingImage(data: showingBack ? card.back : card.front, padding: 24)
                }
                .aspectRatio(5.0 / 3.0, contentMode: .fit)
                .padding(.horizontal, 40)
                .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0))
                .onTapGesture { flip() }

                Text(showingBack ? "Back — tap to flip" : "Front — tap to flip")
                    .font(.subheadline).foregroundStyle(.secondary)

                HStack(spacing: 24) {
                    Button { go(to: index - 1) } label: { Label("Previous", systemImage: "chevron.left") }
                        .disabled(index == 0)
                    Button { go(to: index + 1) } label: { Label("Next", systemImage: "chevron.right") }
                        .disabled(index >= cards.count - 1)
                }
                .buttonStyle(.borderedProminent)
                .font(.title3)
            }
            Spacer()
        }
        .padding(.top, 24)
        .onAppear { cards = deck.sortedCards }
    }

    private var current: Card? { cards.indices.contains(index) ? cards[index] : nil }

    private func go(to newIndex: Int) {
        guard cards.indices.contains(newIndex) else { return }
        index = newIndex
        showingBack = false
    }

    private func flip() {
        withAnimation(.easeIn(duration: 0.18)) { angle = 90 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            showingBack.toggle()
            angle = -90
            withAnimation(.easeOut(duration: 0.18)) { angle = 0 }
        }
    }
}
