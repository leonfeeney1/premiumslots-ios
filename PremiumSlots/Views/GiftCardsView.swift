import SwiftUI

// MARK: - Gift cards, Fix #4 (checklist 1.5, 6.2)
// Web GET /gift-cards (giftcards.py:117): feature toggle
// is_gift_cards_enabled, denominations [200, 500, 1000, 2000, 5000],
// 5 themes, my issued cards (last 20), my redeemed cards (last 20).
// Create is paid by manual M-PESA code. Verify is public and returns
// code, amount, status, expiry, theme, sender and recipient. Redeem
// credits the wallet. All response structs decode with every field
// optional except ok, so a missing field degrades instead of crashing.

// MARK: - Gift card themes (exact hexes from checklist 1.5)

struct PSGiftCardTheme: Identifiable {
    let name: String
    let hexes: [String]

    var id: String { name }

    var colors: [Color] {
        hexes.map { Color(psGiftHex: $0) }
    }

    static let all: [PSGiftCardTheme] = [
        PSGiftCardTheme(name: "Cyber Gold", hexes: ["#d97706", "#fbbf24", "#b45309"]),
        PSGiftCardTheme(name: "Electric Blue", hexes: ["#1d4ed8", "#3b82f6", "#06b6d4"]),
        PSGiftCardTheme(name: "Emerald Luxe", hexes: ["#047857", "#10b981", "#059669"]),
        PSGiftCardTheme(name: "Neon Violet", hexes: ["#6d28d9", "#8b5cf6", "#ec4899"]),
        PSGiftCardTheme(name: "Crimson Ruby", hexes: ["#991b1b", "#ef4444", "#f43f5e"])
    ]

    static func theme(named name: String?) -> PSGiftCardTheme? {
        guard let name else { return nil }
        return all.first { $0.name.lowercased() == name.lowercased() }
    }
}

extension Color {
    /// Colour from a 6-digit hex string such as #d97706.
    init(psGiftHex hex: String) {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        self.init(red: red, green: green, blue: blue)
    }
}

// MARK: - Gift card response models
// Keys verified against backend/api_v1.py list_gift_cards(),
// create_gift_card(), redeem_gift_card() and verify_gift_card().

struct PSGiftCard: Decodable {
    let id: Int?
    let code: String?
    let amount: Int?
    let status: String?
    let sender_name: String?
    let recipient_name: String?
    let recipient_email: String?
    let message: String?
    let theme_style: String?
    let expiry_date: String?
    let expires_at: String?
    let created_at: String?
    let redeemed_at: String?

    var expiryText: String? {
        expiry_date ?? expires_at
    }
}

struct PSGiftCardListData: Decodable {
    let ok: Bool
    let enabled: Bool?
    let denominations: [Int]?
    let themes: [String]?
    let issued: [PSGiftCard]?
    let redeemed: [PSGiftCard]?
}

struct PSGiftCardCreateResult: Decodable {
    let ok: Bool
    let error: String?
    let gift_card_id: Int?
    let code: String?
    let amount: Int?
    let status: String?
}

struct PSGiftCardVerifyItem: Decodable {
    let code: String?
    let amount: Int?
    let status: String?
    let expiry: String?
    let theme: String?
    let sender: String?
    let recipient: String?
}

struct PSGiftCardVerifyData: Decodable {
    let ok: Bool
    let error: String?
    let gift_card: PSGiftCardVerifyItem?
}

// MARK: - Gift cards root

struct GiftCardsRootView: View {
    @State private var data: PSGiftCardListData?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showCreate = false
    @State private var showVerify = false

    private var denominations: [Int] {
        data?.denominations ?? [200, 500, 1000, 2000, 5000]
    }

    private var issued: [PSGiftCard] {
        data?.issued ?? []
    }

