import SwiftUI

// MARK: - Checkout, v2 + Fix #4
// Real M-PESA flow from the live site (ANALYSIS.md §5):
// PayBill 400200, Account 1192526, Number 0734460218. The code is
// exactly 10 alphanumeric characters. The order is created on the
// live site as Pending and is delivered only when an admin approves it.
// Fix #4 adds, without changing the manual flow: a coupon field with
// a validate preview (POST /api/v1/coupons/validate), a payment
// method picker (Manual M-PESA / STK push / Wallet), an STK phone
// field (the server normalises the number to 254 format), a wallet
// balance display, a staged checkout-status screen after submit
// (processing, printing, complete) driven by
// GET /api/v1/checkout/status/<ref>, and retry
// (POST /api/v1/pay/retry/<id>) plus verify-manual
// (POST /api/v1/pay/verify-manual/<id>) actions on pending orders.

enum ChkPaymentMethod: String, CaseIterable {
    case manual = "mpesa"
    case stk = "stk"
    case wallet = "wallet"

    var label: String {
        switch self {
        case .manual: return "Manual M-PESA"
        case .stk: return "STK push"
        case .wallet: return "Wallet"
        }
    }
}

enum ChkCheckoutStage: String {
    case processing = "Processing"
    case printing = "Printing"
    case complete = "Complete"

    var systemImage: String {
        switch self {
        case .processing: return "arrow.triangle.2.circlepath"
        case .printing: return "printer.fill"
        case .complete: return "checkmark.circle.fill"
        }
    }
}

struct CheckoutView: View {
    let platform: Platform
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var mpesaCode = ""
    @State private var couponCode = ""
    @State private var couponPreview: ChkCouponPreview?
    @State private var couponMessage: String?
    @State private var isCheckingCoupon = false
    @State private var paymentMethod: ChkPaymentMethod = .manual
    @State private var stkPhone = ""
    @State private var placedSubscriptionId: Int?
    @State private var placedStatus: String?
    @State private var checkoutRef: String?
    @State private var checkoutStatusText: String?
    @State private var checkoutStage: ChkCheckoutStage = .processing
    @State private var checkoutReceipt: String?
    @State private var statusMessage: String?
    @State private var isCheckingStatus = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isSubmitting = false
    @State private var needsLogin = false

    private static let paybill = "400200"
    private static let account = "1192526"
    private static let number = "0734460218"

    private var amountDue: Int {
        couponPreview?.amount_after_discount ?? platform.priceKES
    }

