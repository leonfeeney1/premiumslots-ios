import SwiftUI
import UIKit

// MARK: - Admin customers, v3 Fix #4 (checklist section 2.3)
// Customers list with live search, filter pills, sort and a detail
// drawer, from the live /api/v1/admin/* endpoints. The list endpoint
// (GET /api/v1/admin/customers) returns id, name, email,
// whatsapp_number, is_verified, is_banned, wallet_balance,
// loyalty_points, referral_count, created_at. It does not return
// is_active, is_vip, has_wallet or LTV, so those fields are decoded
// as optional and the filters fall back to what the list does carry:
// VIP means the documented Gold tier threshold (750 loyalty points)
// unless the server sends is_vip, has-wallet means a balance above
// zero unless the server sends has_wallet, and active means not
// banned unless the server sends is_active. The detail endpoint
// (GET /api/v1/admin/customers/<id>) returns the full user row plus
// that customer's subscriptions.
// No emojis, SF Symbols only, Theme.swift tokens only.

// Rich list row: every field beyond the documented list columns is
// optional, so the list still decodes if the server never sends it.
struct AdminCustomerRow: Decodable, Identifiable, Equatable {
    let id: Int
    let name: String
    let email: String
    let whatsapp_number: String?
    let is_verified: Bool?
    let is_banned: Bool?
    let wallet_balance: Int?
    let loyalty_points: Int?
    let referral_count: Int?
    let created_at: String?
    let clerk_id: String?
    let is_active: Bool?
    let is_vip: Bool?
    let has_wallet: Bool?
    let ltv: Int?
    let total_spent: Int?
    let ltv_amount: Double?
    let loyalty_tier: String?
    let active_subs_count: Int?
    let total_orders_count: Int?
    let receive_email_notifications: Bool?

    var isBanned: Bool { is_banned == true }
    var isActive: Bool { is_active ?? !isBanned }
    var isVIP: Bool { is_vip ?? ((loyalty_points ?? 0) >= 750) }
    var hasWallet: Bool { has_wallet ?? ((wallet_balance ?? 0) > 0) }
    /// The list endpoint sends ltv_amount as a number (a SQL SUM),
    /// not ltv or total_spent, so those two stay as fallbacks only.
    var lifetimeValue: Int { ltv ?? total_spent ?? Int(ltv_amount ?? 0) }
}

struct AdminCustomersListResponse: Decodable {
    let ok: Bool
    let customers: [AdminCustomerRow]?
}

struct AdminCustomerDetailResponse: Decodable {
    let ok: Bool
    let customer: AdminCustomerRow?
    let subscriptions: [AdminSubscriptionRow]?
}

struct AdminResetPasswordResponse: Decodable {
    let ok: Bool
    let temporary_password: String?
}

struct AdminCreateCustomerResponse: Decodable {
    let ok: Bool
    let user_id: Int?
    let temporary_password: String?
}

struct AdminBulkActionResponse: Decodable {
    let ok: Bool
    let action: String?
    let affected: Int?
}

enum AdminCustomerFilter: String, CaseIterable {
    case all = "All"
    case active = "Active"
    case vip = "VIP"
    case wallet = "Has wallet"
    case banned = "Banned"
}

enum AdminCustomerSort: String, CaseIterable {
    case newest = "Newest"
    case name = "Name"
    case ltv = "LTV"
    case wallet = "Wallet"
}

struct AdminCustomersRootView: View {
    @EnvironmentObject private var appState: AppState
    @State private var customers: [AdminCustomerRow] = []
    @State private var searchText = ""
    @State private var filter: AdminCustomerFilter = .all
    @State private var sort: AdminCustomerSort = .newest
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selected: AdminCustomerRow?
    @State private var showCreate = false
    @State private var shareURL: URL?
    @State private var exportError: String?
    @State private var isSelecting = false
    @State private var selectedIds: Set<Int> = []
    @State private var bulkAction = "ban"
    @State private var showBulkConfirm = false
    @State private var actionMessage: String?

