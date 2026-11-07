import SwiftUI

// MARK: - How it works, v3 Fix #3
// HIG pass: inset-grouped List, numbered steps with consistent
// spacing, shared card styling, safe-area padding.

struct HowItWorksView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("PremiumSlots sells slots on shared subscriptions. You pay by M-PESA, your code is verified, and you get your own profile on the account through an encrypted vault.")
                        .font(.psBody)
                        .foregroundStyle(.psMuted)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } header: {
                    Text("How it works")
                }

                Section("Steps") {
                    stepRow(number: "1", title: "Pick a platform",
                            text: "Choose a platform from the catalogue and check the price and slots left.")
                    stepRow(number: "2", title: "Pay by M-PESA",
                            text: "Send the exact amount to PayBill 400200, account 1192526. Keep the transaction code from your confirmation message.")
                    stepRow(number: "3", title: "Submit your code",
                            text: "Enter the 10-letter-and-number M-PESA code in checkout. The team verifies it and approves your slot.")
                    stepRow(number: "4", title: "Get your details",
                            text: "Your vault details appear in My Slots once your order is Active. 1 slot = 1 device, so use it on your own device only.")
                }

                Section("Good to know") {
                    ruleRow(icon: "lock.shield.fill", text: "Your login details are stored in an encrypted vault. They are revealed once only.")
                    ruleRow(icon: "person.fill", text: "Never change the account password or email. Report any issue from My Slots.")
                    ruleRow(icon: "arrow.clockwise", text: "Renew before your slot expires to keep the same profile.")
                }

                Section {
                    Text("Support: WhatsApp +254 799 242 459 · premiumslots.tech")
                        .font(.psCaption)
                        .foregroundStyle(.psMuted)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.psBackground)
            .navigationTitle("How it works")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaPadding(.bottom, 8)
        }
    }

    private func stepRow(number: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.psCyan)
                .frame(width: 32, height: 32)
                .background(Color.psPrimarySoft)
                .clipShape(Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.psHeadline)
                Text(text)
                    .font(.psBody)
                    .foregroundStyle(.psMuted)
            }
        }
        .psTouchTarget()
    }

    private func ruleRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(.psCyan)
                .frame(width: 22)
                .accessibilityHidden(true)
            Text(text)
                .font(.psBody)
        }
        .psTouchTarget()
    }
}

#Preview {
    HowItWorksView()
}
