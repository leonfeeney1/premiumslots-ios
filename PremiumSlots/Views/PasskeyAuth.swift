import SwiftUI
import AuthenticationServices

// MARK: - Passkeys, v5
// Native passkey sign-in and sign-up as an alternative to Clerk.
// The Clerk web view flow stays untouched and keeps working;
// passkeys are an addition, never a replacement.
//
// VERIFIED from the web code (app/blueprints/auth.py, fetched
// read-only from the laptop 7 Nov 2026, lines 461-780):
//   - Library: webauthn 3.x (webauthn 3.0.1 installed here to
//     confirm the wire shapes). Options are produced by
//     generate_registration_options / generate_authentication_options
//     and serialised by options_to_json.
//   - Registration options JSON: {"rp": {"name": "PremiumSlots",
//     "id": <rp id>}, "user": {"id": base64url, "name": email,
//     "displayName": name}, "challenge": base64url,
//     "pubKeyCredParams": [{"type": "public-key", "alg": -7/-8/-257}],
//     "timeout": 60000, "excludeCredentials": [{"id": base64url,
//     "type": "public-key", "transports": ["internal", ...]}],
//     "authenticatorSelection": {"residentKey": "preferred",
//     "requireResidentKey": false, "userVerification": "preferred"},
//     "attestation": "none"}
//   - Authentication options JSON: {"challenge": base64url,
//     "timeout": 60000, "rpId": <rp id>, "allowCredentials":
//     [{"id": base64url, "type": "public-key"}],
//     "userVerification": "preferred"}
//   - Registration credential JSON the server parses
//     (webauthn 3.0.1 parse_registration_credential_json): {"id",
//     "rawId", "type": "public-key", "response": {"clientDataJSON",
//     "attestationObject", "transports": [...]}} (all base64url).
//   - Authentication credential JSON the server parses
//     (parse_authentication_credential_json): {"id", "rawId",
//     "type": "public-key", "response": {"clientDataJSON",
//     "authenticatorData", "signature", "userHandle"}} (base64url).
//   - RP name: "PremiumSlots" (auth.py:465).
//   - RP id: _get_rp_id() returns WEBAUTHN_RP_ID from the server
//     environment, otherwise the request Host header with any port
//     stripped. On the live site the host is premiumslots.tech, so
//     the RP id used here is "premiumslots.tech".
//   - Origin: _get_origin() returns WEBAUTHN_ORIGIN from the server
//     environment, otherwise scheme + host from the request. On the
//     live site that is "https://premiumslots.tech".
//   - Registration requires a signed-in session on the server
//     (@login_required on register/begin). Authentication takes an
//     email in the begin body and, on success, sets the Flask
//     session (session["user_id"]) exactly like a normal login, so
//     the app then confirms the session with GET /api/v1/auth/me,
//     the same check the Clerk flow uses.
//   - Stored credential columns (WebAuthnCredentials): user_id,
//     credential_id (base64url), public_key, sign_count,
//     transports, aaguid, device_name.
//
// UNVERIFIED, do not treat as fact:
//   - The live WEBAUTHN_RP_ID / WEBAUTHN_ORIGIN environment values
//     were not read (server env is not visible from here). If the
//     server sets them to anything other than premiumslots.tech /
//     https://premiumslots.tech, passkey verification will fail and
//     the RP id here must change to match.
//   - The new api_v1 passkey endpoints named in the task
//     (POST /api/v1/auth/passkey/register-options, register-verify,
//     auth-options, auth-verify) are built by the backend agent;
//     they did not exist in the workspace backend at build time, so
//     no live call against them has been made. The list/remove
//     paths used by PasskeyManagementView
//     (GET /api/v1/auth/passkey/list,
//     POST /api/v1/auth/passkey/remove) are assumed names in the
//     same style; they are not confirmed by any server code.
//   - Passkeys on iOS need the Associated Domains capability
//     (webcredentials:premiumslots.tech) plus an
//     apple-app-site-association file on premiumslots.tech. Neither
//     is in this workspace (entitlements are outside the files this
//     agent owns). Without them the system refuses the request at
//     runtime. This must be set up in Xcode and on the server
//     before passkeys can work on a real device.
//   - WEB DEFECT, flag for the backend agent: in auth.py
//     webauthn_authenticate_complete the stored credential is looked
//     up with credential.raw_id.hex(), but registration stores the
//     credential id as base64url
//     (bytes_to_base64url(verification.credential_id)). A hex string
//     never equals a base64url string, so the lookup can never match
//     and passkey sign-in on the web always answers 404
//     "Credential not found". The api_v1 passkey endpoints must look
//     the credential up by its base64url id, or passkey sign-in
//     will fail the same way. Registration, list and remove are not
//     affected by this defect.
//
// v6 fixes (7 Nov 2026, second report that adding a passkey does
// not work). App-side bugs found by reading this flow against the
// workspace backend passkey endpoints (api_v1.py:778-1185):
//   1. authenticate() ignored the allowCredentials list the server
//      returns in auth-options. A passkey created with residentKey
//      preferred is not guaranteed discoverable, so the system
//      sheet could offer no credential at all, or the wrong one,
//      and verify then 404s. The allow list is now passed to the
//      platform provider when it is non-empty.
//   2. authenticationPayload used guard let on rawAuthenticatorData
//      and signature. In the Xcode 26.6 SDK those two are
//      Optional Data on ASAuthorizationPlatformPublicKeyCredentialAssertion,
//      so they keep a guard; rawClientDataJSON is non-Optional and
//      is read directly, as is rawAttestationObject's counterpart
//      only after its own guard on the registration credential.
//   3. The manager was not MainActor-isolated, so
//      performRequests could run off the main thread. It is now
//      @MainActor, and the presentation anchor falls back to the
//      first window of the first scene instead of a fresh UIWindow
//      that belongs to no scene.
//   4. A server RP id that differs from the app RP id used to fail
//      inside the system sheet with no readable error. Both flows
//      now check options.rp.id / options.rpId against
//      premiumslots.tech first and report the mismatch plainly.
//   5. auth-verify can answer needs_verification for an unverified
//      account; the app ignored that field and reported a generic
//      session failure. It now surfaces the verification step.
// The credential id stays base64url everywhere, matching what
// registration stores and what auth-verify looks up. The web hex
// lookup defect is NOT mirrored here. Still needs, outside this
// file: Associated Domains capability webcredentials:premiumslots.tech
// in Xcode plus the apple-app-site-association file on
// premiumslots.tech (backend agent owns the file contents), and
// the live WEBAUTHN_RP_ID / WEBAUTHN_ORIGIN env values must equal
// premiumslots.tech / https://premiumslots.tech.
// The credential id of the passkey created on this device is kept
// in UserDefaults under "premiumslots.passkey.credentialId" so the
// Security screen can show whether this device has a passkey. The
// private key never leaves the device keychain; only the public
// credential id is stored here.

