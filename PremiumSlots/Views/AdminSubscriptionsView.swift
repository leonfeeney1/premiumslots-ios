import SwiftUI

// MARK: - Admin subscriptions, v3 Fix #4 (checklist section 2.2)
// Full subscription management from the live /api/v1/admin/*
// endpoints: search + status filter, detail sheet with edit,
// renew, cancel, delete, unhide credentials, remind expiry and
// bulk update. Admin data only ever comes from the live API.
// No emojis, SF Symbols only, Theme.swift tokens only.

// GET /api/v1/admin/subscriptions returns:
// {"ok": true, "subscriptions": [_subscription_row]} where a row is
// {"id", "service_requested", "amount_due", "mpesa_code",
//  "delivery_type", "status", "expiry_date", "viewed",
//  "issue_reported", "account_group", "created_at", "locked_price"}

struct AdminSubscriptionRow: Decodable, Identifiable, Equatable {
    let id: Int
    let service_requested: String
    let amount_due: Int
    let mpesa_code: String?
    let delivery_type: String?
    let status: String
    let expiry_date: String?
    let viewed: Bool?
    let issue_reported: Bool?
    let account_group: String?
    let created_at: String?
    let locked_price: Int?
}

struct AdminSubscriptionsListResponse: Decodable {
    let ok: Bool
    let subscriptions: [AdminSubscriptionRow]?
}

struct AdminUnhideResponse: Decodable {
    let ok: Bool
    let vault_email: String?
    let vault_password: String?
    let access_details: String?
    let account_group: String?
}

struct AdminRenewResponse: Decodable {
    let ok: Bool
    let status: String?
    let expiry_date: String?
}

struct AdminSubscriptionsRootView: View {
    @EnvironmentObject private var appState: AppState
    @State private var subscriptions: [AdminSubscriptionRow] = []
    @State private var searchText = ""
    @State private var statusFilter = "All"
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selected: AdminSubscriptionRow?
    @State private var isSelecting = false
    @State private var selectedIds: Set<Int> = []
    @State private var bulkStatus = "Approved"
    @State private var showBulkConfirm = false
    @State private var actionMessage: String?

    private let statusOptions = ["All", "Pending", "Approved", "Initiated", "Cancelled", "Rejected"]

    private var filtered: [AdminSubscriptionRow] {
        var list = subscriptions
        if statusFilter != "All" {
            list = list.filter { $0.status == statusFilter }
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            list = list.filter {
                $0.service_requested.localizedCaseInsensitiveContains(query)
                || ($0.mpesa_code ?? "").localizedCaseInsensitiveContains(query)
                || String($0.id).contains(query)
            }
        }
        return list
    }

