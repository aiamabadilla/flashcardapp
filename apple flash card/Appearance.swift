import SwiftUI

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    var scheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
    var title: String { rawValue.capitalized }
    var icon: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }
}

extension Color {
    /// Card paper: white in light mode, near-black in dark mode (like Notes).
    static func paper(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(white: 0.11) : .white
    }
}

struct AppearanceMenu: View {
    @AppStorage("appearance") private var appearance: Appearance = .system

    var body: some View {
        Menu {
            Picker("Appearance", selection: $appearance) {
                ForEach(Appearance.allCases) { Label($0.title, systemImage: $0.icon).tag($0) }
            }
        } label: {
            Label("Appearance", systemImage: appearance.icon)
        }
        .onChange(of: appearance) { Haptics.select() }
    }
}
