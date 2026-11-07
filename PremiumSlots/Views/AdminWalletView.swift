import SwiftUI

// MARK: - Admin wallet, gift cards, transactions, payment methods
// v3 Fix #4 (checklist sections 2.5). All data comes from the live
// /api/v1/admin/* endpoints. No emojis, SF Symbols only,
// Theme.swift tokens only.

// GET /api/v1/admin/wallet returns:
// {"ok": true, "deposits": [WalletTransactions rows],
//  "pending": [rows with status pending]}
// WalletTransactions rows are flat _row_dict rows: id, user_id,
// action_type, amount, mpesa_code, status, created_at.

struct AdminDepositRow: Decodable, Identifiable, Equatable {
    let id: Int
    let user_id: Int?
    let action_type: String?
    let transaction_type: String?
    let amount: Int?
    let mpesa_code: String?
    let status: String?
    let created_at: String?

    var isPending: Bool { (status ?? "pending").lowercased() == "pending" }

    /// WalletTransactions rows carry transaction_type on the live
    /// table, not action_type, so both keys are read.
    var actionLabel: String {
        let raw = action_type ?? transaction_type ?? ""
        return raw.isEmpty ? "Transaction #\(id)" : raw
    }
}

struct AdminWalletResponse: Decodable {
    let ok: Bool
    let deposits: [AdminDepositRow]?
    let pending: [AdminDepositRow]?
}

struct AdminWalletAdjustResponse: Decodable {
    let ok: Bool
    let wallet_balance: Int?
}

struct AdminWalletRootView: View {
    /// Deep link from an admin notification: when set, that deposit
    /// is pinned at the top of the list with its approve and reject
    /// actions, so a tap lands on the deposit itself.
    var highlightedDepositId: Int? = nil

    @EnvironmentObject private var appState: AppState
    @State private var deposits: [AdminDepositRow] = []
    @State private var customers: [AdminCustomerRow] = []
    @State private var customerSearch = ""
    @State private var selectedCustomer: AdminCustomerRow?
    @State private var selectedBalance: Int?
    @State private var walletTransactions: [AdminDepositRow] = []
    @State private var isLoading = false
    @State private var isLoadingCustomers = false
    @State private var errorMessage: String?
    @State private var customersError: String?
    @State private var message: String?
    @State private var adjustAmount = ""
    @State private var isWorking = false
    @State private var isLoadingDetail = false
    @State private var confirmDeposit: AdminDepositRow?
    @State private var confirmReject: AdminDepositRow?

    private var pending: [AdminDepositRow] { deposits.filter { $0.isPending } }

