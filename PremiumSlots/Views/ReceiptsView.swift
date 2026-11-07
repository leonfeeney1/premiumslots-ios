import SwiftUI

// MARK: - Receipts, v5
// Replaces the order-number text field in HelpBlogView ReceiptsView
// (which lives in a file this agent does not own, so that old view
// is left untouched; wire this view in from SettingsView instead).
// The customer picks one of their own receipts from a list, then
// downloads the PDF and shares it, or pastes a receipt code to
// verify it against the server HMAC check.
//
// Endpoints:
//   GET  /api/v1/me/receipts          list of the customer's own
//        receipts (backend agent is adding it). If it is not there
//        yet, the screen falls back to GET /api/v1/me/dashboard,
//        which already returns the customer's FinancialLedger rows
//        (last 50) as `ledger`; a receipt IS one of those rows, so
//        the picker lists them with a note saying where they came
//        from. Only if both calls fail does the screen fall back to
//        a hand-entered order number.
//        Expected shape: {"ok": true, "receipts": [{"id": 12,
//        "order_number": "12", "service": "Spotify Premium Family",
//        "amount": 180, "created_at": "2026-11-01T10:00:00",
//        "status": "Approved"}]}. Keys are decoded tolerantly:
//        service, platform, service_name or service_requested (the
//        FinancialLedger column, which is what a receipt row is on
//        the web: id, service_requested, action_type, amount,
//        created_at; the receipt number is that row id, shown on
//        the web as a 6-digit zero-padded number), created_at or
//        date, amount or amount_kes, order_number or the id as
//        text, status or action_type.
//   GET  /api/v1/receipts/<id>        receipt PDF (exists in the
//        workspace backend). The file is shared with the iOS share
//        sheet (AdminShareSheet wraps UIActivityViewController).
//   GET  /api/v1/receipts/verify?payload=&signature=
//        HMAC verify (exists in the workspace backend). On success
//        it returns {"verified": true, "method": "hmac",
//        "data": {"id", "service", "amount", "action", "customer",
//        "email", "ts"}, "note": "..."}. On failure verified is
//        false and note explains why (for example "Signature
//        mismatch" or "Malformed payload").
// No fake data: if the list endpoint is missing, the screen says
// so and falls back to entering an order number by hand.

struct ReceiptListItem: Decodable, Identifiable {
    let id: Int
    let orderNumber: String
    let service: String
    let amount: Int?
    let createdAt: String?
    let status: String?

    init(id: Int, orderNumber: String, service: String, amount: Int?, createdAt: String?, status: String?) {
        self.id = id
        self.orderNumber = orderNumber
        self.service = service
        self.amount = amount
        self.createdAt = createdAt
        self.status = status
    }

    enum CodingKeys: String, CodingKey {
        case id, order_number, order, receipt_number, service, platform
        case service_name, service_requested, amount, amount_kes, created_at, date, created, status, action_type
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // The id may arrive as a number or as digits in a string.
        if let value = try? container.decode(Int.self, forKey: .id) {
            id = value
        } else if let text = try? container.decode(String.self, forKey: .id),
                  let value = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
            id = value
        } else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: container, debugDescription: "Receipt id is missing.")
        }
        if let text = try? container.decode(String.self, forKey: .order_number), !text.isEmpty {
            orderNumber = text
        } else if let text = try? container.decode(String.self, forKey: .order),
                  !text.isEmpty {
            orderNumber = text
        } else if let text = try? container.decode(String.self, forKey: .receipt_number),
                  !text.isEmpty {
            orderNumber = text
        } else {
            orderNumber = String(id)
        }
        if let text = try? container.decode(String.self, forKey: .service), !text.isEmpty {
            service = text
        } else if let text = try? container.decode(String.self, forKey: .platform),
                  !text.isEmpty {
            service = text
        } else if let text = try? container.decode(String.self, forKey: .service_name),
                  !text.isEmpty {
            service = text
        } else if let text = try? container.decode(String.self, forKey: .service_requested),
                  !text.isEmpty {
            service = text
        } else {
            service = "Subscription"
        }
        // Amount may arrive as 180, 180.0 or "180": a strict Int
        // decode drops the price entirely when the server sends a
        // decimal, so read all three forms for both keys.
        let flexibleAmount: (CodingKeys) -> Int? = { key in
            (try? container.decodeIfPresent(AdminFlexInt.self, forKey: key))??.value
        }
        amount = flexibleAmount(.amount) ?? flexibleAmount(.amount_kes)
        if let text = try? container.decode(String.self, forKey: .created_at), !text.isEmpty {
            createdAt = text
        } else if let text = try? container.decode(String.self, forKey: .date),
                  !text.isEmpty {
            createdAt = text
        } else if let text = try? container.decode(String.self, forKey: .created),
                  !text.isEmpty {
            createdAt = text
        } else {
            createdAt = nil
        }
        if let text = try? container.decode(String.self, forKey: .status), !text.isEmpty {
            status = text
        } else if let text = try? container.decode(String.self, forKey: .action_type),
                  !text.isEmpty {
            status = text
        } else {
            status = nil
        }
    }

    var dateText: String {
        guard let createdAt, !createdAt.isEmpty else { return "" }
        return String(createdAt.prefix(10))
    }

    var rowText: String {
        var parts = ["Order \(orderNumber)", service]
        if let amount { parts.append("KES \(amount)") }
        if !dateText.isEmpty { parts.append(dateText) }
        return parts.joined(separator: "  ")
    }
}

