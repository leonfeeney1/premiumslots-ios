import SwiftUI

// MARK: - Admin, v2
// Gated by admin login, separate from a user login, through
// /api/v1/admin/*. Admin data only ever comes from the live API.
// When the API is unreachable the screens say so plainly and show
// nothing at all: admin data is never faked, never bundled, never
// stored on the device. No admin password is stored in the app.

struct AdminView: View {
    @EnvironmentObject private var appState: AppState
    @State private var password = ""
    @State private var errorMessage = ""
    @State private var showError = false
    @State private var isSubmitting = false
    @State private var selectedSection = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !appState.isAdminLoggedIn {
                        adminLogin
                    } else {
                        adminContent
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.psObsidian)
            .navigationTitle("Admin")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Admin sign-in failed", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .task { await appState.refreshAdmin() }
        }
    }

    // MARK: - login

    private var adminLogin: some View {
        VStack(alignment: .leading, spacing: 12) {
            RealLogoView(size: 48)
            Text("Admin sign-in")
                .font(.psTitle)
            Text("This is a separate sign-in from a customer account. It unlocks the live admin dashboard on premiumslots.tech.")
                .font(.psBody)
                .foregroundStyle(.psMuted)
            SecureField("Admin password", text: $password)
                .textContentType(.password)
                .autocorrectionDisabled()
                .font(.psBody)
                .padding(12)
                .background(Color.psSurface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.psBorder, lineWidth: 1)
                )
            Button {
                Task { await login() }
            } label: {
                if isSubmitting { ProgressView() } else { Text("Sign in as admin") }
            }
            .psPrimary()
            .disabled(isSubmitting || password.isEmpty)
            if appState.liveState != .live {
                Text("Admin needs the live API. It is not reachable right now, so sign-in will fail until the /api/v1 backend is deployed.")
                    .font(.psCaption)
                    .foregroundStyle(.psAmber)
            }
        }
    }

    // MARK: - content

    private var adminContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Admin dashboard")
                    .font(.psTitle)
                Spacer()
                Button("Sign out") {
                    Task { await appState.adminLogout() }
                }
                .font(.psCaption)
            }

            if appState.liveState != .live, appState.adminStats == nil {
                Text("Admin needs the live API. The service is not reachable right now, so no admin data is shown.")
                    .font(.psBody)
                    .foregroundStyle(.psAmber)
                    .padding(14)
                    .background(Color.psSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            if let stats = appState.adminStats {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    statCard(label: "Pending", value: stats.pending ?? 0)
                    statCard(label: "Approved", value: stats.approved ?? 0)
                    statCard(label: "Issues", value: stats.issues ?? 0)
                    statCard(label: "Users", value: stats.users ?? 0)
                    statCard(label: "Revenue (KES)", value: stats.total_revenue ?? 0)
                    statCard(label: "Slots in rotation", value: stats.slots_in_rotation ?? 0)
                }
            }

            Picker("Section", selection: $selectedSection) {
                Text("Pending").tag(0)
                Text("Subscriptions").tag(1)
                Text("Customers").tag(2)
                Text("Services").tag(3)
            }
            .pickerStyle(.segmented)

            switch selectedSection {
            case 0: pendingSection
            case 1: subscriptionsSection
            case 2: customersSection
            default: servicesSection
            }
        }
    }

    private func statCard(label: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.psCaption)
                .foregroundStyle(.psMuted)
            Text("\(value)")
                .font(.system(size: 22, weight: .semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.psSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - pending approvals

    private var pendingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if appState.adminPending.isEmpty {
                Text("No pending approvals.")
                    .font(.psBody)
                    .foregroundStyle(.psMuted)
            }
            ForEach(appState.adminPending) { sub in
                pendingCard(sub)
            }
        }
    }

    private func pendingCard(_ sub: APISubscription) -> some View {
        ApproveCard(subscription: sub, onAction: {
            Task { await appState.refreshAdmin() }
        })
    }

    // MARK: - subscriptions

    private var subscriptionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if appState.adminSubscriptions.isEmpty {
                Text("No subscriptions yet.")
                    .font(.psBody)
                    .foregroundStyle(.psMuted)
            }
            ForEach(appState.adminSubscriptions) { sub in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(sub.service_requested)
                            .font(.psHeadline)
                        Spacer()
                        Text(sub.status)
                            .font(.psCaption)
                            .foregroundStyle(sub.status == "Approved" ? .green : .psAmber)
                    }
                    Text("Order #\(sub.id) · KES \(sub.amount_due) · code \(sub.mpesa_code ?? "-")")
                        .font(.psCaption)
                        .foregroundStyle(.psMuted)
                }
                .padding(12)
                .background(Color.psSurface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // MARK: - customers

    private var customersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if appState.adminCustomers.isEmpty {
                Text("No customers yet.")
                    .font(.psBody)
                    .foregroundStyle(.psMuted)
            }
            ForEach(appState.adminCustomers) { customer in
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(customer.name)
                            .font(.psHeadline)
                        Text(customer.email)
                            .font(.psCaption)
                            .foregroundStyle(.psMuted)
                        Text("Wallet KES \(customer.wallet_balance ?? 0) · \(customer.referral_count ?? 0) referrals")
                            .font(.psCaption)
                            .foregroundStyle(.psMuted)
                    }
                    Spacer()
                    Button(customer.is_banned == true ? "Unban" : "Ban") {
                        Task {
                            _ = try? await appState.api.adminToggleBan(customerId: customer.id)
                            await appState.refreshAdmin()
                        }
                    }
                    .font(.psCaption)
                    .buttonStyle(.bordered)
                    .tint(customer.is_banned == true ? .green : .red)
                }
                .padding(12)
                .background(Color.psSurface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // MARK: - services

    private var servicesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Stock is edited here against the live Services table.")
                .font(.psCaption)
                .foregroundStyle(.psMuted)
            ForEach(appState.platforms) { platform in
                ServiceStockRow(platform: platform) {
                    Task {
                        await appState.refreshCatalogue()
                        await appState.refreshAdmin()
                    }
                }
            }
        }
    }

    private func login() async {
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await appState.adminLogin(password: password)
            password = ""
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

// MARK: - approve / reject card

struct ApproveCard: View {
    let subscription: APISubscription
    var onAction: () -> Void
    @EnvironmentObject private var appState: AppState
    @State private var vaultEmail = ""
    @State private var vaultPassword = ""
    @State private var accountGroup = "Unassigned"
    @State private var showApprove = false
    @State private var errorMessage = ""
    @State private var showError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(subscription.service_requested)
                        .font(.psHeadline)
                    Text("Order #\(subscription.id) · KES \(subscription.amount_due)")
                        .font(.psCaption)
                        .foregroundStyle(.psMuted)
                    Text("Code: \(subscription.mpesa_code ?? "-")")
                        .font(.psMono)
                }
                Spacer()
                Text(subscription.status)
                    .font(.psCaption)
                    .foregroundStyle(.psAmber)
            }
            if showApprove {
                TextField("Vault email", text: $vaultEmail)
                    .textContentType(.emailAddress)
                    .autocorrectionDisabled()
                    .font(.psBody)
                    .padding(10)
                    .background(Color.psObsidian)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                SecureField("Vault password", text: $vaultPassword)
                    .font(.psBody)
                    .padding(10)
                    .background(Color.psObsidian)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                TextField("Account group", text: $accountGroup)
                    .autocorrectionDisabled()
                    .font(.psBody)
                    .padding(10)
                    .background(Color.psObsidian)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                Button("Confirm approve") {
                    Task { await approve() }
                }
                .psPrimary()
            } else {
                HStack(spacing: 10) {
                    Button("Approve") { showApprove = true }
                        .buttonStyle(.borderedProminent)
                        .tint(.psPrimary)
                        .font(.psCaption)
                    Button("Reject", role: .destructive) {
                        Task { await reject() }
                    }
                    .buttonStyle(.bordered)
                    .font(.psCaption)
                }
            }
        }
        .padding(12)
        .background(Color.psSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .alert("Admin action failed", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    private func approve() async {
        guard !vaultEmail.isEmpty, !vaultPassword.isEmpty else {
            errorMessage = "Enter the vault email and password to deliver with this slot."
            showError = true
            return
        }
        do {
            try await appState.api.adminApprove(subscriptionId: subscription.id,
                                                vaultEmail: vaultEmail,
                                                vaultPassword: vaultPassword,
                                                accountGroup: accountGroup)
            onAction()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func reject() async {
        do {
            try await appState.api.adminReject(subscriptionId: subscription.id)
            onAction()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

// MARK: - service stock row

struct ServiceStockRow: View {
    let platform: Platform
    var onSaved: () -> Void
    @EnvironmentObject private var appState: AppState
    @State private var stockText: String
    @State private var isSaving = false

    init(platform: Platform, onSaved: @escaping () -> Void) {
        self.platform = platform
        self.onSaved = onSaved
        _stockText = State(initialValue: "\(platform.slotsLeft)")
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(platform.name)
                    .font(.psHeadline)
                Text(platform.formattedPrice)
                    .font(.psCaption)
                    .foregroundStyle(.psMuted)
            }
            Spacer()
            TextField("Stock", text: $stockText)
                .keyboardType(.numberPad)
                .font(.psBody)
                .multilineTextAlignment(.center)
                .frame(width: 56)
                .padding(8)
                .background(Color.psObsidian)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            Button("Save") {
                Task { await save() }
            }
            .font(.psCaption)
            .buttonStyle(.bordered)
            .tint(.psCyan)
            .disabled(isSaving || stockText == "\(platform.slotsLeft)")
        }
        .padding(12)
        .background(Color.psSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func save() async {
        guard let liveId = platform.liveId,
              let stock = Int(stockText), stock >= 0 else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await appState.api.adminUpdateService(id: liveId,
                                                      fields: ["inventory_count": stock])
            onSaved()
        } catch {
            // The row keeps the edited value so it can be retried.
        }
    }
}

#Preview {
    AdminView()
        .environmentObject(AppState())
}