    private var redeemed: [PSGiftCard] {
        data?.redeemed ?? []
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading, data == nil {
                    VStack(spacing: 16) {
                        PSRingSpinner()
                        Text("Loading gift cards")
                            .font(.psBody)
                            .foregroundStyle(.psMuted)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage, data == nil {
                    PSErrorState(message: errorMessage) {
                        Task { await load() }
                    }
                } else if data?.enabled == false {
                    PSEmptyState(
                        systemImage: "gift.fill",
                        title: "Gift cards are off",
                        body: "The gift card feature is turned off right now. Check back later.",
                        actionLabel: "Try again"
                    ) {
                        Task { await load() }
                    }
                    .psScreenPadding()
                } else {
                    giftCardList
                }
            }
            .background(Color.psBackground)
            .navigationTitle("Gift cards")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showVerify = true
                    } label: {
                        Image(systemName: "checkmark.shield")
                            .font(.psIcon)
                    }
                    .accessibilityLabel("Verify a gift card code")
                }
            }
            .sheet(isPresented: $showCreate) {
                GiftCardCreateSheet(denominations: denominations) {
                    Task { await load() }
                }
                .psSheetDetents()
            }
            .sheet(isPresented: $showVerify) {
                GiftCardVerifyView()
                    .psSheetDetents()
            }
            .task { await load() }
        }
    }

    private var giftCardList: some View {
        List {
            Section {
                Button("Send a gift card") { showCreate = true }
                    .psPrimary()
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .accessibilityLabel("Send a gift card")
                Button("Verify a code") { showVerify = true }
                    .buttonStyle(.bordered)
                    .tint(.psCyan)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .accessibilityLabel("Verify a gift card code")
            }

            Section("Denominations") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(denominations, id: \.self) { amount in
                            Text(psKES(amount))
                                .font(.psMono)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.psSurface)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(Color.psBorder, lineWidth: 1))
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }

            Section("Themes") {
                ForEach(PSGiftCardTheme.all) { theme in
                    GiftCardThemeRow(theme: theme)
                }
            }

            Section("My issued cards") {
                if issued.isEmpty {
                    PSEmptyState(
                        systemImage: "gift",
                        title: "No gift cards sent yet",
                        body: "Gift cards you send will show here with their code, amount and status."
                    )
                } else {
                    ForEach(issued, id: \.id) { card in
                        GiftCardRow(card: card)
                    }
                }
            }

            Section("My redeemed cards") {
                if redeemed.isEmpty {
                    PSEmptyState(
                        systemImage: "checkmark.circle",
                        title: "No gift cards redeemed yet",
                        body: "Gift cards you redeem into your wallet will show here."
                    )
                } else {
                    ForEach(redeemed, id: \.id) { card in
                        GiftCardRow(card: card)
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
            let fresh: PSGiftCardListData = try await APIClient.shared.fetchJSON("api/v1/gift-cards")
            data = fresh
            errorMessage = nil
        } catch {
            if data == nil { errorMessage = error.localizedDescription }
        }
    }
}

// MARK: - Theme row and card row

struct GiftCardThemeRow: View {
    let theme: PSGiftCardTheme

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: -6) {
                ForEach(theme.hexes, id: \.self) { hex in
                    Circle()
                        .fill(Color(psGiftHex: hex))
                        .frame(width: 24, height: 24)
                        .overlay(Circle().stroke(Color.psBorder, lineWidth: 1))
                }
            }
            .accessibilityHidden(true)
            Text(theme.name)
                .font(.psBody)
            Spacer()
        }
        .psTouchTarget()
    }
}

struct GiftCardRow: View {
    let card: PSGiftCard

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if let theme = PSGiftCardTheme.theme(named: card.theme_style) {
                    LinearGradient(colors: theme.colors, startPoint: .leading, endPoint: .trailing)
                        .frame(width: 36, height: 24)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: "gift.fill")
                        .font(.psIcon)
                        .foregroundStyle(.psMuted)
                        .accessibilityHidden(true)
                }
                Text(psKES(card.amount))
                    .font(.psHeadline)
                Spacer()
                if let status = card.status, !status.isEmpty {
                    PSStatusPill(
                        text: psCapitalized(status),
                        systemImage: status.lowercased() == "active" ? "checkmark.circle.fill" : "circle.fill",
                        tint: status.lowercased() == "active" ? .psSuccess : .psMuted
                    )
                }
            }
            if let code = card.code, !code.isEmpty {
                HStack {
                    Text(code)
                        .font(.psMono)
                    Button {
                        UIPasteboard.general.string = code
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.psIcon)
                    }
                    .accessibilityLabel("Copy gift card code \(code)")
                }
            }
            HStack(spacing: 8) {
                if let name = card.recipient_name ?? card.recipient_email, !name.isEmpty {
                    Text("To \(name)")
                        .font(.psCaption)
                        .foregroundStyle(.psMuted)
                }
                if let themeName = card.theme_style, !themeName.isEmpty {
                    Text(themeName)
                        .font(.psCaption)
                        .foregroundStyle(.psMuted)
                }
                if let expiry = card.expiryText {
                    Text("Expires \(psShortDate(expiry))")
                        .font(.psCaption)
                        .foregroundStyle(.psMuted)
                }
            }
            if let message = card.message, !message.isEmpty {
                Text(message)
                    .font(.psBody)
                    .foregroundStyle(.psDim)
            }
            Text("Sent \(psShortDate(card.created_at))")
                .font(.psCaption)
                .foregroundStyle(.psMuted)
        }
        .psTouchTarget()
    }
}

