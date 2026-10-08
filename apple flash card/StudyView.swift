import SwiftUI

/// Shows each card's front; tap to flip to the back.
struct StudyView: View {
    @State private var cards: [Card]
    @Environment(\.dismiss) private var dismiss
    @State private var index = 0
    @State private var showingBack = false
    @State private var angle = 0.0

    init(cards: [Card]) { _cards = State(initialValue: cards) }

    var body: some View {
        VStack(spacing: 24) {
            HStack {
                Button("Done") { Haptics.tap(); dismiss() }
                    .frame(width: 100, alignment: .leading)
                Spacer()
                Text(cards.isEmpty ? "" : "\(index + 1) of \(cards.count)").font(.headline)
                Spacer()
                Button("Shuffle", systemImage: "shuffle") { Haptics.tap(); cards.shuffle(); go(to: 0) }
                    .frame(width: 100, alignment: .trailing)
            }
            .padding(.horizontal)

            if let card = current {
                CardFace(card: card, side: showingBack ? .back : .front, corner: 18, inset: 24)
                    .shadow(radius: 10)
                    .padding(.horizontal, 40)
                    .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0))
                    .onTapGesture { flip() }

                Text(showingBack ? "Back — tap to flip" : "Front — tap to flip")
                    .font(.subheadline).foregroundStyle(.secondary)

                HStack(spacing: 24) {
                    Button { go(to: index - 1) } label: {
                        Label("Previous", systemImage: "chevron.left").frame(width: 170)
                    }
                    .disabled(index == 0)
                    Button { go(to: index + 1) } label: {
                        Label("Next", systemImage: "chevron.right")
                            .labelStyle(TrailingIconLabelStyle()).frame(width: 170)
                    }
                    .disabled(index >= cards.count - 1)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            Spacer()
        }
        .padding(.top, 24)
    }

    private var current: Card? { cards.indices.contains(index) ? cards[index] : nil }

    private func go(to newIndex: Int) {
        guard cards.indices.contains(newIndex) else { return }
        Haptics.select()
        index = newIndex
        showingBack = false
    }

    private func flip() {
        Haptics.flip()
        withAnimation(.easeIn(duration: 0.18)) { angle = 90 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            showingBack.toggle()
            angle = -90
            withAnimation(.easeOut(duration: 0.18)) { angle = 0 }
        }
    }
}
