import SwiftUI

// MARK: - Platform detail sheet, v4 (v6: second design pass)
// Richer detail for one platform: large real logo, price,
// duration and availability as stat tiles, a low-stock or
// sold-out state banner, what-you-get benefits, the slot rules
// and the reserve or waitlist action. Stock states match the
// card: sold out, low stock (5 or fewer left) and plenty of
// stock each read differently. Full screen inside its sheet:
// the scroll content fills the sheet and the background colour
// extends to the sheet edges.

struct PlatformDetailView: View {
    let platform: Platform
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var showCheckout = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 14) {
                        PlatformLogoView(platform: platform, size: 72)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(platform.name)
                                .font(.psTitle)
                                .lineLimit(2)
                            Text(platform.tagline)
                                .font(.psBody)
                                .foregroundStyle(.psMuted)
                            if platform.isSoldOut {
                                PSStatusPill(text: "Sold out", systemImage: "xmark.circle.fill", tint: .psDanger)
                            } else if platform.slotsLeft <= 5 {
                                PSStatusPill(text: "Only \(platform.slotsLeft) left", systemImage: "exclamationmark.circle.fill", tint: .psAmber)
                            } else {
                                PSStatusPill(text: "\(platform.slotsLeft) slots left", systemImage: "checkmark.circle.fill", tint: .psSuccess)
                            }
                        }
                    }

                    HStack(spacing: 10) {
                        detailStat(label: "Price", value: platform.formattedPrice)
                        detailStat(label: "Duration", value: platform.duration)
                        detailStat(
                            label: "Availability",
                            value: platform.isSoldOut ? "Sold out" : "\(platform.slotsLeft) left"
                        )
                    }

                    if platform.isSoldOut {
                        PSCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("This platform is sold out right now.")
                                    .font(.psHeadline)
                                Text("Join the waitlist and you will be told first when a slot opens.")
                                    .font(.psBody)
                                    .foregroundStyle(.psMuted)
                                Button {
                                    if appState.waitlist.contains(platform.id) {
                                        appState.leaveWaitlist(platformId: platform.id)
                                    } else {
                                        appState.joinWaitlist(platformId: platform.id)
                                    }
                                } label: {
                                    Label(
                                        appState.waitlist.contains(platform.id) ? "On waitlist: tap to leave" : "Join waitlist",
                                        systemImage: appState.waitlist.contains(platform.id) ? "checkmark.circle.fill" : "bell.fill"
                                    )
                                }
                                .psPrimary()
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        if platform.slotsLeft <= 5 {
                            HStack(spacing: 10) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundStyle(.psAmber)
                                    .accessibilityHidden(true)
                                Text("Only \(platform.slotsLeft) slot\(platform.slotsLeft == 1 ? "" : "s") left at this price. Slots are approved in the order codes are verified.")
                                    .font(.psCaption)
                                    .foregroundStyle(.psMuted)
                            }
                            .padding(12)
                            .background(Color.psAmber.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        Button("Reserve this slot: \(platform.formattedPrice)") {
                            showCheckout = true
                        }
                        .psPrimary()
                        Text("You pay the exact amount by M-PESA first, then submit your transaction code in checkout.")
                            .font(.psCaption)
                            .foregroundStyle(.psMuted)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("What you get")
                            .font(.psHeadline)
                        benefitRow(icon: "lock.shield.fill", text: "Instant access through an encrypted vault after payment is verified.")
                        benefitRow(icon: "iphone", text: "1 slot = 1 device. Use it on your own device only.")
                        benefitRow(icon: "person.fill", text: "Your own profile on the shared account. No password or email changes.")
                        benefitRow(icon: "creditcard.fill", text: "Pay the exact amount by M-PESA, then submit your transaction code.")
                    }
                    .padding(14)
                    .background(Color.psSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Good to know")
                            .font(.psHeadline)
                        benefitRow(icon: "checkmark.seal.fill", text: "Every M-PESA code is checked by the team before a slot is approved.")
                        benefitRow(icon: "calendar", text: "Your slot runs for \(platform.duration) from approval, and the renewal date is shown in My Slots.")
                        benefitRow(icon: "message.fill", text: "Something wrong with a slot? Report it from My Slots or reach support on WhatsApp.")
                    }
                    .padding(14)
                    .background(Color.psSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                    if appState.liveState != .live {
                        Text("Showing the latest catalogue we could load.")
                            .font(.psCaption)
                            .foregroundStyle(.psMuted)
                    }
                }
                .padding(16)
                .hideKeyboardOnTap()
            }
            .scrollDismissesKeyboard(.interactively)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .psScreenBackground()
            .navigationTitle(platform.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.psBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                dismissKeyboardButton
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(isPresented: $showCheckout) {
                CheckoutView(platform: platform)
                    .psSheetDetents()
            }
        }
    }

    private func detailStat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.psCaption)
                .foregroundStyle(.psMuted)
            Text(value)
                .font(.psButton)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.psSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func benefitRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.psIcon)
                .foregroundStyle(.psCyan)
                .frame(width: 22)
            Text(text)
                .font(.psBody)
        }
    }
}

#Preview {
    PlatformDetailView(platform: Platform.bundled[1])
        .environmentObject(AppState())
}