    private var filteredCustomers: [AdminCustomerRow] {
        let query = customerSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return customers }
        return customers.filter {
            $0.name.localizedCaseInsensitiveContains(query)
            || $0.email.localizedCaseInsensitiveContains(query)
            || ($0.whatsapp_number ?? "").localizedCaseInsensitiveContains(query)
        }
    }

    private func customerName(for userId: Int?) -> String {
        guard let userId else { return "-" }
        return customers.first { $0.id == userId }?.name ?? "Customer #\(userId)"
    }

    var body: some View {
        Group {
            if !appState.isAdminLoggedIn {
                AdminNotSignedInView()
            } else if isLoading && deposits.isEmpty {
                ScrollView {
                    AdminSkeletonView(lines: 4, title: "Loading wallet deposits")
                }
                .scrollIndicators(.hidden)
                .adminFullScreenFrame()
            } else if let errorMessage, deposits.isEmpty {
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
        .navigationTitle("Wallet")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .alert("Approve deposit?", isPresented: .constant(confirmDeposit != nil)) {
            Button("Approve") {
                if let deposit = confirmDeposit {
                    confirmDeposit = nil
                    Task { await approve(deposit) }
                }
            }
            Button("Cancel", role: .cancel) { confirmDeposit = nil }
        } message: {
            Text("This credits the customer wallet balance.")
        }
        .alert("Reject deposit?", isPresented: .constant(confirmReject != nil)) {
            Button("Reject", role: .destructive) {
                if let deposit = confirmReject {
                    confirmReject = nil
                    Task { await reject(deposit) }
                }
            }
            Button("Cancel", role: .cancel) { confirmReject = nil }
        } message: {
            Text("This deposit will be marked rejected and the balance will not move.")
        }
    }

    private var highlightedDeposit: AdminDepositRow? {
        guard let target = highlightedDepositId else { return nil }
        return deposits.first { $0.id == target }
    }

    private var content: some View {
        List {
            if let highlightedDeposit {
                Section("From notification") {
                    depositRow(highlightedDeposit)
                }
            }
            Section("Customer") {
                TextField("Search name, email or WhatsApp", text: $customerSearch)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .psTextField()
                if isLoadingCustomers {
                    PSRingSpinner(diameter: 20, lineWidth: 2)
                } else if let customersError {
                    Text(customersError)
                        .font(.psCaption)
                        .foregroundStyle(.psDanger)
                } else if filteredCustomers.isEmpty {
                    Text(customers.isEmpty ? "No customers yet." : "No customers match that search.")
                        .font(.psBody)
                        .foregroundStyle(.psMuted)
                }
                ForEach(Array(filteredCustomers.prefix(30))) { customer in
                    Button {
                        select(customer)
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(customer.name)
                                    .font(.psHeadline)
                                    .foregroundStyle(.psText)
                                Text(customer.email)
                                    .font(.psCaption)
                                    .foregroundStyle(.psMuted)
                                Text(customer.whatsapp_number ?? "-")
                                    .font(.psCaption)
                                    .foregroundStyle(.psMuted)
                                Text("Wallet KES \(customer.wallet_balance ?? 0)")
                                    .font(.psCaption)
                                    .foregroundStyle(.psMuted)
                            }
                            Spacer()
                            if selectedCustomer?.id == customer.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.psPrimary)
                                    .font(.psHeadline)
                                    .accessibilityHidden(true)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Select customer \(customer.name)")
                }
                if filteredCustomers.count > 30 {
                    Text("Showing the first 30 of \(filteredCustomers.count) matches. Narrow the search to see more.")
                        .font(.psCaption)
                        .foregroundStyle(.psMuted)
                }
            }
            if let selected = selectedCustomer {
                Section("Selected customer") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(selected.name)
                            .font(.psHeadline)
                        Text(selected.email)
                            .font(.psCaption)
                            .foregroundStyle(.psMuted)
                        Text(selected.whatsapp_number ?? "-")
                            .font(.psCaption)
                            .foregroundStyle(.psMuted)
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("Wallet balance")
                                .font(.psCaption)
                                .foregroundStyle(.psMuted)
                            Text("KES \(selectedBalance ?? selected.wallet_balance ?? 0)")
                                .font(.psTitle)
                        }
                        if isLoadingDetail {
                            PSRingSpinner(diameter: 20, lineWidth: 2)
                        }
                    }
                    TextField("Amount in KES", text: $adjustAmount)
                        .keyboardType(.numberPad)
                        .psTextField()
                    HStack(spacing: 10) {
                        Button("Deposit") { Task { await adjust(credit: true) } }
                            .buttonStyle(.borderedProminent)
                            .tint(.psSuccess)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .disabled(isWorking || (Int(adjustAmount) ?? 0) <= 0)
                            .accessibilityLabel("Deposit to \(selected.name) wallet")
                        Button("Deduct") { Task { await adjust(credit: false) } }
                            .buttonStyle(.borderedProminent)
                            .tint(.psWarning)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .disabled(isWorking || (Int(adjustAmount) ?? 0) <= 0)
                            .accessibilityLabel("Deduct from \(selected.name) wallet")
                    }
                    if let message {
                        Text(message)
                            .font(.psCaption)
                            .foregroundStyle(.psMuted)
                    }
                    if isWorking {
                        PSRingSpinner(diameter: 20, lineWidth: 2)
                    }
                }
                Section("Recent wallet transactions") {
                    if walletTransactions.isEmpty {
                        Text("No wallet transactions for this customer yet.")
                            .font(.psBody)
                            .foregroundStyle(.psMuted)
                    }
                    ForEach(walletTransactions) { txn in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(txn.actionLabel)
                                    .font(.psHeadline)
                                Spacer()
                                Text("KES \(txn.amount ?? 0)")
                                    .font(.psHeadline)
                            }
                            Text("Transaction #\(txn.id) · \(txn.status ?? "-") · code \(txn.mpesa_code ?? "-")")
                                .font(.psCaption)
                                .foregroundStyle(.psMuted)
                            Text(adminShortDate(txn.created_at))
                                .font(.psCaption)
                                .foregroundStyle(.psMuted)
                        }
                        .padding(.vertical, 4)
                        .accessibilityElement(children: .combine)
                    }
                }
            } else {
                Section {
                    Text("Pick a customer above to see their wallet balance, recent transactions and deposit or deduct funds.")
                        .font(.psBody)
                        .foregroundStyle(.psMuted)
                }
            }
            Section("Pending deposits (\(pending.count))") {
                if pending.isEmpty {
                    PSEmptyState(
                        systemImage: "wallet.bifold.fill",
                        title: "No pending deposits",
                        body: "Wallet deposits waiting for approval will appear here."
                    )
                }
                ForEach(pending) { deposit in
                    depositRow(deposit)
                }
            }
            Section("All deposits") {
                if deposits.isEmpty {
                    Text("No deposits yet.")
                        .font(.psBody)
                        .foregroundStyle(.psMuted)
                }
                ForEach(deposits) { deposit in
                    depositRow(deposit)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
    }

    private func depositRow(_ deposit: AdminDepositRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("KES \(deposit.amount ?? 0)")
                    .font(.psHeadline)
                Spacer()
                PSStatusPill(
                    text: deposit.status ?? "pending",
                    systemImage: deposit.isPending ? "clock.fill" : "checkmark.circle.fill",
                    tint: deposit.isPending ? .psAmber : .psSuccess
                )
            }
            Text("Deposit #\(deposit.id) · \(customerName(for: deposit.user_id)) · code \(deposit.mpesa_code ?? "-")")
                .font(.psCaption)
                .foregroundStyle(.psMuted)
            Text(adminShortDate(deposit.created_at))
                .font(.psCaption)
                .foregroundStyle(.psMuted)
            if deposit.isPending {
                HStack(spacing: 10) {
                    Button("Approve") { confirmDeposit = deposit }
                        .buttonStyle(.borderedProminent)
                        .tint(.psSuccess)
                        .font(.psCaption)
                        .accessibilityLabel("Approve deposit \(deposit.id)")
                    Button("Reject", role: .destructive) { confirmReject = deposit }
                        .buttonStyle(.bordered)
                        .font(.psCaption)
                        .accessibilityLabel("Reject deposit \(deposit.id)")
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private func select(_ customer: AdminCustomerRow) {
        selectedCustomer = customer
        selectedBalance = customer.wallet_balance
        walletTransactions = []
        message = nil
        Task { await loadCustomerDetail(customer) }
    }

    private func load() async {
        guard appState.isAdminLoggedIn else { return }
        if let cached = AdminCache.load(key: "admin-wallet"),
           let decoded = try? JSONDecoder().decode(AdminWalletResponse.self, from: cached),
           decoded.ok {
            deposits = decoded.deposits ?? []
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let data = try await APIClient.shared.fetchData("api/v1/admin/wallet")
            let result = try JSONDecoder().decode(AdminWalletResponse.self, from: data)
            guard result.ok else {
                if deposits.isEmpty {
                    errorMessage = "Admin needs the live API. The wallet endpoint did not return data."
                }
                return
            }
            AdminCache.save(data, key: "admin-wallet")
            deposits = result.deposits ?? []
        } catch {
            if deposits.isEmpty {
                errorMessage = error.localizedDescription
            } else {
                message = "Live refresh failed: \(error.localizedDescription). Showing the last saved deposits."
            }
        }
        await loadCustomers()
    }

    private func loadCustomers() async {
        guard appState.isAdminLoggedIn else { return }
        isLoadingCustomers = true
        customersError = nil
        defer { isLoadingCustomers = false }
        do {
            let result: AdminCustomersListResponse = try await APIClient.shared.fetchJSON("api/v1/admin/customers")
            guard result.ok else {
                customersError = "The customers list did not return data."
                return
            }
            customers = result.customers ?? []
        } catch {
            customersError = error.localizedDescription
        }
    }

    private func loadCustomerDetail(_ customer: AdminCustomerRow) async {
        isLoadingDetail = true
        defer { isLoadingDetail = false }
        do {
            let result: AdminCustomerWalletDetailResponse = try await APIClient.shared.fetchJSON("api/v1/admin/customers/\(customer.id)")
            guard result.ok else { return }
            if let detailCustomer = result.resolvedCustomer {
                selectedBalance = detailCustomer.wallet_balance
            }
            walletTransactions = result.wallet_transactions ?? []
        } catch {
            message = error.localizedDescription
        }
    }

    private func approve(_ deposit: AdminDepositRow) async {
        // POST /api/v1/admin/wallet/deposit/<id>/approve
        // Returns {"status": "approved"}.
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await APIClient.shared.fetchOK(
                "api/v1/admin/wallet/deposit/\(deposit.id)/approve", method: "POST")
            message = "Deposit #\(deposit.id) approved and credited."
            await load()
            if let selected = selectedCustomer {
                await loadCustomerDetail(selected)
            }
        } catch {
            message = error.localizedDescription
        }
    }

    private func reject(_ deposit: AdminDepositRow) async {
        // POST /api/v1/admin/wallet/deposit/<id>/reject
        // Returns {"status": "rejected"}.
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await APIClient.shared.fetchOK(
                "api/v1/admin/wallet/deposit/\(deposit.id)/reject", method: "POST")
            message = "Deposit #\(deposit.id) rejected."
            await load()
        } catch {
            message = error.localizedDescription
        }
    }

    private func adjust(credit: Bool) async {
        // POST /api/v1/admin/wallet/adjust, body
        // {"user_id": Int, "amount": Int}, returns {"wallet_balance": Int}.
        // The user id comes from the picked customer, never typed in.
        guard let selected = selectedCustomer,
              let entered = Int(adjustAmount), entered > 0 else {
            message = "Enter an amount above zero."
            return
        }
        let amount = credit ? entered : -entered
        isWorking = true
        defer { isWorking = false }
        do {
            let result: AdminWalletAdjustResponse = try await APIClient.shared.fetchJSON(
                "api/v1/admin/wallet/adjust",
                method: "POST", body: ["user_id": selected.id, "amount": amount])
            selectedBalance = result.wallet_balance
            message = "\(selected.name) wallet balance is now KES \(result.wallet_balance ?? 0)."
            adjustAmount = ""
            await loadCustomerDetail(selected)
        } catch {
            message = error.localizedDescription
        }
    }
}

