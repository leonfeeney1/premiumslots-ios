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
    let amount: Int?
    let mpesa_code: String?
    let status: String?
    let created_at: String?

    var isPending: Bool { (status ?? "pending").lowercased() == "pending" }
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
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var message: String?
    @State private var showAdjust = false
    @State private var adjustUserId = ""
    @State private var adjustAmount = ""
    @State private var isWorking = false
    @State private var confirmDeposit: AdminDepositRow?
    @State private var confirmReject: AdminDepositRow?

    private var pending: [AdminDepositRow] { deposits.filter { $0.isPending } }

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
        .alert("Adjust wallet", isPresented: $showAdjust) {
            TextField("Customer user id", text: $adjustUserId)
                .keyboardType(.numberPad)
            TextField("Amount in KES (negative to deduct)", text: $adjustAmount)
                .keyboardType(.numbersAndPunctuation)
            Button("Apply") { Task { await adjust() } }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Credit or deduct a customer wallet balance directly.")
        }
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
            Section {
                Button("Adjust a wallet balance") { showAdjust = true }
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
            Text("Deposit #\(deposit.id) · user \(deposit.user_id.map(String.init) ?? "-") · code \(deposit.mpesa_code ?? "-")")
                .font(.psCaption)
                .foregroundStyle(.psMuted)
            Text(adminShortDate(deposit.created_at))
                .font(.psCaption)
                .foregroundStyle(.psMuted)
            if deposit.isPending {
                HStack(spacing: 10) {
                    Button("Approve") { confirmDeposit = deposit }
                        .buttonStyle(.borderedProminent)
                        .tint(.psPrimary)
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

    private func adjust() async {
        // POST /api/v1/admin/wallet/adjust, body
        // {"user_id": Int, "amount": Int}, returns {"wallet_balance": Int}.
        guard let userId = Int(adjustUserId),
              let amount = Int(adjustAmount), amount != 0 else {
            message = "Enter a user id and a non-zero amount."
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let result: AdminWalletAdjustResponse = try await APIClient.shared.fetchJSON(
                "api/v1/admin/wallet/adjust",
                method: "POST", body: ["user_id": userId, "amount": amount])
            message = "Wallet balance is now KES \(result.wallet_balance ?? 0)."
            adjustUserId = ""
            adjustAmount = ""
        } catch {
            message = error.localizedDescription
        }
    }
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
// POST /api/v1/admin/payment-methods saves the same keys (plus a
// "gateway" alias). POST /api/v1/admin/settings/gateway with
// {"gateway": "mpesa"|"stk"|"intasend"} switches the gateway and
// returns {"payment_gateway": ...}.

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
    @State private var paybill = ""
    @State private var account = ""
    @State private var phone = ""
    @State private var intasendEnabled = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var message: String?
    @State private var isWorking = false

    var body: some View {
        Group {
            if !appState.isAdminLoggedIn {
                AdminNotSignedInView()
            } else if isLoading && errorMessage == nil && paybill.isEmpty && account.isEmpty {
                VStack(spacing: 12) {
                    PSRingSpinner(diameter: 40, lineWidth: 4)
                    Text("Loading payment methods")
                        .font(.psBody)
                        .foregroundStyle(.psMuted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
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
                        PSSectionHeader(title: "Gateway")
                        Picker("Gateway", selection: $gateway) {
                            Text("Manual M-PESA").tag("mpesa")
                            Text("STK push").tag("stk")
                            Text("IntaSend").tag("intasend")
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: gateway) { Task { await switchGateway() } }
                        Text("Manual M-PESA is the default. STK push and IntaSend use the IntaSend integration when it is configured.")
                            .font(.psCaption)
                            .foregroundStyle(.psMuted)
                        AdminKVRow(label: "IntaSend configured", value: intasendEnabled ? "Yes" : "No")
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
            paybill = result.mpesa_paybill ?? ""
            account = result.mpesa_account ?? ""
            phone = result.mpesa_phone ?? ""
            intasendEnabled = result.intasend_enabled ?? false
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
            message = "Payment methods saved."
        } catch {
            message = error.localizedDescription
        }
    }

    private func switchGateway() async {
        // POST /api/v1/admin/settings/gateway, body {"gateway": ...}.
        struct GatewayResponse: Decodable { let ok: Bool; let payment_gateway: String? }
        isWorking = true
        defer { isWorking = false }
        do {
            let result: GatewayResponse = try await APIClient.shared.fetchJSON(
                "api/v1/admin/settings/gateway",
                method: "POST", body: ["gateway": gateway])
            gateway = result.payment_gateway ?? gateway
            message = "Gateway is now \(gateway)."
        } catch {
            message = error.localizedDescription
            await load()
        }
    }
}