struct ReceiptsListResponse: Decodable {
    let ok: Bool?
    let receipts: [ReceiptListItem]?
}

/// Minimal decode of GET /api/v1/me/dashboard, used only as the
/// receipts fallback: the dashboard returns the customer's
/// FinancialLedger rows (last 50) as `ledger`, and a receipt is one
/// of those rows. Only the ledger key is read here.
private struct ReceiptsDashboardResponse: Decodable {
    let ok: Bool?
    let ledger: [ReceiptsLedgerRow]?
}

private struct ReceiptsLedgerRow: Decodable {
    let id: Int?
    let service_requested: String?
    let description: String?
    let action_type: String?
    let amount: Int?
    let created_at: String?

    enum CodingKeys: String, CodingKey {
        case id, service_requested, description, action_type, amount, created_at
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(Int.self, forKey: .id)
        service_requested = try container.decodeIfPresent(String.self, forKey: .service_requested)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        action_type = try container.decodeIfPresent(String.self, forKey: .action_type)
        // Ledger amounts arrive as 180 or 180.0: a strict Int
        // decode would fail the whole dashboard fallback list.
        amount = (try? container.decodeIfPresent(AdminFlexInt.self, forKey: .amount))??.value
        created_at = try container.decodeIfPresent(String.self, forKey: .created_at)
    }
}

struct ReceiptVerifyDetail: Decodable {
    let id: Int?
    let service: String?
    let amount: Int?
    let action: String?
    let customer: String?
    let email: String?
    let ts: String?

    enum CodingKeys: String, CodingKey {
        case id, service, amount, action, customer, email, ts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(Int.self, forKey: .id)
        service = try container.decodeIfPresent(String.self, forKey: .service)
        // Verify data amounts arrive as 180 or 180.0: a strict Int
        // decode would fail the whole verify response.
        amount = (try? container.decodeIfPresent(AdminFlexInt.self, forKey: .amount))??.value
        action = try container.decodeIfPresent(String.self, forKey: .action)
        customer = try container.decodeIfPresent(String.self, forKey: .customer)
        email = try container.decodeIfPresent(String.self, forKey: .email)
        ts = try container.decodeIfPresent(String.self, forKey: .ts)
    }
}

struct ReceiptVerifyDetailResponse: Decodable {
    let ok: Bool
    let verified: Bool?
    let payload: String?
    let method: String?
    let note: String?
    let data: ReceiptVerifyDetail?
}

struct ReceiptsPickerView: View {
    @FocusState private var focusedField: Field?
    private enum Field { case combined, payload, signature, orderNumber }

    @State private var receipts: [ReceiptListItem] = []
    @State private var selectedReceiptID: Int?
    @State private var listState: ListState = .loading
    private enum ListState { case loading, ready, unavailable }
    @State private var listSource: ListSource = .receipts
    private enum ListSource { case receipts, dashboard }
    @State private var manualOrderNumber = ""
    @State private var pdfURL: URL?
    @State private var downloadMessage: String?
    @State private var isDownloading = false
    @State private var combinedCode = ""
    @State private var verifyPayload = ""
    @State private var verifySignature = ""
    @State private var verifyResult: ReceiptVerifyDetailResponse?
    @State private var verifyMessage: String?
    @State private var isVerifying = false

