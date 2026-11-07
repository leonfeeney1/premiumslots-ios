import SwiftUI

// MARK: - Support tickets and feedback, Fix #4 (v6: design overhaul)
// Checklist 1.7: GET /api/v1/me/tickets (my tickets + status),
// POST /api/v1/tickets (submit a ticket), POST /api/v1/feedback
// (message_type Site Feedback / Suggestion, General Inquiry or
// Payment Issue + message, stored as a support ticket).
// One coherent design system with the rest of the app: a hero
// card, a status summary strip, ticket cards that expand to the
// full message, and the two forms as cards with section headers,
// the same 16pt screen padding, 12pt spacing and PSTextStyle
// type as Gift Cards, Wishlist and Help. Skeleton cards show
// immediately on a first load; a failed load shows an error state
// with retry; a failed refresh with tickets on screen shows a
// small retry banner instead of replacing the list.
// No NavigationStack here: this view is pushed from Settings, so it
// uses the parent stack. No emojis, SF Symbols only.

struct TicketsRootView: View {
    @EnvironmentObject private var appState: AppState
    var highlightTicketId: Int? = nil

    @State private var tickets: [TktTicket] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var expandedId: Int?

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

    private var openCount: Int {
        tickets.filter { ($0.status ?? "").lowercased() == "open" }.count
    }

    private var resolvedCount: Int {
        tickets.filter { ($0.status ?? "").lowercased() == "resolved" || ($0.status ?? "").lowercased() == "closed" }.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PSCard {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Image(systemName: "envelope.fill")
                                .font(.psIcon)
                                .foregroundStyle(.psCyan)
                                .accessibilityHidden(true)
                            Text("Support tickets")
                                .psTextStyle(.title)
                        }
                        Text("Send a ticket about a slot, a payment or anything else, and the team will pick it up. Feedback goes to the team the same way.")
                            .psTextStyle(.body)
                            .foregroundStyle(.psMuted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !appState.isLoggedIn {
                    PSCard {
                        Text("Sign in to see your tickets and send a message to the team.")
                            .psTextStyle(.body)
                            .foregroundStyle(.psMuted)
                    }
                } else if isLoading && tickets.isEmpty {
                    PSSkeletonRows(count: 3)
                } else if let loadError, tickets.isEmpty {
                    PSErrorState(message: loadError) {
                        Task { await load() }
                    }
                } else {
                    if let loadError {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.psWarning)
                                .accessibilityHidden(true)
                            Text("Showing your saved tickets. The latest list could not be loaded.")
                                .psTextStyle(.caption)
                                .foregroundStyle(.psMuted)
                            Spacer()
                            Button("Retry") {
                                Task { await load() }
                            }
                            .psTextStyle(.caption)
                        }
                        .padding(10)
                        .background(Color.psSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        PSSectionHeader(title: "My tickets")
                        HStack(spacing: 12) {
                            summaryTile(value: "\(openCount)", label: "Open", systemImage: "clock.fill", tint: .psAmber)
                            summaryTile(value: "\(resolvedCount)", label: "Resolved", systemImage: "checkmark.circle.fill", tint: .psSuccess)
                            summaryTile(value: "\(tickets.count)", label: "Total", systemImage: "envelope.fill", tint: .psCyan)
                        }
                        if tickets.isEmpty {
                            PSEmptyState(
                                systemImage: "envelope",
                                title: "No tickets yet",
                                body: "Send one below and the team will pick it up."
                            )
                        } else {
                            ForEach(tickets) { ticket in
                                ticketCard(ticket)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    PSSectionHeader(title: "Submit a ticket")
                    PSCard {
                        VStack(alignment: .leading, spacing: 12) {
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
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    PSSectionHeader(title: "Message the team")
                    PSCard {
                        VStack(alignment: .leading, spacing: 12) {
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
                            Text("Feedback goes to the team as a support ticket. For a slot problem, include the platform name and your M-PESA code.")
                                .font(.psCaption)
                                .foregroundStyle(.psMuted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .psScreenPadding()
        }
        .psHiddenScrollIndicators()
        .psScreenBackground()
        .navigationTitle("Support tickets")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.psBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .refreshable { await load() }
        .task { await load() }
        .onAppear { expandedId = highlightTicketId }
        .safeAreaPadding(.bottom, 8)
    }

    private func summaryTile(value: String, label: String, systemImage: String, tint: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.psIcon)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(value)
                .psTextStyle(.title)
            Text(label)
                .psTextStyle(.caption)
                .foregroundStyle(.psMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color.psSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.psBorder, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label) tickets")
    }

    /// One ticket card. Tapping expands the full message; the
    /// deep-linked ticket starts expanded.
    private func ticketCard(_ ticket: TktTicket) -> some View {
        let isExpanded = expandedId == ticket.id
        return PSCard {
            Button {
                if let id = ticket.id {
                    expandedId = isExpanded ? nil : id
                }
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(ticket.subject ?? "Support ticket")
                            .font(.psHeadline)
                            .multilineTextAlignment(.leading)
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
                        .lineLimit(isExpanded ? nil : 3)
                    HStack {
                        if let date = ticket.created_at {
                            Text(psShortDate(date))
                                .font(.psCaption)
                                .foregroundStyle(.psMuted)
                        }
                        Spacer()
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.psIconSmall)
                            .foregroundStyle(.psMuted)
                            .accessibilityHidden(true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ticket: \(ticket.subject ?? "Support ticket"), status \(ticket.status ?? "open")")
        }
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
            // Keep the list on screen when a refresh fails; the
            // full error state shows only when there is nothing.
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
