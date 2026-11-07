import SwiftUI

struct CheckoutView: View {
    let platform: Platform
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var mpesaCode = ""
    @State private var placedOrder: SlotOrder?
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Pay by M-PESA")
                        .font(.psTitle)
                    Text("Pay the exact amount, then submit the transaction code you receive. Nothing is charged inside this app.")
                        .font(.psBody)
                        .foregroundStyle(.psMuted)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Step 1: Send the payment")
                            .font(.psHeadline)
                        paymentRow(label: "Platform", value: platform.name)
                        paymentRow(label: "Amount to send", value: platform.formattedPrice)
                        paymentRow(label: "Paybill / Till", value: "Shown on the website at checkout")
                        Text("Send exactly \(platform.formattedPrice) by M-PESA. Keep the confirmation message: it holds your transaction code.")
                            .font(.psCaption)
                            .foregroundStyle(.psMuted)
                    }
                    .padding(16)
                    .background(Color.psSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 18))

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Step 2: Submit your M-PESA code")
                            .font(.psHeadline)
                        TextField("Example: QK7X8Y9Z1A", text: $mpesaCode)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .padding(12)
                            .background(Color.psObsidian)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                            )
                        Text("The code is usually 10 characters. It is checked by the PremiumSlots team, not charged here.")
                            .font(.psCaption)
                            .foregroundStyle(.psMuted)
                    }
                    .padding(16)
                    .background(Color.psSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 18))

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Step 3: Get access")
                            .font(.psHeadline)
                        Text("Once your code is verified, your slot moves to Active in My Slots and your vault details appear there. 1 slot = 1 device.")
                            .font(.psBody)
                            .foregroundStyle(.psMuted)
                    }

                    if let order = placedOrder {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Order saved as \(order.status.rawValue)", systemImage: "clock.fill")
                                .font(.psHeadline)
                                .foregroundStyle(.psAmber)
                            Text("Your code \(order.mpesaCode) was recorded locally. This app does not move money and does not confirm payment by itself.")
                                .font(.psCaption)
                                .foregroundStyle(.psMuted)
                            Button("View in My Slots") { dismiss() }
                                .psPrimary()
                        }
                        .padding(16)
                        .background(Color.psSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                    } else {
                        Button("Submit M-PESA code") {
                            submit()
                        }
                        .psPrimary()
                        Text("No card details are collected in this app.")
                            .font(.psCaption)
                            .foregroundStyle(.psMuted)
                    }
                }
                .padding()
            }
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
        }
    }

    private func paymentRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.psMuted)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .multilineTextAlignment(.trailing)
        }
        .font(.psBody)
    }

    private func submit() {
        let code = mpesaCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard code.count >= 8, code.count <= 12,
              code.allSatisfy({ $0.isLetter || $0.isNumber }) else {
            errorMessage = "Enter the M-PESA transaction code from your confirmation message. It is usually 10 letters and numbers."
            showError = true
            return
        }
        placedOrder = appState.placeOrder(platform: platform, mpesaCode: code)
    }
}

#Preview {
    CheckoutView(platform: Platform.bundled[1])
        .environmentObject(AppState())
}
