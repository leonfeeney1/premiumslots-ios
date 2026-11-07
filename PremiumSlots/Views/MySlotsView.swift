import SwiftUI

// MARK: - My Slots, v3 Fix #3
// HIG overhaul: inset-grouped List with Active / Pending / Past
// sections, pull-to-refresh, shared empty/error states, status
// pills, sheet detents for the vault reveal. Vault details are
// still shown once only, exactly as on the web.

struct MySlotsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showAuth = false
    @State private var vault = ""
    @State private var vaultError = ""
    @State private var isRevealingVault = false
    @State private var loadError: String?
    @State private var selectedSubscription: LiveSubscription?

    private var activeSubs: [LiveSubscription] {
        appState.liveSubscriptions.filter { $0.status == "Approved" }
    }

    private var pendingSubs: [LiveSubscription] {
        appState.liveSubscriptions.filter { $0.status == "Pending" || $0.status == "Initiated" }
    }

    private var pastSubs: [LiveSubscription] {
        appState.liveSubscriptions.filter { $0.status != "Approved" && $0.status != "Pending" && $0.status != "Initiated" }
    }

    var body: some View {
        NavigationStack {
            List {
                if !appState.isLoggedIn {
                    loginGate
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                } else if let loadError {
                    PSErrorState(message: loadError) {
                        Task { await load() }
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else if appState.liveSubscriptions.isEmpty && appState.orders.isEmpty {
                    PSEmptyState(
                        systemImage: "lock.shield",
                        title: "No slots yet",
                        body: "Slots you buy on premiumslots.tech appear here once your M-PESA code is verified. Pending orders show here too.",
                        actionLabel: "Browse the catalogue"
                    ) {
                        // The tab bar takes the user back to Catalogue.
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else {
                    if !activeSubs.isEmpty {
                        Section("Active") {
                            ForEach(activeSubs) { sub in
                                liveSlotCard(sub)
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            }
                        }
                    }
                    if !pendingSubs.isEmpty {
                        Section("Pending verification") {
                            ForEach(pendingSubs) { sub in
                                liveSlotCard(sub)
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            }
                        }
                    }
                    if !pastSubs.isEmpty {
                        Section("Past") {
                            ForEach(pastSubs) { sub in
                                liveSlotCard(sub)
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            }
                        }
                    }
                    if let balance = appState.walletBalance {
                        Section {
                            HStack {
                                Text("Wallet balance")
                                Spacer()
                                Text("KES \(balance)")
                                    .font(.psMono)
                                    .foregroundStyle(.psMuted)
                            }
                        }
                    }
                    if !appState.orders.isEmpty {
                        Section("Saved on this device") {
                            ForEach(appState.orders) { order in
                                orderRow(order)
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.psBackground)
            .navigationTitle("My Slots")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await load() }
            .task { await load() }
            .sheet(isPresented: $showAuth) {
                AuthView()
                    .psSheetDetents()
            }
            .sheet(item: $selectedSubscription) { sub in
                SubscriptionDetailSheet(subscription: sub)
                    .psSheetDetents()
            }
            .alert("Vault", isPresented: Binding(
                get: { !vault.isEmpty || !vaultError.isEmpty },
                set: { if !$0 { vault = ""; vaultError = "" } }
            )) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(vaultError.isEmpty ? vault : vaultError)
            }
            .safeAreaPadding(.bottom, 8)
        }
    }

    private func load() async {
        loadError = nil
        await appState.refreshMySubscriptions()
        await appState.refreshWallet()
    }

    private var loginGate: some View {
        PSCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Sign in to see your slots")
                    .font(.psTitle)
                Text("Your subscriptions live on your PremiumSlots account, not on this phone. Sign in to load them from premiumslots.tech.")
                    .font(.psBody)
                    .foregroundStyle(.psMuted)
                Button("Sign in") { showAuth = true }
                    .psPrimary()
            }
        }
    }

    private func liveSlotCard(_ sub: LiveSubscription) -> some View {
        PSCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(sub.serviceRequested)
                            .font(.psHeadline)
                        Text("Order #\(sub.id) · KES \(sub.amountDue)")
                            .font(.psCaption)
                            .foregroundStyle(.psMuted)
                    }
                    Spacer()
                    PSStatusPill(
                        text: sub.orderStatus.rawValue,
                        systemImage: sub.orderStatus.systemImage,
                        tint: sub.orderStatus == .active ? .psSuccess : .psAmber
                    )
                }
                if let days = sub.daysLeft, sub.status == "Approved" {
                    Text(days >= 0 ? "\(days) days left" : "Expired")
                        .font(.psCaption)
                        .foregroundStyle(.psMuted)
                }
                if sub.status == "Approved" {
                    HStack(spacing: 10) {
                        Button {
                            Task { await revealVault(for: sub) }
                        } label: {
                            if isRevealingVault {
                                PSRingSpinner(diameter: 20, lineWidth: 2)
                            } else {
                                Label("Show vault details", systemImage: "lock.shield.fill")
                                    .font(.psCaption)
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(.psCyan)
                        .disabled(isRevealingVault)
                        .accessibilityLabel("Show vault details for \(sub.serviceRequested)")
                        Button {
                            Task { try? await appState.api.reportIssue(subscriptionId: sub.id) }
                        } label: {
                            Label("Report an issue", systemImage: "exclamationmark.circle")
                                .font(.psCaption)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Report an issue with \(sub.serviceRequested)")
                    }
                } else if sub.status == "Pending" {
                    Text("Your M-PESA code is waiting to be verified by the team.")
                        .font(.psCaption)
                        .foregroundStyle(.psMuted)
                }
                Button("Details and timeline") { selectedSubscription = sub }
                    .font(.psCaption)
            }
        }
    }

    private func orderRow(_ order: SlotOrder) -> some View {
        PSCard {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(order.platformName)
                        .font(.psHeadline)
                    Text("KES \(order.amountKES) · \(order.mpesaCode)")
                        .font(.psCaption)
                        .foregroundStyle(.psMuted)
                }
                Spacer()
                PSStatusPill(
                    text: order.status.rawValue,
                    systemImage: order.status.systemImage,
                    tint: order.status == .active ? .psSuccess : .psAmber
                )
            }
        }
    }

    private func revealVault(for sub: LiveSubscription) async {
        isRevealingVault = true
        defer { isRevealingVault = false }
        do {
            let response = try await appState.api.vault(subscriptionId: sub.id)
            guard response.ok else {
                vaultError = response.error ?? "Vault details are not available for this order."
                return
            }
            if response.revealed == true, let email = response.vault_email,
               let password = response.vault_password {
                vault = "Email: \(email)\nPassword: \(password)\nThis is shown once only, then hidden."
            } else {
                vault = response.message ?? "Vault details were not revealed. Try again."
            }
        } catch {
            vaultError = error.localizedDescription
        }
    }
}

