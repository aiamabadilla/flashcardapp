import SwiftUI

/// A study session with spaced repetition. Flip a card, then mark whether you knew it.
/// Cards you miss come back a few cards later until you know them; each answer is
/// recorded on the card to schedule its next review.
struct StudyView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var queue: [Card]
    private let total: Int
    @State private var showingBack = false
    @State private var angle = 0.0
    @State private var known = 0
    @State private var missedOnce: Set<ObjectIdentifier> = []
    @State private var shownAt = Date()
    @ObservedObject private var log = StudyLog.shared

    let deck: Deck
    @State private var editing: EditorTarget?

    init(cards: [Card], deck: Deck) {
        self.deck = deck
        _queue = State(initialValue: cards)
        total = cards.count
    }

    private var current: Card? { queue.first }
    private var firstTry: Int { total - missedOnce.count }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 24) {
            header

            if let card = current {
                ProgressView(value: Double(known), total: Double(max(total, 1)))
                    .padding(.horizontal, 40)

                CardFace(card: card, side: showingBack ? .back : .front, corner: 18, inset: 24)
                    .shadow(radius: 10)
                    .padding(.horizontal, 40)
                    .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0))
                    .onTapGesture { flip() }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(showingBack ? "Answer side of card" : "Question side of card")
                    .accessibilityHint("Double tap to flip")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { flip() }

                if showingBack {
                    HStack(spacing: 24) {
                        Button { answer(known: false) } label: {
                            Label("Don't Know", systemImage: "xmark").frame(width: 200)
                        }
                        .tint(.red)
                        .keyboardShortcut(.leftArrow, modifiers: [])
                        Button { answer(known: true) } label: {
                            Label("Know It", systemImage: "checkmark").frame(width: 200)
                        }
                        .tint(.green)
                        .keyboardShortcut(.rightArrow, modifiers: [])
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else {
                    Text("Tap the card to reveal the answer")
                        .font(.subheadline).foregroundStyle(.secondary)
                    // Space flips from a hardware keyboard; hidden so it takes no room.
                    Button("Flip") { flip() }
                        .keyboardShortcut(.space, modifiers: [])
                        .frame(width: 0, height: 0).opacity(0)
                        .accessibilityHidden(true)
                }
            } else {
                summary
            }
            Spacer()
        }
        .padding(.top, 24)
        .fullScreenCover(item: $editing) { CardEditor(deck: deck, start: $0.card) }
    }

    private var header: some View {
        HStack {
            Button("Done") { Haptics.tap(); dismiss() }
                .keyboardShortcut(.escape, modifiers: [])
                .frame(width: 100, alignment: .leading)
            Spacer()
            Text(current == nil ? "Session Complete" : "\(known) of \(total) known")
                .font(.headline)
            Spacer()
            if let card = current {
                HStack(spacing: 18) {
                    Button { Haptics.select(); card.isStarred.toggle() } label: {
                        Image(systemName: card.isStarred ? "star.fill" : "star")
                            .foregroundStyle(card.isStarred ? .yellow : .accentColor)
                    }
                    .accessibilityLabel(card.isStarred ? "Unstar card" : "Star card")
                    Button { Haptics.tap(); editing = EditorTarget(card: card) } label: {
                        Image(systemName: "pencil")
                    }
                    .accessibilityLabel("Edit card")
                }
                .font(.title3)
                .frame(width: 100, alignment: .trailing)
            } else {
                Color.clear.frame(width: 100, height: 1)
            }
        }
        .padding(.horizontal)
    }

    private var summary: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64)).foregroundStyle(.green)
            Text(total == 0 ? "Nothing to review" : (total == 1 ? "1 card reviewed" : "All \(total) cards reviewed"))
                .font(.title2.bold())
            if total > 0 {
                Text("\(firstTry) right on the first try · \(missedOnce.count) needed another go")
                    .foregroundStyle(.secondary)
                Label("\(plural(log.currentStreak, "day")) streak", systemImage: "flame.fill")
                    .font(.title3.bold()).foregroundStyle(.orange)
                Text("Cards you knew will come back after a longer break. Missed cards stay due.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding(.horizontal, 60)
            }
            Button("Done") { Haptics.tap(); dismiss() }
                .buttonStyle(.borderedProminent).controlSize(.large)
        }
        .padding(.top, 80)
    }

    private func answer(known isKnown: Bool) {
        guard let card = current else { return }
        card.review(known: isKnown)
        // Time on the card, capped so leaving the app open doesn't inflate study time.
        log.record(known: isKnown, seconds: min(Date().timeIntervalSince(shownAt), 60))
        shownAt = Date()
        queue.removeFirst()
        if isKnown {
            Haptics.success()
            known += 1
        } else {
            Haptics.warning()
            missedOnce.insert(ObjectIdentifier(card))
            queue.insert(card, at: min(3, queue.count))   // see it again in a few cards
        }
        showingBack = false
        angle = 0
    }

    private func flip() {
        Haptics.flip()
        if reduceMotion { showingBack.toggle(); return }
        withAnimation(.easeIn(duration: 0.18)) { angle = 90 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            showingBack.toggle()
            angle = -90
            withAnimation(.easeOut(duration: 0.18)) { angle = 0 }
        }
    }
}