    private var walletShortfall: Bool {
        paymentMethod == .wallet && (appState.walletBalance ?? 0) < amountDue
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Pay by M-PESA")
                        .font(.psTitle)
                    Text("Pay the exact amount, then submit the transaction code you receive. Nothing is charged inside this app.")
                        .font(.psBody)
                        .foregroundStyle(.psMuted)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Payment method")
                            .font(.psHeadline)
                        Picker("Payment method", selection: $paymentMethod) {
                            ForEach(ChkPaymentMethod.allCases, id: \.self) { method in
                                Text(method.label).tag(method)
                            }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityLabel("Payment method")
                        if paymentMethod == .wallet {
                            HStack {
                                Text("Wallet balance")
                                    .foregroundStyle(.psMuted)
                                Spacer()
                                if let balance = appState.walletBalance {
                                    Text("KES \(balance)")
                                        .font(.psMono)
                                        .fontWeight(.semibold)
                                } else {
                                    Text("Sign in to see your balance")
                                        .font(.psCaption)
                                        .foregroundStyle(.psMuted)
                                }
                            }
                            .font(.psBody)
                            if walletShortfall {
                                Text("Your wallet balance is not enough for this slot. Top up your wallet first, or pick another payment method.")
                                    .font(.psCaption)
                                    .foregroundStyle(.psAmber)
                            } else {
                                Text("Paying from your wallet approves the slot straight away, up to the KES 25,000 daily wallet spend limit.")
                                    .font(.psCaption)
                                    .foregroundStyle(.psMuted)
                            }
                        }
                        if paymentMethod == .stk {
                            Text("We send a payment prompt to your phone. Enter the number that will approve it.")
                                .font(.psCaption)
                                .foregroundStyle(.psMuted)
                            TextField("Phone, for example 0712345678", text: $stkPhone)
                                .psTextField()
                                .keyboardType(.phonePad)
                                .accessibilityLabel("Phone number for STK push")
                        }
                    }
                    .padding(14)
                    .background(Color.psSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Coupon")
                            .font(.psHeadline)
                        HStack(spacing: 10) {
                            TextField("Coupon code", text: $couponCode)
                                .psTextField()
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                                .accessibilityLabel("Coupon code")
                            Button {
                                Task { await validateCoupon() }
                            } label: {
                                if isCheckingCoupon { PSRingSpinner(diameter: 20, lineWidth: 2, color: .white, duration: 0.7) }
                                else { Text("Apply") }
                            }
                            .buttonStyle(.bordered)
                            .tint(.psCyan)
                            .disabled(isCheckingCoupon)
                            .accessibilityLabel("Validate coupon code")
                        }
                        if let preview = couponPreview {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Coupon \(preview.code ?? couponCode) saves KES \(preview.discount ?? 0).")
                                    .font(.psBody)
                                    .foregroundStyle(.psSuccess)
                                Text("You pay KES \(preview.amount_after_discount ?? platform.priceKES) instead of KES \(platform.priceKES).")
                                    .font(.psCaption)
                                    .foregroundStyle(.psMuted)
                            }
                            .accessibilityLabel("Coupon saves KES \(preview.discount ?? 0). You pay KES \(preview.amount_after_discount ?? platform.priceKES).")
                        }
                        if let couponMessage {
                            Text(couponMessage)
                                .font(.psCaption)
                                .foregroundStyle(.psMuted)
                        }
                    }
                    .padding(14)
                    .background(Color.psSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                    if paymentMethod == .manual {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Step 1: Send the payment")
                                .font(.psHeadline)
                            paymentRow(label: "Platform", value: platform.name)
                            paymentRow(label: "Amount to send", value: "KES \(amountDue)")
                            paymentRow(label: "PayBill", value: Self.paybill, copyable: true)
                            paymentRow(label: "Account number", value: Self.account, copyable: true)
                            paymentRow(label: "Number", value: Self.number, copyable: true)
                            Text("Send exactly KES \(amountDue) by M-PESA to PayBill \(Self.paybill), account \(Self.account). Keep the confirmation message: it holds your transaction code.")
                                .font(.psCaption)
                                .foregroundStyle(.psMuted)
                        }
                        .padding(14)
                        .background(Color.psSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 14))

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Step 2: Submit your M-PESA code")
                                .font(.psHeadline)
                            TextField("Example: SDA45TY190", text: $mpesaCode)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                                .font(.psMono)
                                .padding(12)
                                .background(Color.psObsidian)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.psBorder, lineWidth: 1)
                                )
                            Text("The code is exactly 10 letters and numbers. It is checked by the PremiumSlots team, not charged here.")
                                .font(.psCaption)
                                .foregroundStyle(.psMuted)
                        }
                        .padding(14)
                        .background(Color.psSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 14))

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Step 3: Get access")
                                .font(.psHeadline)
                            Text("Once your code is verified, your slot moves to Active in My Slots and your vault details appear there. 1 slot = 1 device.")
                                .font(.psBody)
                                .foregroundStyle(.psMuted)
                        }
                    } else if paymentMethod == .stk {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("How STK push works")
                                .font(.psHeadline)
                            Text("Enter your phone number, then submit. A payment prompt arrives on your phone for KES \(amountDue). Approve it with your M-PESA PIN and this screen follows the payment until it is complete.")
                                .font(.psBody)
                                .foregroundStyle(.psMuted)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("How wallet payment works")
                                .font(.psHeadline)
                            Text("KES \(amountDue) is taken from your wallet balance and your slot is approved straight away. 1 slot = 1 device.")
                                .font(.psBody)
                                .foregroundStyle(.psMuted)
                        }
                    }

                    if let ref = checkoutRef {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: checkoutStage.systemImage)
                                    .foregroundStyle(checkoutStage == .complete ? .psSuccess : .psCyan)
                                    .accessibilityHidden(true)
                                Text(checkoutStage.rawValue)
                                    .font(.psHeadline)
                                Spacer()
                                if isCheckingStatus {
                                    PSRingSpinner(diameter: 20, lineWidth: 2)
                                }
                            }
                            Text("Checkout reference \(ref)")
                                .font(.psMono)
                                .foregroundStyle(.psMuted)
                            if let status = checkoutStatusText {
                                Text("Live status: \(status)")
                                    .font(.psBody)
                                    .foregroundStyle(.psMuted)
                            }
                            if let receipt = checkoutReceipt {
                                Text("Receipt: \(receipt)")
                                    .font(.psCaption)
                                    .foregroundStyle(.psMuted)
                            }
                            if checkoutStage == .complete {
                                Text("Payment complete. Your slot moves to Active in My Slots and your vault details appear there.")
                                    .font(.psBody)
                                    .foregroundStyle(.psMuted)
                                Button("View in My Slots") { dismiss() }
                                    .psPrimary()
                            } else {
                                Text("Keep this screen open while the payment is followed. Approve the prompt on your phone if you have not yet.")
                                    .font(.psCaption)
                                    .foregroundStyle(.psMuted)
                                Button("Check status now") {
                                    Task { await refreshCheckoutStatus() }
                                }
                                .buttonStyle(.bordered)
                                .tint(.psCyan)
                                .disabled(isCheckingStatus)
                            }
                            if let statusMessage {
                                Text(statusMessage)
                                    .font(.psCaption)
                                    .foregroundStyle(.psMuted)
                            }
                        }
                        .padding(14)
                        .background(Color.psSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    if let id = placedSubscriptionId {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Order #\(id) saved as \(placedStatus ?? "Pending verification")", systemImage: "clock.fill")
                                .font(.psHeadline)
                                .foregroundStyle(.psAmber)
                            Text("Your order was recorded. It will move to Active once the team approves it.")
                                .font(.psCaption)
                                .foregroundStyle(.psMuted)
                            if placedStatus == "Initiated" || placedStatus == "Pending" {
                                HStack(spacing: 10) {
                                    Button("Retry payment") {
                                        Task { await retryPayment(orderId: id) }
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(.psCyan)
                                    .accessibilityLabel("Retry payment for order \(id)")
                                    Button("Ask for manual verification") {
                                        Task { await verifyManual(orderId: id) }
                                    }
                                    .buttonStyle(.bordered)
                                    .accessibilityLabel("Ask for manual verification of order \(id)")
                                }
                            }
                            if let statusMessage, checkoutRef == nil {
                                Text(statusMessage)
                                    .font(.psCaption)
                                    .foregroundStyle(.psMuted)
                            }
                            Button("View in My Slots") { dismiss() }
                                .psPrimary()
                        }
                        .padding(14)
                        .background(Color.psSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    } else if checkoutRef == nil {
                        Button {
                            Task { await submit() }
                        } label: {
                            if isSubmitting { PSRingSpinner(diameter: 20, lineWidth: 2, color: .white, duration: 0.7) }
                            else { Text(submitLabel) }
                        }
                        .psPrimary()
                        .disabled(isSubmitting || walletShortfall)
                        Text("No card details are collected in this app.")
                            .font(.psCaption)
                            .foregroundStyle(.psMuted)
                        if appState.liveState != .live {
                            Text("The live service is not reachable right now, so this order cannot be sent to the site yet. Your code is not recorded anywhere until the service is back.")
                                .font(.psCaption)
                                .foregroundStyle(.psAmber)
                        }
                    }
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .hideKeyboardOnTap()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.psBackground)
            .navigationTitle("Checkout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
                dismissKeyboardButton
            }
            .alert("Check the details", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .sheet(isPresented: $needsLogin) {
                AuthView()
            }
            .task {
                stkPhone = appState.user?.whatsapp_number ?? ""
                await appState.refreshWallet()
            }
        }
    }

    private var submitLabel: String {
        switch paymentMethod {
        case .manual: return "Submit M-PESA code"
        case .stk: return "Send STK push"
        case .wallet: return "Pay KES \(amountDue) from wallet"
        }
    }

    private func paymentRow(label: String, value: String, copyable: Bool = false) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.psMuted)
            Spacer()
            Text(value)
                .font(.psMono)
                .fontWeight(.semibold)
                .multilineTextAlignment(.trailing)
            if copyable {
                Button {
                    UIPasteboard.general.string = value
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 20))
                }
            }
        }
        .font(.psBody)
    }

    private func validateCoupon() async {
        let code = couponCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !code.isEmpty else {
            couponMessage = "Enter a coupon code first."
            return
        }
        isCheckingCoupon = true
        couponMessage = nil
        defer { isCheckingCoupon = false }
        do {
            let preview: ChkCouponPreview = try await APIClient.shared.fetchJSON(
                "api/v1/coupons/validate", method: "POST",
                body: ["code": code,
                       "service_requested": platform.name,
                       "amount": platform.priceKES])
            guard preview.valid == true else {
                couponPreview = nil
                couponMessage = "That coupon is not valid for this order."
                return
            }
            couponPreview = preview
            couponMessage = nil
        } catch {
            couponPreview = nil
            couponMessage = error.localizedDescription
        }
    }

    private func submit() async {
        guard appState.isLoggedIn else {
            needsLogin = true
            return
        }
        let coupon = couponCode.trimmingCharacters(in: .whitespacesAndNewlines)
        switch paymentMethod {
        case .manual:
            let code = mpesaCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard code.count == 10, code.allSatisfy({ $0.isLetter || $0.isNumber }) else {
                errorMessage = "Enter the M-PESA transaction code from your confirmation message. It is exactly 10 letters and numbers."
                showError = true
                return
            }
            await placeOrder(body: [
                "service_requested": platform.name,
                "payment_method": "mpesa",
                "mpesa_code": code,
                "coupon_code": coupon
            ])
        case .stk:
            let phone = stkPhone.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !phone.isEmpty else {
                errorMessage = "Enter the phone number that will approve the STK push."
                showError = true
                return
            }
            await placeOrder(body: [
                "service_requested": platform.name,
                "payment_method": "stk",
                "phone": phone,
                "coupon_code": coupon
            ])
        case .wallet:
            await placeOrder(body: [
                "service_requested": platform.name,
                "payment_method": "wallet",
                "coupon_code": coupon
            ])
        }
    }

    private func placeOrder(body: [String: Any]) async {
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let response: ChkRequestResponse = try await APIClient.shared.fetchJSON(
                "api/v1/request", method: "POST", body: body)
            guard response.ok, let id = response.subscription_id else {
                errorMessage = response.error ?? "Order failed."
                showError = true
                return
            }
            placedSubscriptionId = id
            placedStatus = response.status
            await appState.refreshMySubscriptions()
            await appState.refreshWallet()
            if let ref = response.tuma_reference, !ref.isEmpty {
                checkoutRef = ref
                checkoutStatusText = response.status
                checkoutStage = .processing
                Task { await pollCheckoutStatus() }
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func refreshCheckoutStatus() async {
        guard let ref = checkoutRef else { return }
        isCheckingStatus = true
        defer { isCheckingStatus = false }
        do {
            let response: ChkCheckoutStatusResponse = try await APIClient.shared.fetchJSON(
                "api/v1/checkout/status/\(ref)")
            checkoutStatusText = response.status
            checkoutReceipt = response.receipt
            if let status = response.status {
                switch status {
                case "Approved": checkoutStage = .complete
                case "Initiated": checkoutStage = .processing
                default: checkoutStage = .printing
                }
                placedStatus = status
            }
            await appState.refreshMySubscriptions()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func pollCheckoutStatus() async {
        for _ in 0..<10 {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await refreshCheckoutStatus()
            if checkoutStage == .complete { return }
            if checkoutRef == nil { return }
        }
        statusMessage = "Still waiting for the payment. Pull the status check again or come back later."
    }

    private func retryPayment(orderId: Int) async {
        do {
            let response: ChkRetryResponse = try await APIClient.shared.fetchJSON(
                "api/v1/pay/retry/\(orderId)", method: "POST", body: [:])
            if let ref = response.tuma_reference {
                checkoutRef = ref
                checkoutStage = .processing
                checkoutStatusText = response.status
                statusMessage = "A new payment prompt was sent. Approve it on your phone."
                Task { await pollCheckoutStatus() }
            } else {
                statusMessage = "Payment retry started."
            }
            placedStatus = response.status ?? placedStatus
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func verifyManual(orderId: Int) async {
        var body: [String: Any] = [:]
        let code = mpesaCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if !code.isEmpty { body["mpesa_code"] = code }
        do {
            let response: APIResponse = try await APIClient.shared.fetchJSON(
                "api/v1/pay/verify-manual/\(orderId)", method: "POST", body: body)
            statusMessage = "Manual verification requested. An admin will confirm your payment."
            _ = response
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}

// MARK: - Checkout response types (keys from backend/api_v1.py)

struct ChkCouponPreview: Decodable {
    let ok: Bool
    let valid: Bool?
    let code: String?
    let discount: Int?
    let discount_type: String?
    let amount: Int?
    let amount_after_discount: Int?
}

struct ChkRequestResponse: Decodable {
    let ok: Bool
    let error: String?
    let subscription_id: Int?
    let status: String?
    let amount_due: Int?
    let discount: Int?
    let service_requested: String?
    let tuma_reference: String?
    let stk_initiated: Bool?
    let stk_note: String?
    let reference: String?
    let wallet_balance: Int?
    let expiry_date: String?
}

struct ChkCheckoutStatusResponse: Decodable {
    let ok: Bool
    let subscription: APISubscription?
    let status: String?
    let tuma_reference: String?
    let receipt: String?
    let amount_due: Int?
}

struct ChkRetryResponse: Decodable {
    let ok: Bool
    let status: String?
    let tuma_reference: String?
}

#Preview {
    CheckoutView(platform: Platform.bundled[1])
        .environmentObject(AppState())
}
