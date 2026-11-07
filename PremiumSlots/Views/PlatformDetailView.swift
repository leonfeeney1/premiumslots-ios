import SwiftUI

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
                        ZStack {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.psAccent(named: platform.accent).opacity(0.16))
                                .frame(width: 64, height: 64)
                            Image(systemName: platform.systemImage)
                                .font(.system(size: 24))
                                .foregroundStyle(Color.psAccent(named: platform.accent))
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(platform.name)
                                .font(.psTitle)
                                .lineLimit(2)
                            Text(platform.tagline)
                                .font(.psBody)
                                .foregroundStyle(.psMuted)
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

                    if platform.isSoldOut {
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
                    } else {
                        Button("Reserve this slot: \(platform.formattedPrice)") {
                            showCheckout = true
                        }
                        .psPrimary()
                    }

                    if appState.liveState != .live {
                        Text("Stock last verified \(Platform.stockVerifiedDate).")
                            .font(.psCaption)
                            .foregroundStyle(.psMuted)
                    }
                }
                .padding(16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.psObsidian)
            .navigationTitle(platform.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(isPresented: $showCheckout) {
                CheckoutView(platform: platform)
            }
        }
    }

    private func detailStat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.psCaption)
                .foregroundStyle(.psMuted)
            Text(value)
                .font(.system(size: 16, weight: .semibold))
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
                .font(.system(size: 20))
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