enum PasskeyError: LocalizedError {
    case missingData(String)
    case cancelled
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .missingData(let what):
            return "Passkey sign-in could not read \(what) from this device."
        case .cancelled:
            return "Passkey sign-in was cancelled."
        case .failed(let message):
            return message
        }
    }
}

extension Data {
    /// Base64url without padding, as WebAuthn expects.
    func passkeyBase64URL() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init?(passkeyBase64URL string: String) {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = base64.count % 4
        if padding > 0 {
            base64 += String(repeating: "=", count: 4 - padding)
        }
        self.init(base64Encoded: base64)
    }
}

// MARK: - Options payloads (webauthn 3.x options_to_json shape)

struct PasskeyRegistrationOptions: Decodable {
    struct RP: Decodable {
        let id: String?
        let name: String?
    }
    struct User: Decodable {
        let id: String
        let name: String
        let displayName: String?
    }
    struct ExcludedCredential: Decodable {
        let id: String
        let type: String?
        let transports: [String]?
    }
    let rp: RP
    let user: User
    let challenge: String
    let excludeCredentials: [ExcludedCredential]?
    let timeout: Int?
    let attestation: String?
}

struct PasskeyAuthOptions: Decodable {
    struct AllowedCredential: Decodable {
        let id: String
        let type: String?
        let transports: [String]?
    }
    let challenge: String
    let rpId: String?
    let allowCredentials: [AllowedCredential]?
    let userVerification: String?
    let timeout: Int?
}

