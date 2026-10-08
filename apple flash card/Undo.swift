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

// MARK: - Deleting (moves to Recently Deleted) and restoring

extension Deck {
    /// Puts a card back at its old position, shifting later cards along.
    func restoreCard(_ card: Card) {
        for other in liveCards where other.order >= card.order { other.order += 1 }
        card.deletedAt = 0
    }

    /// Moves a card to Recently Deleted and offers to undo.
    @MainActor func deleteCard(_ card: Card, in context: ModelContext) {
        card.deletedAt = Date().timeIntervalSince1970
        renumber()
        UndoCenter.shared.offer("Card deleted") { [self] in
            restoreCard(card)
            try? context.save()
        }
    }
}

extension ModelContext {
    /// Moves a deck (and its cards) to Recently Deleted and offers to undo.
    @MainActor func deleteDeck(_ deck: Deck) {
        deck.deletedAt = Date().timeIntervalSince1970
        UndoCenter.shared.offer("Deck deleted") { [self] in
            deck.deletedAt = 0
            try? save()
        }
    }
}
