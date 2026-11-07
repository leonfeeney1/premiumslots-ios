import SwiftUI
import UserNotifications

// MARK: - Admin notifications, v4
// GET /api/v1/admin/notifications returns the newest admin events
// from real tables only (Subscriptions, SupportTickets,
// WalletTransactions), newest first, each with id, kind, title,
// detail, created_at and is_read. GET
// /api/v1/admin/notifications/unread-count returns the badge count.
// POST /api/v1/admin/notifications/mark-read marks unviewed
// subscriptions viewed; tickets clear when resolved and deposits
// when approved or rejected. No admin data is ever faked or bundled.
// No emojis, SF Symbols only, Theme.swift tokens only.

// MARK: - Models

struct AdminNotification: Decodable, Identifiable, Equatable {
    let id: String
    let kind: String
    let title: String
    let detail: String?
    let created_at: String?
    let is_read: Bool?
    let ref_id: Int?

    var isUnread: Bool { is_read == false }

    var relativeDate: String {
        AdminNotificationsRootView.relativeDate(created_at)
    }

    var systemImage: String {
        switch kind {
        case "new_subscription": return "creditcard.fill"
        case "issue_reported": return "exclamationmark.circle.fill"
        case "new_ticket": return "envelope.open.fill"
        case "wallet_deposit_pending": return "wallet.bifold.fill"
        default: return "bell.fill"
        }
    }

    var tint: Color {
        switch kind {
        case "new_subscription": return .psCyan
        case "issue_reported": return .psDanger
        case "new_ticket": return .psAmber
        case "wallet_deposit_pending": return .psAmber
        default: return .psMuted
        }
    }
}

struct AdminNotificationsResponse: Decodable {
    let ok: Bool
    let notifications: [AdminNotification]?
    let unread_count: Int?
    let total: Int?
}

// MARK: - Notifications screen

struct AdminNotificationsRootView: View {
    @EnvironmentObject private var appState: AppState
    @State private var notifications: [AdminNotification] = []
    @State private var unreadCount: Int?
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var actionMessage: String?
    @State private var isMarkingRead = false
    /// Deep-link destination for the tapped notification. Set by
    /// the row tap; navigationDestination below pushes the real
    /// admin screen for that event. No tap is dead.
    @State private var destination: AdminNotificationDestination?

