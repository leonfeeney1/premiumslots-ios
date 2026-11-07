import SwiftUI

// MARK: - Checkout, v2
// Real M-PESA flow from the live site (ANALYSIS.md §5):
// PayBill 400200, Account 1192526, Number 0734460218. The code is
// exactly 10 alphanumeric characters. The order is created on the
// live site as Pending and is delivered only when an admin approves it.

struct CheckoutView: View {
    let platform: Platform
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var mpesaCode = ""
    @State private var placedSubscriptionId: Int?
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isSubmitting = false
    @State private var needsLogin = false

    private static let paybill = "400200"
    private static let account = "1192526"
    private static let number = "0734460218"

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
                        Text("Step 1: Send the payment")
                            .font(.psHeadline)
                        paymentRow(label: "Platform", value: platform.name)
                        paymentRow(label: "Amount to send", value: platform.formattedPrice)
                        paymentRow(label: "PayBill", value: Self.paybill, copyable: true)
                        paymentRow(label: "Account number", value: Self.account, copyable: true)
                        paymentRow(label: "Number", value: Self.number, copyable: true)
                        Text("Send exactly \(platform.formattedPrice) by M-PESA to PayBill \(Self.paybill), account \(Self.account). Keep the confirmation message: it holds your transaction code.")
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

                    if let id = placedSubscriptionId {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Order #\(id) saved as Pending verification", systemImage: "clock.fill")
                                .font(.psHeadline)
                                .foregroundStyle(.psAmber)
                            Text("Your code was recorded on premiumslots.tech. It will move to Active once the team approves it.")
                                .font(.psCaption)
                                .foregroundStyle(.psMuted)
                            Button("View in My Slots") { dismiss() }
                                .psPrimary()
                        }
                        .padding(14)
                        .background(Color.psSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    } else {
                        Button {
                            Task { await submit() }
                        } label: {
                            if isSubmitting { ProgressView() } else { Text("Submit M-PESA code") }
                        }
                        .psPrimary()
                        .disabled(isSubmitting)
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.psObsidian)
            .navigationTitle("Checkout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
            .alert("Check the code", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .sheet(isPresented: $needsLogin) {
                AuthView()
            }
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

    private func submit() async {
        let code = mpesaCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard code.count == 10, code.allSatisfy({ $0.isLetter || $0.isNumber }) else {
            errorMessage = "Enter the M-PESA transaction code from your confirmation message. It is exactly 10 letters and numbers."
            showError = true
            return
        }
        guard appState.isLoggedIn else {
            needsLogin = true
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let response = try await appState.submitOrder(platform: platform, mpesaCode: code)
            placedSubscriptionId = response.subscription_id
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

#Preview {
    CheckoutView(platform: Platform.bundled[1])
        .environmentObject(AppState())
}
