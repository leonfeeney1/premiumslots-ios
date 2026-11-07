import SwiftUI

// MARK: - Notifications, Fix #4
// Checklist 1.7: GET /api/v1/me/notifications returns the last 30
// from NotificationQueue plus unread_count; POST
// /api/v1/me/notifications/read marks all, or the ids given, as read.
// Kinds seen in code: system, subscription, referral, achievement.
// No NavigationStack here: this view is pushed from Settings or the
// dashboard, so it uses the parent stack. No emojis, SF Symbols only.

// MARK: - Customer notification bell (reusable)
// The customer notification centre existed as a screen but had no
// entry point from Home or My Slots. Drop this in a header toolbar:
// it opens NotificationsRootView and shows the unread count as a
// badge. PLACEMENT (Home header and My Slots header are owned by
// another agent): in HomeView add
//   .toolbar { ToolbarItem(placement: .navigationBarTrailing) { CustomerNotificationBell() } }
// to the NavigationStack, and the same line in MySlotsView. The bell
// loads its own count from GET /api/v1/me/notifications and hides
// the badge when signed out or unreachable, so it never blocks the
// header it sits in.

struct CustomerNotificationBell: View {
    @State private var unreadCount: Int?

    var body: some View {
        NavigationLink {
            NotificationsRootView()
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bell.fill")
                    .imageScale(.large)
                    .foregroundStyle(.psText)
                if let unreadCount, unreadCount > 0 {
                    Text(unreadCount > 99 ? "99+" : "\(unreadCount)")
                        .font(.psCaption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.psDanger)
                        .clipShape(Capsule())
                        .offset(x: 10, y: -8)
                }
            }
        }
        .accessibilityLabel(unreadCount.map { "\($0) unread notifications" } ?? "Notifications")
        .task { await loadUnread() }
    }

    private func loadUnread() async {
        do {
            let response: NtfResponse = try await APIClient.shared.fetchJSON("api/v1/me/notifications")
            unreadCount = response.unread_count ?? response.notifications.filter(\.isUnread).count
        } catch {
            unreadCount = nil
        }
    }
}

struct NotificationsRootView: View {
    @State private var notifications: [NtfNotification] = []
    @State private var unreadCount: Int?
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var actionMessage: String?
    @State private var isMarkingRead = false

    var body: some View {
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
                    if isMarkingRead { PSRingSpinner(diameter: 20, lineWidth: 2, color: .white, duration: 0.7) }
                    else { Label("Mark all as read", systemImage: "checkmark.circle.fill") }
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

            if let loadError {
                PSErrorState(message: loadError) {
                    Task { await load() }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else if isLoading && notifications.isEmpty {
                HStack {
                    Spacer()
                    PSRingSpinner(diameter: 28, lineWidth: 3)
                    Spacer()
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else if notifications.isEmpty {
                PSEmptyState(
                    systemImage: "bell",
                    title: "No notifications",
                    body: "Order updates, renewal reminders and referral news will appear here."
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                Section("Last 30") {
                    ForEach(notifications) { item in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: icon(for: item.kindKey))
                                .imageScale(.large)
                                .foregroundStyle(.psCyan)
                                .frame(width: 22)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(item.title ?? item.kind ?? "Notification")
                                        .font(.psHeadline)
                                    if item.isUnread {
                                        Circle()
                                            .fill(Color.psCyan)
                                            .frame(width: 8, height: 8)
                                            .accessibilityLabel("Unread")
                                    }
                                }
                                if let kind = item.kind, !kind.isEmpty {
                                    Text(psCapitalized(kind.replacingOccurrences(of: "_", with: " ")))
                                        .font(.psCaption)
                                        .foregroundStyle(.psMuted)
                                }
                                if let body = item.bodyText, !body.isEmpty {
                                    Text(body)
                                        .font(.psBody)
                                        .foregroundStyle(.psMuted)
                                }
                                if let date = item.created_at {
                                    Text(psShortDate(date))
                                        .font(.psCaption)
                                        .foregroundStyle(.psMuted)
                                }
                                if item.isUnread, let id = item.id {
                                    Button("Mark as read") {
                                        Task { await markRead(ids: [id]) }
                                    }
                                    .font(.psCaption)
                                    .accessibilityLabel("Mark notification as read")
                                }
                            }
                        }
                        .psTouchTarget()
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .background(Color.psBackground)
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .safeAreaPadding(.bottom, 8)
    }

    private func icon(for kind: String?) -> String {
        switch kind {
        case "subscription", "order", "order_approved", "order_rejected":
            return "creditcard.fill"
        case "referral": return "person.2.fill"
        case "achievement": return "trophy.fill"
        case "wallet": return "wallet.pass.fill"
        case "ticket", "ticket_reply": return "envelope.fill"
        case "expiry", "renewal": return "clock.fill"
        default: return "bell.fill"
        }
    }

    private func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let response: NtfResponse = try await APIClient.shared.fetchJSON("api/v1/me/notifications")
            notifications = response.notifications
            // The server returns unread_count null when the table has
            // no read flag. Count from the list instead of showing 0.
            unreadCount = response.unread_count ?? response.notifications.filter(\.isUnread).count
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func markAllRead() async {
        isMarkingRead = true
        defer { isMarkingRead = false }
        do {
            let _: APIResponse = try await APIClient.shared.fetchOK(
                "api/v1/me/notifications/read", method: "POST", body: [:])
            actionMessage = "All notifications marked as read."
            await load()
        } catch {
            actionMessage = error.localizedDescription
        }
    }

    private func markRead(ids: [Int]) async {
        do {
            let _: APIResponse = try await APIClient.shared.fetchOK(
                "api/v1/me/notifications/read", method: "POST", body: ["ids": ids])
            actionMessage = "Notification marked as read."
            await load()
        } catch {
            actionMessage = error.localizedDescription
        }
    }
}

// MARK: - Notification response types (keys from backend/api_v1.py)
// The list endpoint returns raw NotificationQueue rows. The real
// columns are user_id, kind, title, body, link and is_read: the
// body lives in "body", not "message", and the kind in "kind", not
// "type". Both old names are kept as fallbacks only.

struct NtfNotification: Decodable, Identifiable {
    let id: Int?
    let title: String?
    let message: String?
    let body: String?
    let kind: String?
    let type: String?
    let link: String?
    let is_read: Bool?
    let read_at: String?
    let created_at: String?

    var bodyText: String? { message ?? body }
    var kindKey: String? { kind ?? type }
    var isUnread: Bool {
        if let is_read { return !is_read }
        return read_at == nil
    }
}

struct NtfResponse: Decodable {
    let ok: Bool
    let notifications: [NtfNotification]
    let unread_count: Int?
}

#Preview {
    NavigationStack {
        NotificationsRootView()
    }
}