/// The verify endpoints answer with the web's {"success": true}
/// shape or the blueprint's {"ok": true} shape; accept either.
struct PasskeyVerifyResponse: Decodable {
    let ok: Bool?
    let success: Bool?
    let error: String?
    let message: String?
    let redirect: String?
    let needs_verification: Bool?

    var succeeded: Bool { ok == true || success == true }
    var serverMessage: String? { error ?? message }
}

/// Result of a verify call, kept separate from the wire shape so
/// the caller can see needs_verification.
struct PasskeyVerifyResult {
    let succeeded: Bool
    let needsVerification: Bool
    let serverMessage: String?
}

struct PasskeyListResponse: Decodable {
    struct Entry: Decodable, Identifiable {
        let id: Int?
        let credential_id: String?
        let device_name: String?
        let created_at: String?
        let last_used_at: String?
    }
    let ok: Bool?
    let credentials: [Entry]?
}

// MARK: - Passkey manager (ASAuthorizationController)

@MainActor
final class PasskeyAuthManager: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    /// RP id from the live host. See the header note: the server
    /// env override WEBAUTHN_RP_ID is UNVERIFIED.
    static let relyingPartyID = "premiumslots.tech"

    private static let storedCredentialKey = "premiumslots.passkey.credentialId"

    static var storedCredentialID: String? {
        UserDefaults.standard.string(forKey: storedCredentialKey)
    }

    static func storeCredentialID(_ id: String) {
        UserDefaults.standard.set(id, forKey: storedCredentialKey)
    }

    static func clearStoredCredentialID() {
        UserDefaults.standard.removeObject(forKey: storedCredentialKey)
    }

    private var registrationContinuation: CheckedContinuation<ASAuthorizationPlatformPublicKeyCredentialRegistration, Error>?
    private var assertionContinuation: CheckedContinuation<ASAuthorizationPlatformPublicKeyCredentialAssertion, Error>?

    // MARK: Registration (signed-in user)

    /// Runs the system passkey creation sheet and returns the new
    /// platform credential. The caller posts it to register-verify.
    func register(challenge: Data, userID: Data, name: String) async throws -> ASAuthorizationPlatformPublicKeyCredentialRegistration {
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: Self.relyingPartyID)
        let request = provider.createCredentialRegistrationRequest(challenge: challenge, name: name, userID: userID)
        return try await withCheckedThrowingContinuation { continuation in
            registrationContinuation = continuation
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    // MARK: Authentication (sign-in)

    /// Runs the system passkey sheet and returns the assertion. The
    /// caller posts it to auth-verify. The server allow list is
    /// passed when it is non-empty: without it the sheet can offer
    /// no credential for a non-discoverable passkey, and verify
    /// then fails. With an empty list the plain request is used.
    func authenticate(challenge: Data, allowCredentialIDs: [Data] = []) async throws -> ASAuthorizationPlatformPublicKeyCredentialAssertion {
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: Self.relyingPartyID)
        let request = provider.createCredentialAssertionRequest(challenge: challenge)
        // The platform provider has no allowCredentials parameter on
        // the create call: the allow list goes on the request
        // object itself, as ASAuthorizationPlatformPublicKeyCredential
        // descriptors. Without it the sheet can offer no credential
        // for a non-discoverable passkey, and verify then fails.
        if !allowCredentialIDs.isEmpty {
            request.allowedCredentials = allowCredentialIDs.map {
                ASAuthorizationPlatformPublicKeyCredentialDescriptor(credentialID: $0)
            }
        }
        return try await withCheckedThrowingContinuation { continuation in
            assertionContinuation = continuation
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    // MARK: ASAuthorizationControllerDelegate

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        if let registration = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialRegistration {
            let continuation = registrationContinuation
            registrationContinuation = nil
            continuation?.resume(returning: registration)
        } else if let assertion = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialAssertion {
            let continuation = assertionContinuation
            assertionContinuation = nil
            continuation?.resume(returning: assertion)
        } else {
            let registrationContinuation = registrationContinuation
            self.registrationContinuation = nil
            registrationContinuation?.resume(throwing: PasskeyError.failed("The device returned a credential this app does not recognise."))
            let assertionContinuation = assertionContinuation
            self.assertionContinuation = nil
            assertionContinuation?.resume(throwing: PasskeyError.failed("The device returned a credential this app does not recognise."))
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        let nsError = error as NSError
        let passkeyError: Error
        if nsError.domain == ASAuthorizationError.errorDomain && nsError.code == ASAuthorizationError.canceled.rawValue {
            passkeyError = PasskeyError.cancelled
        } else {
            passkeyError = PasskeyError.failed(error.localizedDescription)
        }
        if let continuation = registrationContinuation {
            registrationContinuation = nil
            continuation.resume(throwing: passkeyError)
        }
        if let continuation = assertionContinuation {
            assertionContinuation = nil
            continuation.resume(throwing: passkeyError)
        }
    }

    // MARK: ASAuthorizationControllerPresentationContextProviding

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        let keyWindow = scenes.flatMap { $0.windows }.first { $0.isKeyWindow }
        if let keyWindow { return keyWindow }
        if let anyWindow = scenes.flatMap({ $0.windows }).first { return anyWindow }
        return UIWindow()
    }
}