struct AdminCustomerWalletDetailResponse: Decodable {
    let ok: Bool
    let customer: AdminCustomerRow?
    let user: AdminCustomerRow?
    let wallet_transactions: [AdminDepositRow]?

    var resolvedCustomer: AdminCustomerRow? { customer ?? user }
}

// MARK: - Gift cards (admin)
// GET /api/v1/admin/gift-cards returns:
// {"ok": true, "gift_cards": [_gift_card_row rows], "enabled": String,
//  "metrics": {"total", "pending", "active", "revenue"} when present}
// _gift_card_row rows carry amount = initial_amount, message =
// custom_message, expiry_date = expires_at, plus the raw columns
// (initial_amount, custom_message, mpesa_code, sender_name,
// sender_email, payment_reference, admin_notes). Both the mapped
// keys and the raw keys are decoded, mapped key first, so rows
// read correctly whether or not the backend maps them. Statuses
// are capitalised: Pending / Approved / Active / Redeemed /
// Rejected / Expired. Approve sets Approved; reject sets Rejected
// with an admin_notes reason; resend sends the styled voucher
// email with the real amount. Issue validates 50-50,000, stores
// initial_amount = remaining_balance = amount, status Approved,
// code GIFT-XXXX-XXXX. The toggle posts {"enabled": Bool} to
// /api/v1/admin/settings/gift-cards; the Settings key itself
// (enable_gift_cards) lives server-side.

struct AdminGiftCardRow: Decodable, Identifiable, Equatable {
    let id: Int
    let code: String?
    let amount: Int?
    let initial_amount: Int?
    let status: String?
    let recipient_name: String?
    let recipient_email: String?
    let sender_name: String?
    let sender_email: String?
    let message: String?
    let custom_message: String?
    let mpesa_code: String?
    let payment_reference: String?
    let admin_notes: String?
    let theme_style: String?
    let expiry_date: String?
    let expires_at: String?
    let created_at: String?

    var displayAmount: Int? {
        amount ?? initial_amount
    }

    var displayMessage: String? {
        message ?? custom_message
    }

    var expiryText: String? {
        expiry_date ?? expires_at
    }
}

struct AdminGiftCardMetrics: Decodable {
    let total: Int?
    let pending: Int?
    let active: Int?
    let revenue: Int?
}

struct AdminGiftCardsResponse: Decodable {
    let ok: Bool
    let gift_cards: [AdminGiftCardRow]?
    let enabled: String?
    let metrics: AdminGiftCardMetrics?

    enum CodingKeys: String, CodingKey {
        case ok, gift_cards, enabled, metrics
        case total, pending, active, revenue
    }

    /// enabled may arrive as a Bool or a String; metrics may arrive
    /// nested under "metrics" or as flat top-level keys.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.decode(Bool.self, forKey: .ok)
        gift_cards = try container.decodeIfPresent([AdminGiftCardRow].self, forKey: .gift_cards)
        if let enabledBool = try? container.decode(Bool.self, forKey: .enabled) {
            enabled = enabledBool ? "true" : "false"
        } else {
            enabled = try container.decodeIfPresent(String.self, forKey: .enabled)
        }
        if let nested = try container.decodeIfPresent(AdminGiftCardMetrics.self, forKey: .metrics) {
            metrics = nested
        } else {
            let total = try container.decodeIfPresent(Int.self, forKey: .total)
            let pending = try container.decodeIfPresent(Int.self, forKey: .pending)
            let active = try container.decodeIfPresent(Int.self, forKey: .active)
            let revenue = try container.decodeIfPresent(Int.self, forKey: .revenue)
            if total == nil && pending == nil && active == nil && revenue == nil {
                metrics = nil
            } else {
                metrics = AdminGiftCardMetrics(total: total, pending: pending, active: active, revenue: revenue)
            }
        }
    }
}

