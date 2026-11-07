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

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
        .tint(.psCyan)
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
