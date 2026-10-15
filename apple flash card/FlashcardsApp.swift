import SwiftUI
import SwiftData

@main
struct FlashcardsApp: App {
    @AppStorage("appearance") private var appearance: Appearance = .system

    /// Built once. If the store can't be opened we show a recovery screen instead of crashing,
    /// and never delete the file ourselves.
    private let container: Result<ModelContainer, Error> = Result { try AppStore_.makeContainer() }

    var body: some Scene {
        WindowGroup {
            switch container {
            case .success(let container):
                DeckListView()
                    .preferredColorScheme(appearance.scheme)
                    .modelContainer(container)
            case .failure(let error):
                StoreErrorView(message: error.localizedDescription)
            }
        }
    }
}

/// Shown if the database can't be opened. The data file is left untouched.
struct StoreErrorView: View {
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 56)).foregroundStyle(.orange)
            Text("IMSTUDY couldn't open your data").font(.title2.bold())
            Text("Your decks have not been deleted. Close the app and open it again. If this keeps " +
                 "happening, reinstalling the latest update from TestFlight or the App Store keeps " +
                 "your data, and a backup file can always be restored.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Text(message).font(.footnote).foregroundStyle(.tertiary).multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: 560)
    }
}