struct AdminGiftCardsRootView: View {
    @EnvironmentObject private var appState: AppState
    @State private var cards: [AdminGiftCardRow] = []
    @State private var enabled = true
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var message: String?
    @State private var showIssue = false
    @State private var isWorking = false
    @State private var confirmApprove: AdminGiftCardRow?
    @State private var confirmReject: AdminGiftCardRow?
    @State private var rejectReason = ""
    @State private var metrics: AdminGiftCardMetrics?

    var body: some View {
        Group {
            if !appState.isAdminLoggedIn {
                AdminNotSignedInView()
            } else if isLoading && cards.isEmpty {
                ScrollView {

                    AdminSkeletonView(lines: 4, title: "Loading gift cards")

                }

                .scrollIndicators(.hidden)

                .adminFullScreenFrame()
            } else if let errorMessage, cards.isEmpty {
                PSErrorState(message: errorMessage) {
                    Task { await load() }
                }
                .psScreenPadding()
            } else {
                content
            }
        }
        .adminScreenBackground()
        .navigationTitle("Gift cards")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showIssue = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Issue gift card")
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showIssue) {
            AdminIssueGiftCardSheet {
                showIssue = false
                Task { await load() }
            }
        }
        .alert("Approve gift card?", isPresented: .constant(confirmApprove != nil)) {
            Button("Approve") {
                if let card = confirmApprove {
                    confirmApprove = nil
                    Task { await setStatus(card, approve: true) }
                }
            }
            Button("Cancel", role: .cancel) { confirmApprove = nil }
        } message: {
            Text("This activates the gift card.")
        }
        .alert("Reject gift card?", isPresented: .constant(confirmReject != nil)) {
            TextField("Reason (optional)", text: $rejectReason)
            Button("Reject", role: .destructive) {
                if let card = confirmReject {
                    confirmReject = nil
                    Task { await setStatus(card, approve: false) }
                }
            }
            Button("Cancel", role: .cancel) {
                confirmReject = nil
                rejectReason = ""
            }
        } message: {
            Text("This rejects the gift card. The reason is saved as the admin note.")
        }
    }

    private var content: some View {
        List {
            if let metrics, metrics.total != nil || metrics.pending != nil || metrics.active != nil || metrics.revenue != nil {
                Section("Gift card totals") {
                    HStack(spacing: 16) {
                        if let total = metrics.total {
                            metricCell(label: "Total", value: "\(total)")
                        }
                        if let pending = metrics.pending {
                            metricCell(label: "Pending", value: "\(pending)")
                        }
                        if let active = metrics.active {
                            metricCell(label: "Active", value: "\(active)")
                        }
                        if let revenue = metrics.revenue {
                            metricCell(label: "Revenue", value: psKESGrouped(revenue))
                        }
                    }
                }
            }
            Section {
                Toggle("Gift cards enabled", isOn: $enabled)
                    .font(.psBody)
                    .onChange(of: enabled) { Task { await setEnabled() } }
                    .accessibilityLabel("Gift cards feature enabled")
                Button("Issue a gift card") { showIssue = true }
                    .font(.psCaption)
                if let message {
                    Text(message)
                        .font(.psCaption)
                        .foregroundStyle(.psMuted)
                }
                if isWorking {
                    PSRingSpinner(diameter: 20, lineWidth: 2)
                }
            }
            Section {
                if cards.isEmpty {
                    PSEmptyState(
                        systemImage: "gift.fill",
                        title: "No gift cards yet",
                        body: "Issued gift cards will appear here."
                    )
                }
                ForEach(cards) { card in
                    giftCardRow(card)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
    }

    private func metricCell(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.psHeadline)
            Text(label)
                .font(.psCaption)
                .foregroundStyle(.psMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func giftCardRow(_ card: AdminGiftCardRow) -> some View {
        let statusLower = (card.status ?? "").lowercased()
        let needsDecision = statusLower.isEmpty || statusLower == "pending"
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(card.code ?? "Card #\(card.id)")
                    .font(.psMono)
                Spacer()
                Text(psKESGrouped(card.displayAmount))
                    .font(.psHeadline)
            }
            Text("\(card.recipient_name ?? "-") · \(card.recipient_email ?? "-")")
                .font(.psCaption)
                .foregroundStyle(.psMuted)
            if let sender = card.sender_name, !sender.isEmpty {
                Text("From \(sender)")
                    .font(.psCaption)
                    .foregroundStyle(.psMuted)
            }
            if let mpesaCode = card.mpesa_code, !mpesaCode.isEmpty {
                Text("M-PESA code \(mpesaCode)")
                    .font(.psCaption)
                    .foregroundStyle(.psMuted)
            }
            if let expiry = card.expiryText {
                Text("Expires \(adminShortDate(expiry))")
                    .font(.psCaption)
                    .foregroundStyle(.psMuted)
            }
            if let message = card.displayMessage, !message.isEmpty {
                Text(message)
                    .font(.psBody)
                    .foregroundStyle(.psDim)
            }
            HStack(spacing: 8) {
                psGiftCardStatusPill(status: card.status)
                if let themeName = PSGiftCardTheme.theme(named: card.theme_style)?.name ?? card.theme_style, !themeName.isEmpty {
                    Text(themeName)
                        .font(.psCaption)
                        .foregroundStyle(.psMuted)
                }
            }
            HStack(spacing: 10) {
                Button("Resend") { Task { await resend(card) } }
                    .buttonStyle(.bordered)
                    .tint(.psCyan)
                    .font(.psCaption)
                    .disabled(isWorking)
                if needsDecision {
                    Button("Approve") { confirmApprove = card }
                        .buttonStyle(.bordered)
                        .tint(.psPrimary)
                        .font(.psCaption)
                        .disabled(isWorking)
                    Button("Reject", role: .destructive) { confirmReject = card }
                        .buttonStyle(.bordered)
                        .font(.psCaption)
                        .disabled(isWorking)
                }
            }
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
            let result: AdminGiftCardsResponse = try await APIClient.shared.fetchJSON("api/v1/admin/gift-cards")
            guard result.ok else {
                errorMessage = "Admin needs the live API. The gift cards endpoint did not return data."
                return
            }
            cards = result.gift_cards ?? []
            metrics = result.metrics
            enabled = (result.enabled ?? "true").lowercased() == "true"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func setEnabled() async {
        // POST /api/v1/admin/settings/gift-cards, body {"enabled": Bool},
        // returns {"enabled": Bool}.
        struct ToggleResponse: Decodable { let ok: Bool; let enabled: Bool? }
        do {
            let result: ToggleResponse = try await APIClient.shared.fetchJSON(
                "api/v1/admin/settings/gift-cards",
                method: "POST", body: ["enabled": enabled])
            enabled = result.enabled ?? enabled
            message = "Gift cards are now \(enabled ? "enabled" : "disabled")."
        } catch {
            message = error.localizedDescription
            enabled.toggle()
        }
    }

    private func resend(_ card: AdminGiftCardRow) async {
        // POST /api/v1/admin/gift-cards/resend, body {"code": ...},
        // returns {"resent_to": email}.
        guard let code = card.code else { return }
        struct ResendResponse: Decodable { let ok: Bool; let resent_to: String? }
        isWorking = true
        defer { isWorking = false }
        do {
            let result: ResendResponse = try await APIClient.shared.fetchJSON(
                "api/v1/admin/gift-cards/resend",
                method: "POST", body: ["code": code])
            message = "Gift card resent to \(result.resent_to ?? "-")."
        } catch {
            message = error.localizedDescription
        }
    }

    private func setStatus(_ card: AdminGiftCardRow, approve: Bool) async {
        // POST /api/v1/admin/gift-cards/approve|reject, body {"id": ...}.
        // Reject also carries the admin_notes reason from the alert.
        let path = approve ? "api/v1/admin/gift-cards/approve" : "api/v1/admin/gift-cards/reject"
        var body: [String: Any] = ["id": card.id]
        let reason = rejectReason.trimmingCharacters(in: .whitespacesAndNewlines)
        if !approve, !reason.isEmpty {
            body["admin_notes"] = reason
        }
        rejectReason = ""
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await APIClient.shared.fetchOK(path, method: "POST", body: body)
            message = "Gift card \(card.code ?? "#\(card.id)") \(approve ? "approved" : "rejected")."
            await load()
        } catch {
            message = error.localizedDescription
        }
    }
}

struct AdminIssueGiftCardSheet: View {
    var onDone: () -> Void

    @State private var amount = ""
    @State private var recipientName = ""
    @State private var recipientEmail = ""
    @State private var messageText = ""
    @State private var themeId = "gold"
    @State private var isWorking = false
    @State private var message: String?
    @State private var issuedCode: String?
    @State private var issuedAmount: Int?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    PSCard {
                        VStack(alignment: .leading, spacing: 12) {
                            PSSectionHeader(title: "Issue a gift card")
                            TextField("Amount (KES)", text: $amount)
                                .keyboardType(.numberPad)
                                .psTextField()
                            Text("Amount from KES 50 to KES 50,000. The card is approved at once and emailed to the recipient.")
                                .font(.psCaption)
                                .foregroundStyle(.psMuted)
                            TextField("Recipient name", text: $recipientName)
                                .autocorrectionDisabled()
                                .psTextField()
                            TextField("Recipient email", text: $recipientEmail)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .keyboardType(.emailAddress)
                                .psTextField()
                            TextField("Message (optional)", text: $messageText)
                                .psTextField()
                            PSSectionHeader(title: "Theme")
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                ForEach(PSGiftCardTheme.all) { theme in
                                    Button {
                                        themeId = theme.id
                                    } label: {
                                        VStack(alignment: .leading, spacing: 6) {
                                            LinearGradient(colors: theme.colors, startPoint: .leading, endPoint: .trailing)
                                                .frame(height: 36)
                                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                            Text(theme.name)
                                                .font(.psCaption)
                                                .foregroundStyle(.psText)
                                        }
                                        .padding(8)
                                        .background(Color.psSurface)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(themeId == theme.id ? Color.psPrimary : Color.psBorder, lineWidth: themeId == theme.id ? 2 : 1)
                                        )
                                    }
                                    .accessibilityLabel("Gift card theme \(theme.name)")
                                }
                            }
                            Button("Issue gift card") { Task { await issue() } }
                                .psPrimary()
                                .disabled(isWorking || (Int(amount) ?? 0) <= 0)
                                .accessibilityLabel("Issue gift card")
                        }
                    }
                    if let issuedCode, let issuedAmount {
                        PSCard {
                            VStack(alignment: .leading, spacing: 8) {
                                PSSectionHeader(title: "Gift card issued")
                                Text("Amount \(psKESGrouped(issuedAmount))")
                                    .font(.psBody)
                                HStack {
                                    Text(issuedCode)
                                        .font(.psMono)
                                    Button {
                                        UIPasteboard.general.string = issuedCode
                                    } label: {
                                        Image(systemName: "doc.on.doc")
                                            .font(.psIcon)
                                    }
                                    .accessibilityLabel("Copy gift card code \(issuedCode)")
                                }
                                Text("The voucher was emailed to the recipient.")
                                    .font(.psCaption)
                                    .foregroundStyle(.psMuted)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
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
            .navigationTitle("Issue gift card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { onDone() }
                }
            }
        }
        .psSheetDetents()
    }

    private func issue() async {
        // POST /api/v1/admin/gift-cards/issue returns
        // {"gift_card_id": Int, "code": String, "amount": Int}.
        // The server generates the GIFT-XXXX-XXXX code and stores
        // initial_amount = remaining_balance = amount, status Approved.
        struct IssueResponse: Decodable {
            let ok: Bool
            let gift_card_id: Int?
            let code: String?
            let amount: Int?
        }
        guard let amountValue = Int(amount), amountValue >= 50, amountValue <= 50000 else {
            message = "Gift card amount must be between KES 50 and KES 50,000."
            return
        }
        guard !recipientName.trimmingCharacters(in: .whitespaces).isEmpty else {
            message = "Enter the recipient name."
            return
        }
        let email = recipientEmail.trimmingCharacters(in: .whitespaces)
        guard !email.isEmpty, email.contains("@") else {
            message = "Enter a valid recipient email so they receive their voucher."
            return
        }
        var body: [String: Any] = [
            "amount": amountValue,
            "recipient_name": recipientName.trimmingCharacters(in: .whitespaces),
            "recipient_email": email,
            "theme_style": themeId
        ]
        if !messageText.isEmpty {
            body["message"] = messageText
            body["custom_message"] = messageText
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let result: IssueResponse = try await APIClient.shared.fetchJSON(
                "api/v1/admin/gift-cards/issue", method: "POST", body: body)
            issuedCode = result.code
            issuedAmount = result.amount ?? amountValue
            message = "Gift card issued."
        } catch {
            message = error.localizedDescription
        }
    }
}

