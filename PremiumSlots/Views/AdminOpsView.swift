import SwiftUI

// MARK: - Admin ops, v3 Fix #4 (checklist sections 2.6-2.7)
// Tickets, waitlist messaging, suggestions, comms (bulk email,
// broadcast, promo banner), security logs, recycle bin and backup
// status, from the live /api/v1/admin/* endpoints. Backup is a
// status view only by design: no download, upload or restore is
// built (checklist section 6.4). No raw database query screen.
// No emojis, SF Symbols only, Theme.swift tokens only.

// MARK: - Support tickets
// GET /api/v1/admin/tickets returns {"ok": true, "tickets": [rows]}.
// POST /api/v1/admin/tickets/<id>/resolve returns
// {"status": "resolved"}. POST /api/v1/admin/tickets/<id>/delete
// deletes the ticket. SupportTickets rows are flat _row_dict rows.

struct AdminTicketsResponse: Decodable {
    let ok: Bool
    let tickets: [AdminGenericRow]?
}

struct AdminTicketsRootView: View {
    /// Deep link from an admin notification: when set, that ticket
    /// is pinned at the top of the list so a tap lands on it.
    var highlightedTicketId: Int? = nil

    @EnvironmentObject private var appState: AppState
    @State private var tickets: [AdminGenericRow] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var message: String?
    @State private var isWorking = false
    @State private var confirmDelete: AdminGenericRow?

    private var openTickets: [AdminGenericRow] {
        tickets.filter { ($0.text("status") ?? "open").lowercased() != "resolved" }
    }

    var body: some View {
        Group {
            if !appState.isAdminLoggedIn {
                AdminNotSignedInView()
            } else if isLoading && tickets.isEmpty {
                ScrollView {
                    AdminSkeletonView(lines: 4, title: "Loading tickets")
                }
                .scrollIndicators(.hidden)
                .adminFullScreenFrame()
            } else if let errorMessage, tickets.isEmpty {
                PSErrorState(message: errorMessage) {
                    Task { await load() }
                }
                .psScreenPadding()
                .adminFullScreenFrame()
            } else {
                content
            }
        }
        .adminScreenBackground()
        .navigationTitle("Support tickets")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .alert("Delete ticket?", isPresented: .constant(confirmDelete != nil)) {
            Button("Delete", role: .destructive) {
                if let ticket = confirmDelete {
                    confirmDelete = nil
                    Task { await deleteTicket(ticket) }
                }
            }
            Button("Cancel", role: .cancel) { confirmDelete = nil }
        } message: {
            Text("Ticket #\(confirmDelete?.id ?? 0) will be deleted. This cannot be undone.")
        }
    }

    private var highlightedTicket: AdminGenericRow? {
        guard let target = highlightedTicketId else { return nil }
        return tickets.first { $0.id == target }
    }

