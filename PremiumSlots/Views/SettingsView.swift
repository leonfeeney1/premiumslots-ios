import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("premiumslots.appearance") private var appearance = "dark"
    @AppStorage("premiumslots.notifications") private var notificationsEnabled = false
    @State private var showAuth = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    if appState.isLoggedIn, let user = appState.user {
                        HStack {
                            Text(user.name)
                                .font(.psHeadline)
                            Spacer()
                            Text(user.email)
                                .font(.psCaption)
                                .foregroundStyle(.psMuted)
                        }
                        if let balance = appState.walletBalance {
                            HStack {
                                Text("Wallet balance")
                                Spacer()
                                Text("KES \(balance)")
                                    .foregroundStyle(.psMuted)
                            }
                        }
                        if let referrals = appState.referralCount {
                            HStack {
                                Text("Referrals")
                                Spacer()
                                Text("\(referrals)")
                                    .foregroundStyle(.psMuted)
                            }
                        }
                        Button("Sign out", role: .destructive) {
                            Task { await appState.logout() }
                        }
                    } else {
                        Text("Sign in to see your slots, wallet and referrals on premiumslots.tech.")
                            .font(.psBody)
                            .foregroundStyle(.psMuted)
                        Button("Sign in or create an account") { showAuth = true }
                    }
                }

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
                        Text("Slots in rotation")
                        Spacer()
                        Text("\(appState.liveTotalSlots ?? Platform.liveTotalSlotsOnHomepage)")
                            .foregroundStyle(.psMuted)
                    }
                    HStack {
                        Text("Catalogue state")
                        Spacer()
                        Text(appState.liveState == .live ? "Live" : "Saved copy")
                            .foregroundStyle(.psMuted)
                    }
                    Button("Refresh live catalogue") {
                        Task { await appState.refreshCatalogue() }
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
                        RealLogoView(size: 44)
                        VStack(alignment: .leading) {
                            Text("PremiumSlots")
                                .font(.psHeadline)
                            Text("Version 2.0 (live API client)")
                                .font(.psCaption)
                                .foregroundStyle(.psMuted)
                        }
                    }
                    Link("Visit premiumslots.tech", destination: URL(string: "https://premiumslots.tech")!)
                    Text("Shared subscriptions. Live data comes from the /api/v1 endpoints once the backend blueprint is deployed; until then the app shows the saved catalogue and says so.")
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
            .navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden)
            .background(Color.psObsidian)
            .sheet(isPresented: $showAuth) { AuthView() }
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
}