// MARK: - Transactions
// GET /api/v1/admin/transactions returns:
// {"ok": true, "transactions": [WalletTransactions rows],
//  "ledger": [FinancialLedger rows]}
// POST /api/v1/admin/transactions/<id>/verify marks the row verified
// (WalletTransactions first, then FinancialLedger) and returns
// {"status": "verified"}.

struct AdminTransactionsResponse: Decodable {
    let ok: Bool
    let transactions: [AdminGenericRow]?
    let ledger: [AdminGenericRow]?
}

struct AdminTransactionsRootView: View {
    @EnvironmentObject private var appState: AppState
    @State private var transactions: [AdminGenericRow] = []
    @State private var ledger: [AdminGenericRow] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var message: String?
    @State private var isWorking = false

    var body: some View {
        Group {
            if !appState.isAdminLoggedIn {
                AdminNotSignedInView()
            } else if isLoading && transactions.isEmpty && ledger.isEmpty {
                ScrollView {

                    AdminSkeletonView(lines: 4, title: "Loading transactions")

                }

                .scrollIndicators(.hidden)

                .adminFullScreenFrame()
            } else if let errorMessage, transactions.isEmpty && ledger.isEmpty {
                PSErrorState(message: errorMessage) {
                    Task { await load() }
                }
                .psScreenPadding()
            } else {
                content
            }
        }
        .adminScreenBackground()
        .navigationTitle("Transactions")
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
            Section("Wallet transactions") {
                if transactions.isEmpty {
                    Text("No wallet transactions yet.")
                        .font(.psBody)
                        .foregroundStyle(.psMuted)
                }
                ForEach(transactions) { row in
                    transactionRow(row)
                }
            }
            Section("Financial ledger") {
                if ledger.isEmpty {
                    Text("No ledger entries yet.")
                        .font(.psBody)
                        .foregroundStyle(.psMuted)
                }
                ForEach(ledger) { row in
                    transactionRow(row)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
    }

    private func transactionRow(_ row: AdminGenericRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(row.first("action_type", "description") ?? "Transaction #\(row.id)")
                    .font(.psHeadline)
                Spacer()
                Text("KES \(row.text("amount") ?? "0")")
                    .font(.psHeadline)
            }
            Text("ID \(row.id) · code \(row.text("mpesa_code") ?? "-") · \(row.text("status") ?? "-")")
                .font(.psCaption)
                .foregroundStyle(.psMuted)
            Text(adminShortDate(row.text("created_at")))
                .font(.psCaption)
                .foregroundStyle(.psMuted)
            if (row.text("status") ?? "").lowercased() != "verified" {
                Button("Verify") { Task { await verify(row) } }
                    .buttonStyle(.bordered)
                    .tint(.psCyan)
                    .font(.psCaption)
                    .disabled(isWorking)
                    .accessibilityLabel("Verify transaction \(row.id)")
            }
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
            let result: AdminTransactionsResponse = try await APIClient.shared.fetchJSON("api/v1/admin/transactions")
            guard result.ok else {
                errorMessage = "Admin needs the live API. The transactions endpoint did not return data."
                return
            }
            transactions = result.transactions ?? []
            ledger = result.ledger ?? []
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func verify(_ row: AdminGenericRow) async {
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await APIClient.shared.fetchOK(
                "api/v1/admin/transactions/\(row.id)/verify", method: "POST")
            message = "Transaction #\(row.id) verified."
            await load()
        } catch {
            message = error.localizedDescription
        }
    }
}

// MARK: - Payment methods + gateway switch
// GET /api/v1/admin/payment-methods returns:
// {"ok": true, "payment_gateway": "mpesa"|"stk"|"both"|"intasend",
//  "payment_method": "paybill"|"till"|"send_money"|"pochi",
//  "rail_title", "rail_badge", "rail_instructions",
//  "rail_short_desc", "mpesa_paybill", "mpesa_account",
//  "mpesa_till", "mpesa_till_name", "mpesa_phone",
//  "mpesa_recipient_name", "mpesa_pochi_phone", "mpesa_pochi_name",
//  "intasend_enabled": Bool}
// Two separate settings, never conflated: payment_gateway (which
// checkout rails are offered) and payment_method (the manual
// M-PESA rail: PayBill / Till / Send Money / Pochi La Biashara,
// read by get_payment_method_config). POST accepts payment_method
// and the "gateway" alias for payment_gateway and returns both.
// The gateway switch posts there with {"gateway": ...}; picking a
// row never posts on its own, so loading the screen cannot flip
// the live gateway. The older code posted on every picker change,
// including the change caused by loading the saved value.

struct AdminPaymentMethodsResponse: Decodable {
    let ok: Bool
    let payment_gateway: String?
    let payment_method: String?
    let rail_title: String?
    let rail_badge: String?
    let rail_instructions: String?
    let rail_short_desc: String?
    let mpesa_paybill: String?
    let mpesa_account: String?
    let mpesa_till: String?
    let mpesa_till_name: String?
    let mpesa_phone: String?
    let mpesa_recipient_name: String?
    let mpesa_pochi_phone: String?
    let mpesa_pochi_name: String?
    let intasend_enabled: Bool?
}

struct AdminPaymentMethodsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var gateway = "mpesa"
    @State private var pendingGateway = "mpesa"
    @State private var rail = "paybill"
    @State private var pendingRail = "paybill"
    @State private var railTitle: String?
    @State private var railBadge: String?
    @State private var railInstructions: String?
    @State private var paybill = ""
    @State private var account = ""
    @State private var phone = ""
    @State private var intasendEnabled = false
    @State private var hasLoaded = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var message: String?
    @State private var isWorking = false

