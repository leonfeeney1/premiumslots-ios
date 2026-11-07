import SwiftUI

@main
struct PremiumSlotsApp: App {
    @StateObject private var appState = AppState()
    // Default is System: the app follows the device setting until the
    // user picks Light or Dark in Settings, exactly as the web does
    // (localStorage theme, else prefers-color-scheme, else dark).
    @AppStorage("premiumslots.appearance") private var appearance = "system"

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .environmentObject(appState)
                    .preferredColorScheme(colorScheme)
                // Launch loading state: the website's HUD loader while
                // the stored session is re-validated, fading out over
                // 0.6s when the check finishes (web: fade after load
                // + 1500ms, removed after a further 600ms).
                if appState.isCheckingSession {
                    PSLoaderView()
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.6), value: appState.isCheckingSession)
            .task {
                await appState.checkSession()
                await appState.refreshCatalogue()
            }
        }
    }

    private var colorScheme: ColorScheme? {
        PSThemeMode(rawValue: appearance)?.colorScheme
    }
}
