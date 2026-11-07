import SwiftUI

// MARK: - My Slots, v5
// Complete overhaul: bigger slot cards (large platform logo, name,
// price, status pill, expiry plus days remaining), more detail per
// slot (start date, renewal date, auto-renew state, support
// shortcut), and a clearer button layout (one prominent primary
// action, secondary actions grouped, the destructive choice of
// turning auto-renew off behind its own confirmation, in red).
// Active / Pending verification / Past split kept. Pull-to-refresh
// and proper empty/error states. Days remaining prefers the server
// value (days_remaining) when the API returns it and falls back to
// a local calculation from the expiry date; display is never
// negative. There is no customer cancel endpoint on the API, so no
// Cancel button was invented.
//
// Safe area: the screen lives in a NavigationStack with an inline
// title, so content starts below the notch and Dynamic Island on
// first appearance and only scrolls under the bar once the user
// scrolls. The navigation bar background is an opaque brand colour
// so scrolled content never shows through behind the notch. No
// ignoresSafeArea is used on this screen.

struct MySlotsView: View {
    @EnvironmentObject private var appState: AppState
    var onBrowseCatalogue: () -> Void = {}

    @State private var showAuth = false
    @State private var vault = ""
    @State private var vaultError = ""
    @State private var revealingId: Int?
    @State private var loadError: String?
    @State private var actionError: String?
    @State private var selectedSubscription: LiveSubscription?
    @State private var extras: [Int: PSSubscriptionExtras] = [:]
    @State private var reportedIds: Set<Int> = []

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
                        body: "Slots you buy on the PremiumSlots website appear here once your M-PESA code is verified. Pending orders show here too.",
                        actionLabel: "Browse the catalogue",
                        action: onBrowseCatalogue
                    )
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
                                    .psTextStyle(.mono)
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
            .psHiddenScrollIndicators()
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(Color.psBackground)
            .navigationTitle("My Slots")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.psBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) { CustomerNotificationBell() }
            }
            .refreshable { await load() }
            .task { await load() }
            .sheet(isPresented: $showAuth) {
                AuthView()
                    .psSheetDetents()
            }
            .sheet(item: $selectedSubscription) { sub in
                SubscriptionDetailSheet(
                    subscription: sub,
                    extras: extras[sub.id],
                    onAutoRenewChanged: { value in
                        extras[sub.id] = PSSubscriptionExtras(
                            id: sub.id,
                            days_remaining: extras[sub.id]?.days_remaining,
                            auto_renew: value
                        )
                    }
                )
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
            .alert("Something went wrong", isPresented: Binding(
                get: { actionError != nil },
                set: { if !$0 { actionError = nil } }
            )) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(actionError ?? "")
            }
            .safeAreaPadding(.bottom, 8)
        }
    }

    private func load() async {
        loadError = nil
        await appState.refreshMySubscriptions()
        await appState.refreshWallet()
        do {
            extras = try await appState.api.mySubscriptionExtras()
        } catch {
            extras = [:]
        }
    }

    /// Server days remaining when the API returns it, otherwise the
    /// local day difference from the expiry date. Nil when there is
    /// no expiry date at all.
    private func daysRemaining(for sub: LiveSubscription) -> Int? {
        extras[sub.id]?.days_remaining ?? sub.daysLeft
    }

    private func autoRenew(for sub: LiveSubscription) -> Bool? {
        extras[sub.id]?.auto_renew
    }

    private var loginGate: some View {
        PSCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Sign in to see your slots")
                    .psTextStyle(.title)
                Text("Your subscriptions live on your PremiumSlots account, not on this phone. Sign in to load them from the PremiumSlots website.")
                    .psTextStyle(.body)
                    .foregroundStyle(.psMuted)
                Button("Sign in") { showAuth = true }
                    .psPrimary()
            }
        }
    }

    // MARK: - Slot card

    private func liveSlotCard(_ sub: LiveSubscription) -> some View {
        PSCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    PlatformLogoView(name: sub.serviceRequested, size: 64)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(sub.serviceRequested)
                            .psTextStyle(.headline)
                            .lineLimit(2)
                        Text("KES \(sub.amountDue)")
                            .psTextStyle(.headline)
                        + Text(" · Order #\(sub.id)")
                            .psTextStyle(.caption)
                            .foregroundStyle(.psMuted)
                        if let locked = sub.lockedPrice, locked != sub.amountDue {
                            Text("Locked price KES \(locked)")
                                .psTextStyle(.caption)
                                .foregroundStyle(.psMuted)
                        }
                    }
                    Spacer()
                    PSStatusPill(
                        text: sub.orderStatus.rawValue,
                        systemImage: sub.orderStatus.systemImage,
                        tint: sub.orderStatus == .active ? .psSuccess : sub.orderStatus == .issue ? .psDanger : .psAmber
                    )
                }

                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .psTextStyle(.caption)
                        .foregroundStyle(.psMuted)
                        .accessibilityHidden(true)
                    Text(expiryLabel(for: sub))
                        .psTextStyle(.caption)
                        .foregroundStyle(.psMuted)
                    Spacer()
                    daysPill(for: sub)
                }

                if let line = detailLine(for: sub) {
                    Text(line)
                        .psTextStyle(.caption)
                        .foregroundStyle(.psMuted)
                }

                if sub.status == "Approved" {
                    Button {
                        Task { await revealVault(for: sub) }
                    } label: {
                        if revealingId == sub.id {
                            PSRingSpinner(diameter: 20, lineWidth: 2, color: .psPaper, duration: 0.7)
                        } else {
                            Label("Show vault details", systemImage: "lock.shield.fill")
                        }
                    }
                    .psPrimary()
                    .disabled(revealingId != nil)
                    .accessibilityLabel("Show vault details for \(sub.serviceRequested)")
                    HStack(spacing: 10) {
                        if reportedIds.contains(sub.id) || sub.issueReported {
                            Label("Issue reported", systemImage: "checkmark.circle.fill")
                                .psTextStyle(.caption)
                                .foregroundStyle(.psMuted)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        } else {
                            Button {
                                Task { await reportIssue(for: sub) }
                            } label: {
                                Label("Report an issue", systemImage: "exclamationmark.circle")
                                    .psTextStyle(.caption)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                            }
                            .buttonStyle(.bordered)
                            .accessibilityLabel("Report an issue with \(sub.serviceRequested)")
                        }
                        Link(destination: PSContact.whatsAppSupportURL) {
                            Label("Support", systemImage: "message.fill")
                                .psTextStyle(.caption)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.bordered)
                        .tint(.psCyan)
                        .accessibilityLabel("WhatsApp support, \(PSContact.whatsAppDisplayNumber)")
                    }
                    Button("Details and timeline") { selectedSubscription = sub }
                        .psTextStyle(.caption)
                } else if sub.status == "Pending" || sub.status == "Initiated" {
                    Text("Your M-PESA code is waiting to be verified by the team.")
                        .psTextStyle(.caption)
                        .foregroundStyle(.psMuted)
                    HStack(spacing: 10) {
                        Button("Details and timeline") { selectedSubscription = sub }
                            .psTextStyle(.caption)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .buttonStyle(.bordered)
                        Link(destination: PSContact.whatsAppSupportURL) {
                            Label("Support", systemImage: "message.fill")
                                .psTextStyle(.caption)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.bordered)
                        .tint(.psCyan)
                        .accessibilityLabel("WhatsApp support, \(PSContact.whatsAppDisplayNumber)")
                    }
                } else {
                    Button("Buy again", action: onBrowseCatalogue)
                        .psPrimary()
                    HStack(spacing: 10) {
                        Button("Details and timeline") { selectedSubscription = sub }
                            .psTextStyle(.caption)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .buttonStyle(.bordered)
                        Link(destination: PSContact.whatsAppSupportURL) {
                            Label("Support", systemImage: "message.fill")
                                .psTextStyle(.caption)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.bordered)
                        .tint(.psCyan)
                        .accessibilityLabel("WhatsApp support, \(PSContact.whatsAppDisplayNumber)")
                    }
                }
            }
        }
    }

    /// "Renews <date>" when auto-renew is on for an active slot,
    /// otherwise "Expires <date>".
    private func expiryLabel(for sub: LiveSubscription) -> String {
        guard let date = formattedDate(sub.expiryDate) else {
            return "No expiry date shown"
        }
        if sub.status == "Approved", autoRenew(for: sub) == true {
            return "Renews \(date)"
        }
        return "Expires \(date)"
    }

    @ViewBuilder
    private func daysPill(for sub: LiveSubscription) -> some View {
        if sub.status == "Approved", let days = daysRemaining(for: sub) {
            if days < 0 {
                PSStatusPill(text: "Expired", systemImage: "xmark.circle.fill", tint: .psDanger)
            } else if days == 0 {
                PSStatusPill(text: "Expires today", systemImage: "clock.fill", tint: .psWarning)
            } else {
                PSStatusPill(text: PSDaysRemaining.text(days: days), systemImage: "clock.fill", tint: .psSuccess)
            }
        }
    }

    /// Start date and auto-renew state, shown only when known.
    /// Nothing is shown for a value the server did not return.
    private func detailLine(for sub: LiveSubscription) -> String? {
        var parts: [String] = []
        if let started = formattedDate(sub.createdAt) {
            parts.append("Started \(started)")
        }
        if let renew = autoRenew(for: sub) {
            parts.append(renew ? "Auto-renew on" : "Auto-renew off")
        }
        if parts.isEmpty { return nil }
        return parts.joined(separator: " · ")
    }

    private func orderRow(_ order: SlotOrder) -> some View {
        PSCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    PlatformLogoView(name: order.platformName, size: 48)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(order.platformName)
                            .psTextStyle(.headline)
                        Text("KES \(order.amountKES) · \(order.mpesaCode)")
                            .psTextStyle(.caption)
                            .foregroundStyle(.psMuted)
                    }
                    Spacer()
                    PSStatusPill(
                        text: order.status.rawValue,
                        systemImage: order.status.systemImage,
                        tint: order.status == .active ? .psSuccess : .psAmber
                    )
                }
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .psTextStyle(.caption)
                        .foregroundStyle(.psMuted)
                        .accessibilityHidden(true)
                    Text("Started \(shortDate(order.createdAt))")
                        .psTextStyle(.caption)
                        .foregroundStyle(.psMuted)
                    if let activatedAt = order.activatedAt {
                        Text("· Active since \(shortDate(activatedAt))")
                            .psTextStyle(.caption)
                            .foregroundStyle(.psMuted)
                    }
                }
            }
        }
    }

    /// Formats an ISO 8601 date string from the API as a short date
    /// for display. Returns nil when there is no date to show.
    private func formattedDate(_ iso: String?) -> String? {
        guard let iso, !iso.isEmpty else { return nil }
        let parser = ISO8601DateFormatter()
        if let date = parser.date(from: iso) {
            return shortDate(date)
        }
        return iso
    }

    private func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func revealVault(for sub: LiveSubscription) async {
        revealingId = sub.id
        defer { revealingId = nil }
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

    private func reportIssue(for sub: LiveSubscription) async {
        do {
            try await appState.api.reportIssue(subscriptionId: sub.id)
            reportedIds.insert(sub.id)
        } catch {
            actionError = error.localizedDescription
        }
    }
}

