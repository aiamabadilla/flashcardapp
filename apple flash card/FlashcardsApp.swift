import SwiftUI
import SwiftData

@main
struct FlashcardsApp: App {
    var body: some Scene {
        WindowGroup {
            DeckListView()
                .preferredColorScheme(.light)   // white cards with black ink
        }
        .modelContainer(for: Deck.self)
    }
}
