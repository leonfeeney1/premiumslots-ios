import SwiftUI

// MARK: - Gift cards, Fix #4 (checklist 1.5, 6.2), v7 fixes
// Web GET /gift-cards (giftcards.py:117): feature toggle
// enable_gift_cards, denominations [200, 500, 1000, 2000, 5000],
// 5 themes, my issued cards (last 20), my redeemed cards (last 20).
// Themes are stored by ID on the web (gold / cyber / emerald /
// violet / ruby); the display names (Cyber Gold etc.) are UI only
// and are never sent. Create has two branches: wallet (default
// when the balance covers the amount, card Approved at once) and
// manual M-PESA (PayBill 400200, Account 1192526, card Pending
// until an admin approves). Verify is public and returns valid
// plus a message; Approved and Active both redeem. Redeem credits
// the wallet. All response structs decode with every field
// optional except ok, so a missing field degrades instead of crashing.

// MARK: - Gift card themes (exact hexes from checklist 1.5)

struct PSGiftCardTheme: Identifiable {
    let id: String
    let name: String
    let hexes: [String]

    var colors: [Color] {
        hexes.map { Color(psGiftHex: $0) }
    }

    static let all: [PSGiftCardTheme] = [
        PSGiftCardTheme(id: "gold", name: "Cyber Gold", hexes: ["#d97706", "#fbbf24", "#b45309"]),
        PSGiftCardTheme(id: "cyber", name: "Electric Blue", hexes: ["#1d4ed8", "#3b82f6", "#06b6d4"]),
        PSGiftCardTheme(id: "emerald", name: "Emerald Luxe", hexes: ["#047857", "#10b981", "#059669"]),
        PSGiftCardTheme(id: "violet", name: "Neon Violet", hexes: ["#6d28d9", "#8b5cf6", "#ec4899"]),
        PSGiftCardTheme(id: "ruby", name: "Crimson Ruby", hexes: ["#991b1b", "#ef4444", "#f43f5e"])
    ]

    /// Match by display name ("Cyber Gold") or by stored theme id
    /// ("gold"). Web-created cards store the id, so matching by
    /// name alone left them with no gradient.
    static func theme(named name: String?) -> PSGiftCardTheme? {
        guard let name, !name.isEmpty else { return nil }
        let lower = name.lowercased()
        return all.first { $0.name.lowercased() == lower || $0.id.lowercased() == lower }
    }

