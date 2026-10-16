import SwiftUI
import SwiftData
import UniformTypeIdentifiers

@main
struct FlashcardsApp: App {
    @AppStorage("appearance") private var appearance: Appearance = .system
    @State private var openedMessage: String?

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
                    // Tapping a .imstudy backup in Files, AirDrop or Mail opens it here.
                    .onOpenURL { url in openedMessage = Self.restore(url, into: container) }
                    .alert("Backup", isPresented: Binding(get: { openedMessage != nil },
                                                          set: { if !$0 { openedMessage = nil } })) {
                        Button("OK") { openedMessage = nil }
                    } message: { Text(openedMessage ?? "") }
            case .failure(let error):
                StoreErrorView(message: error.localizedDescription)
            }
        }
    }
}

extension FlashcardsApp {
    /// Restores a backup the person opened from outside the app. Only `.imstudy` files are taken.
    @MainActor
    static func restore(_ url: URL, into container: ModelContainer) -> String {
        guard url.isFileURL, url.pathExtension.lowercased() == "imstudy" else {
            return "IMSTUDY can only open .imstudy backup files."
        }
        do {
            let r = try Backup.importArchive(from: url, into: container.mainContext)
            Haptics.success()
            return "Restored \(plural(r.decks, "deck")) with \(plural(r.cards, "card"))."
        } catch {
            Haptics.warning()
            return error.localizedDescription
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
