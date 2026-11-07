import SwiftUI

// MARK: - My Slots, v5 (v6: cache-first + skeletons + card actions)
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
// v6 loading: the screen never starts blank. Skeleton cards show
// immediately on a first load, the last good subscriptions are
// restored from an on-device cache first (UserDefaults, this
// device only), and the live list refreshes over them. A failed
// refresh keeps the cached list on screen with a retry banner
// instead of wiping it, and only a first load with nothing cached
// shows the full error state with retry.
//
// v6 actions: "Request review of credentials" and the auto-renew
// toggle live on the slot card itself for Active slots as well as
// in the detail sheet. Both call the real endpoints (request-review
// via APIClient.requestReview, auto-renew via
// APIClient.toggleAutoRenew) with loading, success and error
// states. The toggle and the review state read days_remaining,
// auto_renew and review_requested straight from the subscriptions
// response, so they work even when the server extras call is
// absent. A slot whose review was already requested shows that
// state instead of a live button.
//
// Safe area: the screen lives in a NavigationStack with an inline
// title, so content starts below the notch and Dynamic Island on
// first appearance and only scrolls under the bar once the user
// scrolls. The navigation bar background is an opaque brand colour
// so scrolled content never shows through behind the notch. No
// ignoresSafeArea is used on this screen. The background colour
// extends edge to edge under the tab bar through psScreenBackground.

struct MySlotsView: View {
    @EnvironmentObject private var appState: AppState
    var onBrowseCatalogue: () -> Void = {}
    var deepLinkSubscriptionId: Binding<Int?> = .constant(nil)

    @State private var showAuth = false
    @State private var vault = ""
    @State private var vaultError = ""
    @State private var revealingId: Int?
    @State private var loadError: String?
    @State private var isLoading = false
    @State private var actionError: String?
    @State private var selectedSubscription: LiveSubscription?
    @State private var extras: [Int: MySlotState] = [:]
    @State private var cachedSubs: [LiveSubscription] = []
    @State private var reportedIds: Set<Int> = []
    @State private var togglingIds: Set<Int> = []
    @State private var requestingReviewIds: Set<Int> = []
    @State private var pendingDisableSub: LiveSubscription?

    /// Live list when present, otherwise the last good cached list.
    /// The cached list is only ever shown while signed in.
    private var displaySubs: [LiveSubscription] {
        appState.liveSubscriptions.isEmpty ? cachedSubs : appState.liveSubscriptions
    }

    private var activeSubs: [LiveSubscription] {
        displaySubs.filter { $0.status == "Approved" }
    }

    private var pendingSubs: [LiveSubscription] {
        displaySubs.filter { $0.status == "Pending" || $0.status == "Initiated" }
    }

    private var pastSubs: [LiveSubscription] {
        displaySubs.filter { $0.status != "Approved" && $0.status != "Pending" && $0.status != "Initiated" }
    }

