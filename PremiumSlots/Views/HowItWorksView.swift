import SwiftUI

struct HowItWorksView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("How PremiumSlots works")
                        .font(.psTitle)
                    Text("A shared-subscription platform. You buy one slot on a shared account, for one device, instead of paying for a full plan on your own.")
                        .font(.psBody)
                        .foregroundStyle(.psMuted)

                    step(number: 1, icon: "person.crop.circle.badge.plus", title: "Create an account", text: "Sign up on premiumslots.tech, or in this app once accounts are connected.")
                    step(number: 2, icon: "creditcard.fill", title: "Pay by M-PESA", text: "Choose a platform, then send the exact amount by M-PESA.")
                    step(number: 3, icon: "number", title: "Submit your code", text: "Enter the M-PESA transaction code from your confirmation message.")
                    step(number: 4, icon: "lock.shield.fill", title: "Get instant access", text: "Once verified, your vault details appear in My Slots. 1 slot = 1 device.")

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Good to know")
                            .font(.psHeadline)
                        rule(icon: "iphone", text: "1 slot = 1 device. Do not share your slot with another device.")
                        rule(icon: "person.fill", text: "Do not change the account password or email. Your own profile is provided.")
                        rule(icon: "clock.fill", text: "Slots run for the period shown on each platform, for example 1 month or 12 months for Gemini Plus.")
                        rule(icon: "questionmark.circle.fill", text: "If a slot has a problem, open it in My Slots and flag it as needing attention.")
                    }
                    .padding(16)
                    .background(Color.psSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 18))

                    Text("\(Platform.bundled.count) platforms · \(Platform.liveTotalSlotsOnHomepage) slots in rotation · \(Platform.communitySuggestions) community suggestions, as shown on the homepage on \(Platform.homepageCheckedDate).")
                        .font(.psCaption)
                        .foregroundStyle(.psMuted)
                }
                .padding()
            }
            .background(Color.psObsidian)
            .navigationTitle("How it works")
        }
    }

    private func step(number: Int, icon: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.psElectricBlue.opacity(0.18))
                    .frame(width: 48, height: 48)
                Image(systemName: icon)
                    .foregroundStyle(.psCyan)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Step \(number): \(title)")
                    .font(.psHeadline)
                Text(text)
                    .font(.psBody)
                    .foregroundStyle(.psMuted)
            }
        }
    }

    private func rule(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.psCyan)
                .frame(width: 22)
            Text(text)
                .font(.psBody)
        }
    }
}

#Preview {
    HowItWorksView()
}
