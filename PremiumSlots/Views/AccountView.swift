import SwiftUI

// MARK: - Account, Fix #4
// Checklist 1.10: profile update (PUT /api/v1/me/profile, name +
// WhatsApp, both required), change password (POST /api/v1/me/password,
// strong-password rule 8+ chars with upper + lower + digit), privacy
// and notification toggles (PUT /api/v1/me/privacy), sessions list +
// revoke (existing APISession type and APIClient.mySessions /
// revokeSession), security screen, delete account (DELETE /api/v1/me
// with {"confirm": true}, signs out after), GDPR consent
// (GET/POST /api/v1/me/gdpr-consent) and export request
// (POST /api/v1/me/export-request).
// Passkeys: the WebAuthn JSON endpoints were not built, so passkeys
// are not available in this build. The security screen says so
// plainly and does not fake a passkey flow.
// No NavigationStack here: this view is pushed from Settings, so it
// uses the parent stack. No emojis, SF Symbols only.

struct AccountRootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        List {
            Section("Account") {
                if let user = appState.user {
                    HStack {
                        Text(user.name)
                            .font(.psHeadline)
                        Spacer()
                        Text(user.email)
                            .font(.psCaption)
                            .foregroundStyle(.psMuted)
                            .lineLimit(1)
                    }
                    .accessibilityLabel("Signed in as \(user.name), \(user.email)")
                }
                NavigationLink {
                    AccProfileView()
                } label: {
                    Label("Profile", systemImage: "person.fill")
                        .font(.psBody)
                }
                NavigationLink {
                    AccPasswordView()
                } label: {
                    Label("Change password", systemImage: "key.fill")
                        .font(.psBody)
                }
                NavigationLink {
                    AccPrivacyView()
                } label: {
                    Label("Privacy and notifications", systemImage: "bell.fill")
                        .font(.psBody)
                }
            }

            Section("Security") {
                NavigationLink {
                    AccSessionsView()
                } label: {
                    Label("Sessions", systemImage: "desktopcomputer")
                        .font(.psBody)
                }
                NavigationLink {
                    AccSecurityView()
                } label: {
                    Label("Security", systemImage: "lock.shield.fill")
                        .font(.psBody)
                }
            }

            Section("Your data") {
                NavigationLink {
                    AccGDPRView()
                } label: {
                    Label("Data and privacy", systemImage: "doc.text.fill")
                        .font(.psBody)
                }
                NavigationLink {
                    PrivacyView()
                } label: {
                    Label("Privacy policy", systemImage: "hand.raised.fill")
                        .font(.psBody)
                }
                NavigationLink {
                    TermsView()
                } label: {
                    Label("Terms of service", systemImage: "doc.plaintext.fill")
                        .font(.psBody)
                }
            }

            Section("Danger zone") {
                NavigationLink {
                    AccDeleteView()
                } label: {
                    Label("Delete account", systemImage: "trash.fill")
                        .font(.psBody)
                        .foregroundStyle(.psDanger)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.psBackground)
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaPadding(.bottom, 8)
    }
}

// MARK: - Profile

struct AccProfileView: View {
    @EnvironmentObject private var appState: AppState
    @State private var name = ""
    @State private var whatsapp = ""
    @State private var resultMessage: String?
    @State private var isSaving = false

    var body: some View {
        Form {
            Section {
                TextField("Full name", text: $name)
                    .psTextField()
                    .accessibilityLabel("Full name")
                TextField("WhatsApp number", text: $whatsapp)
                    .psTextField()
                    .keyboardType(.phonePad)
                    .accessibilityLabel("WhatsApp number")
                Text("Both fields are required.")
                    .font(.psCaption)
                    .foregroundStyle(.psMuted)
            } header: {
                Text("Profile")
            }
            Section {
                Button {
                    Task { await save() }
                } label: {
                    if isSaving { PSRingSpinner(diameter: 20, lineWidth: 2, color: .white, duration: 0.7) }
                    else { Text("Save profile") }
                }
                .psPrimary()
                .disabled(isSaving)
                if let resultMessage {
                    Text(resultMessage)
                        .font(.psCaption)
                        .foregroundStyle(.psMuted)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.psBackground)
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            name = appState.user?.name ?? ""
            whatsapp = appState.user?.whatsapp_number ?? ""
        }
    }

    private func save() async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedWhatsApp = whatsapp.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedWhatsApp.isEmpty else {
            resultMessage = "Name and WhatsApp number are both required."
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            let _: APIResponse = try await APIClient.shared.putOK(
                "api/v1/me/profile",
                body: ["name": trimmedName, "whatsapp_number": trimmedWhatsApp])
            resultMessage = "Profile saved."
            await appState.refreshMe()
        } catch {
            resultMessage = error.localizedDescription
        }
    }
}