    static func theme(id: String?) -> PSGiftCardTheme? {
        guard let id, !id.isEmpty else { return nil }
        return all.first { $0.id.lowercased() == id.lowercased() }
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

// MARK: - Shared gift card helpers (also used by AdminWalletView)

// KES amount text with thousands separators, for example KES 1,500.
// psKES lives in WalletView.swift, which this file must not edit,
// so the grouped form lives here and is shared module-wide.
func psKESGrouped(_ amount: Int?) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.groupingSeparator = ","
    formatter.locale = Locale(identifier: "en_US")
    let text = formatter.string(from: NSNumber(value: amount ?? 0)) ?? "\(amount ?? 0)"
    return "KES \(text)"
}

/// Status wording and colours, matching the web gift card badges:
/// Pending is amber "Awaiting Admin Approval", Approved and Active
/// are green "Emailed & Active", Redeemed is purple
/// "Redeemed (Single-Use)", Rejected and Expired are red.
func psGiftCardStatusInfo(_ status: String?) -> (text: String, systemImage: String, tint: Color) {
    switch (status ?? "").lowercased() {
    case "pending":
        return ("Awaiting Admin Approval", "clock.fill", .psAmber)
    case "approved", "active":
        return ("Emailed & Active", "checkmark.circle.fill", .psSuccess)
    case "redeemed":
        return ("Redeemed (Single-Use)", "checkmark.circle.fill", Color.purple)
    case "rejected":
        return ("Rejected", "xmark.circle.fill", .psDanger)
    case "expired":
        return ("Expired", "xmark.circle.fill", .psDanger)
    default:
        let raw = status ?? ""
        return (raw.isEmpty ? "Unknown" : psCapitalized(raw), "circle.fill", .psMuted)
    }
}

func psGiftCardStatusPill(status: String?) -> PSStatusPill {
    let info = psGiftCardStatusInfo(status)
    return PSStatusPill(text: info.text, systemImage: info.systemImage, tint: info.tint)
}

/// WhatsApp share link for an Approved or Active card. The text
/// carries the amount and the redeem URL, as on the web. No phone
/// number is pinned: wa.me with only a text parameter opens the
/// WhatsApp share sheet so the sender picks the recipient.
func psGiftCardWhatsAppURL(code: String, amount: Int?) -> URL? {
    let text = "You received a \(psKESGrouped(amount)) PremiumSlots gift card. Redeem it here: https://premiumslots.tech/gift-cards?code=\(code)"
    var components = URLComponents(string: "https://wa.me/")
    components?.queryItems = [URLQueryItem(name: "text", value: text)]
    return components?.url
}

// MARK: - Gift card response models
// Keys verified against backend/api_v1.py list_gift_cards(),
// create_gift_card(), redeem_gift_card() and verify_gift_card().
// The list endpoint maps _gift_card_row rows: amount is
// initial_amount, message is custom_message, expiry_date is
// expires_at, and the raw columns (initial_amount, custom_message,
// mpesa_code, sender_name) ride along, so both the mapped keys
// and the raw keys are decoded with the mapped key winning.

struct PSGiftCard: Decodable {
    let id: Int?
    let code: String?
    let amount: Int?
    let initial_amount: Int?
    let status: String?
    let sender_name: String?
    let recipient_name: String?
    let recipient_email: String?
    let message: String?
    let custom_message: String?
    let mpesa_code: String?
    let theme_style: String?
    let expiry_date: String?
    let expires_at: String?
    let created_at: String?
    let redeemed_at: String?

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
    let valid: Bool?
    let message: String?
    let error: String?
    let status: String?
    let gift_card: PSGiftCardVerifyItem?
}

// MARK: - Gift cards root

struct GiftCardsRootView: View {
    /// Deep link prefill: when the app opens this page with a
    /// ?code= value, the verify sheet opens with that code already
    /// entered. The code arrives here from PSDeepLink.giftCards.
    var prefillVerifyCode: String? = nil

    @State private var data: PSGiftCardListData?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showCreate = false
    @State private var showVerify = false
    @State private var verifyPrefillCode: String?
    @State private var didApplyPrefill = false

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
                    PSSkeletonRows(count: 3)
                        .psScreenPadding()
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
            .psScreenBackground()
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
                GiftCardVerifyView(prefillCode: verifyPrefillCode)
                    .psSheetDetents()
            }
            .onChange(of: showVerify) { _, newValue in
                if !newValue { verifyPrefillCode = nil }
            }
            .task { await load() }
            .onAppear {
                guard !didApplyPrefill else { return }
                didApplyPrefill = true
                if let code = prefillVerifyCode, !code.isEmpty {
                    verifyPrefillCode = code
                    showVerify = true
                }
            }
        }
    }

    // One coherent design system for the whole page: a hero card,
    // one primary action row, denominations as chips, themes as
    // visual swatches, and issued / redeemed cards that all share
    // the same card, header and spacing rules as the rest of the
    // app (PSCard, PSSectionHeader, 16pt screen padding, 12pt
    // spacing, PSTextStyle type only).
    private var giftCardList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PSCard {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Image(systemName: "gift.fill")
                                .font(.psIcon)
                                .foregroundStyle(.psCyan)
                                .accessibilityHidden(true)
                            Text("Send a gift, share a slot")
                                .psTextStyle(.title)
                        }
                        Text("A gift card is wallet credit for someone else: they redeem the code into their wallet and use it on any platform.")
                            .psTextStyle(.body)
                            .foregroundStyle(.psMuted)
                        HStack(spacing: 10) {
                            Button("Send a gift card") { showCreate = true }
                                .psPrimary()
                            Button("Verify a code") { showVerify = true }
                                .buttonStyle(.bordered)
                                .tint(.psCyan)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 12) {
                    PSSectionHeader(title: "Denominations")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(denominations, id: \.self) { amount in
                                Text(psKESGrouped(amount))
                                    .psTextStyle(.mono)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color.psSurface)
                                    .clipShape(Capsule())
                                    .overlay(Capsule().stroke(Color.psBorder, lineWidth: 1))
                            }
                        }
                    }
                    Text("Gift cards come in these amounts. Pay from your wallet balance or with M-PESA.")
                        .psTextStyle(.caption)
                        .foregroundStyle(.psMuted)
                }

                VStack(alignment: .leading, spacing: 12) {
                    PSSectionHeader(title: "Themes")
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(PSGiftCardTheme.all) { theme in
                            VStack(alignment: .leading, spacing: 8) {
                                LinearGradient(colors: theme.colors, startPoint: .leading, endPoint: .trailing)
                                    .frame(height: 44)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .accessibilityHidden(true)
                                Text(theme.name)
                                    .psTextStyle(.body)
                            }
                            .padding(10)
                            .background(Color.psSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.psBorder, lineWidth: 1)
                            )
                            .accessibilityLabel("Gift card theme \(theme.name)")
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    PSSectionHeader(title: "My issued cards")
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

                VStack(alignment: .leading, spacing: 12) {
                    PSSectionHeader(title: "My redeemed cards")
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
            .psScreenPadding()
        }
        .psHiddenScrollIndicators()
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
                .psTextStyle(.body)
            Spacer()
        }
        .psTouchTarget()
    }
}