    var body: some View {
        Group {
            if !appState.isAdminLoggedIn {
                AdminNotSignedInView()
            } else if isLoading && subscriptions.isEmpty {
                VStack(spacing: 12) {
                    PSRingSpinner(diameter: 40, lineWidth: 4)
                    Text("Loading subscriptions")
                        .font(.psBody)
                        .foregroundStyle(.psMuted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage, subscriptions.isEmpty {
                PSErrorState(message: errorMessage) {
                    Task { await load() }
                }
                .psScreenPadding()
            } else {
                content
            }
        }
        .background(Color.psBackground)
        .navigationTitle("Subscriptions")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(isSelecting ? "Done" : "Select") {
                    isSelecting.toggle()
                    if !isSelecting { selectedIds.removeAll() }
                }
                .font(.psCaption)
                .accessibilityLabel(isSelecting ? "Done selecting subscriptions" : "Select subscriptions for bulk update")
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .searchable(text: $searchText, prompt: "Search service, code or order")
        .sheet(item: $selected) { sub in
            AdminSubscriptionDetailSheet(subscription: sub) {
                selected = nil
                Task { await load() }
            }
        }
        .alert("Bulk update", isPresented: $showBulkConfirm) {
            Button("Update \(selectedIds.count) subscriptions", role: .destructive) {
                Task { await bulkUpdate() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Set the status of \(selectedIds.count) selected subscriptions to \(bulkStatus)?")
        }
    }

    private var content: some View {
        List {
            Section {
                Picker("Status", selection: $statusFilter) {
                    ForEach(statusOptions, id: \.self) { value in
                        Text(value).tag(value)
                    }
                }
                .pickerStyle(.menu)
            }
            if isSelecting {
                Section("Bulk update") {
                    Picker("New status", selection: $bulkStatus) {
                        Text("Approved").tag("Approved")
                        Text("Pending").tag("Pending")
                        Text("Cancelled").tag("Cancelled")
                        Text("Rejected").tag("Rejected")
                    }
                    .pickerStyle(.menu)
                    Button("Apply to \(selectedIds.count) selected") {
                        showBulkConfirm = true
                    }
                    .disabled(selectedIds.isEmpty)
                    .accessibilityLabel("Apply bulk status update to selected subscriptions")
                }
            }
            if let actionMessage {
                Section {
                    Text(actionMessage)
                        .font(.psCaption)
                        .foregroundStyle(.psMuted)
                }
            }
            Section {
                if filtered.isEmpty {
                    PSEmptyState(
                        systemImage: "tray.fill",
                        title: "No subscriptions match",
                        body: "Try a different search or status filter."
                    )
                }
                ForEach(filtered) { sub in
                    subscriptionRow(sub)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private func subscriptionRow(_ sub: AdminSubscriptionRow) -> some View {
        HStack(spacing: 12) {
            if isSelecting {
                Image(systemName: selectedIds.contains(sub.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selectedIds.contains(sub.id) ? .psPrimary : .psMuted)
                    .font(.system(size: 20))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(sub.service_requested)
                    .font(.psHeadline)
                Text("Order #\(sub.id) · KES \(sub.amount_due) · code \(sub.mpesa_code ?? "-")")
                    .font(.psCaption)
                    .foregroundStyle(.psMuted)
                Text("Expires \(adminShortDate(sub.expiry_date))")
                    .font(.psCaption)
                    .foregroundStyle(.psMuted)
            }
            Spacer()
            PSStatusPill(
                text: sub.status,
                systemImage: statusIcon(sub.status),
                tint: statusTint(sub.status)
            )
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelecting {
                if selectedIds.contains(sub.id) {
                    selectedIds.remove(sub.id)
                } else {
                    selectedIds.insert(sub.id)
                }
            } else {
                selected = sub
            }
        }
        .accessibilityLabel("Order \(sub.id), \(sub.service_requested), \(sub.status)")
    }

    private func statusIcon(_ status: String) -> String {
        switch status {
        case "Approved": return "checkmark.circle.fill"
        case "Pending", "Initiated": return "clock.fill"
        case "Cancelled", "Rejected": return "xmark.circle.fill"
        default: return "circle.fill"
        }
    }

    private func statusTint(_ status: String) -> Color {
        switch status {
        case "Approved": return .psSuccess
        case "Pending", "Initiated": return .psAmber
        case "Cancelled", "Rejected": return .psDanger
        default: return .psMuted
        }
    }

    private func load() async {
        guard appState.isAdminLoggedIn else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let result: AdminSubscriptionsListResponse = try await APIClient.shared.fetchJSON("api/v1/admin/subscriptions")
            guard result.ok else {
                errorMessage = "Admin needs the live API. The subscriptions endpoint did not return data."
                return
            }
            subscriptions = result.subscriptions ?? []
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func bulkUpdate() async {
        // POST /api/v1/admin/subscriptions/bulk-update
        // Body: {"ids": [...], "status": "..."} returns {"updated": Int}.
        struct BulkResponse: Decodable { let ok: Bool; let updated: Int? }
        do {
            let result: BulkResponse = try await APIClient.shared.fetchJSON(
                "api/v1/admin/subscriptions/bulk-update",
                method: "POST",
                body: ["ids": Array(selectedIds), "status": bulkStatus]
            )
            actionMessage = "Updated \(result.updated ?? selectedIds.count) subscriptions to \(bulkStatus)."
            selectedIds.removeAll()
            isSelecting = false
            await load()
        } catch {
            actionMessage = error.localizedDescription
        }
    }
}

// MARK: - Detail sheet

struct AdminSubscriptionDetailSheet: View {
    let subscription: AdminSubscriptionRow
    var onDone: () -> Void

    @State private var status: String
    @State private var deliveryType: String
    @State private var accountGroup: String
    @State private var accessDetails: String
    @State private var amountDue: String
    @State private var expiryDate: String
    @State private var mpesaCode: String
    @State private var vaultEmail: String
    @State private var vaultPassword: String
    @State private var unhidden: AdminUnhideResponse?
    @State private var isWorking = false
    @State private var message: String?
    @State private var showDeleteConfirm = false
    @State private var showCancelConfirm = false

    init(subscription: AdminSubscriptionRow, onDone: @escaping () -> Void) {
        self.subscription = subscription
        self.onDone = onDone
        _status = State(initialValue: subscription.status)
        _deliveryType = State(initialValue: subscription.delivery_type ?? "")
        _accountGroup = State(initialValue: subscription.account_group ?? "Unassigned")
        _accessDetails = State(initialValue: "")
        _amountDue = State(initialValue: "\(subscription.amount_due)")
        _expiryDate = State(initialValue: subscription.expiry_date.map { String($0.prefix(10)) } ?? "")
        _mpesaCode = State(initialValue: subscription.mpesa_code ?? "")
        _vaultEmail = State(initialValue: "")
        _vaultPassword = State(initialValue: "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    PSCard {
                        VStack(alignment: .leading, spacing: 8) {
                            AdminKVRow(label: "Order", value: "#\(subscription.id)")
                            AdminKVRow(label: "Service", value: subscription.service_requested)
                            AdminKVRow(label: "Created", value: adminShortDate(subscription.created_at))
                            if let locked = subscription.locked_price {
                                AdminKVRow(label: "Locked price", value: "KES \(locked)")
                            }
                            AdminKVRow(label: "Viewed", value: subscription.viewed == true ? "Yes" : "No")
                            AdminKVRow(label: "Issue reported", value: subscription.issue_reported == true ? "Yes" : "No")
                        }
                    }
                    PSCard {
                        VStack(alignment: .leading, spacing: 12) {
                            PSSectionHeader(title: "Edit")
                            Picker("Status", selection: $status) {
                                Text("Pending").tag("Pending")
                                Text("Approved").tag("Approved")
                                Text("Initiated").tag("Initiated")
                                Text("Cancelled").tag("Cancelled")
                                Text("Rejected").tag("Rejected")
                            }
                            .pickerStyle(.menu)
                            TextField("Delivery type", text: $deliveryType)
                                .autocorrectionDisabled()
                                .psTextField()
                            TextField("Account group", text: $accountGroup)
                                .autocorrectionDisabled()
                                .psTextField()
                            TextField("Access details", text: $accessDetails)
                                .autocorrectionDisabled()
                                .psTextField()
                            TextField("Amount due (KES)", text: $amountDue)
                                .keyboardType(.numberPad)
                                .psTextField()
                            TextField("Expiry date (YYYY-MM-DD)", text: $expiryDate)
                                .autocorrectionDisabled()
                                .psTextField()
                            TextField("M-PESA code", text: $mpesaCode)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.characters)
                                .psTextField()
                            TextField("Vault email", text: $vaultEmail)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .psTextField()
                            SecureField("Vault password", text: $vaultPassword)
                                .psTextField()
                            Button("Save changes") { Task { await saveEdits() } }
                                .psPrimary()
                                .disabled(isWorking)
                                .accessibilityLabel("Save subscription changes")
                        }
                    }
                    if let unhidden {
                        PSCard {
                            VStack(alignment: .leading, spacing: 8) {
                                PSSectionHeader(title: "Delivered credentials")
                                AdminKVRow(label: "Vault email", value: unhidden.vault_email ?? "-")
                                AdminKVRow(label: "Vault password", value: unhidden.vault_password ?? "-")
                                AdminKVRow(label: "Access details", value: unhidden.access_details ?? "-")
                                AdminKVRow(label: "Account group", value: unhidden.account_group ?? "-")
                            }
                        }
                    }
                    PSCard {
                        VStack(alignment: .leading, spacing: 10) {
                            PSSectionHeader(title: "Actions")
                            HStack(spacing: 10) {
                                Button("Renew") { Task { await renew() } }
                                    .buttonStyle(.bordered)
                                    .tint(.psCyan)
                                    .disabled(isWorking)
                                Button("Unhide credentials") { Task { await unhide() } }
                                    .buttonStyle(.bordered)
                                    .tint(.psCyan)
                                    .disabled(isWorking)
                                Button("Remind expiry") { Task { await remindExpiry() } }
                                    .buttonStyle(.bordered)
                                    .tint(.psCyan)
                                    .disabled(isWorking)
                            }
                            HStack(spacing: 10) {
                                Button("Cancel", role: .destructive) { showCancelConfirm = true }
                                    .buttonStyle(.bordered)
                                    .disabled(isWorking)
                                Button("Delete", role: .destructive) { showDeleteConfirm = true }
                                    .buttonStyle(.bordered)
                                    .disabled(isWorking)
                            }
                            if isWorking {
                                PSRingSpinner(diameter: 20, lineWidth: 2)
                            }
                            if let message {
                                Text(message)
                                    .font(.psCaption)
                                    .foregroundStyle(.psMuted)
                            }
                        }
                    }
                }
                .psScreenPadding()
            }
            .background(Color.psBackground)
            .navigationTitle("Order #\(subscription.id)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { onDone() }
                }
            }
            .alert("Delete subscription?", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) { Task { await deleteSubscription() } }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Order #\(subscription.id) will be deleted. This cannot be undone.")
            }
            .alert("Cancel subscription?", isPresented: $showCancelConfirm) {
                Button("Cancel subscription", role: .destructive) { Task { await cancel() } }
                Button("Keep it", role: .cancel) { }
            } message: {
                Text("Order #\(subscription.id) will be marked Cancelled.")
            }
        }
        .psSheetDetents()
    }

    private func saveEdits() async {
        // PUT /api/v1/admin/subscriptions/<id>; only whitelisted
        // fields are written: service_requested, status,
        // delivery_type, account_group, access_details, amount_due,
        // expiry_date, mpesa_code, vault_email, vault_password,
        // review_requested, issue_reported, auto_renew, locked_price.
        var body: [String: Any] = ["status": status]
        if !deliveryType.isEmpty { body["delivery_type"] = deliveryType }
        if !accountGroup.isEmpty { body["account_group"] = accountGroup }
        if !accessDetails.isEmpty { body["access_details"] = accessDetails }
        if let amount = Int(amountDue) { body["amount_due"] = amount }
        if !expiryDate.isEmpty { body["expiry_date"] = expiryDate }
        if !mpesaCode.isEmpty { body["mpesa_code"] = mpesaCode }
        if !vaultEmail.isEmpty { body["vault_email"] = vaultEmail }
        if !vaultPassword.isEmpty { body["vault_password"] = vaultPassword }
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await APIClient.shared.putOK("api/v1/admin/subscriptions/\(subscription.id)", body: body)
            message = "Changes saved."
        } catch {
            message = error.localizedDescription
        }
    }

    private func renew() async {
        // POST /api/v1/admin/subscriptions/<id>/renew
        // Returns {"status": "Approved", "expiry_date": "..."}.
        isWorking = true
        defer { isWorking = false }
        do {
            let result: AdminRenewResponse = try await APIClient.shared.fetchJSON(
                "api/v1/admin/subscriptions/\(subscription.id)/renew", method: "POST")
            message = "Renewed. New expiry \(adminShortDate(result.expiry_date))."
        } catch {
            message = error.localizedDescription
        }
    }

    private func cancel() async {
        // POST /api/v1/admin/subscriptions/<id>/cancel
        // Returns {"status": "Cancelled"}.
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await APIClient.shared.fetchOK(
                "api/v1/admin/subscriptions/\(subscription.id)/cancel", method: "POST")
            message = "Subscription cancelled."
        } catch {
            message = error.localizedDescription
        }
    }

    private func deleteSubscription() async {
        // DELETE /api/v1/admin/subscriptions/<id>.
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await APIClient.shared.deleteOK("api/v1/admin/subscriptions/\(subscription.id)")
            message = "Subscription deleted."
            onDone()
        } catch {
            message = error.localizedDescription
        }
    }

    private func unhide() async {
        // POST /api/v1/admin/subscriptions/<id>/unhide returns
        // {"vault_email", "vault_password", "access_details", "account_group"}.
        isWorking = true
        defer { isWorking = false }
        do {
            let result: AdminUnhideResponse = try await APIClient.shared.fetchJSON(
                "api/v1/admin/subscriptions/\(subscription.id)/unhide", method: "POST")
            unhidden = result
            message = nil
        } catch {
            message = error.localizedDescription
        }
    }

    private func remindExpiry() async {
        // POST /api/v1/admin/subscriptions/<id>/remind-expiry.
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await APIClient.shared.fetchOK(
                "api/v1/admin/subscriptions/\(subscription.id)/remind-expiry", method: "POST")
            message = "Expiry reminder sent."
        } catch {
            message = error.localizedDescription
        }
    }
}
