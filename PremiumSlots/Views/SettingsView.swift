import SwiftUI

// MARK: - Settings, v4
// HIG pass: grouped Form, consistent section headers, 44pt touch
// targets, accessibility labels, safe-area padding. Content is the
// same as v3; Fix #4 adds the account, wallet, help and security
// screens linked from here. The Support section uses the WhatsApp
// number from the live homepage, and the Admin row opens the admin
// area when an admin session exists, otherwise the admin sign-in.
// There is no email support row: no support email address appears in
// the workspace docs, so none is shown rather than guessing one.

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("premiumslots.appearance") private var appearance = "system"
    @AppStorage("premiumslots.notifications") private var notificationsEnabled = false
    @State private var showAuth = false

    private var supportWhatsAppURL: URL {
        URL(string: "https://wa.me/254747412440?text=Hi%20PremiumSlots%2C%20I%20need%20help%20with%20my%20subscription.")!
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if appState.isLoggedIn, let user = appState.user {
                        HStack {
                            Text(user.name)
                                .font(.psHeadline)
                            Spacer()
                            Text(user.email)
                                .font(.psCaption)
                                .foregroundStyle(.psMuted)
                                .lineLimit(1)
                        }
                        if let balance = appState.walletBalance {
                            HStack {
                                Text("Wallet balance")
                                Spacer()
                                Text("KES \(balance)")
                                    .font(.psMono)
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
                        .accessibilityLabel("Sign out of PremiumSlots")
                    } else {
                        Text("Sign in to see your slots, wallet and referrals on premiumslots.tech.")
                            .font(.psBody)
                            .foregroundStyle(.psMuted)
                        Button("Sign in or create an account") { showAuth = true }
                    }
                } header: {
                    Text("Account")
                }

                Section {
                    NavigationLink {
                        DashboardRootView()
                    } label: {
                        Label("Dashboard", systemImage: "house.fill")
                            .font(.psBody)
                    }
                    NavigationLink {
                        WalletRootView()
                    } label: {
                        Label("Wallet", systemImage: "wallet.pass.fill")
                            .font(.psBody)
                    }
                    NavigationLink {
                        GiftCardsRootView()
                    } label: {
                        Label("Gift cards", systemImage: "gift.fill")
                            .font(.psBody)
                    }
                    NavigationLink {
                        StoreRootView()
                    } label: {
                        Label("Rewards store", systemImage: "bag.fill")
                            .font(.psBody)
                    }
                    NavigationLink {
                        LoyaltyRootView()
                    } label: {
                        Label("Loyalty", systemImage: "star.fill")
                            .font(.psBody)
                    }
                    NavigationLink {
                        AchievementsRootView()
                    } label: {
                        Label("Achievements", systemImage: "trophy.fill")
                            .font(.psBody)
                    }
                    NavigationLink {
                        LeaderboardRootView()
                    } label: {
                        Label("Leaderboard", systemImage: "list.number")
                            .font(.psBody)
                    }
                    NavigationLink {
                        WishlistRootView()
                    } label: {
                        Label("Wishlist", systemImage: "star")
                            .font(.psBody)
                    }
                    NavigationLink {
                        HelpRootView()
                    } label: {
                        Label("Help centre", systemImage: "questionmark.circle.fill")
                            .font(.psBody)
                    }
                    NavigationLink {
                        BlogRootView()
                    } label: {
                        Label("Blog", systemImage: "newspaper.fill")
                            .font(.psBody)
                    }
                    NavigationLink {
                        TicketsRootView()
                    } label: {
                        Label("Support tickets", systemImage: "envelope.fill")
                            .font(.psBody)
                    }
                    NavigationLink {
                        NotificationsRootView()
                    } label: {
                        Label("Notifications", systemImage: "bell.fill")
                            .font(.psBody)
                    }
                    NavigationLink {
                        AccountRootView()
                    } label: {
                        Label("Account", systemImage: "person.fill")
                            .font(.psBody)
                    }
                    NavigationLink {
                        ReceiptsPickerView()
                    } label: {
                        Label("Receipts", systemImage: "doc.text.fill")
                            .font(.psBody)
                    }
                } header: {
                    Text("Features")
                }

                Section {
                    Picker("Theme", selection: $appearance) {
                        Text("Dark").tag("dark")
                        Text("Light").tag("light")
                        Text("System").tag("system")
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Appearance theme")
                    Text("Dark-first design. Light mode follows the same blue and cyan brand.")
                        .font(.psCaption)
                        .foregroundStyle(.psMuted)
                } header: {
                    Text("Appearance")
                }

                Section {
                    Toggle("Slot and waitlist updates", isOn: $notificationsEnabled)
                        .tint(.psCyan)
                    Text("Off by default. This build does not send notifications yet; the switch is kept for the connected backend.")
                        .font(.psCaption)
                        .foregroundStyle(.psMuted)
                } header: {
                    Text("Notifications")
                }

                Section {
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
                        Text(appState.liveState == .live ? "Live" : "Saved catalogue")
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
                } header: {
                    Text("Catalogue")
                }

                Section {
                    Link(destination: supportWhatsAppURL) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("WhatsApp support")
                                    .font(.psBody)
                                Text("+254 747 412 440")
                                    .font(.psCaption)
                                    .foregroundStyle(.psMuted)
                            }
                        } icon: {
                            Image(systemName: "message.fill")
                        }
                    }
                    .accessibilityLabel("WhatsApp support, plus 254 747 412 440")
                    NavigationLink {
                        HelpRootView()
                    } label: {
                        Label("Help and FAQ", systemImage: "questionmark.circle.fill")
                            .font(.psBody)
                    }
                    NavigationLink {
                        TicketsRootView()
                    } label: {
                        Label("My tickets", systemImage: "ticket.fill")
                            .font(.psBody)
                    }
                    Text("For a slot problem, include the platform name and your M-PESA code.")
                        .font(.psCaption)
                        .foregroundStyle(.psMuted)
                } header: {
                    Text("Support")
                }

                Section {
                    NavigationLink {
                        AdminView()
                    } label: {
                        Label(
                            appState.isAdminLoggedIn ? "Admin dashboard" : "Admin sign-in",
                            systemImage: "person.badge.key.fill"
                        )
                        .font(.psBody)
                    }
                    Text("Admin uses a separate sign-in from a customer account.")
                        .font(.psCaption)
                        .foregroundStyle(.psMuted)
                } header: {
                    Text("Admin")
                }

                Section {
                    NavigationLink {
                        FullPrivacyPolicyView()
                    } label: {
                        Label("Privacy policy", systemImage: "hand.raised.fill")
                            .font(.psBody)
                    }
                    NavigationLink {
                        FullTermsView()
                    } label: {
                        Label("Terms of service", systemImage: "doc.plaintext.fill")
                            .font(.psBody)
                    }
                    Text("The full privacy policy and terms of service, as published on premiumslots.tech.")
                        .font(.psCaption)
                        .foregroundStyle(.psMuted)
                } header: {
                    Text("Legal")
                }

                Section {
                    HStack(spacing: 12) {
                        RealLogoView(size: 44)
                        VStack(alignment: .leading) {
                            Text("PremiumSlots")
                                .font(.psHeadline)
                            Text("Shared subscriptions")
                                .font(.psCaption)
                                .foregroundStyle(.psMuted)
                        }
                    }
                    Link("Visit premiumslots.tech", destination: URL(string: "https://premiumslots.tech")!)
                    Text("Live data comes from the live service when it is reachable. Otherwise the app shows the saved catalogue and labels it as saved.")
                        .font(.psCaption)
                        .foregroundStyle(.psMuted)
                } header: {
                    Text("About")
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollIndicators(.hidden)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden)
            .adminScreenBackground()
            .sheet(isPresented: $showAuth) {
                AuthView()
                    .psSheetDetents()
            }
            .safeAreaPadding(.bottom, 8)
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
}