    var body: some View {
        Group {
            if !appState.isAdminLoggedIn {
                AdminNotSignedInView()
            } else if isLoading && notifications.isEmpty {
                ScrollView {
                    AdminSkeletonView(lines: 5, title: "Loading notifications")
                }
                .scrollIndicators(.hidden)
                .adminFullScreenFrame()
            } else if let loadError, notifications.isEmpty {
                PSErrorState(message: loadError) {
                    Task { await load() }
                }
                .psScreenPadding()
                .adminFullScreenFrame()
            } else {
                content
            }
        }
        .adminScreenBackground()
        .navigationTitle("Notifications")
        .navigationDestination(item: $destination) { target in
            switch target {
            case .subscription(let id):
                AdminSubscriptionsRootView(preselectedSubscriptionId: id)
            case .ticket(let id):
                AdminTicketsRootView(highlightedTicketId: id)
            case .deposit(let id):
                AdminWalletRootView(highlightedDepositId: id)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task {
            await load()
            await pollWhileVisible()
        }
        .safeAreaPadding(.bottom, 8)
    }

    private var content: some View {
        List {
            Section {
                HStack {
                    Label("Unread", systemImage: "bell.fill")
                        .font(.psBody)
                    Spacer()
                    Text("\(unreadCount ?? 0)")
                        .font(.psHeadline)
                        .foregroundStyle(.psCyan)
                        .accessibilityLabel("\(unreadCount ?? 0) unread notifications")
                }
                Button {
                    Task { await markAllRead() }
                } label: {
                    if isMarkingRead {
                        PSRingSpinner(diameter: 20, lineWidth: 2, color: .white, duration: 0.7)
                    } else {
                        Label("Mark all as read", systemImage: "checkmark.circle.fill")
                    }
                }
                .psPrimary()
                .disabled(isMarkingRead || notifications.isEmpty)
                if let actionMessage {
                    Text(actionMessage)
                        .font(.psCaption)
                        .foregroundStyle(.psMuted)
                }
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            if notifications.isEmpty {
                PSEmptyState(
                    systemImage: "bell",
                    title: "No admin events",
                    body: "New subscriptions, reported issues, support tickets and pending wallet deposits will appear here."
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                Section("Newest first") {
                    ForEach(notifications) { item in
                        Button {
                            openNotification(item)
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: item.systemImage)
                                    .font(.psIcon)
                                    .foregroundStyle(item.tint)
                                    .frame(width: 22)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(item.title)
                                            .font(.psHeadline)
                                            .foregroundStyle(.psText)
                                        if item.isUnread {
                                            Circle()
                                                .fill(Color.psCyan)
                                                .frame(width: 8, height: 8)
                                                .accessibilityLabel("Unread")
                                        }
                                    }
                                    if let detail = item.detail, !detail.isEmpty {
                                        Text(detail)
                                            .font(.psBody)
                                            .foregroundStyle(.psMuted)
                                    }
                                    if !item.relativeDate.isEmpty {
                                        Text(item.relativeDate)
                                            .font(.psCaption)
                                            .foregroundStyle(.psMuted)
                                    }
                                    Text(destinationLabel(for: item))
                                        .font(.psCaption)
                                        .foregroundStyle(.psCyan)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.psCaption)
                                    .foregroundStyle(.psMuted)
                                    .accessibilityHidden(true)
                            }
                        }
                        .buttonStyle(.plain)
                        .psTouchTarget()
                        .accessibilityLabel("\(item.title). Open \(destinationLabel(for: item).lowercased()).")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    /// Polls the feed every 60 seconds while this screen is visible.
    /// The task is cancelled when the screen goes away.
    private func pollWhileVisible() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(60))
            if Task.isCancelled { break }
            await load()
        }
    }

    /// Plain-language destination for a notification row, so the
    /// tap target is honest about where it goes.
    private func destinationLabel(for item: AdminNotification) -> String {
        guard let target = AdminNotificationDestination.from(notification: item) else {
            return "Open notifications"
        }
        switch target {
        case .subscription: return "Open subscription"
        case .ticket: return "Open ticket"
        case .deposit: return "Open deposit"
        }
    }

    /// Opens the destination for a tapped notification. A
    /// notification with no usable reference id stays on this
    /// list and says so instead of navigating nowhere.
    private func openNotification(_ item: AdminNotification) {
        guard let target = AdminNotificationDestination.from(notification: item) else {
            actionMessage = "This event has no linked order, ticket or deposit to open."
            return
        }
        destination = target
    }

    private func load() async {
        guard appState.isAdminLoggedIn else { return }
        // Cache first: show the last saved feed immediately, then
        // refresh live.
        if let cached = AdminCache.load(key: "admin-notifications"),
           let decoded = try? JSONDecoder().decode(AdminNotificationsResponse.self, from: cached),
           decoded.ok {
            notifications = decoded.notifications ?? []
            unreadCount = decoded.unread_count
        }
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let data = try await APIClient.shared.fetchData("api/v1/admin/notifications")
            let response = try JSONDecoder().decode(AdminNotificationsResponse.self, from: data)
            guard response.ok else {
                if notifications.isEmpty {
                    loadError = "Admin needs the live API. The notifications endpoint did not return data."
                }
                return
            }
            AdminCache.save(data, key: "admin-notifications")
            notifications = response.notifications ?? []
            unreadCount = response.unread_count
            if let unreadCount {
                appState.adminUnreadCount = unreadCount
            }
        } catch {
            if notifications.isEmpty {
                loadError = error.localizedDescription
            } else {
                actionMessage = "Live refresh failed: \(error.localizedDescription). Showing the last saved notifications."
            }
        }
    }

    private func markAllRead() async {
        isMarkingRead = true
        defer { isMarkingRead = false }
        do {
            let _: APIResponse = try await APIClient.shared.adminMarkAllNotificationsRead()
            actionMessage = "Unviewed subscriptions marked as read. Tickets clear when resolved and deposits when approved or rejected."
            await load()
            await appState.adminNotifier.refreshUnreadCount()
        } catch {
            actionMessage = error.localizedDescription
        }
    }

    /// Relative timestamp ("2 hours ago") from an ISO string. Falls
    /// back to the plain date when the string cannot be parsed.
    static func relativeDate(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "" }
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        guard let date = withFractional.date(from: value) ?? plain.date(from: value) else {
            return String(value.prefix(10))
        }
        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .full
        return relative.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Admin notifier (v4)
// Polls GET /api/v1/admin/subscriptions?status=Pending every 60
// seconds while an admin session exists (started by AppState on
// admin sign-in, stopped on sign-out). When a pending subscription
// id appears that was not seen before, it fires a LOCAL notification
// through UNUserNotificationCenter and the unread badge updates from
// GET /api/v1/admin/notifications/unread-count. The first poll after
// sign-in only records the pending ids as seen, so existing pending
// orders do not all alert at once. Seen ids persist across launches.
// This is local polling, not push: true push notifications need APNs
// plus a server push, which are NOT in this build.

@MainActor
final class AdminNotifier: ObservableObject {
    @Published private(set) var unreadCount = 0
    @Published private(set) var pendingCount = 0
    var onUnreadCount: (@MainActor (Int) -> Void)?

    private let api = APIClient.shared
    private var pollTask: Task<Void, Never>?
    private var seenPendingIds: Set<Int> = []
    private var didSeedSeen = false
    private let seenKey = "premiumslots.admin.seenPending.v1"
    private let seededKey = "premiumslots.admin.seenPending.seeded.v1"
    private let authAskedKey = "premiumslots.admin.localNotifyAuthAsked.v1"

    func start() {
        guard pollTask == nil else { return }
        loadSeen()
        pollTask = Task { await pollLoop() }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    func pollOnce() async {
        await refreshPending()
        await refreshUnreadCount()
    }

    func refreshUnreadCount() async {
        do {
            let count = try await api.adminNotificationsUnreadCount()
            unreadCount = count
            onUnreadCount?(count)
        } catch {
            // Unreachable: keep the last known count; the next good
            // poll refreshes the badge.
        }
    }

    private func pollLoop() async {
        while !Task.isCancelled {
            await pollOnce()
            try? await Task.sleep(for: .seconds(60))
        }
    }

    private func refreshPending() async {
        do {
            let pending = try await api.adminSubscriptions(status: "Pending")
            pendingCount = pending.count
            let ids = Set(pending.map { $0.id })
            if !didSeedSeen {
                seenPendingIds = ids
                didSeedSeen = true
                saveSeen()
                return
            }
            let fresh = pending.filter { !seenPendingIds.contains($0.id) }
            seenPendingIds = ids
            saveSeen()
            for sub in fresh {
                fireLocalNotification(subscription: sub)
            }
        } catch {
            // Unreachable: keep the last known pending set.
        }
    }

    private func fireLocalNotification(subscription: APISubscription) {
        let center = UNUserNotificationCenter.current()
        if !UserDefaults.standard.bool(forKey: authAskedKey) {
            UserDefaults.standard.set(true, forKey: authAskedKey)
            center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        }
        let content = UNMutableNotificationContent()
        content.title = "New subscription pending"
        content.body = "\(subscription.service_requested) for \(subscription.customerDisplayName)"
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "pending-sub-\(subscription.id)",
            content: content,
            trigger: nil)
        center.add(request)
    }

    private func loadSeen() {
        didSeedSeen = UserDefaults.standard.bool(forKey: seededKey)
        let saved = UserDefaults.standard.array(forKey: seenKey) as? [Int] ?? []
        seenPendingIds = Set(saved)
    }

    private func saveSeen() {
        UserDefaults.standard.set(Array(seenPendingIds), forKey: seenKey)
        UserDefaults.standard.set(true, forKey: seededKey)
    }
}

#Preview {
    NavigationStack {
        AdminNotificationsRootView()
            .environmentObject(AppState())
    }
}
