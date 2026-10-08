import SwiftUI
import SwiftData

@main
struct FlashcardsApp: App {
    @AppStorage("appearance") private var appearance: Appearance = .system

    var body: some Scene {
        WindowGroup {
            DeckListView()
                .preferredColorScheme(appearance.scheme)
        }
        .modelContainer(for: Deck.self)
    }
}
