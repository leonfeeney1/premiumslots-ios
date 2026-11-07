import SwiftUI

// MARK: - Wallet, Fix #4 (checklist 1.4, 6.2)
// Web GET /wallet (wallet.py:12): balance, last 50 transactions,
// metrics (total deposited / spent / redeemed), denominations
// [200, 500, 1000, 2000, 5000], renewable subscriptions, daily spend
// limit KES 25,000. Deposit is manual M-PESA and admin-approved
// before the balance moves. Statement is JSON plus a PDF download.
// All response structs decode with every field optional except ok,
// so a missing field degrades instead of crashing.

// MARK: - Shared small helpers (used by all three Fix #4 files)

/// KES amount text, for example KES 1,500. Plain formatting only.
func psKES(_ amount: Int?) -> String {
    "KES \(amount ?? 0)"
}

/// First 10 characters of an ISO timestamp, which is the YYYY-MM-DD date.
func psShortDate(_ text: String?) -> String {
    guard let text, !text.isEmpty else { return "Date not shown" }
    return String(text.prefix(10))
}

/// Capitalize the first letter of a string, for status labels.
func psCapitalized(_ text: String) -> String {
    guard let first = text.first else { return text }
    return String(first).uppercased() + String(text.dropFirst())
}

/// Client-side M-PESA code check, mirroring the web validator
/// (utils.py is_valid_mpesa_format): exactly 10 characters, starts
/// with a letter, letters and numbers only, not all the same
/// character, and not one of the blocked test codes. The server
/// enforces the same rules and rejects reused codes.
func psIsValidMpesaCode(_ code: String) -> Bool {
    let upper = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    guard upper.count == 10 else { return false }
    guard upper.first?.isLetter == true else { return false }
    guard upper.allSatisfy({ $0.isLetter || $0.isNumber }) else { return false }
    let blocked = ["AAAAAAAAAA", "XXXXXXXXXX", "TESTCODE12",
                   "TESTPAY123", "MPESAPAY12", "0000000000"]
    if blocked.contains(upper) { return false }
    if Set(upper).count == 1 { return false }
    return true
}

// MARK: - Wallet response models
// Keys verified against backend/api_v1.py wallet(), wallet_deposit(),
// wallet_instant_renew(), wallet_redeem_gift_card(),
// wallet_statement() and wallet_statement_pdf().

struct PSWalletMetrics: Decodable {
    let total_deposited: Int?
    let total_spent: Int?
    let total_redeemed: Int?
}

struct PSWalletTxn: Decodable {
    let id: Int?
    let action_type: String?
    let amount: Int?
    let mpesa_code: String?
    let created_at: String?
}

struct PSRenewableSubscription: Decodable {
    let id: Int?
    let service_requested: String?
    let amount_due: Int?
    let locked_price: Int?
    let status: String?
    let expiry_date: String?
    let delivery_type: String?
}

struct PSWalletData: Decodable {
    let ok: Bool
    let wallet_balance: Int?
    let transactions: [PSWalletTxn]?
    let metrics: PSWalletMetrics?
    let denominations: [Int]?
    let renewable_subscriptions: [PSRenewableSubscription]?
    let daily_spend_limit: Int?
}

struct PSWalletActionResult: Decodable {
    let ok: Bool
    let error: String?
    let status: String?
    let amount: Int?
    let wallet_balance: Int?
    let reference: String?
    let expiry_date: String?
}

struct PSWalletStatementData: Decodable {
    let ok: Bool
    let wallet_balance: Int?
    let transactions: [PSWalletTxn]?
    let totals: [String: Int]?
    let pdf_url: String?
}

// MARK: - Wallet root

struct WalletRootView: View {
    @State private var data: PSWalletData?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showDeposit = false
    @State private var preselectedAmount: Int?
    @State private var redeemCode = ""
    @State private var redeemMessage: String?
    @State private var redeemBusy = false
    @State private var renewTarget: PSRenewableSubscription?
    @State private var showRenewConfirm = false
    @State private var renewBusyId: Int?
    @State private var renewMessage: String?