// MARK: - Wire helpers (options in, credential JSON out)

enum PasskeyWire {
    /// Registration credential JSON in the exact shape the
    /// server's parse_registration_credential_json expects.
    static func registrationPayload(
        _ credential: ASAuthorizationPlatformPublicKeyCredentialRegistration
    ) throws -> [String: Any] {
        guard let attestationObject = credential.rawAttestationObject else {
            throw PasskeyError.missingData("the attestation data")
        }
        let clientData = credential.rawClientDataJSON
        return [
            "id": credential.credentialID.passkeyBase64URL(),
            "rawId": credential.credentialID.passkeyBase64URL(),
            "type": "public-key",
            "response": [
                "clientDataJSON": clientData.passkeyBase64URL(),
                "attestationObject": attestationObject.passkeyBase64URL(),
                "transports": ["internal"],
            ],
        ]
    }

    /// Authentication credential JSON in the exact shape the
    /// server's parse_authentication_credential_json expects.
    static func authenticationPayload(
        _ credential: ASAuthorizationPlatformPublicKeyCredentialAssertion
    ) throws -> [String: Any] {
        // In this SDK rawAuthenticatorData and signature are
        // Optional Data on the assertion credential, so they
        // are unwrapped here; rawClientDataJSON is non-Optional
        // and is read directly.
        guard let authenticatorData = credential.rawAuthenticatorData,
              let signature = credential.signature else {
            throw PasskeyError.missingData("the authenticator data")
        }
        let clientData = credential.rawClientDataJSON
        var response: [String: Any] = [
            "clientDataJSON": clientData.passkeyBase64URL(),
            "authenticatorData": authenticatorData.passkeyBase64URL(),
            "signature": signature.passkeyBase64URL(),
        ]
        if let userHandle = credential.userID {
            response["userHandle"] = userHandle.passkeyBase64URL()
        }
        return [
            "id": credential.credentialID.passkeyBase64URL(),
            "rawId": credential.credentialID.passkeyBase64URL(),
            "type": "public-key",
            "response": response,
        ]
    }

    /// POSTs a credential payload to a passkey verify endpoint and
    /// reports success from either the {"ok": true} or the
    /// {"success": true} shape. Returns the full result so the
    /// caller can see needs_verification, which the old void
    /// version silently dropped.
    static func postVerify(_ path: String, payload: [String: Any]) async throws -> PasskeyVerifyResult {
        let response: PasskeyVerifyResponse = try await APIClient.shared.fetchJSON(path, method: "POST", body: payload)
        guard response.succeeded else {
            throw APIError.message(response.serverMessage ?? "Passkey verification failed.")
        }
        return PasskeyVerifyResult(
            succeeded: true,
            needsVerification: response.needs_verification == true,
            serverMessage: response.serverMessage
        )
    }

    /// User id bytes for registration: the server sends the user id
    /// base64url-encoded (base64url of the ASCII user id). If that
    /// decode ever fails, fall back to the raw UTF-8 bytes instead
    /// of failing the whole registration.
    static func userIDData(from value: String) -> Data {
        if let decoded = Data(passkeyBase64URL: value) { return decoded }
        return Data(value.utf8)
    }
}

// MARK: - Passkey sign-in sheet (from AuthView)

