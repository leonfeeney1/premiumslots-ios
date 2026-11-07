import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        TabView {
            CatalogView()
                .tabItem {
                    Label("Catalogue", systemImage: "square.grid.2x2.fill")
                }

            MySlotsView()
                .tabItem {
                    Label("My Slots", systemImage: "lock.shield.fill")
                }

            HowItWorksView()
                .tabItem {
                    Label("How it works", systemImage: "questionmark.circle.fill")
                }

            AdminView()
                .tabItem {
                    Label("Admin", systemImage: "person.badge.key.fill")
                }
                .badge(appState.adminPending.count)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
        .tint(.psCyan)
        // Onboarding gate, as on the web: after Clerk sign-in, if
        // WhatsApp or date of birth is missing, the user must finish
        // onboarding before using the app.
        .sheet(isPresented: $appState.needsOnboarding) {
            OnboardingView()
                .environmentObject(appState)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