    private var denominations: [Int] {
        data?.denominations ?? [200, 500, 1000, 2000, 5000]
    }

    private var transactions: [PSWalletTxn] {
        data?.transactions ?? []
    }

    private var renewable: [PSRenewableSubscription] {
        data?.renewable_subscriptions ?? []
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading, data == nil {
                    VStack(spacing: 16) {
                        PSRingSpinner()
                        Text("Loading wallet")
                            .font(.psBody)
                            .foregroundStyle(.psMuted)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage, data == nil {
                    PSErrorState(message: errorMessage) {
                        Task { await load() }
                    }
                } else {
                    walletList
                }
            }
            .background(Color.psBackground)
            .navigationTitle("Wallet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        WalletStatementView()
                    } label: {
                        Image(systemName: "doc.text")
                            .font(.psIcon)
                    }
                    .accessibilityLabel("Wallet statement")
                }
            }
            .sheet(isPresented: $showDeposit) {
                WalletDepositSheet(
                    preselectedAmount: preselectedAmount,
                    denominations: denominations
                ) {
                    Task { await load() }
                }
                .psSheetDetents()
            }
            .alert("Renew from wallet?", isPresented: $showRenewConfirm) {
                Button("Cancel", role: .cancel) { renewTarget = nil }
                Button("Renew") {
                    if let target = renewTarget {
                        Task { await instantRenew(target) }
                    }
                }
            } message: {
                if let target = renewTarget {
                    Text("Renew \(target.service_requested ?? "this slot") for \(psKES(target.locked_price ?? target.amount_due)) from your wallet balance.")
                }
            }
            .task { await load() }
        }
    }

    private var walletList: some View {
        List {
            Section {
                PSCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Wallet balance", systemImage: "wallet.pass.fill")
                            .font(.psCaption)
                            .foregroundStyle(.psMuted)
                        Text(psKES(data?.wallet_balance))
                            .font(.psTitle)
                        if let limit = data?.daily_spend_limit {
                            Text("Daily spend limit \(psKES(limit))")
                                .font(.psCaption)
                                .foregroundStyle(.psMuted)
                        }
                        Button("Add funds") {
                            preselectedAmount = nil
                            showDeposit = true
                        }
                        .psPrimary()
                        .padding(.top, 4)
                        .accessibilityLabel("Add funds to wallet")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            if let metrics = data?.metrics {
                Section("Totals") {
                    walletMetricRow(label: "Deposited", amount: metrics.total_deposited)
                    walletMetricRow(label: "Spent", amount: metrics.total_spent)
                    walletMetricRow(label: "Gift card credit", amount: metrics.total_redeemed)
                }
            }

            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(denominations, id: \.self) { amount in
                            Button(psKES(amount)) {
                                preselectedAmount = amount
                                showDeposit = true
                            }
                            .buttonStyle(.bordered)
                            .tint(.psCyan)
                            .accessibilityLabel("Deposit \(psKES(amount))")
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                Text("Pay with M-PESA first, then enter the amount and the 10-character code. An admin approves the deposit before the balance moves.")
                    .font(.psCaption)
                    .foregroundStyle(.psMuted)
            } header: {
                Text("Denominations")
            }

            if !renewable.isEmpty {
                Section("Renew from wallet") {
                    ForEach(renewable, id: \.id) { sub in
                        walletRenewRow(sub)
                    }
                    if let message = renewMessage {
                        Text(message)
                            .font(.psCaption)
                            .foregroundStyle(.psMuted)
                    }
                }
            }

            Section("Redeem a gift card") {
                HStack(spacing: 8) {
                    TextField("Gift card code", text: $redeemCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .psTextField()
                    Button("Redeem") {
                        Task { await redeemGiftCard() }
                    }
                    .buttonStyle(.bordered)
                    .tint(.psCyan)
                    .disabled(redeemCode.trimmingCharacters(in: .whitespaces).isEmpty || redeemBusy)
                    .accessibilityLabel("Redeem gift card into wallet")
                }
                if redeemBusy {
                    PSRingSpinner(diameter: 24, lineWidth: 2)
                }
                if let message = redeemMessage {
                    Text(message)
                        .font(.psCaption)
                        .foregroundStyle(.psMuted)
                }
            }

            Section("Transactions") {
                if transactions.isEmpty {
                    PSEmptyState(
                        systemImage: "list.bullet",
                        title: "No transactions yet",
                        body: "Deposits, renewals and gift card credits will show here."
                    )
                } else {
                    ForEach(transactions, id: \.id) { txn in
                        PSWalletTxnRow(txn: txn)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.psBackground)
        .refreshable { await load() }
    }

    private func walletMetricRow(label: String, amount: Int?) -> some View {
        HStack {
            Text(label)
                .font(.psBody)
            Spacer()
            Text(psKES(amount))
                .font(.psMono)
                .foregroundStyle(.psMuted)
        }
    }

    private func walletRenewRow(_ sub: PSRenewableSubscription) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(sub.service_requested ?? "Slot")
                    .font(.psBody)
                Text("Expires \(psShortDate(sub.expiry_date))")
                    .font(.psCaption)
                    .foregroundStyle(.psMuted)
            }
            Spacer()
            Text(psKES(sub.locked_price ?? sub.amount_due))
                .font(.psMono)
            if renewBusyId == sub.id {
                PSRingSpinner(diameter: 20, lineWidth: 2)
            } else {
                Button("Renew") {
                    renewTarget = sub
                    showRenewConfirm = true
                }
                .buttonStyle(.bordered)
                .tint(.psCyan)
                .accessibilityLabel("Renew \(sub.service_requested ?? "slot") from wallet")
            }
        }
    }

    private func load() async {
        if data == nil { isLoading = true }
        defer { isLoading = false }
        do {
            let fresh: PSWalletData = try await APIClient.shared.fetchJSON("api/v1/wallet")
            data = fresh
            errorMessage = nil
        } catch {
            if data == nil { errorMessage = error.localizedDescription }
        }
    }

    private func redeemGiftCard() async {
        let code = redeemCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !code.isEmpty else { return }
        redeemBusy = true
        defer { redeemBusy = false }
        do {
            let result: PSWalletActionResult = try await APIClient.shared.fetchJSON(
                "api/v1/wallet/redeem-gift-card", method: "POST", body: ["code": code])
            redeemMessage = "Gift card credited: \(psKES(result.amount)). New balance \(psKES(result.wallet_balance))."
            redeemCode = ""
            await load()
        } catch {
            redeemMessage = error.localizedDescription
        }
    }

    private func instantRenew(_ sub: PSRenewableSubscription) async {
        guard let id = sub.id else { return }
        renewBusyId = id
        defer { renewBusyId = nil }
        do {
            let result: PSWalletActionResult = try await APIClient.shared.fetchJSON(
                "api/v1/wallet/instant-renew/\(id)", method: "POST")
            renewMessage = "Renewed for \(psKES(result.amount)). New expiry \(psShortDate(result.expiry_date)). Balance \(psKES(result.wallet_balance))."
            renewTarget = nil
            await load()
        } catch {
            renewMessage = error.localizedDescription
            renewTarget = nil
        }
    }
}

// MARK: - Transaction row

struct PSWalletTxnRow: View {
    let txn: PSWalletTxn

    private var actionLabel: String {
        switch (txn.action_type ?? "").lowercased() {
        case "deposit", "deposited": return "Deposit"
        case "spend", "spent", "payment", "purchase", "renewal", "debit": return "Payment"
        case "redeem", "redeemed", "gift_card", "gift-card": return "Gift card credit"
        default:
            let raw = txn.action_type ?? "Transaction"
            return psCapitalized(raw)
        }
    }

    private var isCredit: Bool {
        let action = (txn.action_type ?? "").lowercased()
        return action == "deposit" || action == "deposited"
            || action == "redeem" || action == "redeemed"
            || action == "gift_card" || action == "gift-card"
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isCredit ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                .font(.psIcon)
                .foregroundStyle(isCredit ? .psSuccess : .psMuted)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(actionLabel)
                    .font(.psBody)
                HStack(spacing: 8) {
                    Text(psShortDate(txn.created_at))
                        .font(.psCaption)
                        .foregroundStyle(.psMuted)
                    if let code = txn.mpesa_code, !code.isEmpty {
                        Text(code)
                            .font(.psMono)
                            .foregroundStyle(.psMuted)
                    }
                }
            }
            Spacer()
            Text("\(isCredit ? "+" : "-")\(psKES(txn.amount))")
                .font(.psMono)
                .foregroundStyle(isCredit ? .psSuccess : .psText)
        }
        .psTouchTarget()
    }
}

