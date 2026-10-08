import UIKit

enum Haptics {
    /// Light tap for ordinary buttons.
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    /// Firmer tap for flipping a card.
    static func flip() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    /// Tick when moving between cards.
    static func select() { UISelectionFeedbackGenerator().selectionChanged() }
    /// Confirmation, e.g. a new card or deck was created.
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    /// Destructive actions.
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}
