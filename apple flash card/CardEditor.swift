import SwiftUI
import SwiftData

struct CardEditor: View {
    let deck: Deck
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    @State private var card: Card
    @State private var showingFront = true
    @State private var angle = 0.0
    @State private var typing = false
    @State private var confirmingDelete = false
    @FocusState private var textFocused: Bool
    @StateObject private var viewport = Viewport()

    init(deck: Deck, start: Card) {
        self.deck = deck
        _card = State(initialValue: start)
    }

    private let buttonWidth: CGFloat = 170
    private var side: Side { showingFront ? .front : .back }

    var body: some View {
        let editing = Bindable(card)
        let cards = deck.sortedCards
        let index = cards.firstIndex { $0 === card } ?? 0

        VStack(spacing: typing ? 12 : 20) {
            header(index: index, count: cards.count)
            cardArea(editing)
            if typing {
                // Keep the card as large as possible above the keyboard.
                HStack(spacing: 16) {
                    Button { Haptics.tap(); scaleFont(0.9) } label: {
                        Label("Smaller", systemImage: "textformat.size.smaller").frame(width: buttonWidth)
                    }
                    .buttonStyle(.bordered)
                    Button { Haptics.tap(); toggleTyping() } label: {
                        Label("Done Typing", systemImage: "checkmark").frame(width: buttonWidth)
                    }
                    .buttonStyle(.borderedProminent)
                    Button { Haptics.tap(); scaleFont(1.1) } label: {
                        Label("Larger", systemImage: "textformat.size.larger").frame(width: buttonWidth)
                    }
                    .buttonStyle(.bordered)
                }
                .controlSize(.large)
            } else {
                controls(index: index, count: cards.count)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, typing ? 12 : 24)
        .animation(.easeInOut(duration: 0.2), value: typing)
    }

    // MARK: Header

    private func header(index: Int, count: Int) -> some View {
        // Equal-width side slots keep the title truly centered.
        HStack {
            Button("Done") { Haptics.tap(); dismiss() }
                .frame(width: 80, alignment: .leading)
            Spacer()
            VStack(spacing: 2) {
                Text(showingFront ? "Front" : "Back").font(.headline)
                Text("Card \(index + 1) of \(count)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(role: .destructive) { Haptics.tap(); confirmingDelete = true } label: {
                Label("Delete Card", systemImage: "trash").labelStyle(.iconOnly)
            }
            .frame(width: 80, alignment: .trailing)
            .confirmationDialog("Delete this card?", isPresented: $confirmingDelete,
                                titleVisibility: .visible) {
                Button("Delete Card", role: .destructive) { deleteCard() }
            }
        }
        .padding(.horizontal)
    }

    // MARK: Card

    private func cardArea(_ editing: Bindable<Card>) -> some View {
        let drawing = showingFront ? editing.front : editing.back
        let text = Binding(get: { card.text(side) }, set: { card.setText($0, side) })
        let boxBinding = Binding(get: { card.box(side) }, set: { card.setBox($0, side) })

        // The placeholder fixes the card's size; the content is overlaid so the
        // canvas's large intrinsic size can't stretch the layout.
        return Color.clear
            .aspectRatio(5.0 / 3.0, contentMode: .fit)
            .overlay {
                GeometryReader { geo in
                    ZStack {
                        RoundedRectangle(cornerRadius: 18).fill(Color.paper(scheme)).shadow(radius: 10)
                        if card.isLined(side) {
                            ZoomingLines(viewport: viewport)
                                .clipShape(RoundedRectangle(cornerRadius: 18))
                        }
                        if !typing, !text.wrappedValue.isEmpty {
                            ZoomingText(viewport: viewport, text: text.wrappedValue,
                                        box: boxBinding.wrappedValue, card: geo.size)
                                .clipShape(RoundedRectangle(cornerRadius: 18))
                        }
                        DrawingCanvas(data: drawing, viewport: viewport, isActive: !typing)
                            .id("\(ObjectIdentifier(card).hashValue)-\(showingFront)")
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                            .allowsHitTesting(!typing)
                        if typing {
                            TextBoxEditor(text: text, box: boxBinding, card: geo.size, focus: $textFocused)
                        }
                    }
                }
            }
            .padding(.horizontal, 40)
            .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0))
    }

    // MARK: Controls

    private func controls(index: Int, count: Int) -> some View {
        VStack(spacing: 16) {
            // Row 1: previous / rotate / next
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
                .disabled(index >= count - 1)
            }

            // Row 2: per-card options (lines and typed text apply to the side shown)
            HStack(spacing: 16) {
                toggleButton("Lines", icon: "text.justify", on: card.isLined(side), tint: .blue) {
                    card.toggleLines(side)
                }
                toggleButton("Text", icon: "keyboard", on: typing, tint: .blue) { toggleTyping() }
                toggleButton("Star", icon: card.isStarred ? "star.fill" : "star",
                             on: card.isStarred, tint: .yellow) {
                    card.isStarred.toggle()
                }
            }

            // Row 3: add the next card
            Button { addCard() } label: {
                Label("New Card", systemImage: "plus").frame(width: buttonWidth * 3 + 32)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        }
        .controlSize(.large)
    }

    private func toggleButton(_ title: String, icon: String, on: Bool, tint: Color,
                              action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Label(title, systemImage: icon).frame(width: buttonWidth)
        }
        .buttonStyle(.bordered)
        .tint(on ? tint : .gray)
    }

    // MARK: Actions

    private func scaleFont(_ factor: Double) {
        var b = card.box(side)
        b.size = min(max(b.size * factor, 0.012), 0.2)
        card.setBox(b, side)
    }

    private func toggleTyping() {
        if !typing { viewport.resetCanvasZoom() }   // position the box at 1x
        typing.toggle()
        if !typing { textFocused = false }
    }

    private func show(_ newCard: Card) {
        card = newCard
        showingFront = true
        angle = 0
        typing = false
    }

    private func go(to newIndex: Int) {
        let cards = deck.sortedCards
        guard cards.indices.contains(newIndex) else { return }
        Haptics.select()
        show(cards[newIndex])
    }

    private func addCard() {
        Haptics.success()
        let new = deck.newCard()
        try? context.save()   // give the card its permanent identity right away
        show(new)
    }

    private func deleteCard() {
        Haptics.warning()
        let doomed = card
        let all = deck.sortedCards
        let index = all.firstIndex { $0 === doomed } ?? 0
        let neighbor = all.indices.contains(index + 1) ? all[index + 1]
                     : (index > 0 ? all[index - 1] : nil)
        if let neighbor { show(neighbor) }
        deck.cards.removeAll { $0 === doomed }
        context.delete(doomed)
        deck.renumber()
        if neighbor == nil { dismiss() }
    }

    private func flip() {
        Haptics.flip()
        withAnimation(.easeIn(duration: 0.18)) { angle = 90 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            showingFront.toggle()
            typing = false
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
