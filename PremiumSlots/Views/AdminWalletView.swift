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
                VStack(spacing: 12) {
                    PSRingSpinner(diameter: 40, lineWidth: 4)
                    Text("Loading wallet deposits")
                        .font(.psBody)
                        .foregroundStyle(.psMuted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage, deposits.isEmpty {
                PSErrorState(message: errorMessage) {
                    Task { await load() }
                }
                .psScreenPadding()
            } else {
                content
            }
        }
        .background(Color.psBackground)
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

    private var content: some View {
        List {
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
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let result: AdminWalletResponse = try await APIClient.shared.fetchJSON("api/v1/admin/wallet")
            guard result.ok else {
                errorMessage = "Admin needs the live API. The wallet endpoint did not return data."
                return
            }
            deposits = result.deposits ?? []
        } catch {
            errorMessage = error.localizedDescription
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
// {"ok": true, "gift_cards": [GiftCards rows], "enabled": String}
// GiftCards rows are flat _row_dict rows: id, code, amount, status,
// recipient_name, recipient_email, sender_name, message, theme_style,
// created_at. Approve/reject take {"id": ...} or {"code": ...} and
// return {"status": "active"} or {"status": "rejected"}.
// Resend takes {"code": ...} and returns {"resent_to": email}.
// Issue takes {"amount", "code"?, "recipient_name", "recipient_email",
// "message", "theme_style"} and returns
// {"gift_card_id", "code", "amount"}.

struct AdminGiftCardRow: Decodable, Identifiable, Equatable {
    let id: Int
    let code: String?
    let amount: Int?
    let status: String?
    let recipient_name: String?
    let recipient_email: String?
    let sender_name: String?
    let message: String?
    let theme_style: String?
    let created_at: String?
}

struct AdminGiftCardsResponse: Decodable {
    let ok: Bool
    let gift_cards: [AdminGiftCardRow]?
    let enabled: String?
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

    var body: some View {
        Group {
            if !appState.isAdminLoggedIn {
                AdminNotSignedInView()
            } else if isLoading && cards.isEmpty {
                VStack(spacing: 12) {
                    PSRingSpinner(diameter: 40, lineWidth: 4)
                    Text("Loading gift cards")
                        .font(.psBody)
                        .foregroundStyle(.psMuted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage, cards.isEmpty {
                PSErrorState(message: errorMessage) {
                    Task { await load() }
                }
                .psScreenPadding()
            } else {
                content
            }
        }
        .background(Color.psBackground)
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
            Button("Reject", role: .destructive) {
                if let card = confirmReject {
                    confirmReject = nil
                    Task { await setStatus(card, approve: false) }
                }
            }
            Button("Cancel", role: .cancel) { confirmReject = nil }
        } message: {
            Text("This rejects the gift card.")
        }
    }

    private var content: some View {
        List {
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

    private func giftCardRow(_ card: AdminGiftCardRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(card.code ?? "Card #\(card.id)")
                    .font(.psMono)
                Spacer()
                Text("KES \(card.amount ?? 0)")
                    .font(.psHeadline)
            }
            Text("\(card.recipient_name ?? "-") · \(card.recipient_email ?? "-")")
                .font(.psCaption)
                .foregroundStyle(.psMuted)
            HStack(spacing: 8) {
                PSStatusPill(
                    text: card.status ?? "-",
                    systemImage: "tag.fill",
                    tint: (card.status ?? "").lowercased() == "active" ? .psSuccess : .psAmber
                )
                if let theme = card.theme_style, !theme.isEmpty {
                    Text(theme)
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
        let path = approve ? "api/v1/admin/gift-cards/approve" : "api/v1/admin/gift-cards/reject"
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await APIClient.shared.fetchOK(path, method: "POST", body: ["id": card.id])
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
    @State private var themeStyle = ""
    @State private var isWorking = false
    @State private var message: String?
    @State private var issuedCode: String?

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
                            TextField("Theme (optional)", text: $themeStyle)
                                .autocorrectionDisabled()
                                .psTextField()
                            Button("Issue gift card") { Task { await issue() } }
                                .psPrimary()
                                .disabled(isWorking || (Int(amount) ?? 0) <= 0)
                                .accessibilityLabel("Issue gift card")
                        }
                    }
                    if let issuedCode {
                        PSCard {
                            VStack(alignment: .leading, spacing: 8) {
                                PSSectionHeader(title: "Issued code")
                                Text(issuedCode)
                                    .font(.psMono)
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
            .background(Color.psBackground)
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
        struct IssueResponse: Decodable {
            let ok: Bool
            let gift_card_id: Int?
            let code: String?
            let amount: Int?
        }
        guard let amountValue = Int(amount), amountValue > 0 else {
            message = "Enter an amount."
            return
        }
        var body: [String: Any] = ["amount": amountValue]
        if !recipientName.isEmpty { body["recipient_name"] = recipientName }
        if !recipientEmail.isEmpty { body["recipient_email"] = recipientEmail }
        if !messageText.isEmpty { body["message"] = messageText }
        if !themeStyle.isEmpty { body["theme_style"] = themeStyle }
        isWorking = true
        defer { isWorking = false }
        do {
            let result: IssueResponse = try await APIClient.shared.fetchJSON(
                "api/v1/admin/gift-cards/issue", method: "POST", body: body)
            issuedCode = result.code
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
                VStack(spacing: 12) {
                    PSRingSpinner(diameter: 40, lineWidth: 4)
                    Text("Loading transactions")
                        .font(.psBody)
                        .foregroundStyle(.psMuted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage, transactions.isEmpty && ledger.isEmpty {
                PSErrorState(message: errorMessage) {
                    Task { await load() }
                }
                .psScreenPadding()
            } else {
                content
            }
        }
        .background(Color.psBackground)
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
// {"ok": true, "payment_gateway": "mpesa"|"stk"|"intasend",
//  "mpesa_paybill": String, "mpesa_account": String,
//  "mpesa_phone": String, "intasend_enabled": Bool}
// It returns no methods array, so the screen lists the three real
// methods from those facts: manual M-PESA and wallet are always
// available, STK push only when IntaSend is configured.
// POST /api/v1/admin/payment-methods saves the same keys (plus a
// "gateway" alias) and returns {"payment_gateway": ...}. The
// gateway switch posts there with {"gateway": ...}; picking a row
// never posts on its own, so loading the screen cannot flip the
// live gateway. The older code posted on every picker change,
// including the change caused by loading the saved value.

struct AdminPaymentMethodsResponse: Decodable {
    let ok: Bool
    let payment_gateway: String?
    let mpesa_paybill: String?
    let mpesa_account: String?
    let mpesa_phone: String?
    let intasend_enabled: Bool?
}

struct AdminPaymentMethodsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var gateway = "mpesa"
    @State private var pendingGateway = "mpesa"
    @State private var paybill = ""
    @State private var account = ""
    @State private var phone = ""
    @State private var intasendEnabled = false
    @State private var hasLoaded = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var message: String?
    @State private var isWorking = false

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
            ("wallet", "Wallet", "Pay from the customer wallet balance", "wallet.bifold.fill")
        ]
    }

    private var stkAvailable: Bool { intasendEnabled }

    var body: some View {
        Group {
            if !appState.isAdminLoggedIn {
                AdminNotSignedInView()
            } else if isLoading && !hasLoaded && errorMessage == nil {
                VStack(spacing: 12) {
                    PSRingSpinner(diameter: 40, lineWidth: 4)
                    Text("Loading payment methods")
                        .font(.psBody)
                        .foregroundStyle(.psMuted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage, !hasLoaded {
                PSErrorState(message: errorMessage) {
                    Task { await load() }
                }
                .psScreenPadding()
            } else {
                content
            }
        }
        .background(Color.psBackground)
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
                        Text("Active gateway: \(gateway == "mpesa" ? "Manual M-PESA" : gateway == "stk" ? "STK push" : gateway). Tap a gateway below, then switch it on.")
                            .font(.psCaption)
                            .foregroundStyle(.psMuted)
                        ForEach(methods, id: \.id) { method in
                            let isGateway = method.id != "wallet"
                            let isActive = isGateway && gateway == method.id
                            let isPicked = isGateway && pendingGateway == method.id
                            let isDisabled = method.id == "stk" && !stkAvailable
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
                            .disabled(isWorking || pendingGateway == gateway || (pendingGateway == "stk" && !stkAvailable))
                            .accessibilityLabel("Switch gateway to \(pendingGateway)")
                        if pendingGateway != gateway {
                            Text("Switching to \(pendingGateway == "mpesa" ? "Manual M-PESA" : "STK push") will change how customers pay at checkout.")
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
            message = "Gateway is now \(gateway == "mpesa" ? "Manual M-PESA" : "STK push")."
        } catch {
            message = error.localizedDescription
            await load()
        }
    }
}

