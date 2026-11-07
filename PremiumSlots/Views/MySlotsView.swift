import SwiftUI

struct MySlotsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showAuth = false
    @State private var vault = ""
    @State private var vaultError = ""
    @State private var isRevealingVault = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !appState.isLoggedIn {
                        loginGate
                    } else if appState.liveSubscriptions.isEmpty {
                        emptyState
                    } else {
                        ForEach(appState.liveSubscriptions) { sub in
                            liveSlotCard(sub)
                        }
                        if let balance = appState.walletBalance {
                            Text("Wallet balance: KES \(balance)")
                                .font(.psCaption)
                                .foregroundStyle(.psMuted)
                        }
                    }

                    if !appState.orders.isEmpty {
                        Text("Saved on this device")
                            .font(.psHeadline)
                        ForEach(appState.orders) { order in
                            orderRow(order)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.psObsidian)
            .navigationTitle("My Slots")
            .navigationBarTitleDisplayMode(.inline)
            .task { await appState.refreshMySubscriptions() }
            .sheet(isPresented: $showAuth) { AuthView() }
            .alert("Vault", isPresented: Binding(
                get: { !vault.isEmpty || !vaultError.isEmpty },
                set: { if !$0 { vault = ""; vaultError = "" } }
            )) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(vaultError.isEmpty ? vault : vaultError)
            }
        }
    }

    private var loginGate: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sign in to see your slots")
                .font(.psTitle)
            Text("Your subscriptions live on your PremiumSlots account, not on this phone. Sign in to load them from premiumslots.tech.")
                .font(.psBody)
                .foregroundStyle(.psMuted)
            Button("Sign in") { showAuth = true }
                .psPrimary()
        }
        .padding(14)
        .background(Color.psSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No slots yet")
                .font(.psTitle)
            Text("Slots you buy on premiumslots.tech appear here once your M-PESA code is verified. Pending orders show here too.")
                .font(.psBody)
                .foregroundStyle(.psMuted)
            Text("Tip: log in on the site first, then pull to refresh here.")
                .font(.psCaption)
                .foregroundStyle(.psMuted)
        }
        .padding(14)
        .background(Color.psSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func liveSlotCard(_ sub: LiveSubscription) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(sub.serviceRequested)
                        .font(.psHeadline)
                    Text("Order #\(sub.id) · KES \(sub.amountDue)")
                        .font(.psCaption)
                        .foregroundStyle(.psMuted)
                }
                Spacer()
                Label(sub.orderStatus.rawValue, systemImage: sub.orderStatus.systemImage)
                    .font(.psCaption)
                    .foregroundStyle(sub.orderStatus == .active ? .green : .psAmber)
            }
            if let days = sub.daysLeft, sub.status == "Approved" {
                Text(days >= 0 ? "\(days) days left" : "Expired")
                    .font(.psCaption)
                    .foregroundStyle(.psMuted)
            }
            if sub.status == "Approved" {
                HStack(spacing: 10) {
                    Button {
                        Task { await revealVault(for: sub) }
                    } label: {
                        if isRevealingVault {
                            ProgressView()
                        } else {
                            Label("Show vault details", systemImage: "lock.shield.fill")
                                .font(.psCaption)
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(.psCyan)
                    .disabled(isRevealingVault)
                    Button {
                        Task { try? await appState.api.reportIssue(subscriptionId: sub.id) }
                    } label: {
                        Label("Report an issue", systemImage: "exclamationmark.circle")
                            .font(.psCaption)
                    }
                    .buttonStyle(.bordered)
                }
            } else if sub.status == "Pending" {
                Text("Your M-PESA code is waiting to be verified by the team.")
                    .font(.psCaption)
                    .foregroundStyle(.psMuted)
            }
        }
        .padding(14)
        .background(Color.psSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func orderRow(_ order: SlotOrder) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(order.platformName)
                    .font(.psHeadline)
                Text("KES \(order.amountKES) · \(order.mpesaCode)")
                    .font(.psCaption)
                    .foregroundStyle(.psMuted)
            }
            Spacer()
            Label(order.status.rawValue, systemImage: order.status.systemImage)
                .font(.psCaption)
                .foregroundStyle(order.status == .active ? .green : .psAmber)
        }
        .padding(14)
        .background(Color.psSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func revealVault(for sub: LiveSubscription) async {
        isRevealingVault = true
        defer { isRevealingVault = false }
        do {
            let response = try await appState.api.vault(subscriptionId: sub.id)
            guard response.ok else {
                vaultError = response.error ?? "Vault details are not available for this order."
                return
            }
            if response.revealed == true, let email = response.vault_email,
               let password = response.vault_password {
                vault = "Email: \(email)\nPassword: \(password)\nThis is shown once only, then hidden."
            } else {
                vault = response.message ?? "Vault details were not revealed. Try again."
            }
        } catch {
            vaultError = error.localizedDescription
        }
    }
}

#Preview {
    MySlotsView()
        .environmentObject(AppState())
}