    /// Display name for a gateway value. "both" and "intasend"
    /// are real values the server accepts; they used to render as
    /// raw text with no row active.
    private func gatewayLabel(_ value: String) -> String {
        switch value.lowercased() {
        case "mpesa": return "Manual M-PESA"
        case "stk": return "STK push"
        case "both": return "Both (Manual + STK)"
        case "intasend": return "IntaSend"
        default: return psCapitalized(value)
        }
    }

    /// Display name for a manual M-PESA rail id.
    private func railDisplayName(_ value: String) -> String {
        switch value.lowercased() {
        case "paybill": return "PayBill"
        case "till": return "Till"
        case "send_money": return "Send Money"
        case "pochi": return "Pochi La Biashara"
        default: return psCapitalized(value)
        }
    }

    private var rails: [(id: String, title: String, detail: String)] {
        [
            ("paybill", "PayBill", "PayBill \(paybill.isEmpty ? "-" : paybill) · Account \(account.isEmpty ? "-" : account)"),
            ("till", "Till", "Till number shown at checkout"),
            ("send_money", "Send Money", "Send money to \(phone.isEmpty ? "-" : phone)"),
            ("pochi", "Pochi La Biashara", "Pochi La Biashara number shown at checkout")
        ]
    }

    /// The real methods the site offers. The GET endpoint returns
    /// no methods array, only the active gateway and the IntaSend
    /// flag, so the list is built from those two facts: manual
    /// M-PESA and wallet are always available, STK push only when
    /// IntaSend is configured. Wallet is a payment method, not a
    /// gateway, so it is listed as always on and never switched.
    private var methods: [(id: String, title: String, detail: String, systemImage: String)] {
        [
            ("mpesa", "Manual M-PESA", "PayBill \(paybill.isEmpty ? "-" : paybill) · Account \(account.isEmpty ? "-" : account)", "phone.fill"),
            ("stk", "STK push", intasendEnabled ? "IntaSend STK push to the customer phone" : "Not configured: IntaSend is not set up", "bolt.fill"),
            ("both", "Both (Manual + STK)", intasendEnabled ? "Manual M-PESA and STK push both offered" : "Manual M-PESA offered now, STK push once IntaSend is set up", "arrow.left.arrow.right"),
            ("intasend", "IntaSend", intasendEnabled ? "IntaSend STK push to the customer phone" : "Not configured: IntaSend is not set up", "bolt.fill"),
            ("wallet", "Wallet", "Pay from the customer wallet balance", "wallet.bifold.fill")
        ]
    }