// MARK: - Deposit sheet

struct WalletDepositSheet: View {
    let preselectedAmount: Int?
    let denominations: [Int]
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var amountText = ""
    @State private var mpesaCode = ""
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Pay with M-PESA first, then enter the exact amount and the code from your confirmation message.")
                        .font(.psBody)
                        .foregroundStyle(.psMuted)

                    PSCard {
                        VStack(alignment: .leading, spacing: 8) {
                            WalletPayInstructionRow(label: "PayBill", value: "400200")
                            WalletPayInstructionRow(label: "Account", value: "1192526")
                            WalletPayInstructionRow(label: "Number", value: "0734460218")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    PSSectionHeader(title: "Amount (KES)")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(denominations, id: \.self) { amount in
                                Button(psKES(amount)) { amountText = "\(amount)" }
                                    .buttonStyle(.bordered)
                                    .tint(.psCyan)
                                    .accessibilityLabel("Deposit amount \(psKES(amount))")
                            }
                        }
                    }
                    TextField("Amount in KES", text: $amountText)
                        .keyboardType(.numberPad)
                        .psTextField()
                        .accessibilityLabel("Deposit amount in KES")

                    PSSectionHeader(title: "M-PESA code")
                    TextField("Example: SDA45TY190", text: $mpesaCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .psTextField()
                        .accessibilityLabel("M-PESA transaction code")

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.psBody)
                            .foregroundStyle(.psDanger)
                    }
                    if let successMessage {
                        Text(successMessage)
                            .font(.psBody)
                            .foregroundStyle(.psSuccess)
                    }

                    Button {
                        Task { await submit() }
                    } label: {
                        if isSubmitting {
                            PSRingSpinner(diameter: 20, lineWidth: 2, color: .psPaper)
                        } else {
                            Text("Submit deposit")
                        }
                    }
                    .psPrimary()
                    .disabled(isSubmitting)
                    .accessibilityLabel("Submit wallet deposit")

                    Text("An admin approves the deposit before the balance moves. The code must be exactly 10 letters and numbers, and a code can only be used once.")
                        .font(.psCaption)
                        .foregroundStyle(.psMuted)
                }
                .psScreenPadding()
            }
            .background(Color.psBackground)
            .navigationTitle("Add funds")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .accessibilityLabel("Close deposit sheet")
                }
            }
            .onAppear {
                if let preselectedAmount { amountText = "\(preselectedAmount)" }
            }
        }
    }

    private func submit() async {
        errorMessage = nil
        successMessage = nil
        guard let amount = Int(amountText.trimmingCharacters(in: .whitespaces)), amount > 0 else {
            errorMessage = "Enter the amount you sent."
            return
        }
        let code = mpesaCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard psIsValidMpesaCode(code) else {
            errorMessage = "The M-PESA code must be exactly 10 letters and numbers."
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let _: APIResponse = try await APIClient.shared.fetchOK(
                "api/v1/wallet/deposit", method: "POST",
                body: ["amount": amount, "mpesa_code": code])
            successMessage = "Deposit of \(psKES(amount)) submitted. It will show in your balance once an admin approves it."
            onDone()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct WalletPayInstructionRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.psBody)
                .foregroundStyle(.psMuted)
            Spacer()
            Text(value)
                .font(.psMono)
            Button {
                UIPasteboard.general.string = value
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.psIcon)
            }
            .accessibilityLabel("Copy \(label) \(value)")
        }
        .font(.psBody)
    }
}

