import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    static let storageKey = "appAppearance"

    case automatic
    case light
    case dark

    var id: Self { self }

    var title: String {
        switch self {
        case .automatic:
            return "자동"
        case .light:
            return "라이트"
        case .dark:
            return "다크"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .automatic:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

@main
struct VPNRouterApp: App {
    @NSApplicationDelegateAdaptor(ApplicationDelegate.self)
    private var applicationDelegate

    @AppStorage(AppAppearance.storageKey)
    private var appAppearanceRawValue = AppAppearance.automatic.rawValue

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(
                    AppAppearance(rawValue: appAppearanceRawValue)?.colorScheme
                )
        }
        .windowResizability(.contentMinSize)
    }
}