// MARK: - Subscription detail sheet (timeline + request-review, Fix #4;
// v5: start/renewal dates, auto-renew toggle, support actions)
// Timeline from GET /api/v1/me/subscriptions/<id>/timeline (OrderEvents);
// request-review via POST /api/v1/me/subscriptions/<id>/request-review.
// Auto-renew uses POST /api/v1/subscription/<id>/toggle-auto-renew,
// which flips the server flag and returns the new value. The toggle
// is shown only when the server reported the current state; turning
// it off asks for confirmation with a destructive button, kept
// separate from every other action.

struct SubscriptionDetailSheet: View {
    let subscription: LiveSubscription
    let extras: PSSubscriptionExtras?
    var onAutoRenewChanged: ((Bool) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var autoRenewState: Bool?
    @State private var isTogglingAutoRenew = false
    @State private var showDisableConfirm = false
    @State private var autoRenewMessage: String?
    @State private var timeline: [TmlEvent] = []
    @State private var isLoadingTimeline = false
    @State private var timelineError: String?
    @State private var reviewMessage: String?
    @State private var isRequestingReview = false
    @State private var issueReported: Bool
    @State private var issueMessage: String?
    @State private var isReportingIssue = false

    init(subscription: LiveSubscription, extras: PSSubscriptionExtras? = nil, onAutoRenewChanged: ((Bool) -> Void)? = nil) {
        self.subscription = subscription
        self.extras = extras
        self.onAutoRenewChanged = onAutoRenewChanged
        _autoRenewState = State(initialValue: extras?.auto_renew)
        _issueReported = State(initialValue: subscription.issueReported)
    }

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
                            .psTextStyle(.mono)
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
                    if let started = formattedDate(subscription.createdAt) {
                        HStack {
                            Text("Started")
                            Spacer()
                            Text(started)
                                .foregroundStyle(.psMuted)
                        }
                    }
                    if let expiry = formattedDate(subscription.expiryDate) {
                        HStack {
                            Text(autoRenewState == true ? "Renews on" : "Expires on")
                            Spacer()
                            Text(expiry)
                                .foregroundStyle(.psMuted)
                        }
                    }
                    if let group = subscription.accountGroup, !group.isEmpty {
                        HStack {
                            Text("Account group")
                            Spacer()
                            Text(group)
                                .foregroundStyle(.psMuted)
                        }
                    }
                }
                Section("Auto-renew") {
                    if let _ = autoRenewState {
                        Toggle("Auto-renew", isOn: autoRenewBinding)
                            .disabled(isTogglingAutoRenew)
                        Text("When auto-renew is on, your slot renews on the renewal date. When it is off, the slot ends on that date.")
                            .psTextStyle(.caption)
                            .foregroundStyle(.psMuted)
                    } else {
                        Text("Not available yet")
                            .foregroundStyle(.psMuted)
                        Text("The server does not report auto-renew for this slot yet.")
                            .psTextStyle(.caption)
                            .foregroundStyle(.psMuted)
                    }
                    if let autoRenewMessage {
                        Text(autoRenewMessage)
                            .psTextStyle(.caption)
                            .foregroundStyle(.psMuted)
                    }
                }
                Section("Support") {
                    if issueReported {
                        Label("Issue reported", systemImage: "checkmark.circle.fill")
                            .psTextStyle(.body)
                            .foregroundStyle(.psMuted)
                    } else {
                        Button {
                            Task { await reportIssue() }
                        } label: {
                            if isReportingIssue {
                                PSRingSpinner(diameter: 20, lineWidth: 2, color: .psPaper, duration: 0.7)
                            } else {
                                Label("Report an issue", systemImage: "exclamationmark.circle")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isReportingIssue)
                        .accessibilityLabel("Report an issue with \(subscription.serviceRequested)")
                    }
                    if let issueMessage {
                        Text(issueMessage)
                            .psTextStyle(.caption)
                            .foregroundStyle(.psMuted)
                    }
                    Link(destination: PSContact.whatsAppSupportURL) {
                        Label("WhatsApp support (\(PSContact.whatsAppDisplayNumber))", systemImage: "message.fill")
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
                            .psTextStyle(.body)
                            .foregroundStyle(.psMuted)
                    } else {
                        ForEach(timeline) { event in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(event.displayTitle)
                                    .psTextStyle(.headline)
                                if let message = event.message, !message.isEmpty {
                                    Text(message)
                                        .psTextStyle(.body)
                                        .foregroundStyle(.psMuted)
                                }
                                if let date = event.created_at {
                                    Text(date)
                                        .psTextStyle(.caption)
                                        .foregroundStyle(.psMuted)
                                }
                            }
                            .accessibilityLabel("\(event.displayTitle). \(event.message ?? "")")
                        }
                    }
                }
                Section("Review") {
                    Text("Ask the team to request a review of this slot.")
                        .psTextStyle(.body)
                        .foregroundStyle(.psMuted)
                    Button {
                        Task { await requestReview() }
                    } label: {
                        if isRequestingReview { PSRingSpinner(diameter: 20, lineWidth: 2, color: .psPaper, duration: 0.7) }
                        else { Label("Request a review", systemImage: "star.fill") }
                    }
                    .psPrimary()
                    .disabled(isRequestingReview)
                    .accessibilityLabel("Request a review of \(subscription.serviceRequested)")
                    if let reviewMessage {
                        Text(reviewMessage)
                            .psTextStyle(.caption)
                            .foregroundStyle(.psMuted)
                    }
                }
            }
            .psHiddenScrollIndicators()
            .navigationTitle(subscription.serviceRequested)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.psBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .accessibilityLabel("Close details")
                }
            }
            .task { await loadTimeline() }
            .alert("Turn off auto-renew?", isPresented: $showDisableConfirm) {
                Button("Turn off auto-renew", role: .destructive) {
                    Task { await applyAutoRenew(false) }
                }
                Button("Keep it on", role: .cancel) { }
            } message: {
                Text("Your slot will expire on the renewal date and will not renew. You can turn auto-renew back on any time before then.")
            }
        }
    }

    private var autoRenewBinding: Binding<Bool> {
        Binding(
            get: { autoRenewState ?? false },
            set: { newValue in
                if newValue {
                    Task { await applyAutoRenew(true) }
                } else {
                    showDisableConfirm = true
                }
            }
        )
    }

    private func applyAutoRenew(_ enable: Bool) async {
        isTogglingAutoRenew = true
        defer { isTogglingAutoRenew = false }
        do {
            let value = try await APIClient.shared.toggleAutoRenew(subscriptionId: subscription.id)
            autoRenewState = value
            onAutoRenewChanged?(value)
            autoRenewMessage = value
                ? "Auto-renew is on. Your slot renews on the renewal date."
                : "Auto-renew is off. Your slot will expire on the renewal date and will not renew."
        } catch {
            autoRenewMessage = error.localizedDescription
        }
    }

    private func reportIssue() async {
        isReportingIssue = true
        defer { isReportingIssue = false }
        do {
            try await APIClient.shared.reportIssue(subscriptionId: subscription.id)
            issueReported = true
            issueMessage = "Thanks. The team has been told about this slot."
        } catch {
            issueMessage = error.localizedDescription
        }
    }

    private func formattedDate(_ iso: String?) -> String? {
        guard let iso, !iso.isEmpty else { return nil }
        let parser = ISO8601DateFormatter()
        if let date = parser.date(from: iso) {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return formatter.string(from: date)
        }
        return iso
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