struct PasskeySignInView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @FocusState private var emailFocused: Bool
    @State private var email = ""
    @State private var message = ""
    @State private var isWorking = false
    @State private var manager = PasskeyAuthManager()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Sign in with a passkey")
                        .font(.psTitle)
                    Text("Use the passkey on this device instead of your password. Your passkey never leaves this device.")
                        .font(.psBody)
                        .foregroundStyle(.psMuted)
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .focused($emailFocused)
                        .psTextField()
                    Button {
                        Task { await signIn() }
                    } label: {
                        if isWorking {
                            PSRingSpinner(diameter: 20, lineWidth: 2, color: .white, duration: 0.7)
                        } else {
                            Label("Sign in with passkey", systemImage: "person.badge.key.fill")
                        }
                    }
                    .psPrimary()
                    .disabled(isWorking)
                    if !message.isEmpty {
                        Text(message)
                            .font(.psBody)
                            .foregroundStyle(.psMuted)
                    }
                    Text("No passkey yet? Sign in with Clerk first, then add one from Account, then Security.")
                        .font(.psCaption)
                        .foregroundStyle(.psMuted)
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollIndicators(.hidden)
            .onTapGesture { emailFocused = false }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.psBackground)
            .navigationTitle("Passkey")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .keyboard) {
                    Button("Done") { emailFocused = false }
                }
            }
            .task {
                email = appState.user?.email ?? ""
            }
        }
    }

    private func signIn() async {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmedEmail.contains("@") else {
            message = "Enter the email address for your account."
            return
        }
        emailFocused = false
        isWorking = true
        defer { isWorking = false }
        do {
            let options: PasskeyAuthOptions = try await APIClient.shared.fetchJSON(
                "api/v1/auth/passkey/auth-options", method: "POST", body: ["email": trimmedEmail])
            if let serverRP = options.rpId, serverRP != PasskeyAuthManager.relyingPartyID {
                throw PasskeyError.failed("The server expects passkeys for \(serverRP), but this app uses \(PasskeyAuthManager.relyingPartyID). Ask support to check the server passkey settings.")
            }
            guard let challenge = Data(passkeyBase64URL: options.challenge) else {
                throw PasskeyError.missingData("the sign-in challenge")
            }
            let allowIDs = (options.allowCredentials ?? []).compactMap { Data(passkeyBase64URL: $0.id) }
            let assertion = try await manager.authenticate(challenge: challenge, allowCredentialIDs: allowIDs)
            let payload = try PasskeyWire.authenticationPayload(assertion)
            let result = try await PasskeyWire.postVerify("api/v1/auth/passkey/auth-verify", payload: payload)
            PasskeyAuthManager.storeCredentialID(assertion.credentialID.passkeyBase64URL())
            if result.needsVerification {
                message = "Passkey verified. Check your email to finish verifying your account, then sign in."
                return
            }
            // The server sets the Flask session on verify, exactly
            // like a normal login, so confirm it the same way the
            // Clerk flow does: re-validate with /auth/me.
            await appState.checkSession()
            guard appState.isLoggedIn else {
                throw APIError.message("Passkey verification passed but the session did not start. Please try again.")
            }
            dismiss()
        } catch {
            message = error.localizedDescription
        }
    }
}

// MARK: - Passkey management (signed-in, from Account Security)

struct PasskeyManagementView: View {
    @EnvironmentObject private var appState: AppState

    @State private var serverCredentials: [PasskeyListResponse.Entry] = []
    @State private var isLoading = false
    @State private var isWorking = false
    @State private var message = ""
    @State private var manager = PasskeyAuthManager()

    private var storedID: String? { PasskeyAuthManager.storedCredentialID }

