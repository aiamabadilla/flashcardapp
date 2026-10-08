import SwiftUI
import SwiftData
import Combine

/// Holds the most recent undoable action and offers it for a few seconds, like a
/// "Card deleted — Undo" banner. One shared instance so any screen can show it.
@MainActor final class UndoCenter: ObservableObject {
    static let shared = UndoCenter()

    @Published private(set) var message: String?
    private var action: (() -> Void)?
    private var timer: Task<Void, Never>?

    func offer(_ message: String, undo: @escaping () -> Void) {
        action = undo
        self.message = message
        timer?.cancel()
        timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(7))
            if !Task.isCancelled { self?.clear() }
        }
    }

    func perform() {
        let run = action
        clear()
        run?()
        Haptics.success()
    }

    func clear() {
        timer?.cancel()
        message = nil
        action = nil
    }
}

private struct UndoBannerModifier: ViewModifier {
    @ObservedObject private var center = UndoCenter.shared
    let bottom: CGFloat

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let message = center.message {
                HStack(spacing: 16) {
                    Image(systemName: "trash").foregroundStyle(.secondary)
                    Text(message).font(.headline)
                    Button("Undo") { center.perform() }
                        .font(.headline)
                        .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal, 20).padding(.vertical, 12)
                .background(.regularMaterial, in: Capsule())
                .shadow(radius: 8)
                .padding(.bottom, bottom)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: center.message)
    }
}

extension View {
    /// Shows the "Undo" banner for the latest delete. `bottom` keeps it clear of toolbars.
    func undoBanner(bottom: CGFloat = 28) -> some View {
        modifier(UndoBannerModifier(bottom: bottom))
    }
}

// MARK: - Deleting with undo

extension Card {
    /// A free-standing copy (not in any context) used to bring a deleted card back.
    func detachedCopy() -> Card {
        let c = Card(order: order)
        c.front = front; c.back = back
        c.frontText = frontText; c.backText = backText
        c.frontLined = frontLined; c.backLined = backLined
        c.isStarred = isStarred
        c.frontBoxX = frontBoxX; c.frontBoxY = frontBoxY; c.frontBoxW = frontBoxW; c.frontBoxSize = frontBoxSize
        c.backBoxX = backBoxX; c.backBoxY = backBoxY; c.backBoxW = backBoxW; c.backBoxSize = backBoxSize
        c.textItemsJSON = textItemsJSON
        c.imageItemsJSON = imageItemsJSON
        c.leitnerBox = leitnerBox; c.dueTime = dueTime
        c.reviewCount = reviewCount; c.correctCount = correctCount; c.lastReviewed = lastReviewed
        return c
    }
}

extension Deck {
    func detachedCopy() -> Deck {
        let d = Deck(title: title)
        d.created = created
        d.cards = cards.map { $0.detachedCopy() }
        return d
    }

    /// Puts a card back at its old position, shifting later cards along.
    func insertCard(_ card: Card) {
        for other in cards where other.order >= card.order { other.order += 1 }
        cards.append(card)
    }

    /// Deletes a card and offers to undo it.
    @MainActor func deleteCard(_ card: Card, in context: ModelContext) {
        let copy = card.detachedCopy()
        cards.removeAll { $0 === card }
        context.delete(card)
        renumber()
        UndoCenter.shared.offer("Card deleted") { [self] in
            insertCard(copy)
            try? context.save()
        }
    }
}

extension ModelContext {
    /// Deletes a deck (and its cards) and offers to undo it.
    @MainActor func deleteDeck(_ deck: Deck) {
        let copy = deck.detachedCopy()
        delete(deck)
        UndoCenter.shared.offer("Deck deleted") { [self] in
            insert(copy)
            try? save()
        }
    }
}