    var body: some View {
        NavigationStack {
            List {
                if !appState.isLoggedIn {
                    loginGate
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                } else if isLoading && displaySubs.isEmpty && appState.orders.isEmpty && loadError == nil {
                    Section {
                        PSSkeletonRows(count: 3)
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                } else if let loadError, displaySubs.isEmpty && appState.orders.isEmpty {
                    PSErrorState(message: loadError) {
                        Task { await load() }
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else if displaySubs.isEmpty && appState.orders.isEmpty {
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
                    if let loadError {
                        Section {
                            HStack(spacing: 10) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.psWarning)
                                    .accessibilityHidden(true)
                                Text("Showing your saved slots. The latest list could not be loaded.")
                                    .psTextStyle(.caption)
                                    .foregroundStyle(.psMuted)
                                Spacer()
                                Button("Retry") {
                                    Task { await load() }
                                }
                                .psTextStyle(.caption)
                            }
                        }
                        .listRowBackground(Color.psSurface)
                    }
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
            .psScreenBackground()
            .navigationTitle("My Slots")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.psBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) { CustomerNotificationBell() }
            }
            .refreshable { await load() }
            .task { await load() }
            .onChange(of: deepLinkSubscriptionId.wrappedValue) { _, newId in
                openDeepLink(id: newId)
            }
            .sheet(isPresented: $showAuth) {
                AuthView()
                    .psSheetDetents()
            }
            .sheet(item: $selectedSubscription) { sub in
                SubscriptionDetailSheet(
                    subscription: sub,
                    extras: extras[sub.id],
                    onAutoRenewChanged: { value in
                        updateAutoRenewState(subId: sub.id, value: value)
                    },
                    onReviewRequested: {
                        updateReviewRequested(subId: sub.id)
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
            .alert("Turn off auto-renew?", isPresented: Binding(
                get: { pendingDisableSub != nil },
                set: { if !$0 { pendingDisableSub = nil } }
            )) {
                Button("Turn off auto-renew", role: .destructive) {
                    if let sub = pendingDisableSub {
                        Task { await applyAutoRenew(sub: sub, enable: false) }
                    }
                    pendingDisableSub = nil
                }
                Button("Keep it on", role: .cancel) { pendingDisableSub = nil }
            } message: {
                Text("Your slot will expire on the renewal date and will not renew. You can turn auto-renew back on any time before then.")
            }
            .safeAreaPadding(.bottom, 8)
        }
    }

    // MARK: - Loading, cache first

    private func load() async {
        guard appState.isLoggedIn else {
            cachedSubs = []
            return
        }
        if displaySubs.isEmpty {
            restoreCache()
        }
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let apiSubs = try await appState.api.mySubscriptions()
            let fresh = apiSubs.map(LiveSubscription.init)
            var states: [Int: MySlotState] = [:]
            for api in apiSubs {
                states[api.id] = MySlotState(api)
            }
            await MainActor.run {
                appState.liveSubscriptions = fresh
                extras = states
            }
            cachedSubs = fresh
            saveCache(fresh, states: states)
            loadError = nil
        } catch {
            // Keep whatever is on screen (cached list or nothing).
            // The full error state shows only when there is nothing
            // to show; otherwise the retry banner above the list
            // shows, so a flaky refresh never wipes the screen.
            loadError = error.localizedDescription
        }
        await appState.refreshWallet()
        openDeepLinkIfReady()
    }

    /// Open the deep-linked subscription once it is on screen.
    private func openDeepLinkIfReady() {
        openDeepLink(id: deepLinkSubscriptionId.wrappedValue)
    }

    private func openDeepLink(id: Int?) {
        guard let id else { return }
        guard let sub = displaySubs.first(where: { $0.id == id }) else { return }
        selectedSubscription = sub
        deepLinkSubscriptionId.wrappedValue = nil
    }

    // MARK: - On-device cache (this device only, never faked data)

    private static let cacheKey = "premiumslots.myslots.cache.v1"

    private func restoreCache() {
        guard let data = UserDefaults.standard.data(forKey: Self.cacheKey),
              let items = try? JSONDecoder().decode([MySlotCacheItem].self, from: data) else {
            return
        }
        cachedSubs = items.map { $0.liveSubscription }
        var states: [Int: MySlotState] = [:]
        for item in items {
            states[item.id] = item.state
        }
        extras = states
    }

    private func saveCache(_ subs: [LiveSubscription], states: [Int: MySlotState]) {
        let items = subs.map { MySlotCacheItem(sub: $0, state: states[$0.id]) }
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: Self.cacheKey)
        }
    }

    // MARK: - Per-slot state helpers

    /// Server days remaining when the API returns it, otherwise the
    /// local day difference from the expiry date. Nil when there is
    /// no expiry date at all.
    private func daysRemaining(for sub: LiveSubscription) -> Int? {
        extras[sub.id]?.days_remaining ?? sub.daysLeft
    }

    private func autoRenew(for sub: LiveSubscription) -> Bool? {
        extras[sub.id]?.auto_renew
    }

    private func reviewRequested(for sub: LiveSubscription) -> Bool {
        extras[sub.id]?.review_requested == true
    }

    private func updateAutoRenewState(subId: Int, value: Bool) {
        if extras[subId] == nil {
            extras[subId] = MySlotState(id: subId, days_remaining: nil, auto_renew: value, review_requested: nil)
        } else {
            extras[subId]?.auto_renew = value
        }
    }

    private func updateReviewRequested(subId: Int) {
        if extras[subId] == nil {
            extras[subId] = MySlotState(id: subId, days_remaining: nil, auto_renew: nil, review_requested: true)
        } else {
            extras[subId]?.review_requested = true
        }
        saveCache(displaySubs, states: extras)
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
                        HStack(spacing: 0) {
                            Text("KES \(sub.amountDue)")
                                .psTextStyle(.headline)
                            Text(" · Order #\(sub.id)")
                                .psTextStyle(.caption)
                                .foregroundStyle(.psMuted)
                        }
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
                    autoRenewRow(for: sub)
                    reviewRow(for: sub)
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

    /// Auto-renew toggle on the card, for Active slots only. Shown
    /// only when the server reported the current state; turning it
    /// off asks for confirmation with a destructive button.
    @ViewBuilder
    private func autoRenewRow(for sub: LiveSubscription) -> some View {
        if let renew = autoRenew(for: sub) {
            HStack {
                Label("Auto-renew", systemImage: "arrow.triangle.2.circlepath")
                    .psTextStyle(.body)
                Spacer()
                if togglingIds.contains(sub.id) {
                    PSRingSpinner(diameter: 20, lineWidth: 2, duration: 0.7)
                } else {
                    Toggle("", isOn: autoRenewCardBinding(for: sub, current: renew))
                        .labelsHidden()
                        .accessibilityLabel("Auto-renew for \(sub.serviceRequested), currently \(renew ? "on" : "off")")
                }
            }
        }
    }

    private func autoRenewCardBinding(for sub: LiveSubscription, current: Bool) -> Binding<Bool> {
        Binding(
            get: { autoRenew(for: sub) ?? current },
            set: { newValue in
                if newValue {
                    Task { await applyAutoRenew(sub: sub, enable: true) }
                } else {
                    pendingDisableSub = sub
                }
            }
        )
    }

    /// Request-review row on the card, for Active slots only. After
    /// a successful request it reads "Review requested" and the
    /// button is gone, so the same slot cannot be requested twice
    /// by accident.
    @ViewBuilder
    private func reviewRow(for sub: LiveSubscription) -> some View {
        if reviewRequested(for: sub) {
            Label("Review requested", systemImage: "checkmark.circle.fill")
                .psTextStyle(.caption)
                .foregroundStyle(.psMuted)
        } else {
            Button {
                Task { await requestReview(for: sub) }
            } label: {
                if requestingReviewIds.contains(sub.id) {
                    PSRingSpinner(diameter: 20, lineWidth: 2, color: .psPaper, duration: 0.7)
                } else {
                    Label("Request a review of credentials", systemImage: "star.fill")
                        .psTextStyle(.caption)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
            }
            .buttonStyle(.bordered)
            .tint(.psCyan)
            .disabled(requestingReviewIds.contains(sub.id))
            .accessibilityLabel("Request a review of credentials for \(sub.serviceRequested)")
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

    private func applyAutoRenew(sub: LiveSubscription, enable: Bool) async {
        togglingIds.insert(sub.id)
        defer { togglingIds.remove(sub.id) }
        do {
            let value = try await APIClient.shared.toggleAutoRenew(subscriptionId: sub.id)
            updateAutoRenewState(subId: sub.id, value: value)
            saveCache(displaySubs, states: extras)
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func requestReview(for sub: LiveSubscription) async {
        requestingReviewIds.insert(sub.id)
        defer { requestingReviewIds.remove(sub.id) }
        do {
            try await APIClient.shared.requestReview(subscriptionId: sub.id)
            updateReviewRequested(subId: sub.id)
        } catch {
            actionError = error.localizedDescription
        }
    }
}

// MARK: - Per-subscription server state (from /me/subscriptions)
// The subscriptions response itself carries days_remaining,
// auto_renew and review_requested (optional on older backends).
// Reading them here, instead of a second extras call, is what
// makes the auto-renew toggle and the review state actually
// appear: the old extras call returned nil for both on the
// current backend, so the toggle was hidden behind
// "Not available yet" on almost every slot.

struct MySlotState: Decodable {
    let id: Int
    var days_remaining: Int?
    var auto_renew: Bool?
    var review_requested: Bool?

    init(id: Int, days_remaining: Int?, auto_renew: Bool?, review_requested: Bool?) {
        self.id = id
        self.days_remaining = days_remaining
        self.auto_renew = auto_renew
        self.review_requested = review_requested
    }

    init(_ api: APISubscription) {
        self.id = api.id
        self.days_remaining = api.days_remaining
        self.auto_renew = api.auto_renew
        self.review_requested = api.review_requested
    }
}

/// One cached subscription, for the on-device cache only. Built
/// from the live API values, never from invented data.
struct MySlotCacheItem: Codable {
    let id: Int
    let serviceRequested: String
    let amountDue: Int
    let mpesaCode: String?
    let status: String
    let expiryDate: String?
    let issueReported: Bool
    let accountGroup: String?
    let lockedPrice: Int?
    let createdAt: String?
    let daysRemaining: Int?
    let autoRenew: Bool?
    let reviewRequested: Bool?

    init(sub: LiveSubscription, state: MySlotState?) {
        self.id = sub.id
        self.serviceRequested = sub.serviceRequested
        self.amountDue = sub.amountDue
        self.mpesaCode = sub.mpesaCode
        self.status = sub.status
        self.expiryDate = sub.expiryDate
        self.issueReported = sub.issueReported
        self.accountGroup = sub.accountGroup
        self.lockedPrice = sub.lockedPrice
        self.createdAt = sub.createdAt
        self.daysRemaining = state?.days_remaining
        self.autoRenew = state?.auto_renew
        self.reviewRequested = state?.review_requested
    }

    var state: MySlotState {
        MySlotState(
            id: id,
            days_remaining: daysRemaining,
            auto_renew: autoRenew,
            review_requested: reviewRequested
        )
    }

    var liveSubscription: LiveSubscription {
        LiveSubscription(APISubscription(
            id: id,
            service_requested: serviceRequested,
            amount_due: amountDue,
            mpesa_code: mpesaCode,
            delivery_type: nil,
            status: status,
            expiry_date: expiryDate,
            viewed: nil,
            issue_reported: issueReported,
            account_group: accountGroup,
            locked_price: lockedPrice,
            created_at: createdAt,
            days_remaining: daysRemaining,
            auto_renew: autoRenew,
            review_requested: reviewRequested,
            customer_name: nil,
            customer_whatsapp: nil,
            customer_email: nil
        ))
    }
}

// MARK: - Subscription detail sheet (timeline + request-review;
// v5: start/renewal dates, auto-renew toggle, support actions)
// Timeline from GET /api/v1/me/subscriptions/<id>/timeline (OrderEvents);
// request-review via APIClient.requestReview
// (POST /api/v1/me/subscriptions/<id>/request-review).
// Auto-renew uses POST /api/v1/subscription/<id>/toggle-auto-renew,
// which flips the server flag and returns the new value. The toggle
// is shown only when the server reported the current state; turning
// it off asks for confirmation with a destructive button, kept
// separate from every other action.

struct SubscriptionDetailSheet: View {
    let subscription: LiveSubscription
    let extras: MySlotState?
    var onAutoRenewChanged: ((Bool) -> Void)?
    var onReviewRequested: (() -> Void)?

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
    @State private var reviewRequested: Bool
    @State private var issueReported: Bool
    @State private var issueMessage: String?
    @State private var isReportingIssue = false

    init(subscription: LiveSubscription, extras: MySlotState? = nil, onAutoRenewChanged: ((Bool) -> Void)? = nil, onReviewRequested: (() -> Void)? = nil) {
        self.subscription = subscription
        self.extras = extras
        self.onAutoRenewChanged = onAutoRenewChanged
        self.onReviewRequested = onReviewRequested
        _autoRenewState = State(initialValue: extras?.auto_renew)
        _reviewRequested = State(initialValue: extras?.review_requested == true)
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
                    if autoRenewState != nil {
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
                    if reviewRequested {
                        Label("Review requested", systemImage: "checkmark.circle.fill")
                            .psTextStyle(.body)
                            .foregroundStyle(.psMuted)
                    } else {
                        Button {
                            Task { await requestReview() }
                        } label: {
                            if isRequestingReview { PSRingSpinner(diameter: 20, lineWidth: 2, color: .psPaper, duration: 0.7) }
                            else { Label("Request a review", systemImage: "star.fill") }
                        }
                        .psPrimary()
                        .disabled(isRequestingReview)
                        .accessibilityLabel("Request a review of \(subscription.serviceRequested)")
                    }
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
            try await APIClient.shared.requestReview(subscriptionId: subscription.id)
            reviewRequested = true
            onReviewRequested?()
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
