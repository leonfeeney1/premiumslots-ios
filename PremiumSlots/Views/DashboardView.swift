import SwiftUI

// MARK: - Dashboard, Fix #4
// The logged-in home dashboard from checklist 1.1: subscriptions,
// FinancialLedger (last 50), waitlist positions, unread notification
// count and the global alert banner, from GET /api/v1/me/dashboard.
// Hero, stats strip, marquee, process and rankings are in-app
// sections; their counts come from GET /api/v1/services. Community
// suggestions come from GET/POST /api/v1/suggestions.
// No NavigationStack here: this view is pushed from Settings, so it
// uses the parent stack. No emojis, SF Symbols only.

struct DashboardRootView: View {
    @EnvironmentObject private var appState: AppState
    @State private var dashboard: DashDashboardResponse?
    @State private var services: ServicesResponse?
    @State private var suggestions: [DashSuggestion] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var suggestionName = ""
    @State private var suggestionEmail = ""
    @State private var suggestionMessage: String?
    @State private var isSubmittingSuggestion = false
    @State private var showAuth = false

    var body: some View {
        List {
            if let alert = dashboard?.global_alert, !alert.isEmpty {
                Label(alert, systemImage: "megaphone.fill")
                    .font(.psBody)
                    .foregroundStyle(.psAmber)
                    .listRowBackground(Color.psSurface)
                    .accessibilityLabel("Announcement: \(alert)")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    LogoLockupView(height: 30)
                    Text("Shared subscriptions, one slot at a time.")
                        .font(.psTitle)
                    Text("PremiumSlots sells slots on shared subscriptions. You pay by M-PESA, your code is verified, and you get your own profile on the account through an encrypted vault.")
                        .font(.psBody)
                        .foregroundStyle(.psMuted)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            Section("At a glance") {
                statRow(label: "Platforms", value: "\(services?.platforms ?? appState.platformCount)")
                statRow(label: "Slots in rotation", value: "\(services?.slots_in_rotation ?? appState.liveTotalSlots ?? Platform.liveTotalSlotsOnHomepage)")
                statRow(label: "Active slots", value: "\(dashboard?.approved_count ?? 0)")
                statRow(label: "Unread notifications", value: "\(dashboard?.unread_count ?? 0)")
            }

            Section {
                Text("SECURE M-PESA CHECKOUT  /  INSTANT DELIVERY  /  ENCRYPTED VAULT")
                    .font(.psCaption)
                    .foregroundStyle(.psCyan)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .accessibilityLabel("Secure M-PESA checkout, instant delivery, encrypted vault")
            }

            Section("How it works") {
                dashStep(number: "1", title: "Pick a platform", text: "Choose a platform from the catalogue and check the price and slots left.")
                dashStep(number: "2", title: "Pay by M-PESA", text: "Send the exact amount to PayBill 400200, account 1192526. Keep the transaction code from your confirmation message.")
                dashStep(number: "3", title: "Submit your code", text: "Enter the 10-letter-and-number M-PESA code in checkout. The team verifies it and approves your slot.")
                dashStep(number: "4", title: "Get your details", text: "Your vault details appear in My Slots once your order is Active. 1 slot = 1 device, so use it on your own device only.")
            }

            if let ranked = rankedServices, !ranked.isEmpty {
                Section("Most in demand") {
                    ForEach(Array(ranked.enumerated()), id: \.element.id) { index, service in
                        HStack {
                            Text("\(index + 1)")
                                .font(.psHeadline)
                                .foregroundStyle(.psCyan)
                                .frame(width: 24)
                                .accessibilityHidden(true)
                            Text(service.name)
                                .font(.psBody)
                            Spacer()
                            Text("\(service.waitlist_count ?? 0) waiting")
                                .font(.psCaption)
                                .foregroundStyle(.psMuted)
                        }
                        .accessibilityLabel("\(service.name), \(service.waitlist_count ?? 0) people waiting")
                    }
                }
            }

            if !appState.isLoggedIn {
                Section {
                    PSCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Sign in for your dashboard")
                                .font(.psHeadline)
                            Text("Your subscriptions, ledger, waitlist positions and notifications live on your PremiumSlots account.")
                                .font(.psBody)
                                .foregroundStyle(.psMuted)
                            Button("Sign in") { showAuth = true }
                                .psPrimary()
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            } else if let loadError {
                Section {
                    PSErrorState(message: loadError) {
                        Task { await load() }
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            } else if isLoading && dashboard == nil {
                Section {
                    HStack {
                        Spacer()
                        PSRingSpinner(diameter: 28, lineWidth: 3)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            } else if let dashboard {
                Section("My subscriptions") {
                    if dashboard.subscriptions.isEmpty {
                        Text("No subscriptions yet. Browse the catalogue to buy your first slot.")
                            .font(.psBody)
                            .foregroundStyle(.psMuted)
                    } else {
                        ForEach(dashboard.subscriptions) { sub in
                            let live = LiveSubscription(sub)
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(sub.service_requested)
                                        .font(.psBody)
                                    Text("Order #\(sub.id) · KES \(sub.amount_due)")
                                        .font(.psCaption)
                                        .foregroundStyle(.psMuted)
                                }
                                Spacer()
                                PSStatusPill(
                                    text: live.orderStatus.rawValue,
                                    systemImage: live.orderStatus.systemImage,
                                    tint: live.orderStatus == .active ? .psSuccess : .psAmber
                                )
                            }
                            .accessibilityLabel("\(sub.service_requested), order \(sub.id), \(live.orderStatus.rawValue)")
                        }
                    }
                }

                Section("Recent ledger") {
                    if dashboard.ledger.isEmpty {
                        Text("No ledger entries yet.")
                            .font(.psBody)
                            .foregroundStyle(.psMuted)
                    } else {
                        ForEach(dashboard.ledger) { entry in
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(entry.displayText)
                                        .font(.psBody)
                                    if let date = entry.created_at {
                                        Text(date)
                                            .font(.psCaption)
                                            .foregroundStyle(.psMuted)
                                    }
                                }
                                Spacer()
                                if let amount = entry.amount {
                                    Text("KES \(amount)")
                                        .font(.psMono)
                                        .foregroundStyle(.psMuted)
                                }
                            }
                        }
                    }
                }

                Section("My waitlist") {
                    if dashboard.waitlist.isEmpty {
                        Text("You are not on any waitlist.")
                            .font(.psBody)
                            .foregroundStyle(.psMuted)
                    } else {
                        ForEach(dashboard.waitlist) { item in
                            HStack {
                                Text(item.service_requested ?? "Platform")
                                    .font(.psBody)
                                Spacer()
                                if let position = item.position ?? item.priority_pos {
                                    Text("Position \(position)")
                                        .font(.psCaption)
                                        .foregroundStyle(.psMuted)
                                }
                            }
                            .accessibilityLabel("\(item.service_requested ?? "Platform"), waitlist position \(item.position ?? item.priority_pos ?? 0)")
                        }
                    }
                }

                Section("Notifications") {
                    HStack {
                        Label("Unread notifications", systemImage: "bell.fill")
                            .font(.psBody)
                        Spacer()
                        Text("\(dashboard.unread_count ?? 0)")
                            .font(.psHeadline)
                            .foregroundStyle(.psCyan)
                    }
                    NavigationLink {
                        NotificationsRootView()
                    } label: {
                        Text("Open notifications")
                            .font(.psBody)
                    }
                    .accessibilityLabel("Open notifications, \(dashboard.unread_count ?? 0) unread")
                }
            }

            Section("Community suggestions") {
                if suggestions.isEmpty {
                    Text("No suggestions yet. Tell us which platform you want to see next.")
                        .font(.psBody)
                        .foregroundStyle(.psMuted)
                } else {
                    ForEach(suggestions) { suggestion in
                        HStack {
                            Text(suggestion.service_name)
                                .font(.psBody)
                            Spacer()
                            Label("\(suggestion.votes)", systemImage: "hand.thumbsup.fill")
                                .font(.psCaption)
                                .foregroundStyle(.psMuted)
                        }
                    }
                }
                TextField("Platform name", text: $suggestionName)
                    .psTextField()
                    .autocorrectionDisabled()
                    .accessibilityLabel("Suggested platform name")
                TextField("Email", text: $suggestionEmail)
                    .psTextField()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Your email for the suggestion")
                Button {
                    Task { await submitSuggestion() }
                } label: {
                    if isSubmittingSuggestion { PSRingSpinner(diameter: 20, lineWidth: 2, color: .white, duration: 0.7) }
                    else { Text("Suggest this platform") }
                }
                .psPrimary()
                .disabled(isSubmittingSuggestion || !appState.isLoggedIn)
                if !appState.isLoggedIn {
                    Text("Sign in to suggest a platform.")
                        .font(.psCaption)
                        .foregroundStyle(.psMuted)
                }
                if let suggestionMessage {
                    Text(suggestionMessage)
                        .font(.psCaption)
                        .foregroundStyle(.psMuted)
                }
            }

            Section("Questions") {
                dashFAQ(question: "How do I pay?", answer: "Send the exact amount by M-PESA to PayBill 400200, account 1192526, then submit the 10-letter-and-number code from your confirmation message in checkout.")
                dashFAQ(question: "When do I get my details?", answer: "Once the team verifies your code, your slot moves to Active in My Slots and your vault details appear there.")
                dashFAQ(question: "Can I use my slot on more than one device?", answer: "No. 1 slot = 1 device. Use it on your own device only.")
                dashFAQ(question: "What if my code is rejected?", answer: "Check the code is exactly 10 letters and numbers and has not been used before, then try again or report the issue from My Slots.")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.psBackground)
        .navigationTitle("Dashboard")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .sheet(isPresented: $showAuth) {
            AuthView()
                .psSheetDetents()
        }
        .safeAreaPadding(.bottom, 8)
    }

    private var rankedServices: [APIService]? {
        guard let services else { return nil }
        let ranked = services.services.sorted { ($0.waitlist_count ?? 0) > ($1.waitlist_count ?? 0) }
        return Array(ranked.prefix(5))
    }

    private func statRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.psBody)
            Spacer()
            Text(value)
                .font(.psMono)
                .foregroundStyle(.psMuted)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    private func dashStep(number: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.psCyan)
                .frame(width: 32, height: 32)
                .background(Color.psPrimarySoft)
                .clipShape(Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.psHeadline)
                Text(text)
                    .font(.psBody)
                    .foregroundStyle(.psMuted)
            }
        }
        .psTouchTarget()
    }

    private func dashFAQ(question: String, answer: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(question)
                .font(.psHeadline)
            Text(answer)
                .font(.psBody)
                .foregroundStyle(.psMuted)
        }
        .psTouchTarget()
    }

    private func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            services = try await APIClient.shared.services()
        } catch {
            // Public sections fall back to the bundled catalogue counts.
        }
        do {
            let response: DashSuggestionsResponse = try await APIClient.shared.fetchJSON("api/v1/suggestions")
            suggestions = response.suggestions
        } catch {
            suggestions = []
        }
        guard appState.isLoggedIn else { return }
        do {
            dashboard = try await APIClient.shared.fetchJSON("api/v1/me/dashboard")
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func submitSuggestion() async {
        let name = suggestionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            suggestionMessage = "Enter the platform name first."
            return
        }
        isSubmittingSuggestion = true
        defer { isSubmittingSuggestion = false }
        do {
            let _: APIResponse = try await APIClient.shared.fetchJSON(
                "api/v1/suggestions", method: "POST",
                body: ["service_name": name, "email": suggestionEmail])
            suggestionMessage = "Thanks. Your suggestion was sent."
            suggestionName = ""
            suggestionEmail = ""
            let response: DashSuggestionsResponse = try await APIClient.shared.fetchJSON("api/v1/suggestions")
            suggestions = response.suggestions
        } catch {
            suggestionMessage = error.localizedDescription
        }
    }
}

// MARK: - Dashboard response types (keys from backend/api_v1.py my_dashboard)

struct DashDashboardResponse: Decodable {
    let ok: Bool
    let subscriptions: [APISubscription]
    let ledger: [DashLedgerRow]
    let waitlist: [DashWaitlistRow]
    let unread_count: Int?
    let approved_count: Int?
    let global_alert: String?
}

struct DashLedgerRow: Decodable, Identifiable {
    let id: Int?
    let amount: Int?
    let description: String?
    let action_type: String?
    let type: String?
    let created_at: String?

    var displayText: String {
        description ?? action_type ?? type ?? "Ledger entry"
    }
}

struct DashWaitlistRow: Decodable, Identifiable {
    let id: Int?
    let service_requested: String?
    let priority_pos: Int?
    let position: Int?
    let created_at: String?
}

struct DashSuggestion: Decodable, Identifiable {
    var id: String { service_name }
    let service_name: String
    let votes: Int
}

struct DashSuggestionsResponse: Decodable {
    let ok: Bool
    let suggestions: [DashSuggestion]
}

#Preview {
    NavigationStack {
        DashboardRootView()
            .environmentObject(AppState())
    }
}
