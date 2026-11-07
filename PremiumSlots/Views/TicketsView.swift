import SwiftUI

// MARK: - Support tickets and feedback, Fix #4
// Checklist 1.7: GET /api/v1/me/tickets (my tickets + status),
// POST /api/v1/tickets (submit a ticket), POST /api/v1/feedback
// (message_type Site Feedback / Suggestion, General Inquiry or
// Payment Issue + message, stored as a support ticket).
// No NavigationStack here: this view is pushed from Settings, so it
// uses the parent stack. No emojis, SF Symbols only.

struct TicketsRootView: View {
    @EnvironmentObject private var appState: AppState
    @State private var tickets: [TktTicket] = []
    @State private var isLoading = false
    @State private var loadError: String?

    @State private var ticketSubject = ""
    @State private var ticketMessage = ""
    @State private var ticketType = "General Inquiry"
    @State private var ticketResult: String?
    @State private var isSubmittingTicket = false

    @State private var feedbackType = "Site Feedback"
    @State private var feedbackMessage = ""
    @State private var feedbackResult: String?
    @State private var isSubmittingFeedback = false

    private let messageTypes = ["Site Feedback", "Suggestion", "General Inquiry", "Payment Issue"]

    var body: some View {
        List {
            if !appState.isLoggedIn {
                Section {
                    Text("Sign in to see your tickets and send a message to the team.")
                        .font(.psBody)
                        .foregroundStyle(.psMuted)
                }
            } else if let loadError {
                Section {
                    PSErrorState(message: loadError) {
                        Task { await load() }
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            } else if isLoading && tickets.isEmpty {
                Section {
                    HStack {
                        Spacer()
                        PSRingSpinner(diameter: 28, lineWidth: 3)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            } else {
                Section("My tickets") {
                    if tickets.isEmpty {
                        Text("No tickets yet. Send one below and the team will pick it up.")
                            .font(.psBody)
                            .foregroundStyle(.psMuted)
                    } else {
                        ForEach(tickets) { ticket in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(ticket.subject ?? "Support ticket")
                                        .font(.psHeadline)
                                    Spacer()
                                    PSStatusPill(
                                        text: ticket.status ?? "open",
                                        systemImage: ticketStatusIcon(ticket.status),
                                        tint: ticket.status == "resolved" ? .psSuccess : .psAmber
                                    )
                                }
                                if let type = ticket.message_type {
                                    Text(type)
                                        .font(.psCaption)
                                        .foregroundStyle(.psMuted)
                                }
                                Text(ticket.message ?? "")
                                    .font(.psBody)
                                    .foregroundStyle(.psMuted)
                                if let date = ticket.created_at {
                                    Text(psShortDate(date))
                                        .font(.psCaption)
                                        .foregroundStyle(.psMuted)
                                }
                            }
                            .accessibilityLabel("Ticket: \(ticket.subject ?? "Support ticket"), status \(ticket.status ?? "open")")
                        }
                    }
                }
            }

            Section {
                TextField("Subject", text: $ticketSubject)
                    .psTextField()
                    .accessibilityLabel("Ticket subject")
                Picker("Type", selection: $ticketType) {
                    ForEach(messageTypes, id: \.self) { type in
                        Text(type).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Ticket type")
                TextField("Describe the issue", text: $ticketMessage, axis: .vertical)
                    .psTextField()
                    .lineLimit(4...)
                    .accessibilityLabel("Ticket message")
                Button {
                    Task { await submitTicket() }
                } label: {
                    if isSubmittingTicket { PSRingSpinner(diameter: 20, lineWidth: 2, color: .white, duration: 0.7) }
                    else { Label("Send ticket", systemImage: "paperplane.fill") }
                }
                .psPrimary()
                .disabled(isSubmittingTicket || !appState.isLoggedIn)
                if let ticketResult {
                    Text(ticketResult)
                        .font(.psCaption)
                        .foregroundStyle(.psMuted)
                }
            } header: {
                Text("Submit a ticket")
            }

            Section {
                Picker("Type", selection: $feedbackType) {
                    ForEach(["Site Feedback", "Suggestion", "General Inquiry", "Payment Issue"], id: \.self) { type in
                        Text(type).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Feedback type")
                TextField("Your message to the team", text: $feedbackMessage, axis: .vertical)
                    .psTextField()
                    .lineLimit(4...)
                    .accessibilityLabel("Feedback message")
                Button {
                    Task { await submitFeedback() }
                } label: {
                    if isSubmittingFeedback { PSRingSpinner(diameter: 20, lineWidth: 2, color: .white, duration: 0.7) }
                    else { Label("Send feedback", systemImage: "paperplane.fill") }
                }
                .psPrimary()
                .disabled(isSubmittingFeedback || !appState.isLoggedIn)
                if let feedbackResult {
                    Text(feedbackResult)
                        .font(.psCaption)
                        .foregroundStyle(.psMuted)
                }
            } header: {
                Text("Message the team")
            } footer: {
                Text("Feedback goes to the team as a support ticket. For a slot problem, include the platform name and your M-PESA code.")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .background(Color.psBackground)
        .navigationTitle("Support tickets")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .safeAreaPadding(.bottom, 8)
    }

    private func ticketStatusIcon(_ status: String?) -> String {
        switch status {
        case "resolved", "closed": return "checkmark.circle.fill"
        case "open": return "clock.fill"
        default: return "exclamationmark.circle.fill"
        }
    }

    private func load() async {
        guard appState.isLoggedIn else { return }
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let response: TktTicketsResponse = try await APIClient.shared.fetchJSON("api/v1/me/tickets")
            tickets = response.tickets
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func submitTicket() async {
        let message = ticketMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else {
            ticketResult = "Describe the issue first."
            return
        }
        isSubmittingTicket = true
        defer { isSubmittingTicket = false }
        do {
            let _: APIResponse = try await APIClient.shared.fetchJSON(
                "api/v1/tickets", method: "POST",
                body: ["subject": ticketSubject.trimmingCharacters(in: .whitespacesAndNewlines),
                       "message": message,
                       "message_type": ticketType])
            ticketResult = "Ticket sent. The team will pick it up."
            ticketSubject = ""
            ticketMessage = ""
            await load()
        } catch {
            ticketResult = error.localizedDescription
        }
    }

    private func submitFeedback() async {
        let message = feedbackMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else {
            feedbackResult = "Write your message first."
            return
        }
        isSubmittingFeedback = true
        defer { isSubmittingFeedback = false }
        do {
            let _: APIResponse = try await APIClient.shared.fetchJSON(
                "api/v1/feedback", method: "POST",
                body: ["message_type": feedbackType, "message": message])
            feedbackResult = "Thanks. Your message was sent to the team."
            feedbackMessage = ""
            await load()
        } catch {
            feedbackResult = error.localizedDescription
        }
    }
}

// MARK: - Ticket response types (keys from backend/api_v1.py)

struct TktTicket: Decodable, Identifiable {
    let id: Int?
    let subject: String?
    let message: String?
    let message_type: String?
    let status: String?
    let created_at: String?
}

struct TktTicketsResponse: Decodable {
    let ok: Bool
    let tickets: [TktTicket]
}

#Preview {
    NavigationStack {
        TicketsRootView()
            .environmentObject(AppState())
    }
}
