import SwiftUI

// MARK: - Notifications, Fix #4
// Checklist 1.7: GET /api/v1/me/notifications returns the last 30
// from NotificationQueue plus unread_count; POST
// /api/v1/me/notifications/read marks all, or the ids given, as read.
// Kinds seen in code: system, subscription, referral, achievement.
// No NavigationStack here: this view is pushed from Settings or the
// dashboard, so it uses the parent stack. No emojis, SF Symbols only.

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
                            Image(systemName: icon(for: item.kind))
                                .font(.system(size: 20))
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
                                if let body = item.bodyText, !body.isEmpty {
                                    Text(body)
                                        .font(.psBody)
                                        .foregroundStyle(.psMuted)
                                }
                                if let date = item.created_at {
                                    Text(date)
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
        .background(Color.psBackground)
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .safeAreaPadding(.bottom, 8)
    }

    private func icon(for kind: String?) -> String {
        switch kind {
        case "subscription": return "creditcard.fill"
        case "referral": return "person.2.fill"
        case "achievement": return "trophy.fill"
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
            unreadCount = response.unread_count
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
// The list endpoint returns raw NotificationQueue rows, so the title,
// message and kind keys are all optional here.

struct NtfNotification: Decodable, Identifiable {
    let id: Int?
    let title: String?
    let message: String?
    let body: String?
    let kind: String?
    let type: String?
    let is_read: Bool?
    let read_at: String?
    let created_at: String?

    var bodyText: String? { message ?? body }
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