struct GiftCardRow: View {
    let card: PSGiftCard

    private var isShareable: Bool {
        let status = (card.status ?? "").lowercased()
        return status == "approved" || status == "active"
    }

    var body: some View {
        PSCard {
            VStack(alignment: .leading, spacing: 10) {
                if let theme = PSGiftCardTheme.theme(named: card.theme_style) {
                    LinearGradient(colors: theme.colors, startPoint: .leading, endPoint: .trailing)
                        .frame(height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .accessibilityHidden(true)
                }
                HStack {
                    Text(psKESGrouped(card.displayAmount))
                        .psTextStyle(.title)
                    Spacer()
                    if let status = card.status, !status.isEmpty {
                        psGiftCardStatusPill(status: status)
                    }
                }
                if let code = card.code, !code.isEmpty {
                    HStack {
                        Text(code)
                            .psTextStyle(.mono)
                        Button {
                            UIPasteboard.general.string = code
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.psIcon)
                        }
                        .accessibilityLabel("Copy gift card code \(code)")
                        if isShareable, let url = psGiftCardWhatsAppURL(code: code, amount: card.displayAmount) {
                            Button {
                                UIApplication.shared.open(url)
                            } label: {
                                Image(systemName: "message.fill")
                                    .font(.psIcon)
                            }
                            .accessibilityLabel("Share gift card \(code) on WhatsApp")
                        }
                    }
                }
                HStack(spacing: 8) {
                    if let name = card.recipient_name ?? card.recipient_email, !name.isEmpty {
                        Text("To \(name)")
                            .psTextStyle(.caption)
                            .foregroundStyle(.psMuted)
                    }
                    if let sender = card.sender_name, !sender.isEmpty {
                        Text("From \(sender)")
                            .psTextStyle(.caption)
                            .foregroundStyle(.psMuted)
                    }
                    if let themeName = PSGiftCardTheme.theme(named: card.theme_style)?.name ?? card.theme_style, !themeName.isEmpty {
                        Text(themeName)
                            .psTextStyle(.caption)
                            .foregroundStyle(.psMuted)
                    }
                    if let expiry = card.expiryText {
                        Text("Expires \(psShortDate(expiry))")
                            .psTextStyle(.caption)
                            .foregroundStyle(.psMuted)
                    }
                }
                if let mpesaCode = card.mpesa_code, !mpesaCode.isEmpty {
                    Text("M-PESA code \(mpesaCode)")
                        .psTextStyle(.caption)
                        .foregroundStyle(.psMuted)
                }
                if let message = card.displayMessage, !message.isEmpty {
                    Text(message)
                        .psTextStyle(.body)
                        .foregroundStyle(.psDim)
                }
                Text("Sent \(psShortDate(card.created_at))")
                    .psTextStyle(.caption)
                    .foregroundStyle(.psMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Create sheet

struct GiftCardCreateSheet: View {
    let denominations: [Int]
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var amountText = "500"
    @State private var recipientName = ""
    @State private var recipientEmail = ""
    @State private var message = ""
    @State private var selectedThemeId = "gold"
    @State private var paymentMethod = "mpesa"
    @State private var paymentMethodExplicit = false
    @State private var walletBalance: Int?
    @State private var walletLoading = false
    @State private var mpesaCode = ""
    @State private var errorMessage: String?
    @State private var createdCode: String?
    @State private var createdAmount: Int?
    @State private var createdStatus: String?
    @State private var isSubmitting = false

    private var amountValue: Int {
        Int(amountText.trimmingCharacters(in: .whitespaces)) ?? 0
    }

    private var selectedTheme: PSGiftCardTheme {
        PSGiftCardTheme.theme(id: selectedThemeId) ?? PSGiftCardTheme.all[0]
    }

    private var canAffordWallet: Bool {
        amountValue > 0 && (walletBalance ?? 0) >= amountValue
    }

    private var walletShortfall: Int {
        max(0, amountValue - (walletBalance ?? 0))
    }

    private var paymentMethodBinding: Binding<String> {
        Binding(
            get: { paymentMethod },
            set: {
                paymentMethod = $0
                paymentMethodExplicit = true
            }
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    previewCard

                    Text("Send a gift card from your wallet balance or with M-PESA. The recipient gets the code by email and redeems it into their wallet.")
                        .psTextStyle(.body)
                        .foregroundStyle(.psMuted)

                    PSSectionHeader(title: "Amount (KES)")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(denominations, id: \.self) { amount in
                                Button(psKESGrouped(amount)) { amountText = "\(amount)" }
                                    .buttonStyle(.bordered)
                                    .tint(.psCyan)
                                    .accessibilityLabel("Gift card amount \(psKESGrouped(amount))")
                            }
                        }
                    }
                    TextField("Amount in KES", text: $amountText)
                        .keyboardType(.numberPad)
                        .psTextField()
                        .accessibilityLabel("Gift card amount in KES")
                    Text("Custom amount from KES 100 to KES 20,000.")
                        .psTextStyle(.caption)
                        .foregroundStyle(.psMuted)

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
                                selectedThemeId = theme.id
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    LinearGradient(colors: theme.colors, startPoint: .leading, endPoint: .trailing)
                                        .frame(height: 36)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    Text(theme.name)
                                        .psTextStyle(.caption)
                                        .foregroundStyle(.psText)
                                }
                                .padding(8)
                                .background(Color.psSurface)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(selectedThemeId == theme.id ? Color.psPrimary : Color.psBorder, lineWidth: selectedThemeId == theme.id ? 2 : 1)
                                )
                            }
                            .accessibilityLabel("Gift card theme \(theme.name)")
                        }
                    }

