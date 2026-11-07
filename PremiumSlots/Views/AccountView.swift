import SwiftUI

// MARK: - Account, Fix #4, v5
// Checklist 1.10: profile update (PUT /api/v1/me/profile, name +
// WhatsApp, both required), change password (POST /api/v1/me/password,
// strong-password rule 8+ chars with upper + lower + digit), privacy
// and notification toggles (PUT /api/v1/me/privacy), sessions list +
// revoke (existing APISession type and APIClient.mySessions /
// revokeSession), security screen, delete account (DELETE /api/v1/me
// with {"confirm": true}, signs out after), GDPR consent
// (GET/POST /api/v1/me/gdpr-consent, four types data_processing,
// marketing, analytics, communications, each defaulting to granted)
// and data export (GET /api/v1/me/export when the server offers it,
// else POST /api/v1/me/export-request).
// Passkeys (v5): native sign-in and management in PasskeyAuth.swift.
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
                    FullPrivacyPolicyView()
                } label: {
                    Label("Privacy policy", systemImage: "hand.raised.fill")
                        .font(.psBody)
                }
                NavigationLink {
                    FullTermsView()
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
        .scrollContentBackground(.hidden)
        .background(Color.psBackground)
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .scrollIndicators(.hidden)
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
        .scrollDismissesKeyboard(.interactively)
        .scrollIndicators(.hidden)
        .hideKeyboardOnTap()
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
        .scrollDismissesKeyboard(.interactively)
        .scrollIndicators(.hidden)
        .hideKeyboardOnTap()
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
                Text("These are the same notification settings as on the PremiumSlots website. Turning them off stops order and renewal messages on that channel.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.psBackground)
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .scrollIndicators(.hidden)
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
        .scrollIndicators(.hidden)
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

// MARK: - Security (passkeys, v5)

struct AccSecurityView: View {
    var body: some View {
        List {
            Section("Passkeys") {
                NavigationLink {
                    PasskeyManagementView()
                } label: {
                    Label("Passkeys", systemImage: "key.fill")
                        .font(.psBody)
                }
                if let storedID = PasskeyAuthManager.storedCredentialID {
                    Text("This device has a passkey (credential \(storedID.prefix(12))...).")
                        .font(.psCaption)
                        .foregroundStyle(.psMuted)
                } else {
                    Text("No passkey on this device yet. Add one to sign in without your password.")
                        .font(.psBody)
                        .foregroundStyle(.psMuted)
                }
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
        .scrollIndicators(.hidden)
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
        .scrollDismissesKeyboard(.interactively)
        .scrollIndicators(.hidden)
        .hideKeyboardOnTap()
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

// MARK: - GDPR consent and data export, v5
// Four consent types from GET /api/v1/me/gdpr-consent, each a
// {granted, granted_at, revoked_at} entry defaulting to granted.
// data_processing is REQUIRED: the privacy policy says data is used
// strictly for operational purposes (verifying payments, fulfilling
// subscription slots, sending account notifications, verification
// codes, password resets and renewal reminders), so turning it off
// means the account cannot run. Turning it off shows a clear
// message first, and a saved off state shows a banner with a
// one-tap way back on. There is no silent lockout and no dead end:
// the same screen always lets the user re-enable it.
// marketing, analytics and communications are optional and can be
// turned off freely.
// Export: GET /api/v1/me/export when the server offers it (the
// backend agent is adding it); the real file is then shared with
// the iOS share sheet (AdminShareSheet wraps
// UIActivityViewController) and an empty file is never presented.
// NOTE: the web has no download endpoint and no file format at all
// (SOURCES.md section 11): the web export is a request workflow
// only (DataExportRequests, pending to processing, nothing ever
// generates a file). So GET /api/v1/me/export must generate the
// file itself from the real tables; there is no web file to mirror.
// Until that endpoint exists, POST /api/v1/me/export-request
// records the request and the app says so, with the request id.

struct AccGDPRView: View {
    @State private var dataProcessing = true
    @State private var marketing = true
    @State private var analytics = true
    @State private var communications = true
    @State private var isLoading = false
    @State private var resultMessage: String?
    @State private var isSaving = false
    @State private var showRequiredAlert = false
    @State private var savedDataProcessingOff = false
    @State private var isExporting = false
    @State private var exportFileURL: URL?
    @State private var exportMessage: String?
    @State private var showExportShare = false

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
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Data processing", isOn: $dataProcessing)
                            .tint(.psCyan)
                            .accessibilityLabel("Data processing consent, required")
                            .onChange(of: dataProcessing) { _, newValue in
                                if !newValue { showRequiredAlert = true }
                            }
                        Text("Required to run your account: verifying payments, fulfilling subscription slots, and sending account notifications, verification codes, password resets and renewal reminders.")
                            .font(.psCaption)
                            .foregroundStyle(.psMuted)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Marketing messages", isOn: $marketing)
                            .tint(.psCyan)
                            .accessibilityLabel("Marketing messages consent")
                        Text("Offers and news about PremiumSlots. Optional.")
                            .font(.psCaption)
                            .foregroundStyle(.psMuted)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Analytics", isOn: $analytics)
                            .tint(.psCyan)
                            .accessibilityLabel("Analytics consent")
                        Text("Usage data used to improve PremiumSlots. Optional.")
                            .font(.psCaption)
                            .foregroundStyle(.psMuted)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Account communications", isOn: $communications)
                            .tint(.psCyan)
                            .accessibilityLabel("Account communications consent")
                        Text("Account messages by email and WhatsApp. Optional.")
                            .font(.psCaption)
                            .foregroundStyle(.psMuted)
                    }
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
            } footer: {
                Text("All four start on. Only data processing is required; the other three can be turned off at any time.")
            }
            if savedDataProcessingOff {
                Section {
                    Label("Data processing is off", systemImage: "exclamationmark.triangle.fill")
                        .font(.psHeadline)
                        .foregroundStyle(.psWarning)
                    Text("PremiumSlots cannot run your account without it: payments cannot be verified and slots cannot be delivered. Turn it back on to use your account again.")
                        .font(.psBody)
                        .foregroundStyle(.psMuted)
                    Button("Turn data processing back on") {
                        dataProcessing = true
                        Task { await saveConsent() }
                    }
                    .psPrimary()
                    .disabled(isSaving)
                }
            }
            Section {
                Text("Download a copy of the data PremiumSlots holds about you. The file opens in the share sheet so you can save it or send it where you like.")
                    .font(.psBody)
                    .foregroundStyle(.psMuted)
                Button {
                    Task { await fetchExport() }
                } label: {
                    if isExporting { PSRingSpinner(diameter: 20, lineWidth: 2, color: .white, duration: 0.7) }
                    else { Label("Download my data export", systemImage: "square.and.arrow.down.fill") }
                }
                .psPrimary()
                .disabled(isExporting)
                if let exportMessage {
                    Text(exportMessage)
                        .font(.psCaption)
                        .foregroundStyle(.psMuted)
                }
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
        .scrollDismissesKeyboard(.interactively)
        .scrollIndicators(.hidden)
        .task { await load() }
        .alert("Data processing is required", isPresented: $showRequiredAlert) {
            Button("Keep it on") {
                dataProcessing = true
            }
            Button("Turn it off", role: .destructive) {
                dataProcessing = false
            }
        } message: {
            Text("PremiumSlots uses your data strictly to run your account: verifying payments, fulfilling subscription slots, and sending account notifications, verification codes, password resets and renewal reminders. Without it your account cannot be used. You can turn it back on here at any time.")
        }
        .sheet(isPresented: $showExportShare) {
            if let exportFileURL {
                AdminShareSheet(urls: [exportFileURL])
            }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let response: AccGDPRMapResponse = try await APIClient.shared.fetchJSON("api/v1/me/gdpr-consent")
            if let consent = response.consent {
                dataProcessing = consent["data_processing"]?.granted ?? true
                marketing = consent["marketing"]?.granted ?? true
                analytics = consent["analytics"]?.granted ?? true
                communications = consent["communications"]?.granted ?? true
                savedDataProcessingOff = !dataProcessing
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
                body: ["consent": [
                    "data_processing": dataProcessing,
                    "marketing": marketing,
                    "analytics": analytics,
                    "communications": communications,
                ]])
            savedDataProcessingOff = !dataProcessing
            resultMessage = dataProcessing
                ? "Consent saved."
                : "Consent saved. Data processing is off, so your account cannot be used until you turn it back on above."
        } catch {
            resultMessage = error.localizedDescription
        }
    }

    private func fetchExport() async {
        isExporting = true
        exportMessage = nil
        exportFileURL = nil
        defer { isExporting = false }
        do {
            let data = try await APIClient.shared.fetchData("api/v1/me/export")
            guard !data.isEmpty else {
                exportMessage = "The export came back empty. Please try again."
                return
            }
            // There is no export file on the web at all (the web
            // export is a request workflow only), so the format is
            // whatever GET /api/v1/me/export generates from the
            // real tables. The name below is the file the share
            // sheet offers.
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("premiumslots-data-export.json")
            try data.write(to: url, options: .atomic)
            exportFileURL = url
            exportMessage = "Your data export is ready to share."
            showExportShare = true
        } catch {
            if case APIError.http(let code, _) = error, code == 404 {
                await requestExport()
            } else {
                exportMessage = error.localizedDescription
            }
        }
    }

    private func requestExport() async {
        do {
            let response: AccExportRequestResponse = try await APIClient.shared.fetchJSON(
                "api/v1/me/export-request", method: "POST", body: ["request_type": "export_all"])
            if let requestID = response.request_id {
                exportMessage = "Your data export was requested (request #\(requestID)). You will be notified when it is ready."
            } else {
                exportMessage = response.message ?? "Your data export request was recorded."
            }
        } catch {
            exportMessage = error.localizedDescription
        }
    }
}

// MARK: - GDPR response types (keys from backend/api_v1.py)

struct AccGDPRConsentEntry: Decodable {
    let granted: Bool?
    let granted_at: String?
    let revoked_at: String?
}

struct AccGDPRMapResponse: Decodable {
    let ok: Bool
    let consent: [String: AccGDPRConsentEntry]?
}

struct AccExportRequestResponse: Decodable {
    let ok: Bool
    let request_id: Int?
    let status: String?
    let message: String?
    let error: String?
}

#Preview {
    NavigationStack {
        AccountRootView()
            .environmentObject(AppState())
    }
}