    private var stkAvailable: Bool { intasendEnabled }

    var body: some View {
        Group {
            if !appState.isAdminLoggedIn {
                AdminNotSignedInView()
            } else if isLoading && !hasLoaded && errorMessage == nil {
                ScrollView {

                    AdminSkeletonView(lines: 4, title: "Loading payment methods")

                }

                .scrollIndicators(.hidden)

                .adminFullScreenFrame()
            } else if let errorMessage, !hasLoaded {
                PSErrorState(message: errorMessage) {
                    Task { await load() }
                }
                .psScreenPadding()
            } else {
                content
            }
        }
        .adminScreenBackground()
        .navigationTitle("Payment methods")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                PSCard {
                    VStack(alignment: .leading, spacing: 12) {
                        PSSectionHeader(title: "Payment methods")
                        Text("Active gateway: \(gatewayLabel(gateway)). Tap a gateway below, then switch it on.")
                            .font(.psCaption)
                            .foregroundStyle(.psMuted)
                        ForEach(methods, id: \.id) { method in
                            let isGateway = method.id != "wallet"
                            let isActive = isGateway && gateway == method.id
                            let isPicked = isGateway && pendingGateway == method.id
                            let isDisabled = (method.id == "stk" || method.id == "intasend") && !stkAvailable
                            Button {
                                if isGateway && !isDisabled {
                                    pendingGateway = method.id
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: method.systemImage)
                                        .font(.psHeadline)
                                        .foregroundStyle(isActive ? .psSuccess : .psMuted)
                                        .frame(width: 24)
                                        .accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(method.title)
                                            .font(.psHeadline)
                                            .foregroundStyle(.psText)
                                        Text(method.detail)
                                            .font(.psCaption)
                                            .foregroundStyle(.psMuted)
                                    }
                                    Spacer()
                                    if isActive {
                                        PSStatusPill(text: "Active", systemImage: "checkmark.circle.fill", tint: .psSuccess)
                                    } else if method.id == "wallet" {
                                        PSStatusPill(text: "Always on", systemImage: "checkmark.circle.fill", tint: .psPrimary)
                                    } else if isPicked {
                                        PSStatusPill(text: "Selected", systemImage: "circle.fill", tint: .psPrimary)
                                    } else if isDisabled {
                                        PSStatusPill(text: "Not configured", systemImage: "exclamationmark.triangle.fill", tint: .psWarning)
                                    }
                                }
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .padding(12)
                                .background(isPicked ? Color.psPrimarySoft : Color.psSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(isPicked ? Color.psPrimary : Color.psBorder, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(!isGateway || isDisabled)
                            .accessibilityLabel("\(method.title), \(isActive ? "active gateway" : method.detail)")
                        }
                        Button("Switch gateway") { Task { await switchGateway() } }
                            .psPrimary()
                            .disabled(isWorking || pendingGateway == gateway || ((pendingGateway == "stk" || pendingGateway == "intasend") && !stkAvailable))
                            .accessibilityLabel("Switch gateway to \(gatewayLabel(pendingGateway))")
                        if pendingGateway != gateway {
                            Text("Switching to \(gatewayLabel(pendingGateway)) will change how customers pay at checkout.")
                                .font(.psCaption)
                                .foregroundStyle(.psMuted)
                        }
                    }
                }
                PSCard {
                    VStack(alignment: .leading, spacing: 12) {
                        PSSectionHeader(title: "Manual M-PESA rail")
                        Text("Active rail: \(railTitle ?? railDisplayName(rail))")
                            .font(.psHeadline)
                        if let railBadge, !railBadge.isEmpty {
                            PSStatusPill(text: railBadge, systemImage: "tag.fill", tint: .psPrimary)
                        }
                        if let railInstructions, !railInstructions.isEmpty {
                            Text(railInstructions)
                                .font(.psCaption)
                                .foregroundStyle(.psMuted)
                        }
                        ForEach(rails, id: \.id) { railOption in
                            let isActive = rail == railOption.id
                            let isPicked = pendingRail == railOption.id
                            Button {
                                pendingRail = railOption.id
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "phone.fill")
                                        .font(.psHeadline)
                                        .foregroundStyle(isActive ? .psSuccess : .psMuted)
                                        .frame(width: 24)
                                        .accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(railOption.title)
                                            .font(.psHeadline)
                                            .foregroundStyle(.psText)
                                        Text(railOption.detail)
                                            .font(.psCaption)
                                            .foregroundStyle(.psMuted)
                                    }
                                    Spacer()
                                    if isActive {
                                        PSStatusPill(text: "Active", systemImage: "checkmark.circle.fill", tint: .psSuccess)
                                    } else if isPicked {
                                        PSStatusPill(text: "Selected", systemImage: "circle.fill", tint: .psPrimary)
                                    }
                                }
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .padding(12)
                                .background(isPicked ? Color.psPrimarySoft : Color.psSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(isPicked ? Color.psPrimary : Color.psBorder, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(railOption.title), \(isActive ? "active rail" : railOption.detail)")
                        }
                        Button("Switch rail") { Task { await switchRail() } }
                            .psPrimary()
                            .disabled(isWorking || pendingRail == rail)
                            .accessibilityLabel("Switch M-PESA rail to \(railDisplayName(pendingRail))")
                        if pendingRail != rail {
                            Text("Switching to \(railDisplayName(pendingRail)) will change the M-PESA instructions customers see at checkout.")
                                .font(.psCaption)
                                .foregroundStyle(.psMuted)
                        }
                    }
                }
                PSCard {
                    VStack(alignment: .leading, spacing: 12) {
                        PSSectionHeader(title: "M-PESA details")
                        Text("These are the public payment instructions shown to customers at checkout.")
                            .font(.psCaption)
                            .foregroundStyle(.psMuted)
                        TextField("PayBill", text: $paybill)
                            .keyboardType(.numberPad)
                            .psTextField()
                        TextField("Account", text: $account)
                            .keyboardType(.numberPad)
                            .psTextField()
                        TextField("Phone", text: $phone)
                            .keyboardType(.phonePad)
                            .psTextField()
                        Button("Save payment methods") { Task { await save() } }
                            .psPrimary()
                            .disabled(isWorking)
                            .accessibilityLabel("Save payment methods")
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

    private func load() async {
        guard appState.isAdminLoggedIn else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let result: AdminPaymentMethodsResponse = try await APIClient.shared.fetchJSON("api/v1/admin/payment-methods")
            guard result.ok else {
                errorMessage = "Admin needs the live API. The payment methods endpoint did not return data."
                return
            }
            gateway = result.payment_gateway ?? "mpesa"
            pendingGateway = gateway
            rail = result.payment_method ?? "paybill"
            pendingRail = rail
            railTitle = result.rail_title
            railBadge = result.rail_badge
            railInstructions = result.rail_instructions
            paybill = result.mpesa_paybill ?? ""
            account = result.mpesa_account ?? ""
            phone = result.mpesa_phone ?? ""
            intasendEnabled = result.intasend_enabled ?? false
            hasLoaded = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() async {
        // POST /api/v1/admin/payment-methods, body
        // {"payment_gateway", "mpesa_paybill", "mpesa_account", "mpesa_phone"}.
        struct SaveResponse: Decodable { let ok: Bool; let payment_gateway: String? }
        isWorking = true
        defer { isWorking = false }
        do {
            let result: SaveResponse = try await APIClient.shared.fetchJSON(
                "api/v1/admin/payment-methods",
                method: "POST",
                body: [
                    "payment_gateway": gateway,
                    "mpesa_paybill": paybill,
                    "mpesa_account": account,
                    "mpesa_phone": phone
                ])
            gateway = result.payment_gateway ?? gateway
            pendingGateway = gateway
            message = "Payment methods saved."
        } catch {
            message = error.localizedDescription
        }
    }

    private func switchGateway() async {
        // POST /api/v1/admin/payment-methods with the "gateway"
        // alias, which the server accepts and saves as
        // payment_gateway. The switch only happens when the admin
        // taps Switch gateway: picking a row never posts on its own,
        // so loading the screen can never flip the live gateway.
        struct GatewayResponse: Decodable { let ok: Bool; let payment_gateway: String? }
        guard pendingGateway != gateway else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let result: GatewayResponse = try await APIClient.shared.fetchJSON(
                "api/v1/admin/payment-methods",
                method: "POST", body: ["gateway": pendingGateway])
            gateway = result.payment_gateway ?? pendingGateway
            pendingGateway = gateway
            message = "Gateway is now \(gatewayLabel(gateway))."
        } catch {
            message = error.localizedDescription
            await load()
        }
    }

    private func switchRail() async {
        // POST /api/v1/admin/payment-methods with
        // {"payment_method": ...}, which the server validates
        // against paybill/till/send_money/pochi and saves as the
        // manual M-PESA rail. Picking a row never posts on its own.
        struct RailResponse: Decodable {
            let ok: Bool
            let payment_gateway: String?
            let payment_method: String?
        }
        guard pendingRail != rail else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let result: RailResponse = try await APIClient.shared.fetchJSON(
                "api/v1/admin/payment-methods",
                method: "POST", body: ["payment_method": pendingRail])
            rail = result.payment_method ?? pendingRail
            pendingRail = rail
            message = "M-PESA rail is now \(railDisplayName(rail))."
            await load()
        } catch {
            message = error.localizedDescription
            await load()
        }
    }
}