    var body: some View {
        List {
            Section {
                if let storedID {
                    Label("This device has a passkey", systemImage: "checkmark.circle.fill")
                        .font(.psHeadline)
                        .foregroundStyle(.psSuccess)
                    Text("Credential \(storedID.prefix(12))...")
                        .font(.psMono)
                        .foregroundStyle(.psMuted)
                } else {
                    Text("This device has no passkey yet.")
                        .font(.psHeadline)
                    Text("Add one here and you can sign in with it instead of your password. The passkey stays on this device.")
                        .font(.psBody)
                        .foregroundStyle(.psMuted)
                }
                Button {
                    Task { await register() }
                } label: {
                    if isWorking {
                        PSRingSpinner(diameter: 20, lineWidth: 2, color: .white, duration: 0.7)
                    } else {
                        Label("Add a passkey on this device", systemImage: "key.fill")
                    }
                }
                .psPrimary()
                .disabled(isWorking)
                if let storedID {
                    Button("Remove this device passkey", role: .destructive) {
                        Task { await remove(credentialID: storedID) }
                    }
                    .font(.psBody)
                    .disabled(isWorking)
                }
            } header: {
                Text("Passkeys")
            }

            Section {
                if isLoading && serverCredentials.isEmpty {
                    HStack {
                        Spacer()
                        PSRingSpinner(diameter: 28, lineWidth: 3)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else if serverCredentials.isEmpty {
                    Text("No passkeys are registered on your account, or the list could not be loaded.")
                        .font(.psBody)
                        .foregroundStyle(.psMuted)
                } else {
                    ForEach(serverCredentials) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.device_name ?? "Passkey")
                                .font(.psHeadline)
                            if let created = entry.created_at {
                                Text("Added \(String(created.prefix(10)))")
                                    .font(.psCaption)
                                    .foregroundStyle(.psMuted)
                            }
                            if let lastUsed = entry.last_used_at {
                                Text("Last used \(String(lastUsed.prefix(10)))")
                                    .font(.psCaption)
                                    .foregroundStyle(.psMuted)
                            }
                            if let credentialID = entry.credential_id {
                                Button("Remove", role: .destructive) {
                                    Task { await remove(credentialID: credentialID) }
                                }
                                .font(.psBody)
                                .disabled(isWorking)
                            }
                        }
                    }
                }
            } header: {
                Text("Passkeys on your account")
            }

            if !message.isEmpty {
                Section {
                    Text(message)
                        .font(.psCaption)
                        .foregroundStyle(.psMuted)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .background(Color.psBackground)
        .navigationTitle("Passkeys")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .safeAreaPadding(.bottom, 8)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            // UNVERIFIED path (see file header): the list endpoint
            // name is assumed from the web's /auth/webauthn/list.
            let response: PasskeyListResponse = try await APIClient.shared.fetchJSON("api/v1/auth/passkey/list")
            serverCredentials = response.credentials ?? []
        } catch {
            serverCredentials = []
            message = error.localizedDescription
        }
    }

    private func register() async {
        guard let user = appState.user else {
            message = "Sign in first, then add a passkey."
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let options: PasskeyRegistrationOptions = try await APIClient.shared.fetchJSON(
                "api/v1/auth/passkey/register-options", method: "POST", body: [:])
            if let serverRP = options.rp.id, serverRP != PasskeyAuthManager.relyingPartyID {
                throw PasskeyError.failed("The server expects passkeys for \(serverRP), but this app uses \(PasskeyAuthManager.relyingPartyID). Ask support to check the server passkey settings.")
            }
            guard let challenge = Data(passkeyBase64URL: options.challenge) else {
                throw PasskeyError.missingData("the registration challenge")
            }
            let userID = PasskeyWire.userIDData(from: options.user.id)
            let registration = try await manager.register(challenge: challenge, userID: userID, name: user.email)
            var payload = try PasskeyWire.registrationPayload(registration)
            payload["device_name"] = UIDevice.current.name
            _ = try await PasskeyWire.postVerify("api/v1/auth/passkey/register-verify", payload: payload)
            PasskeyAuthManager.storeCredentialID(registration.credentialID.passkeyBase64URL())
            message = "Passkey added on this device."
            await load()
        } catch {
            message = error.localizedDescription
        }
    }

    private func remove(credentialID: String) async {
        isWorking = true
        defer { isWorking = false }
        do {
            // UNVERIFIED path (see file header): the remove endpoint
            // name is assumed from the web's /auth/webauthn/remove.
            let _: APIResponse = try await APIClient.shared.fetchJSON(
                "api/v1/auth/passkey/remove", method: "POST", body: ["credential_id": credentialID])
            if PasskeyAuthManager.storedCredentialID == credentialID {
                PasskeyAuthManager.clearStoredCredentialID()
            }
            message = "Passkey removed."
            await load()
        } catch {
            message = error.localizedDescription
        }
    }
}