    private var selectedReceipt: ReceiptListItem? {
        receipts.first { $0.id == selectedReceiptID }
    }

    /// The receipt id to download: the picked receipt, or the
    /// hand-entered order number when the list is unavailable.
    private var downloadID: Int? {
        if let selectedReceipt { return selectedReceipt.id }
        return Int(manualOrderNumber.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var body: some View {
        List {
            Section {
                switch listState {
                case .loading:
                    HStack {
                        Spacer()
                        PSRingSpinner(diameter: 28, lineWidth: 3)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                case .ready:
                    if receipts.isEmpty {
                        PSEmptyState(
                            systemImage: "doc.text.fill",
                            title: "No receipts yet",
                            body: "Receipts appear here after your first approved order."
                        )
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    } else {
                        Picker("Receipt", selection: $selectedReceiptID) {
                            ForEach(receipts) { receipt in
                                Text(receipt.rowText)
                                    .font(.psBody)
                                    .tag(receipt.id as Int?)
                            }
                        }
                        .pickerStyle(.menu)
                        .accessibilityLabel("Choose a receipt")
                        if let selectedReceipt {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(selectedReceipt.service)
                                    .font(.psHeadline)
                                HStack {
                                    Text("Order \(selectedReceipt.orderNumber)")
                                    if let amount = selectedReceipt.amount {
                                        Text("KES \(amount)")
                                            .font(.psMono)
                                    }
                                }
                                .font(.psBody)
                                .foregroundStyle(.psMuted)
                                if !selectedReceipt.dateText.isEmpty {
                                    Text(selectedReceipt.dateText)
                                        .font(.psCaption)
                                        .foregroundStyle(.psMuted)
                                }
                                if let status = selectedReceipt.status, !status.isEmpty {
                                    PSStatusPill(text: status, systemImage: "doc.text.fill", tint: .psCyan)
                                }
                            }
                        }
                    }
                case .unavailable:
                    Text("Your receipts list is not available on the server yet. Enter an order number below to download its receipt.")
                        .font(.psBody)
                        .foregroundStyle(.psMuted)
                    TextField("Order number, for example 12", text: $manualOrderNumber)
                        .psTextField()
                        .keyboardType(.numberPad)
                        .focused($focusedField, equals: .orderNumber)
                        .accessibilityLabel("Receipt order number")
                }
                Button {
                    Task { await downloadReceipt() }
                } label: {
                    if isDownloading {
                        PSRingSpinner(diameter: 20, lineWidth: 2, color: .white, duration: 0.7)
                    } else {
                        Label("Download receipt PDF", systemImage: "arrow.down.doc.fill")
                    }
                }
                .psPrimary()
                .disabled(isDownloading || downloadID == nil)
                if let pdfURL {
                    ShareLink(item: pdfURL) {
                        Label("Share receipt PDF", systemImage: "square.and.arrow.up")
                            .font(.psBody)
                    }
                    .accessibilityLabel("Share receipt PDF")
                }
                if let downloadMessage {
                    Text(downloadMessage)
                        .font(.psCaption)
                        .foregroundStyle(.psMuted)
                }
            } header: {
                Text("Download a receipt")
            } footer: {
                if listState == .ready && listSource == .dashboard {
                    Text("Receipts shown from your recent account activity (last 50 entries). The receipt number is the entry number.")
                }
            }

            Section {
                Text("Paste the full receipt code or verify link from the receipt, or paste the payload and signature separately. Extra spaces and the PS- prefix are ignored.")
                    .font(.psBody)
                    .foregroundStyle(.psMuted)
                TextField("Paste receipt code", text: $combinedCode)
                    .psTextField()
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .combined)
                    .accessibilityLabel("Pasted receipt code")
                TextField("Payload", text: $verifyPayload)
                    .psTextField()
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .payload)
                    .accessibilityLabel("Receipt payload")
                TextField("Signature", text: $verifySignature)
                    .psTextField()
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .signature)
                    .accessibilityLabel("Receipt signature")
                Button {
                    Task { await verifyReceipt() }
                } label: {
                    if isVerifying {
                        PSRingSpinner(diameter: 20, lineWidth: 2, color: .white, duration: 0.7)
                    } else {
                        Label("Verify receipt", systemImage: "checkmark.seal.fill")
                    }
                }
                .psPrimary()
                .disabled(isVerifying)
                if let verifyResult {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: verifyResult.verified == true ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(verifyResult.verified == true ? .psSuccess : .psDanger)
                                .accessibilityHidden(true)
                            Text(verifyResult.verified == true ? "Receipt verified." : "Receipt could not be verified.")
                                .font(.psHeadline)
                        }
                        if let data = verifyResult.data, verifyResult.verified == true {
                            if let service = data.service, !service.isEmpty {
                                Text(service)
                                    .font(.psBody)
                            }
                            HStack {
                                if let id = data.id {
                                    Text("Order \(id)")
                                }
                                if let amount = data.amount {
                                    Text("KES \(amount)")
                                        .font(.psMono)
                                }
                            }
                            .font(.psBody)
                            .foregroundStyle(.psMuted)
                            if let customer = data.customer, !customer.isEmpty {
                                Text(customer)
                                    .font(.psCaption)
                                    .foregroundStyle(.psMuted)
                            }
                            if let ts = data.ts, !ts.isEmpty {
                                Text(String(ts.prefix(10)))
                                    .font(.psCaption)
                                    .foregroundStyle(.psMuted)
                            }
                        }
                        if let method = verifyResult.method {
                            Text("Check: \(method)")
                                .font(.psCaption)
                                .foregroundStyle(.psMuted)
                        }
                        if let note = verifyResult.note, !note.isEmpty {
                            Text(note)
                                .font(.psCaption)
                                .foregroundStyle(.psMuted)
                        }
                        if verifyResult.verified != true {
                            Text("Check the code and try again. A receipt from a different order, or one with a changed letter, will not verify.")
                                .font(.psCaption)
                                .foregroundStyle(.psMuted)
                        }
                    }
                }
                if let verifyMessage {
                    Text(verifyMessage)
                        .font(.psCaption)
                        .foregroundStyle(.psMuted)
                }
            } header: {
                Text("Verify a receipt")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .background(Color.psBackground)
        .navigationTitle("Receipts")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItem(placement: .keyboard) {
                Button("Done") { focusedField = nil }
            }
        }
        .refreshable { await load() }
        .task { await load() }
        .safeAreaPadding(.bottom, 8)
    }

    private func load() async {
        listState = .loading
        // First choice: the dedicated receipts list, if the backend
        // agent has added GET /api/v1/me/receipts.
        do {
            let response: ReceiptsListResponse = try await APIClient.shared.fetchJSON("api/v1/me/receipts")
            receipts = response.receipts ?? []
            selectedReceiptID = receipts.first?.id
            listSource = .receipts
            listState = .ready
            return
        } catch {
            // No dedicated receipt-list endpoint exists on the web:
            // a customer's receipts are their FinancialLedger rows,
            // and the dashboard already returns the last 50, so use
            // those rows as the list instead of showing nothing.
            do {
                let dashboard: ReceiptsDashboardResponse = try await APIClient.shared.fetchJSON("api/v1/me/dashboard")
                receipts = (dashboard.ledger ?? []).compactMap { row in
                    guard let id = row.id else { return nil as ReceiptListItem? }
                    return ReceiptListItem(
                        id: id,
                        orderNumber: String(id),
                        service: row.service_requested ?? row.description ?? row.action_type ?? "Subscription",
                        amount: row.amount,
                        createdAt: row.created_at,
                        status: row.action_type)
                }
                selectedReceiptID = receipts.first?.id
                listSource = .dashboard
                listState = .ready
            } catch {
                receipts = []
                selectedReceiptID = nil
                listState = .unavailable
                downloadMessage = error.localizedDescription
            }
        }
    }

    private func downloadReceipt() async {
        guard let id = downloadID else {
            downloadMessage = "Choose a receipt first."
            return
        }
        focusedField = nil
        isDownloading = true
        downloadMessage = nil
        pdfURL = nil
        defer { isDownloading = false }
        do {
            let data = try await APIClient.shared.fetchData("api/v1/receipts/\(id)")
            guard !data.isEmpty else {
                downloadMessage = "The receipt file came back empty. Please try again."
                return
            }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("receipt-\(id).pdf")
            try data.write(to: url, options: .atomic)
            pdfURL = url
            downloadMessage = "Receipt PDF is ready to share."
        } catch {
            downloadMessage = error.localizedDescription
        }
    }

    private func verifyReceipt() async {
        let parsed = ReceiptsPickerView.parsePastedCode(
            combined: combinedCode, payload: verifyPayload, signature: verifySignature)
        guard !parsed.payload.isEmpty else {
            verifyMessage = "Paste the receipt code first."
            return
        }
        guard !parsed.signature.isEmpty else {
            verifyMessage = "The signature is missing. Paste the full receipt code, or the payload and signature separately."
            return
        }
        focusedField = nil
        isVerifying = true
        verifyMessage = nil
        verifyResult = nil
        defer { isVerifying = false }
        do {
            var components = URLComponents()
            components.queryItems = [
                URLQueryItem(name: "payload", value: parsed.payload),
                URLQueryItem(name: "signature", value: parsed.signature),
            ]
            let query = components.percentEncodedQuery ?? ""
            let response: ReceiptVerifyDetailResponse = try await APIClient.shared.fetchJSON(
                "api/v1/receipts/verify?\(query)")
            verifyResult = response
        } catch {
            verifyMessage = error.localizedDescription
        }
    }

    /// Tolerant parsing of a pasted receipt code. Trims whitespace,
    /// strips common prefixes ("PS-", "PS:", "Receipt:", "Payload:",
    /// "Signature:"), and splits a combined paste into payload and
    /// signature on whitespace, a dot or a pipe. A pasted full
    /// verify link (https://premiumslots.tech/.../verify?payload=...
    /// &signature=...) is read from its query items first: splitting
    /// it on dots would chop the host and the payload apart. The
    /// payload is base64url, which is case sensitive, so it is kept
    /// exactly as pasted: uppercasing it would corrupt it and break
    /// the HMAC check. The signature is hex, so it is lowercased to
    /// match the lowercase hexdigest the server compares against.
    static func parsePastedCode(combined: String, payload: String, signature: String) -> (payload: String, signature: String) {
        // Pull payload and signature out of a pasted verify link.
        // Returns nil unless both query items are present.
        let fromVerifyLink: (String) -> (String, String)? = { text in
            guard let url = URL(string: text),
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let items = components.queryItems,
                  let linkPayload = items.first(where: { $0.name == "payload" })?.value,
                  !linkPayload.isEmpty,
                  let linkSignature = items.first(where: { $0.name == "signature" })?.value,
                  !linkSignature.isEmpty else { return nil }
            return (linkPayload, linkSignature.lowercased())
        }
        let stripPrefixes: (String) -> String = { value in
            var text = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = text.lowercased()
            for prefix in ["ps-", "ps:", "receipt:", "receipt ", "payload:", "signature:"] {
                if lower.hasPrefix(prefix) {
                    text = String(text.dropFirst(prefix.count))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    break
                }
            }
            return text
        }
        let combinedText = stripPrefixes(combined)
        if !combinedText.isEmpty {
            if let fromLink = fromVerifyLink(combinedText) {
                return fromLink
            }
            let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".|"))
            let tokens = combinedText.components(separatedBy: separators).filter { !$0.isEmpty }
            if tokens.count >= 2 {
                return (stripPrefixes(tokens[0]), stripPrefixes(tokens[1]).lowercased())
            }
            if tokens.count == 1 {
                let single = tokens[0]
                if single.contains(":") {
                    let parts = single.split(separator: ":", maxSplits: 1).map(String.init)
                    if parts.count == 2 {
                        return (stripPrefixes(parts[0]), stripPrefixes(parts[1]).lowercased())
                    }
                }
                return (single, stripPrefixes(signature).lowercased())
            }
        }
        let payloadText = stripPrefixes(payload)
        if let fromLink = fromVerifyLink(payloadText) {
            return fromLink
        }
        return (payloadText, stripPrefixes(signature).lowercased())
    }
}
