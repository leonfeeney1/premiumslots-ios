import SwiftUI

@main
struct PremiumSlotsApp: App {
    @StateObject private var appState = AppState()
    @AppStorage("premiumslots.appearance") private var appearance = "dark"

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .preferredColorScheme(colorScheme)
        }
    }

    private var colorScheme: ColorScheme? {
        switch appearance {
        case "dark": return .dark
        case "light": return .light
        default: return nil
        }
    }
}