                    PSSectionHeader(title: "Payment method")
                    Picker("Payment method", selection: paymentMethodBinding) {
                        Text("Wallet").tag("wallet")
                        Text("M-PESA").tag("mpesa")
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Gift card payment method")

                    if paymentMethod == "wallet" {
                        walletSection
                    } else {
                        mpesaSection
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .psTextStyle(.body)
                            .foregroundStyle(.psDanger)
                    }

                    if let createdCode {
                        PSCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Gift card created", systemImage: "checkmark.circle.fill")
                                    .psTextStyle(.headline)
                                    .foregroundStyle(.psSuccess)
                                Text("Amount \(psKESGrouped(createdAmount))")
                                    .psTextStyle(.body)
                                HStack {
                                    Text(createdCode)
                                        .psTextStyle(.mono)
                                    Button {
                                        UIPasteboard.general.string = createdCode
                                    } label: {
                                        Image(systemName: "doc.on.doc")
                                            .font(.psIcon)
                                    }
                                    .accessibilityLabel("Copy gift card code \(createdCode)")
                                }
                                Text(createdStatusText)
                                    .psTextStyle(.caption)
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
            .psScreenBackground()
            .navigationTitle("Send a gift card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .accessibilityLabel("Close gift card sheet")
                }
            }
            .task { await loadWallet() }
            .onChange(of: amountText) { _, _ in
                if !paymentMethodExplicit {
                    paymentMethod = canAffordWallet ? "wallet" : "mpesa"
                }
            }
        }
    }

    private var createdStatusText: String {
        if (createdStatus ?? "").lowercased() == "approved" {
            return "Approved - emailed to recipient."
        }
        return "Pending admin approval. The recipient gets the code once an admin approves the payment."
    }

    /// Live preview: updates as amount, recipient, message and
    /// theme change. The sender is always "You".
    private var previewCard: some View {
        ZStack(alignment: .leading) {
            LinearGradient(colors: selectedTheme.colors, startPoint: .leading, endPoint: .trailing)
            VStack(alignment: .leading, spacing: 6) {
                Text("To \(recipientName.trimmingCharacters(in: .whitespaces).isEmpty ? "Recipient" : recipientName)")
                    .psTextStyle(.headline)
                    .foregroundStyle(.psPaper)
                Text(psKESGrouped(amountValue))
                    .psTextStyle(.title)
                    .foregroundStyle(.psPaper)
                Text(message.trimmingCharacters(in: .whitespaces).isEmpty ? "Enjoy your premium access!" : message)
                    .psTextStyle(.body)
                    .foregroundStyle(.psPaper)
                Text("From You")
                    .psTextStyle(.caption)
                    .foregroundStyle(.psPaper)
            }
            .padding(14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityLabel("Gift card preview for \(recipientName.isEmpty ? "recipient" : recipientName), \(psKESGrouped(amountValue))")
    }

    private var walletSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if walletLoading {
                PSRingSpinner(diameter: 20, lineWidth: 2)
            } else if let balance = walletBalance {
                Text("Wallet balance \(psKESGrouped(balance))")
                    .psTextStyle(.body)
                if amountValue > 0 {
                    if canAffordWallet {
                        Text("Balance after \(psKESGrouped(balance - amountValue))")
                            .psTextStyle(.caption)
                            .foregroundStyle(.psMuted)
                    } else {
                        Text("Short by \(psKESGrouped(walletShortfall)). Top up your wallet from the Wallet tab first, or pay with M-PESA.")
                            .psTextStyle(.body)
                            .foregroundStyle(.psDanger)
                    }
                }
            } else {
                Text("Wallet balance could not be loaded. Pay with M-PESA instead.")
                    .psTextStyle(.body)
                    .foregroundStyle(.psMuted)
            }
            Text("Wallet gift cards are approved at once and emailed to the recipient right away.")
                .psTextStyle(.caption)
                .foregroundStyle(.psMuted)
        }
    }

    private var mpesaSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pay \(psKESGrouped(amountValue)) with M-PESA first, then enter the 10-character code from your confirmation message.")
                .psTextStyle(.body)
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("PayBill")
                        .psTextStyle(.caption)
                        .foregroundStyle(.psMuted)
                    Text("400200")
                        .psTextStyle(.headline)
                }
                Button {
                    UIPasteboard.general.string = "400200"
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.psIcon)
                }
                .accessibilityLabel("Copy PayBill 400200")
                Spacer()
                VStack(alignment: .leading, spacing: 3) {
                    Text("Account")
                        .psTextStyle(.caption)
                        .foregroundStyle(.psMuted)
                    Text("1192526")
                        .psTextStyle(.headline)
                }
                Button {
                    UIPasteboard.general.string = "1192526"
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.psIcon)
                }
                .accessibilityLabel("Copy account 1192526")
            }
            .padding(12)
            .background(Color.psSurface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.psBorder, lineWidth: 1)
            )
            TextField("Example: SDA45TY190", text: $mpesaCode)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .psTextField()
                .accessibilityLabel("M-PESA transaction code")
            Text("Your card stays pending until an admin approves the payment.")
                .psTextStyle(.caption)
                .foregroundStyle(.psMuted)
        }
    }

    private func loadWallet() async {
        walletLoading = true
        defer { walletLoading = false }
        do {
            let data: PSWalletData = try await APIClient.shared.fetchJSON("api/v1/wallet")
            walletBalance = data.wallet_balance
            if !paymentMethodExplicit {
                paymentMethod = canAffordWallet ? "wallet" : "mpesa"
            }
        } catch {
            walletBalance = nil
        }
    }

    private func submit() async {
        errorMessage = nil
        guard amountValue >= 100, amountValue <= 20000 else {
            errorMessage = "Gift card amount must be between KES 100 and KES 20,000."
            return
        }
        guard !recipientName.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Enter the recipient name."
            return
        }
        let email = recipientEmail.trimmingCharacters(in: .whitespaces)
        guard !email.isEmpty, email.contains("@") else {
            errorMessage = "Enter a valid recipient email so they receive their voucher."
            return
        }
        var body: [String: Any] = [
            "amount": amountValue,
            "custom_amount": amountValue,
            "recipient_name": recipientName.trimmingCharacters(in: .whitespaces),
            "recipient_email": email,
            "message": message,
            "custom_message": message,
            "theme_style": selectedThemeId,
            "payment_method": paymentMethod
        ]
        if paymentMethod == "wallet" {
            guard canAffordWallet else {
                errorMessage = "Wallet balance is short by \(psKESGrouped(walletShortfall)). Top up your wallet first, or pay with M-PESA."
                return
            }
        } else {
            let code = mpesaCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard psIsValidMpesaCode(code) else {
                errorMessage = "The M-PESA code must be exactly 10 letters and numbers."
                return
            }
            body["mpesa_code"] = code
        }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let result: PSGiftCardCreateResult = try await APIClient.shared.fetchJSON(
                "api/v1/gift-cards", method: "POST", body: body)
            createdCode = result.code
            createdAmount = result.amount ?? amountValue
            createdStatus = result.status
            onDone()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Verify screen (public endpoint, no sign-in needed to check)