// MARK: - Create sheet

struct GiftCardCreateSheet: View {
    let denominations: [Int]
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var amountText = ""
    @State private var recipientName = ""
    @State private var recipientEmail = ""
    @State private var message = ""
    @State private var selectedTheme = "Cyber Gold"
    @State private var mpesaCode = ""
    @State private var errorMessage: String?
    @State private var createdCode: String?
    @State private var createdAmount: Int?
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Send a gift card paid with M-PESA. The recipient gets the code by email and redeems it into their wallet.")
                        .font(.psBody)
                        .foregroundStyle(.psMuted)

                    PSSectionHeader(title: "Amount (KES)")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(denominations, id: \.self) { amount in
                                Button(psKES(amount)) { amountText = "\(amount)" }
                                    .buttonStyle(.bordered)
                                    .tint(.psCyan)
                                    .accessibilityLabel("Gift card amount \(psKES(amount))")
                            }
                        }
                    }
                    TextField("Amount in KES", text: $amountText)
                        .keyboardType(.numberPad)
                        .psTextField()
                        .accessibilityLabel("Gift card amount in KES")

                    PSSectionHeader(title: "Recipient")
                    TextField("Recipient name", text: $recipientName)
                        .psTextField()
                        .accessibilityLabel("Recipient name")
                    TextField("Recipient email", text: $recipientEmail)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .psTextField()
                        .accessibilityLabel("Recipient email")

                    PSSectionHeader(title: "Message")
                    TextField("A short message for the recipient", text: $message, axis: .vertical)
                        .psTextField()
                        .accessibilityLabel("Gift card message")

                    PSSectionHeader(title: "Theme")
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(PSGiftCardTheme.all) { theme in
                            Button {
                                selectedTheme = theme.name
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
                                        .stroke(selectedTheme == theme.name ? Color.psPrimary : Color.psBorder, lineWidth: selectedTheme == theme.name ? 2 : 1)
                                )
                            }
                            .accessibilityLabel("Gift card theme \(theme.name)")
                        }
                    }

                    PSSectionHeader(title: "M-PESA code")
                    Text("Pay the gift card amount first, then enter the 10-character code from your confirmation message.")
                        .font(.psCaption)
                        .foregroundStyle(.psMuted)
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

                    if let createdCode {
                        PSCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Gift card created", systemImage: "checkmark.circle.fill")
                                    .font(.psHeadline)
                                    .foregroundStyle(.psSuccess)
                                Text("Amount \(psKES(createdAmount))")
                                    .font(.psBody)
                                HStack {
                                    Text(createdCode)
                                        .font(.psMono)
                                    Button {
                                        UIPasteboard.general.string = createdCode
                                    } label: {
                                        Image(systemName: "doc.on.doc")
                                            .font(.psIcon)
                                    }
                                    .accessibilityLabel("Copy gift card code \(createdCode)")
                                }
                                Text("The code was also emailed to the recipient.")
                                    .font(.psCaption)
                                    .foregroundStyle(.psMuted)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        Button {
                            Task { await submit() }
                        } label: {
                            if isSubmitting {
                                PSRingSpinner(diameter: 20, lineWidth: 2, color: .psPaper)
                            } else {
                                Text("Create gift card")
                            }
                        }
                        .psPrimary()
                        .disabled(isSubmitting)
                        .accessibilityLabel("Create gift card")
                    }
                }
                .psScreenPadding()
            }
            .background(Color.psBackground)
            .navigationTitle("Send a gift card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .accessibilityLabel("Close gift card sheet")
                }
            }
        }
    }

    private func submit() async {
        errorMessage = nil
        guard let amount = Int(amountText.trimmingCharacters(in: .whitespaces)), amount > 0 else {
            errorMessage = "Choose a gift card amount."
            return
        }
        guard !recipientName.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Enter the recipient name."
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
            let result: PSGiftCardCreateResult = try await APIClient.shared.fetchJSON(
                "api/v1/gift-cards", method: "POST",
                body: [
                    "amount": amount,
                    "recipient_name": recipientName.trimmingCharacters(in: .whitespaces),
                    "recipient_email": recipientEmail.trimmingCharacters(in: .whitespaces),
                    "message": message,
                    "theme_style": selectedTheme,
                    "mpesa_code": code
                ])
            createdCode = result.code
            createdAmount = result.amount ?? amount
            onDone()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Verify screen (public endpoint, no sign-in needed to check)

struct GiftCardVerifyView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var result: PSGiftCardVerifyItem?
    @State private var errorMessage: String?
    @State private var isChecking = false
    @State private var redeemBusy = false
    @State private var redeemMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Enter a gift card code to see its amount, status, expiry, theme, sender and recipient.")
                        .font(.psBody)
                        .foregroundStyle(.psMuted)

                    HStack(spacing: 8) {
                        TextField("Gift card code", text: $code)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .psTextField()
                            .accessibilityLabel("Gift card code to verify")
                        Button("Verify") {
                            Task { await verify() }
                        }
                        .buttonStyle(.bordered)
                        .tint(.psCyan)
                        .disabled(code.trimmingCharacters(in: .whitespaces).isEmpty || isChecking)
                        .accessibilityLabel("Verify gift card code")
                    }

                    if isChecking {
                        PSRingSpinner()
                    }
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.psBody)
                            .foregroundStyle(.psDanger)
                    }

                    if let result {
                        PSCard {
                            VStack(alignment: .leading, spacing: 8) {
                                if let theme = PSGiftCardTheme.theme(named: result.theme) {
                                    LinearGradient(colors: theme.colors, startPoint: .leading, endPoint: .trailing)
                                        .frame(height: 48)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                        .accessibilityHidden(true)
                                }
                                HStack {
                                    Text(psKES(result.amount))
                                        .font(.psTitle)
                                    Spacer()
                                    if let status = result.status, !status.isEmpty {
                                        PSStatusPill(
                                            text: psCapitalized(status),
                                            systemImage: status.lowercased() == "active" ? "checkmark.circle.fill" : "circle.fill",
                                            tint: status.lowercased() == "active" ? .psSuccess : .psMuted
                                        )
                                    }
                                }
                                GiftCardVerifyRow(label: "Code", value: result.code)
                                GiftCardVerifyRow(label: "Expiry", value: result.expiry.map { psShortDate($0) })
                                GiftCardVerifyRow(label: "Theme", value: result.theme)
                                GiftCardVerifyRow(label: "From", value: result.sender)
                                GiftCardVerifyRow(label: "To", value: result.recipient)

                                if (result.status ?? "").lowercased() == "active" {
                                    Button {
                                        Task { await redeem() }
                                    } label: {
                                        if redeemBusy {
                                            PSRingSpinner(diameter: 20, lineWidth: 2, color: .psPaper)
                                        } else {
                                            Text("Redeem into my wallet")
                                        }
                                    }
                                    .psPrimary()
                                    .disabled(redeemBusy)
                                    .accessibilityLabel("Redeem this gift card into my wallet")
                                }
                                if let redeemMessage {
                                    Text(redeemMessage)
                                        .font(.psBody)
                                        .foregroundStyle(.psSuccess)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .psScreenPadding()
            }
            .background(Color.psBackground)
            .navigationTitle("Verify a gift card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .accessibilityLabel("Close gift card verification")
                }
            }
        }
    }

    private func verify() async {
        let clean = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !clean.isEmpty else { return }
        isChecking = true
        defer { isChecking = false }
        errorMessage = nil
        result = nil
        redeemMessage = nil
        do {
            let data: PSGiftCardVerifyData = try await APIClient.shared.fetchJSON("api/v1/gift-cards/verify/\(clean)")
            result = data.gift_card
            if data.gift_card == nil {
                errorMessage = "That gift card could not be found."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func redeem() async {
        let clean = result?.code ?? code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !clean.isEmpty else { return }
        redeemBusy = true
        defer { redeemBusy = false }
        do {
            let response: PSWalletActionResult = try await APIClient.shared.fetchJSON(
                "api/v1/gift-cards/redeem", method: "POST", body: ["code": clean])
            redeemMessage = "Redeemed \(psKES(response.amount)). New wallet balance \(psKES(response.wallet_balance))."
            await verify()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct GiftCardVerifyRow: View {
    let label: String
    let value: String?

    var body: some View {
        if let value, !value.isEmpty {
            HStack {
                Text(label)
                    .font(.psBody)
                    .foregroundStyle(.psMuted)
                Spacer()
                Text(value)
                    .font(.psBody)
            }
        }
    }
}