// MARK: - Statement (JSON list + PDF share)

struct WalletStatementView: View {
    @State private var data: PSWalletStatementData?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var pdfURL: URL?
    @State private var showShare = false
    @State private var pdfBusy = false
    @State private var pdfMessage: String?

    var body: some View {
        Group {
            if isLoading, data == nil {
                VStack(spacing: 16) {
                    PSRingSpinner()
                    Text("Loading statement")
                        .font(.psBody)
                        .foregroundStyle(.psMuted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage, data == nil {
                PSErrorState(message: errorMessage) {
                    Task { await load() }
                }
            } else {
                statementList
            }
        }
        .background(Color.psBackground)
        .navigationTitle("Statement")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await downloadPDF() }
                } label: {
                    if pdfBusy {
                        PSRingSpinner(diameter: 20, lineWidth: 2)
                    } else {
                        Image(systemName: "square.and.arrow.up")
                            .font(.psIcon)
                    }
                }
                .disabled(pdfBusy)
                .accessibilityLabel("Share wallet statement PDF")
            }
        }
        .sheet(isPresented: $showShare) {
            if let pdfURL {
                PSWalletShareSheet(items: [pdfURL])
                    .psSheetDetents()
            }
        }
        .task { await load() }
    }

    private var statementList: some View {
        List {
            Section {
                HStack {
                    Text("Balance")
                        .font(.psBody)
                    Spacer()
                    Text(psKES(data?.wallet_balance))
                        .font(.psMono)
                }
                if let totals = data?.totals, !totals.isEmpty {
                    ForEach(totals.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        HStack {
                            Text(psCapitalized(key))
                                .font(.psBody)
                            Spacer()
                            Text(psKES(value))
                                .font(.psMono)
                                .foregroundStyle(.psMuted)
                        }
                    }
                }
                if let message = pdfMessage {
                    Text(message)
                        .font(.psCaption)
                        .foregroundStyle(.psMuted)
                }
            } header: {
                Text("Summary")
            }

            Section("Transactions") {
                let txns = data?.transactions ?? []
                if txns.isEmpty {
                    PSEmptyState(
                        systemImage: "list.bullet",
                        title: "No transactions yet",
                        body: "Your statement will list deposits, payments and gift card credits here."
                    )
                } else {
                    ForEach(txns, id: \.id) { txn in
                        PSWalletTxnRow(txn: txn)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.psBackground)
        .refreshable { await load() }
    }

    private func load() async {
        if data == nil { isLoading = true }
        defer { isLoading = false }
        do {
            let fresh: PSWalletStatementData = try await APIClient.shared.fetchJSON("api/v1/wallet/statement")
            data = fresh
            errorMessage = nil
        } catch {
            if data == nil { errorMessage = error.localizedDescription }
        }
    }

    private func downloadPDF() async {
        pdfBusy = true
        defer { pdfBusy = false }
        do {
            let bytes = try await APIClient.shared.fetchData("api/v1/wallet/statement/pdf")
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("wallet-statement.pdf")
            try bytes.write(to: url, options: .atomic)
            pdfURL = url
            pdfMessage = nil
            showShare = true
        } catch {
            pdfMessage = error.localizedDescription
        }
    }
}

struct PSWalletShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
