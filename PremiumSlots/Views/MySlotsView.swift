import SwiftUI

struct MySlotsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Your vault")
                        .font(.psTitle)
                    Text("Slots you have reserved appear here. Demo state is labelled clearly until a real backend is connected.")
                        .font(.psBody)
                        .foregroundStyle(.psMuted)

                    if appState.orders.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "lock.shield")
                                .font(.system(size: 44))
                                .foregroundStyle(.psCyan)
                            Text("No slots yet")
                                .font(.psHeadline)
                            Text("Browse the catalogue, reserve a slot, and submit your M-PESA code. Your slot will appear here as Pending verification, then Active.")
                                .font(.psBody)
                                .foregroundStyle(.psMuted)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                    } else {
                        ForEach(appState.orders) { order in
                            orderCard(order)
                        }
                    }

                    if !appState.waitlist.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Waitlist")
                                .font(.psHeadline)
                            ForEach(Array(appState.waitlist), id: \.self) { id in
                                if let platform = appState.platform(id: id) {
                                    HStack {
                                        Image(systemName: "bell.fill")
                                            .foregroundStyle(.psCyan)
                                        Text(platform.name)
                                        Spacer()
                                        Button("Leave") {
                                            appState.leaveWaitlist(platformId: id)
                                        }
                                        .font(.psCaption)
                                    }
                                    .font(.psBody)
                                }
                            }
                        }
                        .padding(16)
                        .background(Color.psSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                    }

                    Text("Demo note: orders in this build are stored only on this device. They are not a live purchase and no money moves in the app.")
                        .font(.psCaption)
                        .foregroundStyle(.psMuted)
                }
                .padding()
            }
            .background(Color.psObsidian)
            .navigationTitle("My Slots")
        }
    }

    private func orderCard(_ order: SlotOrder) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(order.platformName)
                        .font(.psHeadline)
                    Text("KES \(order.amountKES) · Code \(order.mpesaCode)")
                        .font(.psCaption)
                        .foregroundStyle(.psMuted)
                    Text(order.createdAt, style: .date)
                        .font(.psCaption)
                        .foregroundStyle(.psMuted)
                }
                Spacer()
                Label(order.status.rawValue, systemImage: order.status.systemImage)
                    .font(.psCaption)
                    .foregroundStyle(statusColour(order.status))
            }
            if order.status == .active {
                Text("Vault details would appear here once the backend confirms this order.")
                    .font(.psCaption)
                    .foregroundStyle(.psMuted)
            } else if order.status == .pendingVerification {
                Text("Waiting for the PremiumSlots team to verify your M-PESA code.")
                    .font(.psCaption)
                    .foregroundStyle(.psMuted)
            }
            if order.status != .active {
                Button("Mark as active (demo)") {
                    appState.updateOrderStatus(id: order.id, status: .active)
                }
                .font(.psCaption)
            }
        }
        .padding(16)
        .background(Color.psSurface)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func statusColour(_ status: OrderStatus) -> Color {
        switch status {
        case .pendingVerification: return .psAmber
        case .active: return .green
        case .issue: return .red
        }
    }
}

#Preview {
    MySlotsView()
        .environmentObject(AppState())
}