struct GiftCardVerifyView: View {
    let prefillCode: String?

    @Environment(\.dismiss) private var dismiss
    @State private var code: String
    @State private var result: PSGiftCardVerifyItem?
    @State private var errorMessage: String?
    @State private var isChecking = false
    @State private var redeemBusy = false
    @State private var redeemMessage: String?

    init(prefillCode: String? = nil) {
        self.prefillCode = prefillCode
        _code = State(initialValue: prefillCode ?? "")
    }

    private var isRedeemable: Bool {
        let status = (result?.status ?? "").lowercased()
        return status == "approved" || status == "active"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Enter a gift card code to see its amount, status, expiry, theme, sender and recipient.")
                        .psTextStyle(.body)
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
                            .psTextStyle(.body)
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
                                    Text(psKESGrouped(result.amount))
                                        .psTextStyle(.title)
                                    Spacer()
                                    if let status = result.status, !status.isEmpty {
                                        psGiftCardStatusPill(status: status)
                                    }
                                }
                                GiftCardVerifyRow(label: "Code", value: result.code)
                                GiftCardVerifyRow(label: "Expiry", value: result.expiry.map { psShortDate($0) })
                                GiftCardVerifyRow(label: "Theme", value: PSGiftCardTheme.theme(named: result.theme)?.name ?? result.theme)
                                GiftCardVerifyRow(label: "From", value: result.sender)
                                GiftCardVerifyRow(label: "To", value: result.recipient)

                                if isRedeemable {
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
                                        .psTextStyle(.body)
                                        .foregroundStyle(.psSuccess)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .psScreenPadding()
            }
            .psScreenBackground()
            .navigationTitle("Verify a gift card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .accessibilityLabel("Close gift card verification")
                }
            }
            .task {
                if let prefillCode, !prefillCode.isEmpty {
                    await verify()
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
            if data.valid == false {
                errorMessage = data.message ?? data.error ?? "That gift card could not be found."
            } else if data.gift_card == nil {
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
            redeemMessage = "Redeemed \(psKESGrouped(response.amount)). New wallet balance \(psKESGrouped(response.wallet_balance))."
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
                    .psTextStyle(.body)
                    .foregroundStyle(.psMuted)
                Spacer()
                Text(value)
                    .psTextStyle(.body)
            }
        }
    }
}