    private var content: some View {
        List {
            if let message {
                Section {
                    Text(message)
                        .font(.psCaption)
                        .foregroundStyle(.psMuted)
                }
            }
            if let highlightedTicket {
                Section("From notification") {
                    ticketRow(highlightedTicket)
                }
            }
            Section("Open (\(openTickets.count))") {
                if openTickets.isEmpty {
                    PSEmptyState(
                        systemImage: "envelope.open.fill",
                        title: "No open tickets",
                        body: "Customer support tickets will appear here."
                    )
                }
                ForEach(openTickets) { ticket in
                    ticketRow(ticket)
                }
            }
            Section("All tickets") {
                ForEach(tickets) { ticket in
                    ticketRow(ticket)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
    }

    private func ticketRow(_ ticket: AdminGenericRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(ticket.first("subject", "message_type") ?? "Ticket #\(ticket.id)")
                    .font(.psHeadline)
                Spacer()
                PSStatusPill(
                    text: ticket.text("status") ?? "open",
                    systemImage: (ticket.text("status") ?? "").lowercased() == "resolved" ? "checkmark.circle.fill" : "clock.fill",
                    tint: (ticket.text("status") ?? "").lowercased() == "resolved" ? .psSuccess : .psAmber
                )
            }
            if let body = ticket.text("message") {
                Text(body)
                    .font(.psBody)
                    .foregroundStyle(.psMuted)
                    .lineLimit(3)
            }
            Text("Ticket #\(ticket.id) · user \(ticket.text("user_id") ?? "-") · \(adminShortDate(ticket.text("created_at")))")
                .font(.psCaption)
                .foregroundStyle(.psMuted)
            HStack(spacing: 10) {
                if (ticket.text("status") ?? "").lowercased() != "resolved" {
                    Button("Resolve") { Task { await resolve(ticket) } }
                        .buttonStyle(.bordered)
                        .tint(.psPrimary)
                        .font(.psCaption)
                        .disabled(isWorking)
                        .accessibilityLabel("Resolve ticket \(ticket.id)")
                }
                Button("Delete", role: .destructive) { confirmDelete = ticket }
                    .buttonStyle(.bordered)
                    .font(.psCaption)
                    .disabled(isWorking)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private func load() async {
        guard appState.isAdminLoggedIn else { return }
        if let cached = AdminCache.load(key: "admin-tickets"),
           let decoded = try? JSONDecoder().decode(AdminTicketsResponse.self, from: cached),
           decoded.ok {
            tickets = decoded.tickets ?? []
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let data = try await APIClient.shared.fetchData("api/v1/admin/tickets")
            let result = try JSONDecoder().decode(AdminTicketsResponse.self, from: data)
            guard result.ok else {
                if tickets.isEmpty {
                    errorMessage = "Admin needs the live API. The tickets endpoint did not return data."
                }
                return
            }
            AdminCache.save(data, key: "admin-tickets")
            tickets = result.tickets ?? []
        } catch {
            if tickets.isEmpty {
                errorMessage = error.localizedDescription
            } else {
                message = "Live refresh failed: \(error.localizedDescription). Showing the last saved tickets."
            }
        }
    }

    private func resolve(_ ticket: AdminGenericRow) async {
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await APIClient.shared.fetchOK(
                "api/v1/admin/tickets/\(ticket.id)/resolve", method: "POST")
            message = "Ticket #\(ticket.id) resolved."
            await load()
        } catch {
            message = error.localizedDescription
        }
    }

    private func deleteTicket(_ ticket: AdminGenericRow) async {
        // Note: delete is a POST, not a DELETE, on this endpoint.
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await APIClient.shared.fetchOK(
                "api/v1/admin/tickets/\(ticket.id)/delete", method: "POST")
            message = "Ticket #\(ticket.id) deleted."
            await load()
        } catch {
            message = error.localizedDescription
        }
    }
}

// MARK: - Waitlist message
// POST /api/v1/admin/waitlist/message with
// {"message": ..., "service_requested"?} returns
// {"messaged": Int} (users queued for a notification).

struct AdminWaitlistView: View {
    @EnvironmentObject private var appState: AppState
    @State private var service = ""
    @State private var messageText = ""
    @State private var isWorking = false
    @State private var message: String?

    var body: some View {
        Group {
            if !appState.isAdminLoggedIn {
                AdminNotSignedInView()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        PSCard {
                            VStack(alignment: .leading, spacing: 12) {
                                PSSectionHeader(title: "Message waitlisted users")
                                Text("Queues a notification for every waitlisted user, or only those waiting for the service named below. Email is best-effort.")
                                    .font(.psCaption)
                                    .foregroundStyle(.psMuted)
                                TextField("Service (optional, blank means all)", text: $service)
                                    .autocorrectionDisabled()
                                    .psTextField()
                                TextField("Message", text: $messageText, axis: .vertical)
                                    .lineLimit(4...)
                                    .psTextField()
                                Button("Send to waitlist") { Task { await send() } }
                                    .psPrimary()
                                    .disabled(isWorking || messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                    .accessibilityLabel("Send message to waitlisted users")
                            }
                        }
                        if isWorking {
                            PSRingSpinner(diameter: 20, lineWidth: 2)
                                .frame(maxWidth: .infinity)
                        }
                        if let message {
                            Text(message)
                                .font(.psCaption)
                                .foregroundStyle(.psMuted)
                        }
                    }
                    .psScreenPadding()
                }
                .scrollIndicators(.hidden)
            }
        }
        .adminScreenBackground()
        .navigationTitle("Waitlist")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func send() async {
        struct WaitlistResponse: Decodable { let ok: Bool; let messaged: Int? }
        var body: [String: Any] = ["message": messageText]
        let trimmedService = service.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedService.isEmpty { body["service_requested"] = trimmedService }
        isWorking = true
        defer { isWorking = false }
        do {
            let result: WaitlistResponse = try await APIClient.shared.fetchJSON(
                "api/v1/admin/waitlist/message", method: "POST", body: body)
            message = "Message queued for \(result.messaged ?? 0) waitlisted users."
            messageText = ""
        } catch {
            message = error.localizedDescription
        }
    }
}

// MARK: - Suggested services (admin)
// GET /api/v1/admin/suggestions returns
// {"ok": true, "suggestions": [SuggestedServices rows]}.
// DELETE /api/v1/admin/suggestions/<id> deletes one.

struct AdminSuggestionsResponse: Decodable {
    let ok: Bool
    let suggestions: [AdminGenericRow]?
}

struct AdminSuggestionsRootView: View {
    @EnvironmentObject private var appState: AppState
    @State private var suggestions: [AdminGenericRow] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var message: String?
    @State private var confirmDelete: AdminGenericRow?

    var body: some View {
        Group {
            if !appState.isAdminLoggedIn {
                AdminNotSignedInView()
            } else if isLoading && suggestions.isEmpty {
                ScrollView {

                    AdminSkeletonView(lines: 4, title: "Loading suggestions")

                }

                .scrollIndicators(.hidden)

                .adminFullScreenFrame()
            } else if let errorMessage, suggestions.isEmpty {
                PSErrorState(message: errorMessage) {
                    Task { await load() }
                }
                .psScreenPadding()
            } else {
                content
            }
        }
        .adminScreenBackground()
        .navigationTitle("Suggestions")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .alert("Delete suggestion?", isPresented: .constant(confirmDelete != nil)) {
            Button("Delete", role: .destructive) {
                if let suggestion = confirmDelete {
                    confirmDelete = nil
                    Task { await deleteSuggestion(suggestion) }
                }
            }
            Button("Cancel", role: .cancel) { confirmDelete = nil }
        } message: {
            Text("This suggestion will be deleted. This cannot be undone.")
        }
    }

    private var content: some View {
        List {
            if let message {
                Section {
                    Text(message)
                        .font(.psCaption)
                        .foregroundStyle(.psMuted)
                }
            }
            Section {
                if suggestions.isEmpty {
                    PSEmptyState(
                        systemImage: "lightbulb.fill",
                        title: "No suggestions yet",
                        body: "Community suggestions for new platforms will appear here."
                    )
                }
                ForEach(suggestions) { suggestion in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(suggestion.first("service_name", "name", "suggestion") ?? "Suggestion #\(suggestion.id)")
                            .font(.psHeadline)
                        if let email = suggestion.text("email") {
                            Text(email)
                                .font(.psCaption)
                                .foregroundStyle(.psMuted)
                        }
                        Text(adminShortDate(suggestion.text("created_at")))
                            .font(.psCaption)
                            .foregroundStyle(.psMuted)
                        Button("Delete", role: .destructive) { confirmDelete = suggestion }
                            .buttonStyle(.bordered)
                            .font(.psCaption)
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
    }

    private func load() async {
        guard appState.isAdminLoggedIn else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let result: AdminSuggestionsResponse = try await APIClient.shared.fetchJSON("api/v1/admin/suggestions")
            guard result.ok else {
                errorMessage = "Admin needs the live API. The suggestions endpoint did not return data."
                return
            }
            suggestions = result.suggestions ?? []
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteSuggestion(_ suggestion: AdminGenericRow) async {
        do {
            _ = try await APIClient.shared.deleteOK("api/v1/admin/suggestions/\(suggestion.id)")
            message = "Suggestion deleted."
            await load()
        } catch {
            message = error.localizedDescription
        }
    }
}

// MARK: - Comms: bulk email, broadcast, promo banner
// POST /api/v1/admin/bulk-email with
// {"subject", "body", "user_ids"?, "audience": "all"|"verified"|"active"}
// returns {"emailed": Int}.
// POST /api/v1/admin/broadcast with
// {"message", "title"?, "global_alert"?} returns {"broadcast_to": Int}.
// POST /api/v1/admin/settings/promo-banner with
// {"text", "enabled"} returns {"promo_banner_text", "promo_banner_enabled"}.

struct AdminCommsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var emailSubject = ""
    @State private var emailBody = ""
    @State private var emailAudience = "all"
    @State private var broadcastTitle = ""
    @State private var broadcastMessage = ""
    @State private var setGlobalAlert = false
    @State private var promoText = ""
    @State private var promoEnabled = false
    @State private var isWorking = false
    @State private var message: String?

    var body: some View {
        Group {
            if !appState.isAdminLoggedIn {
                AdminNotSignedInView()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        PSCard {
                            VStack(alignment: .leading, spacing: 12) {
                                PSSectionHeader(title: "Bulk email")
                                TextField("Subject", text: $emailSubject)
                                    .psTextField()
                                TextField("Message", text: $emailBody, axis: .vertical)
                                    .lineLimit(4...)
                                    .psTextField()
                                Picker("Audience", selection: $emailAudience) {
                                    Text("All users").tag("all")
                                    Text("Verified").tag("verified")
                                    Text("Active").tag("active")
                                }
                                .pickerStyle(.segmented)
                                Button("Send bulk email") { Task { await sendBulkEmail() } }
                                    .psPrimary()
                                    .disabled(isWorking || emailSubject.isEmpty || emailBody.isEmpty)
                                    .accessibilityLabel("Send bulk email")
                            }
                        }
                        PSCard {
                            VStack(alignment: .leading, spacing: 12) {
                                PSSectionHeader(title: "Broadcast")
                                Text("Queues an in-app notification for every user.")
                                    .font(.psCaption)
                                    .foregroundStyle(.psMuted)
                                TextField("Title (optional)", text: $broadcastTitle)
                                    .psTextField()
                                TextField("Message", text: $broadcastMessage, axis: .vertical)
                                    .lineLimit(4...)
                                    .psTextField()
                                Toggle("Also set as the global alert", isOn: $setGlobalAlert)
                                    .font(.psBody)
                                Button("Send broadcast") { Task { await sendBroadcast() } }
                                    .psPrimary()
                                    .disabled(isWorking || broadcastMessage.isEmpty)
                                    .accessibilityLabel("Send broadcast")
                            }
                        }
                        PSCard {
                            VStack(alignment: .leading, spacing: 12) {
                                PSSectionHeader(title: "Promo banner")
                                TextField("Banner text", text: $promoText)
                                    .psTextField()
                                Toggle("Banner enabled", isOn: $promoEnabled)
                                    .font(.psBody)
                                Button("Save promo banner") { Task { await savePromoBanner() } }
                                    .psPrimary()
                                    .disabled(isWorking)
                                    .accessibilityLabel("Save promo banner")
                            }
                        }
                        if isWorking {
                            PSRingSpinner(diameter: 20, lineWidth: 2)
                                .frame(maxWidth: .infinity)
                        }
                        if let message {
                            Text(message)
                                .font(.psCaption)
                                .foregroundStyle(.psMuted)
                        }
                    }
                    .psScreenPadding()
                }
                .scrollIndicators(.hidden)
            }
        }
        .adminScreenBackground()
        .navigationTitle("Comms")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func sendBulkEmail() async {
        struct BulkEmailResponse: Decodable { let ok: Bool; let emailed: Int? }
        isWorking = true
        defer { isWorking = false }
        do {
            let result: BulkEmailResponse = try await APIClient.shared.fetchJSON(
                "api/v1/admin/bulk-email",
                method: "POST",
                body: ["subject": emailSubject, "body": emailBody, "audience": emailAudience])
            message = "Bulk email sent to \(result.emailed ?? 0) addresses."
            emailSubject = ""
            emailBody = ""
        } catch {
            message = error.localizedDescription
        }
    }

    private func sendBroadcast() async {
        struct BroadcastResponse: Decodable { let ok: Bool; let broadcast_to: Int? }
        var body: [String: Any] = ["message": broadcastMessage]
        if !broadcastTitle.isEmpty { body["title"] = broadcastTitle }
        if setGlobalAlert { body["global_alert"] = broadcastMessage }
        isWorking = true
        defer { isWorking = false }
        do {
            let result: BroadcastResponse = try await APIClient.shared.fetchJSON(
                "api/v1/admin/broadcast", method: "POST", body: body)
            message = "Broadcast queued for \(result.broadcast_to ?? 0) users."
            broadcastMessage = ""
            broadcastTitle = ""
        } catch {
            message = error.localizedDescription
        }
    }

    private func savePromoBanner() async {
        struct PromoResponse: Decodable {
            let ok: Bool
            let promo_banner_text: String?
            let promo_banner_enabled: String?
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let result: PromoResponse = try await APIClient.shared.fetchJSON(
                "api/v1/admin/settings/promo-banner",
                method: "POST",
                body: ["text": promoText, "enabled": promoEnabled])
            message = "Promo banner saved."
            promoText = result.promo_banner_text ?? promoText
        } catch {
            message = error.localizedDescription
        }
    }
}

// MARK: - Security logs
// GET /api/v1/admin/security-logs returns
// {"ok": true, "logs": [AuditLog or LoginActivity rows],
//  "source_table": "AuditLog"|"LoginActivity"}.
// POST /api/v1/admin/security-logs/purge returns
// {"purged": Int, "source_table": String}.
// POST /api/v1/admin/security-logs/revoke/<id> returns {"revoked": true}.
// There is no export endpoint in api_v1, so export builds a CSV
// locally from the rows already loaded and shares it.

struct AdminSecurityLogsResponse: Decodable {
    let ok: Bool
    let logs: [AdminGenericRow]?
    let source_table: String?
}

struct AdminSecurityLogsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var logs: [AdminGenericRow] = []
    @State private var sourceTable = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var message: String?
    @State private var shareURL: URL?
    @State private var showPurgeConfirm = false
    @State private var isWorking = false

    var body: some View {
        Group {
            if !appState.isAdminLoggedIn {
                AdminNotSignedInView()
            } else if isLoading && logs.isEmpty {
                ScrollView {

                    AdminSkeletonView(lines: 4, title: "Loading security logs")

                }

                .scrollIndicators(.hidden)

                .adminFullScreenFrame()
            } else if let errorMessage, logs.isEmpty {
                PSErrorState(message: errorMessage) {
                    Task { await load() }
                }
                .psScreenPadding()
            } else {
                content
            }
        }
        .adminScreenBackground()
        .navigationTitle("Security logs")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: Binding(get: { shareURL != nil }, set: { if !$0 { shareURL = nil } })) {
            if let url = shareURL {
                AdminShareSheet(urls: [url])
            }
        }
        .alert("Purge all security logs?", isPresented: $showPurgeConfirm) {
            Button("Purge all", role: .destructive) { Task { await purge() } }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Every entry in \(sourceTable.isEmpty ? "the log table" : sourceTable) will be deleted. This cannot be undone.")
        }
    }

    private var content: some View {
        List {
            Section {
                Text("Source table: \(sourceTable.isEmpty ? "-" : sourceTable)")
                    .font(.psCaption)
                    .foregroundStyle(.psMuted)
                HStack(spacing: 10) {
                    Button("Share as CSV") { shareCSV() }
                        .buttonStyle(.bordered)
                        .tint(.psCyan)
                        .font(.psCaption)
                        .accessibilityLabel("Share security logs as CSV")
                    Button("Purge all", role: .destructive) { showPurgeConfirm = true }
                        .buttonStyle(.bordered)
                        .font(.psCaption)
                        .disabled(logs.isEmpty || isWorking)
                }
                if let message {
                    Text(message)
                        .font(.psCaption)
                        .foregroundStyle(.psMuted)
                }
            }
            Section {
                if logs.isEmpty {
                    PSEmptyState(
                        systemImage: "shield.fill",
                        title: "No security logs",
                        body: "Login activity and audit entries will appear here."
                    )
                }
                ForEach(logs) { log in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(log.first("action", "event_type", "event") ?? "Log #\(log.id)")
                            .font(.psHeadline)
                        if let detail = log.first("message", "details", "ip_address", "device") {
                            Text(detail)
                                .font(.psBody)
                                .foregroundStyle(.psMuted)
                        }
                        Text("ID \(log.id) · user \(log.text("user_id") ?? "-") · \(adminShortDate(log.text("created_at") ?? log.text("signed_in_at")))")
                            .font(.psCaption)
                            .foregroundStyle(.psMuted)
                        Button("Revoke session") { Task { await revoke(log) } }
                            .buttonStyle(.bordered)
                            .tint(.psCyan)
                            .font(.psCaption)
                            .disabled(isWorking)
                            .accessibilityLabel("Revoke session for log entry \(log.id)")
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
    }

    private func load() async {
        guard appState.isAdminLoggedIn else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let result: AdminSecurityLogsResponse = try await APIClient.shared.fetchJSON("api/v1/admin/security-logs")
            guard result.ok else {
                errorMessage = "Admin needs the live API. The security logs endpoint did not return data."
                return
            }
            logs = result.logs ?? []
            sourceTable = result.source_table ?? ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func shareCSV() {
        // No export endpoint exists in api_v1, so the CSV is built
        // locally from the rows already loaded.
        var lines: [String] = []
        let keys = Array(Set(logs.flatMap { $0.values.keys })).sorted()
        lines.append(keys.joined(separator: ","))
        for log in logs {
            let row = keys.map { key in
                "\"\((log.values[key] ?? "").replacingOccurrences(of: "\"", with: "\"\""))\""
            }.joined(separator: ",")
            lines.append(row)
        }
        let csv = lines.joined(separator: "\n")
        if let url = adminTempFileURL(data: Data(csv.utf8), fileName: "premiumslots-security-logs.csv") {
            shareURL = url
        } else {
            message = "The CSV could not be saved for sharing."
        }
    }

    private func purge() async {
        struct PurgeResponse: Decodable { let ok: Bool; let purged: Int?; let source_table: String? }
        isWorking = true
        defer { isWorking = false }
        do {
            let result: PurgeResponse = try await APIClient.shared.fetchJSON(
                "api/v1/admin/security-logs/purge", method: "POST")
            message = "Purged \(result.purged ?? 0) log entries."
            await load()
        } catch {
            message = error.localizedDescription
        }
    }

    private func revoke(_ log: AdminGenericRow) async {
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await APIClient.shared.fetchOK(
                "api/v1/admin/security-logs/revoke/\(log.id)", method: "POST")
            message = "Session for log #\(log.id) revoked."
        } catch {
            message = error.localizedDescription
        }
    }
}

// MARK: - Recycle bin
// GET /api/v1/admin/recycle-bin returns
// {"ok": true, "archived_users": [Archive_Users rows],
//  "archived_subscriptions": [Archive_Subscriptions rows]}.
// POST /api/v1/admin/recycle-bin/restore with
// {"kind": "user"|"subscription", "id": Int} returns
// {"restored_id": Int, "kind": String}.

struct AdminRecycleBinResponse: Decodable {
    let ok: Bool
    let archived_users: [AdminGenericRow]?
    let archived_subscriptions: [AdminGenericRow]?
}

struct AdminRecycleBinView: View {
    @EnvironmentObject private var appState: AppState
    @State private var users: [AdminGenericRow] = []
    @State private var subscriptions: [AdminGenericRow] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var message: String?
    @State private var isWorking = false

    var body: some View {
        Group {
            if !appState.isAdminLoggedIn {
                AdminNotSignedInView()
            } else if isLoading && users.isEmpty && subscriptions.isEmpty {
                ScrollView {

                    AdminSkeletonView(lines: 4, title: "Loading recycle bin")

                }

                .scrollIndicators(.hidden)

                .adminFullScreenFrame()
            } else if let errorMessage, users.isEmpty && subscriptions.isEmpty {
                PSErrorState(message: errorMessage) {
                    Task { await load() }
                }
                .psScreenPadding()
            } else {
                content
            }
        }
        .adminScreenBackground()
        .navigationTitle("Recycle bin")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private var content: some View {
        List {
            if let message {
                Section {
                    Text(message)
                        .font(.psCaption)
                        .foregroundStyle(.psMuted)
                }
            }
            Section("Archived users") {
                if users.isEmpty {
                    Text("No archived users.")
                        .font(.psBody)
                        .foregroundStyle(.psMuted)
                }
                ForEach(users) { user in
                    archivedRow(user, kind: "user")
                }
            }
            Section("Archived subscriptions") {
                if subscriptions.isEmpty {
                    Text("No archived subscriptions.")
                        .font(.psBody)
                        .foregroundStyle(.psMuted)
                }
                ForEach(subscriptions) { sub in
                    archivedRow(sub, kind: "subscription")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
    }

    private func archivedRow(_ row: AdminGenericRow, kind: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(row.first("name", "email", "service_requested") ?? "Item #\(row.id)")
                .font(.psHeadline)
            Text("ID \(row.id) · \(adminShortDate(row.text("created_at")))")
                .font(.psCaption)
                .foregroundStyle(.psMuted)
            Button("Restore") { Task { await restore(row, kind: kind) } }
                .buttonStyle(.bordered)
                .tint(.psCyan)
                .font(.psCaption)
                .disabled(isWorking)
                .accessibilityLabel("Restore archived \(kind) \(row.id)")
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private func load() async {
        guard appState.isAdminLoggedIn else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let result: AdminRecycleBinResponse = try await APIClient.shared.fetchJSON("api/v1/admin/recycle-bin")
            guard result.ok else {
                errorMessage = "Admin needs the live API. The recycle bin endpoint did not return data."
                return
            }
            users = result.archived_users ?? []
            subscriptions = result.archived_subscriptions ?? []
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func restore(_ row: AdminGenericRow, kind: String) async {
        struct RestoreResponse: Decodable { let ok: Bool; let restored_id: Int?; let kind: String? }
        isWorking = true
        defer { isWorking = false }
        do {
            let result: RestoreResponse = try await APIClient.shared.fetchJSON(
                "api/v1/admin/recycle-bin/restore",
                method: "POST", body: ["kind": kind, "id": row.id])
            message = "Restored \(result.kind ?? kind) #\(result.restored_id ?? row.id)."
            await load()
        } catch {
            message = error.localizedDescription
        }
    }
}

// MARK: - Backup status (view only)
// GET /api/v1/admin/backup/status returns
// {"ok": true, "tables": [{"table": String, "rows": Int?, "exists": Bool}],
//  "note": String}. Download, upload and restore stay web-only
// by design (checklist section 6.4) and are not built here.

struct AdminBackupTable: Decodable, Identifiable {
    let table: String
    let rows: Int?
    let exists: Bool?

    var id: String { table }
}

struct AdminBackupStatusResponse: Decodable {
    let ok: Bool
    let tables: [AdminBackupTable]?
    let note: String?
}

struct AdminBackupStatusView: View {
    @EnvironmentObject private var appState: AppState
    @State private var tables: [AdminBackupTable] = []
    @State private var note: String?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if !appState.isAdminLoggedIn {
                AdminNotSignedInView()
            } else if isLoading && tables.isEmpty {
                ScrollView {

                    AdminSkeletonView(lines: 4, title: "Loading backup status")

                }

                .scrollIndicators(.hidden)

                .adminFullScreenFrame()
            } else if let errorMessage, tables.isEmpty {
                PSErrorState(message: errorMessage) {
                    Task { await load() }
                }
                .psScreenPadding()
            } else {
                content
            }
        }
        .adminScreenBackground()
        .navigationTitle("Backup status")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private var content: some View {
        List {
            Section {
                Text(note ?? "Status only. Backup download, upload and restore stay web-only by design.")
                    .font(.psCaption)
                    .foregroundStyle(.psMuted)
            }
            Section("Database tables") {
                if tables.isEmpty {
                    PSEmptyState(
                        systemImage: "externaldrive.fill",
                        title: "No table status",
                        body: "The backup status endpoint did not return any tables."
                    )
                }
                ForEach(tables) { table in
                    HStack {
                        Text(table.table)
                            .font(.psHeadline)
                        Spacer()
                        if table.exists == false {
                            PSStatusPill(text: "Missing", systemImage: "exclamationmark.triangle.fill", tint: .psDanger)
                        } else {
                            Text("\(table.rows ?? 0) rows")
                                .font(.psCaption)
                                .foregroundStyle(.psMuted)
                        }
                    }
                    .padding(.vertical, 4)
                    .accessibilityLabel("Table \(table.table), \(table.rows ?? 0) rows")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
    }

    private func load() async {
        guard appState.isAdminLoggedIn else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let result: AdminBackupStatusResponse = try await APIClient.shared.fetchJSON("api/v1/admin/backup/status")
            guard result.ok else {
                errorMessage = "Admin needs the live API. The backup status endpoint did not return data."
                return
            }
            tables = result.tables ?? []
            note = result.note
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