// MARK: - Subscription detail sheet (timeline + request-review, Fix #4)
// Timeline from GET /api/v1/me/subscriptions/<id>/timeline (OrderEvents);
// request-review via POST /api/v1/me/subscriptions/<id>/request-review.

struct SubscriptionDetailSheet: View {
    let subscription: LiveSubscription
    @Environment(\.dismiss) private var dismiss
    @State private var timeline: [TmlEvent] = []
    @State private var isLoadingTimeline = false
    @State private var timelineError: String?
    @State private var reviewMessage: String?
    @State private var isRequestingReview = false

    var body: some View {
        NavigationStack {
            List {
                Section("Order") {
                    HStack {
                        Text("Service")
                        Spacer()
                        Text(subscription.serviceRequested)
                            .foregroundStyle(.psMuted)
                    }
                    HStack {
                        Text("Order")
                        Spacer()
                        Text("#\(subscription.id)")
                            .font(.psMono)
                            .foregroundStyle(.psMuted)
                    }
                    HStack {
                        Text("Amount")
                        Spacer()
                        Text("KES \(subscription.amountDue)")
                            .foregroundStyle(.psMuted)
                    }
                    if let locked = subscription.lockedPrice, locked != subscription.amountDue {
                        HStack {
                            Text("Locked price")
                            Spacer()
                            Text("KES \(locked)")
                                .foregroundStyle(.psMuted)
                        }
                    }
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(subscription.status)
                            .foregroundStyle(.psMuted)
                    }
                    if let expiry = subscription.expiryDate {
                        HStack {
                            Text("Expires")
                            Spacer()
                            Text(expiry)
                                .font(.psMono)
                                .foregroundStyle(.psMuted)
                        }
                    }
                }
                Section("Timeline") {
                    if let timelineError {
                        PSErrorState(message: timelineError) {
                            Task { await loadTimeline() }
                        }
                    } else if isLoadingTimeline && timeline.isEmpty {
                        HStack {
                            Spacer()
                            PSRingSpinner(diameter: 24, lineWidth: 3)
                            Spacer()
                        }
                    } else if timeline.isEmpty {
                        Text("No timeline events yet.")
                            .font(.psBody)
                            .foregroundStyle(.psMuted)
                    } else {
                        ForEach(timeline) { event in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(event.displayTitle)
                                    .font(.psHeadline)
                                if let message = event.message, !message.isEmpty {
                                    Text(message)
                                        .font(.psBody)
                                        .foregroundStyle(.psMuted)
                                }
                                if let date = event.created_at {
                                    Text(date)
                                        .font(.psCaption)
                                        .foregroundStyle(.psMuted)
                                }
                            }
                            .accessibilityLabel("\(event.displayTitle). \(event.message ?? "")")
                        }
                    }
                }
                Section("Review") {
                    Text("Ask the team to request a review of this slot.")
                        .font(.psBody)
                        .foregroundStyle(.psMuted)
                    Button {
                        Task { await requestReview() }
                    } label: {
                        if isRequestingReview { PSRingSpinner(diameter: 20, lineWidth: 2, color: .white, duration: 0.7) }
                        else { Label("Request a review", systemImage: "star.fill") }
                    }
                    .psPrimary()
                    .disabled(isRequestingReview)
                    .accessibilityLabel("Request a review of \(subscription.serviceRequested)")
                    if let reviewMessage {
                        Text(reviewMessage)
                            .font(.psCaption)
                            .foregroundStyle(.psMuted)
                    }
                }
            }
            .navigationTitle(subscription.serviceRequested)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .accessibilityLabel("Close details")
                }
            }
            .task { await loadTimeline() }
        }
    }

    private func loadTimeline() async {
        isLoadingTimeline = true
        timelineError = nil
        defer { isLoadingTimeline = false }
        do {
            let response: TmlTimelineResponse = try await APIClient.shared.fetchJSON(
                "api/v1/me/subscriptions/\(subscription.id)/timeline")
            timeline = response.timeline
        } catch {
            timelineError = error.localizedDescription
        }
    }

    private func requestReview() async {
        isRequestingReview = true
        defer { isRequestingReview = false }
        do {
            let _: APIResponse = try await APIClient.shared.fetchOK(
                "api/v1/me/subscriptions/\(subscription.id)/request-review",
                method: "POST", body: [:])
            reviewMessage = "Review requested. Thanks for helping other customers choose."
        } catch {
            reviewMessage = error.localizedDescription
        }
    }
}

// MARK: - Timeline response types (keys from backend/api_v1.py)

struct TmlEvent: Decodable, Identifiable {
    let id: Int?
    let event_type: String?
    let message: String?
    let created_at: String?

    var displayTitle: String {
        guard let event_type, !event_type.isEmpty else { return "Event" }
        return event_type.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

struct TmlTimelineResponse: Decodable {
    let ok: Bool
    let subscription: APISubscription?
    let timeline: [TmlEvent]
}

#Preview {
    MySlotsView()
        .environmentObject(AppState())
}