    private var filtered: [AdminCustomerRow] {
        var list = customers
        switch filter {
        case .all: break
        case .active: list = list.filter { $0.isActive }
        case .vip: list = list.filter { $0.isVIP }
        case .wallet: list = list.filter { $0.hasWallet }
        case .banned: list = list.filter { $0.isBanned }
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            list = list.filter {
                $0.name.localizedCaseInsensitiveContains(query)
                || $0.email.localizedCaseInsensitiveContains(query)
                || ($0.whatsapp_number ?? "").localizedCaseInsensitiveContains(query)
            }
        }
        switch sort {
        case .newest: list.sort { $0.id > $1.id }
        case .name: list.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .ltv: list.sort { $0.lifetimeValue > $1.lifetimeValue }
        case .wallet: list.sort { ($0.wallet_balance ?? 0) > ($1.wallet_balance ?? 0) }
        }
        return list
    }

    var body: some View {
        Group {
            if !appState.isAdminLoggedIn {
                AdminNotSignedInView()
            } else if isLoading && customers.isEmpty {
                ScrollView {

                    AdminSkeletonView(lines: 4, title: "Loading customers")

                }

                .scrollIndicators(.hidden)

                .adminFullScreenFrame()
            } else if let errorMessage, customers.isEmpty {
                PSErrorState(message: errorMessage) {
                    Task { await load() }
                }
                .psScreenPadding()
            } else {
                content
            }
        }
        .adminScreenBackground()
        .navigationTitle("Customers")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button(isSelecting ? "Done" : "Select") {
                    isSelecting.toggle()
                    if !isSelecting { selectedIds.removeAll() }
                }
                .font(.psCaption)
                Button {
                    showCreate = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Create customer")
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .searchable(text: $searchText, prompt: "Search name, email or phone")
        .sheet(item: $selected) { customer in
            AdminCustomerDetailSheet(customer: customer) {
                selected = nil
                Task { await load() }
            }
        }
        .sheet(isPresented: $showCreate) {
            AdminCreateCustomerSheet {
                showCreate = false
                Task { await load() }
            }
        }
        .sheet(isPresented: Binding(get: { shareURL != nil }, set: { if !$0 { shareURL = nil } })) {
            if let url = shareURL {
                AdminShareSheet(urls: [url])
            }
        }
        .alert("Bulk action", isPresented: $showBulkConfirm) {
            Button("\(bulkActionLabel) \(selectedIds.count) customers", role: .destructive) {
                Task { await bulkActionRun() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This applies \(bulkActionLabel.lowercased()) to \(selectedIds.count) selected customers.")
        }
    }

    private var bulkActionLabel: String {
        switch bulkAction {
        case "ban": return "Ban"
        case "unban": return "Unban"
        case "delete": return "Delete"
        default: return "Toggle emails for"
        }
    }

    private var content: some View {
        List {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(AdminCustomerFilter.allCases, id: \.self) { option in
                            Button(option.rawValue) { filter = option }
                                .font(.psCaption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(filter == option ? Color.psPrimary : Color.psSurface)
                                .foregroundStyle(filter == option ? Color.psSurface : .psText)
                                .clipShape(Capsule())
                                .accessibilityLabel("Filter customers: \(option.rawValue)")
                        }
                    }
                }
                Picker("Sort", selection: $sort) {
                    ForEach(AdminCustomerSort.allCases, id: \.self) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.menu)
            }
            if isSelecting {
                Section("Bulk action") {
                    Picker("Action", selection: $bulkAction) {
                        Text("Ban").tag("ban")
                        Text("Unban").tag("unban")
                        Text("Toggle emails").tag("toggle_emails")
                        Text("Delete").tag("delete")
                    }
                    .pickerStyle(.menu)
                    Button("Apply to \(selectedIds.count) selected") {
                        showBulkConfirm = true
                    }
                    .disabled(selectedIds.isEmpty)
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
                Button("Share customers CSV") { Task { await exportCustomers() } }
                    .font(.psCaption)
                if let exportError {
                    Text(exportError)
                        .font(.psCaption)
                        .foregroundStyle(.psDanger)
                }
            }
            Section {
                if filtered.isEmpty {
                    PSEmptyState(
                        systemImage: "person.2.fill",
                        title: "No customers match",
                        body: "Try a different search or filter."
                    )
                }
                ForEach(filtered) { customer in
                    customerRow(customer)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
    }

    private func customerRow(_ customer: AdminCustomerRow) -> some View {
        HStack(spacing: 12) {
            if isSelecting {
                Image(systemName: selectedIds.contains(customer.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selectedIds.contains(customer.id) ? .psPrimary : .psMuted)
                    .font(.psHeadline)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(customer.name)
                        .font(.psHeadline)
                    if customer.isVIP {
                        PSStatusPill(text: "VIP", systemImage: "star.fill", tint: .psAmber)
                    }
                    if customer.isBanned {
                        PSStatusPill(text: "Banned", systemImage: "nosign", tint: .psDanger)
                    }
                }
                Text(customer.email)
                    .font(.psCaption)
                    .foregroundStyle(.psMuted)
                Text("Wallet KES \(customer.wallet_balance ?? 0) · \(customer.loyalty_points ?? 0) points · \(customer.referral_count ?? 0) referrals")
                    .font(.psCaption)
                    .foregroundStyle(.psMuted)
            }
            Spacer()
            Button(customer.isBanned ? "Unban" : "Ban") {
                Task { await toggleBan(customer) }
            }
            .font(.psCaption)
            .buttonStyle(.bordered)
            .tint(customer.isBanned ? .psSuccess : .psDanger)
            .accessibilityLabel(customer.isBanned ? "Unban \(customer.name)" : "Ban \(customer.name)")
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelecting {
                if selectedIds.contains(customer.id) {
                    selectedIds.remove(customer.id)
                } else {
                    selectedIds.insert(customer.id)
                }
            } else {
                selected = customer
            }
        }
        .accessibilityLabel("Customer \(customer.name), \(customer.email)")
    }

    private func load() async {
        guard appState.isAdminLoggedIn else { return }
        // Cache first: show the last saved list immediately, then
        // refresh live.
        if let cached = AdminCache.load(key: "admin-customers"),
           let decoded = try? JSONDecoder().decode(AdminCustomersListResponse.self, from: cached),
           decoded.ok {
            customers = decoded.customers ?? []
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let data = try await APIClient.shared.fetchData("api/v1/admin/customers")
            let result = try JSONDecoder().decode(AdminCustomersListResponse.self, from: data)
            guard result.ok else {
                if customers.isEmpty {
                    errorMessage = "Admin needs the live API. The customers endpoint did not return data."
                }
                return
            }
            AdminCache.save(data, key: "admin-customers")
            customers = result.customers ?? []
        } catch {
            if customers.isEmpty {
                errorMessage = error.localizedDescription
            } else {
                actionMessage = "Live refresh failed: \(error.localizedDescription). Showing the last saved customers."
            }
        }
    }

    private func toggleBan(_ customer: AdminCustomerRow) async {
        do {
            _ = try await APIClient.shared.adminToggleBan(customerId: customer.id)
            await load()
        } catch {
            actionMessage = error.localizedDescription
        }
    }

    private func exportCustomers() async {
        // GET /api/v1/admin/customers/export returns a CSV file.
        exportError = nil
        do {
            let data = try await APIClient.shared.fetchData("api/v1/admin/customers/export")
            if let url = adminTempFileURL(data: data, fileName: "premiumslots-customers.csv") {
                shareURL = url
            } else {
                exportError = "The CSV could not be saved for sharing."
            }
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func bulkActionRun() async {
        // POST /api/v1/admin/customers/bulk-action
        // Body: {"action": "ban"|"unban"|"delete"|"toggle_emails", "ids": [...]}
        // Returns {"action": ..., "affected": Int}.
        do {
            let result: AdminBulkActionResponse = try await APIClient.shared.fetchJSON(
                "api/v1/admin/customers/bulk-action",
                method: "POST",
                body: ["action": bulkAction, "ids": Array(selectedIds)]
            )
            actionMessage = "\(result.action ?? bulkAction) applied to \(result.affected ?? selectedIds.count) customers."
            selectedIds.removeAll()
            isSelecting = false
            await load()
        } catch {
            actionMessage = error.localizedDescription
        }
    }
}

// MARK: - Detail drawer

struct AdminCustomerDetailSheet: View {
    let customer: AdminCustomerRow
    var onDone: () -> Void

    @EnvironmentObject private var appState: AppState
    @State private var detail: AdminCustomerRow?
    @State private var subscriptions: [AdminSubscriptionRow] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var message: String?
    @State private var tempPassword: String?
    @State private var showDeleteConfirm = false
    @State private var showEmailForm = false
    @State private var showWalletForm = false
    @State private var showPointsForm = false
    @State private var emailSubject = ""
    @State private var emailBody = ""
    @State private var walletAmount = ""
    @State private var pointsAmount = ""
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if isLoading {
                        AdminSkeletonView(lines: 4, title: "Loading customer")
                    } else if let errorMessage {
                        PSErrorState(message: errorMessage) {
                            Task { await loadDetail() }
                        }
                    } else {
                        detailContent
                    }
                }
                .psScreenPadding()
            }
            .scrollIndicators(.hidden)
            .adminScreenBackground()
            .navigationTitle(customer.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { onDone() }
                }
            }
            .task { await loadDetail() }
            .alert("Delete customer?", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) { Task { await deleteCustomer() } }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This deletes \(customer.name) and their account. This cannot be undone.")
            }
            .alert("Send email", isPresented: $showEmailForm) {
                TextField("Subject", text: $emailSubject)
                TextField("Message", text: $emailBody)
                Button("Send") { Task { await sendEmail() } }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Email \(customer.email).")
            }
            .alert("Adjust wallet", isPresented: $showWalletForm) {
                TextField("Amount in KES (negative to deduct)", text: $walletAmount)
                    .keyboardType(.numbersAndPunctuation)
                Button("Apply") { Task { await adjustWallet() } }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Current balance KES \(detail?.wallet_balance ?? customer.wallet_balance ?? 0).")
            }
            .alert("Adjust loyalty points", isPresented: $showPointsForm) {
                TextField("Points (negative to deduct)", text: $pointsAmount)
                    .keyboardType(.numbersAndPunctuation)
                Button("Apply") { Task { await adjustPoints() } }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Current points \(detail?.loyalty_points ?? customer.loyalty_points ?? 0).")
            }
        }
        .psSheetDetents()
    }

    private var detailContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            PSCard {
                VStack(alignment: .leading, spacing: 8) {
                    let row = detail ?? customer
                    AdminKVRow(label: "Email", value: row.email)
                    AdminKVRow(label: "Phone", value: row.whatsapp_number ?? "-")
                    AdminKVRow(label: "Registered", value: adminShortDate(row.created_at))
                    AdminKVRow(label: "Verified", value: row.is_verified == true ? "Yes" : "No")
                    if let clerkId = row.clerk_id, !clerkId.isEmpty {
                        AdminKVRow(label: "Clerk", value: "Linked")
                    }
                    AdminKVRow(label: "Lifetime value", value: "KES \(row.lifetimeValue)")
                    AdminKVRow(label: "Wallet", value: "KES \(row.wallet_balance ?? 0)")
                    AdminKVRow(label: "Loyalty points", value: "\(row.loyalty_points ?? 0)")
                    AdminKVRow(label: "Referrals", value: "\(row.referral_count ?? 0)")
                    AdminKVRow(label: "Emails", value: row.receive_email_notifications == false ? "Off" : "On")
                    AdminKVRow(label: "Banned", value: row.isBanned ? "Yes" : "No")
                }
            }
            if let tempPassword {
                PSCard {
                    VStack(alignment: .leading, spacing: 8) {
                        PSSectionHeader(title: "Temporary password")
                        Text("Shown once only. Copy it now and share it with the customer through a secure channel.")
                            .font(.psCaption)
                            .foregroundStyle(.psMuted)
                        Text(tempPassword)
                            .font(.psMono)
                        Button("Copy password") {
                            UIPasteboard.general.string = tempPassword
                        }
                        .buttonStyle(.bordered)
                        .tint(.psCyan)
                        .accessibilityLabel("Copy temporary password")
                    }
                }
            }
            PSCard {
                VStack(alignment: .leading, spacing: 10) {
                    PSSectionHeader(title: "Actions")
                    AdminActionButton(label: "Adjust wallet", systemImage: "wallet.bifold.fill", tint: .psPrimary, disabled: isWorking) {
                        showWalletForm = true
                    }
                    AdminActionButton(label: "Send email", systemImage: "envelope.fill", tint: .psPrimary, disabled: isWorking) {
                        showEmailForm = true
                    }
                    AdminActionButton(label: "Toggle emails", systemImage: "bell.fill", tint: .psDim, disabled: isWorking) {
                        Task { await toggleEmails() }
                    }
                    AdminActionButton(label: "Adjust points", systemImage: "star.fill", tint: .psDim, disabled: isWorking) {
                        showPointsForm = true
                    }
                    AdminActionButton(label: "Reset password", systemImage: "key.fill", tint: .psDim, disabled: isWorking) {
                        Task { await resetPassword() }
                    }
                    AdminActionButton(label: customer.isBanned ? "Unban customer" : "Ban customer", systemImage: customer.isBanned ? "checkmark.circle.fill" : "nosign", tint: customer.isBanned ? .psSuccess : .psDanger, isDestructive: !customer.isBanned, disabled: isWorking) {
                        Task { await toggleBan() }
                    }
                    AdminActionButton(label: "Delete customer", systemImage: "trash.fill", tint: .psDanger, isDestructive: true, disabled: isWorking) {
                        showDeleteConfirm = true
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
            PSCard {
                VStack(alignment: .leading, spacing: 12) {
                    PSSectionHeader(title: "Subscriptions")
                    if subscriptions.isEmpty {
                        Text("No subscriptions yet.")
                            .font(.psBody)
                            .foregroundStyle(.psMuted)
                    }
                    ForEach(subscriptions) { sub in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(sub.service_requested)
                                .font(.psHeadline)
                            Text("Order #\(sub.id) · KES \(sub.amount_due) · \(sub.status) · \(sub.daysLeftText)")
                                .font(.psCaption)
                                .foregroundStyle(adminDaysLeftTint(expiryDate: sub.expiry_date, apiDays: sub.days_remaining))
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    private func loadDetail() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let result: AdminCustomerDetailResponse = try await APIClient.shared.fetchJSON("api/v1/admin/customers/\(customer.id)")
            guard result.ok else {
                errorMessage = "Admin needs the live API. The customer detail endpoint did not return data."
                return
            }
            detail = result.customer
            subscriptions = result.subscriptions ?? []
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func toggleEmails() async {
        // POST /api/v1/admin/customers/<id>/toggle-emails returns
        // {"receive_email_notifications": Bool}.
        struct ToggleResponse: Decodable { let ok: Bool; let receive_email_notifications: Bool? }
        isWorking = true
        defer { isWorking = false }
        do {
            let result: ToggleResponse = try await APIClient.shared.fetchJSON(
                "api/v1/admin/customers/\(customer.id)/toggle-emails", method: "POST")
            message = "Emails are now \((result.receive_email_notifications ?? true) ? "on" : "off") for this customer."
            await loadDetail()
        } catch {
            message = error.localizedDescription
        }
    }

    private func adjustWallet() async {
        // POST /api/v1/admin/customers/<id>/adjust-wallet, body
        // {"amount": Int}, returns {"wallet_balance": Int}.
        guard let amount = Int(walletAmount), amount != 0 else {
            message = "Enter a non-zero amount."
            return
        }
        struct WalletResponse: Decodable { let ok: Bool; let wallet_balance: Int? }
        isWorking = true
        defer { isWorking = false }
        do {
            let result: WalletResponse = try await APIClient.shared.fetchJSON(
                "api/v1/admin/customers/\(customer.id)/adjust-wallet",
                method: "POST", body: ["amount": amount])
            message = "Wallet balance is now KES \(result.wallet_balance ?? 0)."
            walletAmount = ""
            await loadDetail()
        } catch {
            message = error.localizedDescription
        }
    }

    private func adjustPoints() async {
        // POST /api/v1/admin/customers/<id>/adjust-points, body
        // {"amount": Int}, returns {"loyalty_points": Int}.
        guard let amount = Int(pointsAmount), amount != 0 else {
            message = "Enter a non-zero points amount."
            return
        }
        struct PointsResponse: Decodable { let ok: Bool; let loyalty_points: Int? }
        isWorking = true
        defer { isWorking = false }
        do {
            let result: PointsResponse = try await APIClient.shared.fetchJSON(
                "api/v1/admin/customers/\(customer.id)/adjust-points",
                method: "POST", body: ["amount": amount])
            message = "Loyalty points are now \(result.loyalty_points ?? 0)."
            pointsAmount = ""
            await loadDetail()
        } catch {
            message = error.localizedDescription
        }
    }

    private func resetPassword() async {
        // POST /api/v1/admin/customers/<id>/reset-password returns
        // {"temporary_password": String} once. It is shown once below
        // and never stored.
        isWorking = true
        defer { isWorking = false }
        do {
            let result: AdminResetPasswordResponse = try await APIClient.shared.fetchJSON(
                "api/v1/admin/customers/\(customer.id)/reset-password", method: "POST")
            tempPassword = result.temporary_password
            message = "A new temporary password was generated. It is shown once above."
        } catch {
            message = error.localizedDescription
        }
    }

    private func sendEmail() async {
        // POST /api/v1/admin/customers/<id>/send-email, body
        // {"subject": ..., "body": ...}, returns {"sent_to": email}.
        guard !emailSubject.isEmpty, !emailBody.isEmpty else {
            message = "Enter a subject and a message."
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await APIClient.shared.fetchOK(
                "api/v1/admin/customers/\(customer.id)/send-email",
                method: "POST", body: ["subject": emailSubject, "body": emailBody])
            message = "Email sent to \(customer.email)."
            emailSubject = ""
            emailBody = ""
        } catch {
            message = error.localizedDescription
        }
    }

    private func toggleBan() async {
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await APIClient.shared.adminToggleBan(customerId: customer.id)
            message = customer.isBanned ? "Customer unbanned." : "Customer banned."
            await loadDetail()
        } catch {
            message = error.localizedDescription
        }
    }

    private func deleteCustomer() async {
        // DELETE /api/v1/admin/customers/<id>.
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await APIClient.shared.deleteOK("api/v1/admin/customers/\(customer.id)")
            message = "Customer deleted."
            onDone()
        } catch {
            message = error.localizedDescription
        }
    }
}

// MARK: - Create customer

struct AdminCreateCustomerSheet: View {
    var onDone: () -> Void

    @State private var name = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var tempPasswordInput = ""
    @State private var initialWallet = ""
    @State private var isWorking = false
    @State private var message: String?
    @State private var createdPassword: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    PSCard {
                        VStack(alignment: .leading, spacing: 12) {
                            PSSectionHeader(title: "New customer")
                            Text("Name, email and phone are required. A temporary password is generated when the field is left blank.")
                                .font(.psCaption)
                                .foregroundStyle(.psMuted)
                            TextField("Full name", text: $name)
                                .autocorrectionDisabled()
                                .psTextField()
                            TextField("Email", text: $email)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .keyboardType(.emailAddress)
                                .psTextField()
                            TextField("Phone / WhatsApp", text: $phone)
                                .keyboardType(.phonePad)
                                .psTextField()
                            SecureField("Temporary password (optional)", text: $tempPasswordInput)
                                .psTextField()
                            TextField("Initial wallet balance (KES, optional)", text: $initialWallet)
                                .keyboardType(.numberPad)
                                .psTextField()
                            Button("Create customer") { Task { await create() } }
                                .psPrimary()
                                .disabled(isWorking || name.isEmpty || email.isEmpty || phone.isEmpty)
                                .accessibilityLabel("Create customer")
                        }
                    }
                    if let createdPassword {
                        PSCard {
                            VStack(alignment: .leading, spacing: 8) {
                                PSSectionHeader(title: "Temporary password")
                                Text("Shown once only. Copy it now and share it with the customer through a secure channel.")
                                    .font(.psCaption)
                                    .foregroundStyle(.psMuted)
                                Text(createdPassword)
                                    .font(.psMono)
                                Button("Copy password") {
                                    UIPasteboard.general.string = createdPassword
                                }
                                .buttonStyle(.bordered)
                                .tint(.psCyan)
                                .accessibilityLabel("Copy temporary password")
                            }
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
            .adminScreenBackground()
            .navigationTitle("Create customer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { onDone() }
                }
            }
        }
        .psSheetDetents()
    }

    private func create() async {
        // POST /api/v1/admin/customers, body {"name", "email",
        // "phone", "temporary_password"?, "wallet_balance"?}.
        // Returns {"user_id": Int, "temporary_password": String}.
        var body: [String: Any] = [
            "name": name,
            "email": email,
            "phone": phone
        ]
        if !tempPasswordInput.isEmpty { body["temporary_password"] = tempPasswordInput }
        if let wallet = Int(initialWallet), wallet != 0 { body["wallet_balance"] = wallet }
        isWorking = true
        defer { isWorking = false }
        do {
            let result: AdminCreateCustomerResponse = try await APIClient.shared.fetchJSON(
                "api/v1/admin/customers", method: "POST", body: body)
            createdPassword = result.temporary_password
            message = "Customer created."
        } catch {
            message = error.localizedDescription
        }
    }
}