// MARK: - Change password

struct AccPasswordView: View {
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var resultMessage: String?
    @State private var isSaving = false

    private var isStrong: Bool {
        newPassword.count >= 8
            && newPassword.contains(where: { $0.isUppercase })
            && newPassword.contains(where: { $0.isLowercase })
            && newPassword.contains(where: { $0.isNumber })
    }

    var body: some View {
        Form {
            Section {
                SecureField("Current password", text: $currentPassword)
                    .psTextField()
                    .accessibilityLabel("Current password")
                SecureField("New password", text: $newPassword)
                    .psTextField()
                    .accessibilityLabel("New password")
                VStack(alignment: .leading, spacing: 4) {
                    Label("Strong password rule", systemImage: "key.fill")
                        .font(.psHeadline)
                    Text("At least 8 characters, with an upper-case letter, a lower-case letter and a number.")
                        .font(.psBody)
                        .foregroundStyle(.psMuted)
                    HStack(spacing: 6) {
                        Image(systemName: isStrong ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isStrong ? .psSuccess : .psMuted)
                            .accessibilityHidden(true)
                        Text(isStrong ? "New password meets the rule." : "New password does not meet the rule yet.")
                            .font(.psCaption)
                            .foregroundStyle(.psMuted)
                    }
                }
            } header: {
                Text("Change password")
            }
            Section {
                Button {
                    Task { await save() }
                } label: {
                    if isSaving { PSRingSpinner(diameter: 20, lineWidth: 2, color: .white, duration: 0.7) }
                    else { Text("Change password") }
                }
                .psPrimary()
                .disabled(isSaving || !isStrong)
                if let resultMessage {
                    Text(resultMessage)
                        .font(.psCaption)
                        .foregroundStyle(.psMuted)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.psBackground)
        .navigationTitle("Password")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func save() async {
        guard !currentPassword.isEmpty else {
            resultMessage = "Enter your current password."
            return
        }
        guard isStrong else {
            resultMessage = "The new password must be 8+ characters, with upper and lower case and a number."
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            let _: APIResponse = try await APIClient.shared.fetchOK(
                "api/v1/me/password",
                body: ["current_password": currentPassword, "new_password": newPassword])
            resultMessage = "Password changed."
            currentPassword = ""
            newPassword = ""
        } catch {
            resultMessage = error.localizedDescription
        }
    }
}

// MARK: - Privacy and notification toggles

struct AccPrivacyView: View {
    @State private var emailNotifications = true
    @State private var whatsappNotifications = true
    @State private var resultMessage: String?
    @State private var isSaving = false

    var body: some View {
        Form {
            Section {
                Toggle("Email notifications", isOn: $emailNotifications)
                    .tint(.psCyan)
                    .accessibilityLabel("Email notifications")
                    .onChange(of: emailNotifications) { _, _ in Task { await save() } }
                Toggle("WhatsApp notifications", isOn: $whatsappNotifications)
                    .tint(.psCyan)
                    .accessibilityLabel("WhatsApp notifications")
                    .onChange(of: whatsappNotifications) { _, _ in Task { await save() } }
                if isSaving {
                    HStack {
                        PSRingSpinner(diameter: 18, lineWidth: 2)
                        Text("Saving...")
                            .font(.psCaption)
                            .foregroundStyle(.psMuted)
                    }
                }
                if let resultMessage {
                    Text(resultMessage)
                        .font(.psCaption)
                        .foregroundStyle(.psMuted)
                }
            } header: {
                Text("Privacy and notifications")
            } footer: {
                Text("These are the same notification settings as on premiumslots.tech. Turning them off stops order and renewal messages on that channel.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.psBackground)
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let _: APIResponse = try await APIClient.shared.putOK(
                "api/v1/me/privacy",
                body: ["receive_email_notifications": emailNotifications,
                       "receive_whatsapp_notifications": whatsappNotifications])
            resultMessage = "Notification settings saved."
        } catch {
            resultMessage = error.localizedDescription
        }
    }
}

// MARK: - Sessions

struct AccSessionsView: View {
    @State private var sessions: [APISession] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var actionMessage: String?

    var body: some View {
        List {
            if let loadError {
                PSErrorState(message: loadError) {
                    Task { await load() }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else if isLoading && sessions.isEmpty {
                HStack {
                    Spacer()
                    PSRingSpinner(diameter: 28, lineWidth: 3)
                    Spacer()
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else if sessions.isEmpty {
                PSEmptyState(
                    systemImage: "desktopcomputer",
                    title: "No sessions",
                    body: "No signed-in sessions were found for this account."
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                Section("Signed-in sessions") {
                    ForEach(sessions) { session in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(session.device ?? "Unknown device")
                                    .font(.psHeadline)
                                Spacer()
                                if session.revoked_at != nil {
                                    PSStatusPill(text: "Revoked", systemImage: "xmark.circle.fill", tint: .psDanger)
                                }
                            }
                            if let ip = session.ip_address {
                                Text("IP \(ip)")
                                    .font(.psCaption)
                                    .foregroundStyle(.psMuted)
                            }
                            if let signedIn = session.signed_in_at {
                                Text("Signed in \(signedIn)")
                                    .font(.psCaption)
                                    .foregroundStyle(.psMuted)
                            }
                            if let lastSeen = session.last_seen_at {
                                Text("Last seen \(lastSeen)")
                                    .font(.psCaption)
                                    .foregroundStyle(.psMuted)
                            }
                            if session.revoked_at == nil {
                                Button("Revoke this session", role: .destructive) {
                                    Task { await revoke(session) }
                                }
                                .font(.psBody)
                                .accessibilityLabel("Revoke session on \(session.device ?? "unknown device")")
                            }
                        }
                    }
                }
                Section {
                    Text("At most 3 sessions per account. A sign-in from a new IP raises a New Login Detected notification.")
                        .font(.psCaption)
                        .foregroundStyle(.psMuted)
                }
            }
            if let actionMessage {
                Section {
                    Text(actionMessage)
                        .font(.psCaption)
                        .foregroundStyle(.psMuted)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.psBackground)
        .navigationTitle("Sessions")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .safeAreaPadding(.bottom, 8)
    }

    private func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            sessions = try await APIClient.shared.mySessions()
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func revoke(_ session: APISession) async {
        do {
            try await APIClient.shared.revokeSession(sessionId: session.id)
            actionMessage = "Session revoked."
            await load()
        } catch {
            actionMessage = error.localizedDescription
        }
    }
}

// MARK: - Security (passkeys honestly unavailable)

struct AccSecurityView: View {
    var body: some View {
        List {
            Section("Passkeys") {
                Text("Passkeys are not available in this build.")
                    .font(.psHeadline)
                Text("The WebAuthn JSON endpoints were not built on the server, so there is no passkey sign-in to set up here. Sign in stays with your password and your Clerk session.")
                    .font(.psBody)
                    .foregroundStyle(.psMuted)
            }
            Section("Password and sessions") {
                NavigationLink {
                    AccPasswordView()
                } label: {
                    Label("Change password", systemImage: "key.fill")
                        .font(.psBody)
                }
                NavigationLink {
                    AccSessionsView()
                } label: {
                    Label("Sessions", systemImage: "desktopcomputer")
                        .font(.psBody)
                }
            }
            Section {
                Text("Sign-out clears both the PremiumSlots session and the Clerk session.")
                    .font(.psCaption)
                    .foregroundStyle(.psMuted)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.psBackground)
        .navigationTitle("Security")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaPadding(.bottom, 8)
    }
}

// MARK: - Delete account

struct AccDeleteView: View {
    @EnvironmentObject private var appState: AppState
    @State private var confirmText = ""
    @State private var resultMessage: String?
    @State private var isDeleting = false
    @State private var showConfirm = false

    var body: some View {
        Form {
            Section {
                Text("Deleting your account is permanent. Your subscriptions, wallet history and saved details are removed. This cannot be undone.")
                    .font(.psBody)
                    .foregroundStyle(.psMuted)
                TextField("Type DELETE to confirm", text: $confirmText)
                    .psTextField()
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Type DELETE to confirm account deletion")
            } header: {
                Text("Delete account")
            }
            Section {
                Button("Delete my account", role: .destructive) {
                    showConfirm = true
                }
                .disabled(confirmText.trimmingCharacters(in: .whitespacesAndNewlines) != "DELETE" || isDeleting)
                .accessibilityLabel("Delete my account")
                if let resultMessage {
                    Text(resultMessage)
                        .font(.psCaption)
                        .foregroundStyle(.psMuted)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.psBackground)
        .navigationTitle("Delete account")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Delete your account?", isPresented: $showConfirm) {
            Button("Delete", role: .destructive) {
                Task { await deleteAccount() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This is permanent. Your account and its data will be removed.")
        }
    }

    private func deleteAccount() async {
        isDeleting = true
        defer { isDeleting = false }
        do {
            let _: APIResponse = try await APIClient.shared.fetchJSON(
                "api/v1/me", method: "DELETE", body: ["confirm": true])
            await appState.logout()
        } catch {
            resultMessage = error.localizedDescription
        }
    }
}

// MARK: - GDPR consent and data export

struct AccGDPRView: View {
    @State private var consented = false
    @State private var marketing = false
    @State private var analytics = false
    @State private var isLoading = false
    @State private var resultMessage: String?
    @State private var isSaving = false
    @State private var isRequestingExport = false

    var body: some View {
        Form {
            Section {
                if isLoading {
                    HStack {
                        Spacer()
                        PSRingSpinner(diameter: 28, lineWidth: 3)
                        Spacer()
                    }
                } else {
                    Toggle("I consent to my data being used to run my account", isOn: $consented)
                        .tint(.psCyan)
                        .accessibilityLabel("Consent to data use for my account")
                    Toggle("Marketing messages", isOn: $marketing)
                        .tint(.psCyan)
                        .accessibilityLabel("Marketing messages consent")
                    Toggle("Analytics", isOn: $analytics)
                        .tint(.psCyan)
                        .accessibilityLabel("Analytics consent")
                    Button {
                        Task { await saveConsent() }
                    } label: {
                        if isSaving { PSRingSpinner(diameter: 20, lineWidth: 2, color: .white, duration: 0.7) }
                        else { Text("Save consent") }
                    }
                    .psPrimary()
                    .disabled(isSaving)
                }
            } header: {
                Text("GDPR consent")
            }
            Section {
                Text("Ask for a copy of the data PremiumSlots holds about you. The request is recorded and handled by the team.")
                    .font(.psBody)
                    .foregroundStyle(.psMuted)
                Button {
                    Task { await requestExport() }
                } label: {
                    if isRequestingExport { PSRingSpinner(diameter: 20, lineWidth: 2, color: .white, duration: 0.7) }
                    else { Label("Request my data export", systemImage: "square.and.arrow.down.fill") }
                }
                .psPrimary()
                .disabled(isRequestingExport)
            } header: {
                Text("Data export")
            }
            if let resultMessage {
                Section {
                    Text(resultMessage)
                        .font(.psCaption)
                        .foregroundStyle(.psMuted)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.psBackground)
        .navigationTitle("Data and privacy")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let response: AccGDPRResponse = try await APIClient.shared.fetchJSON("api/v1/me/gdpr-consent")
            if let consent = response.consent {
                consented = consent.consented ?? false
                marketing = consent.marketing ?? false
                analytics = consent.analytics ?? false
            }
        } catch {
            resultMessage = error.localizedDescription
        }
    }

    private func saveConsent() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let _: APIResponse = try await APIClient.shared.fetchJSON(
                "api/v1/me/gdpr-consent", method: "POST",
                body: ["consented": consented, "marketing": marketing, "analytics": analytics])
            resultMessage = "Consent saved."
        } catch {
            resultMessage = error.localizedDescription
        }
    }

    private func requestExport() async {
        isRequestingExport = true
        defer { isRequestingExport = false }
        do {
            let _: APIResponse = try await APIClient.shared.fetchJSON(
                "api/v1/me/export-request", method: "POST", body: [:])
            resultMessage = "Your data export request was recorded."
        } catch {
            resultMessage = error.localizedDescription
        }
    }
}

// MARK: - GDPR response types (keys from backend/api_v1.py)

struct AccGDPRConsent: Decodable {
    let consented: Bool?
    let marketing: Bool?
    let analytics: Bool?
    let created_at: String?
}

struct AccGDPRResponse: Decodable {
    let ok: Bool
    let consent: AccGDPRConsent?
}

#Preview {
    NavigationStack {
        AccountRootView()
            .environmentObject(AppState())
    }
}
