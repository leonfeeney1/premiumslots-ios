import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("premiumslots.appearance") private var appearance = "dark"
    @AppStorage("premiumslots.notifications") private var notificationsEnabled = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: $appearance) {
                        Text("Dark").tag("dark")
                        Text("Light").tag("light")
                        Text("System").tag("system")
                    }
                    .pickerStyle(.segmented)
                    Text("Dark-first design. Light mode follows the same blue and cyan brand.")
                        .font(.psCaption)
                        .foregroundStyle(.psMuted)
                }

                Section("Notifications") {
                    Toggle("Slot and waitlist updates", isOn: $notificationsEnabled)
                        .tint(.psCyan)
                    Text("Off by default. This build does not send notifications yet; the switch is kept for the connected backend.")
                        .font(.psCaption)
                        .foregroundStyle(.psMuted)
                }

                Section("Catalogue") {
                    HStack {
                        Text("Platforms")
                        Spacer()
                        Text("\(appState.platformCount)")
                            .foregroundStyle(.psMuted)
                    }
                    HStack {
                        Text("Slots in rotation (homepage)")
                        Spacer()
                        Text("\(appState.liveTotalSlots ?? Platform.liveTotalSlotsOnHomepage)")
                            .foregroundStyle(.psMuted)
                    }
                    Button("Refresh live total") {
                        Task { await appState.refreshLiveTotal() }
                    }
                    if let message = appState.refreshMessage {
                        Text(message)
                            .font(.psCaption)
                            .foregroundStyle(.psMuted)
                    }
                    Text("Stock last verified \(Platform.stockVerifiedDate). Homepage checked \(Platform.homepageCheckedDate).")
                        .font(.psCaption)
                        .foregroundStyle(.psMuted)
                }

                Section("About") {
                    HStack(spacing: 12) {
                        ShieldLogoView(size: 44)
                        VStack(alignment: .leading) {
                            Text("PremiumSlots")
                                .font(.psHeadline)
                            Text("Version 1.0 (client only)")
                                .font(.psCaption)
                                .foregroundStyle(.psMuted)
                        }
                    }
                    Link("Visit premiumslots.tech", destination: URL(string: "https://premiumslots.tech")!)
                    Text("Shared subscriptions. This app is a client only: no backend is connected yet, and orders are stored on this device.")
                        .font(.psCaption)
                        .foregroundStyle(.psMuted)
                }

                Section("Support") {
                    Link("Support on premiumslots.tech", destination: URL(string: "https://premiumslots.tech")!)
                    Text("For a slot problem, include the platform name and your M-PESA code.")
                        .font(.psCaption)
                        .foregroundStyle(.psMuted)
                }
            }
            .navigationTitle("Settings")
            .scrollContentBackground(.hidden)
            .background(Color.psObsidian)
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
}
