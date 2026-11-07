import SwiftUI

// MARK: - Sign-in, v4
// Clerk-first entry screen. The v2 placeholder own-auth login is gone
// and stays gone: Clerk-created accounts have an empty password hash,
// so an email and password login could never sign them in. Customers
// sign in with Clerk through ClerkAuthView (hosted WKWebView), launched
// here as a fullScreenCover so the sign-in page fills the screen.
// The own-auth recovery paths are kept as secondary options only:
// forgot/reset password and magic-link sign-in, which still work
// for accounts created with a password on the web.

struct AuthView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var showClerkSignIn = false
    @State private var showClerkSignUp = false
    @State private var showPasskey = false
    @State private var showForgot = false
    @State private var showMagic = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 12) {
                        LogoLockupView(height: 40)
                        Text("Welcome back")
                            .font(.psTitle)
                        Text("Sign in with Clerk, the same secure sign-in you use on the PremiumSlots website. Your password is never visible to PremiumSlots.")
                            .font(.psBody)
                            .foregroundStyle(.psMuted)
                    }
                    .padding(.top, 24)

                    VStack(spacing: 12) {
                        Button {
                            showClerkSignIn = true
                        } label: {
                            Label("Continue", systemImage: "person.badge.key.fill")
                        }
                        .psPrimary()

                        Button {
                            showClerkSignUp = true
                        } label: {
                            Text("Create account")
                                .font(.psHeadline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                        }
                        .buttonStyle(.bordered)
                        .tint(.psCyan)
                        .controlSize(.large)

                        Button {
                            showPasskey = true
                        } label: {
                            Label("Sign in with a passkey", systemImage: "key.fill")
                                .font(.psHeadline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                        }
                        .buttonStyle(.bordered)
                        .tint(.psCyan)
                        .controlSize(.large)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Having trouble signing in?")
                            .font(.psHeadline)
                        Button("Forgot password?") { showForgot = true }
                            .font(.psBody)
                        Button("Email me a sign-in link") { showMagic = true }
                            .font(.psBody)
                    }
                    .padding(.top, 8)

                    if appState.liveState != .live {
                        Text("The live service is not reachable right now, so sign-in may fail until the connection returns.")
                            .font(.psCaption)
                            .foregroundStyle(.psAmber)
                    }
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollIndicators(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.psBackground)
            .navigationTitle("Sign in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.psHeadline)
                            .foregroundStyle(.psMuted)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Close sign-in")
                }
            }
            .fullScreenCover(isPresented: $showClerkSignIn) {
                ClerkAuthView(mode: .signIn) { needsOnboarding in
                    Task { await appState.clerkSignedIn(needsOnboarding: needsOnboarding) }
                    dismiss()
                }
            }
            .fullScreenCover(isPresented: $showClerkSignUp) {
                ClerkAuthView(mode: .signUp) { needsOnboarding in
                    Task { await appState.clerkSignedIn(needsOnboarding: needsOnboarding) }
                    dismiss()
                }
            }
            .sheet(isPresented: $showForgot) { ForgotPasswordView().psSheetDetents() }
            .sheet(isPresented: $showMagic) { MagicLinkView().psSheetDetents() }
            .sheet(isPresented: $showPasskey) { PasskeySignInView().psSheetDetents() }
            .onChange(of: appState.isLoggedIn) { _, loggedIn in
                if loggedIn { dismiss() }
            }
        }
    }
}

// MARK: - Forgot password (own-auth recovery)

private struct ForgotPasswordView: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var emailFocused: Bool
    @State private var email = ""
    @State private var message = ""
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Reset your password")
                        .font(.psTitle)
                    Text("A reset link is valid for 15 minutes. If that email has an account, the link is on its way.")
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
                        Task { await submit() }
                    } label: {
                        if isSubmitting {
                            PSRingSpinner(diameter: 20, lineWidth: 2, color: .white, duration: 0.7)
                        } else {
                            Text("Send reset link")
                        }
                    }
                    .psPrimary()
                    .disabled(isSubmitting)
                    if !message.isEmpty {
                        Text(message)
                            .font(.psBody)
                            .foregroundStyle(.psMuted)
                    }
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollIndicators(.hidden)
            .onTapGesture { emailFocused = false }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.psBackground)
            .navigationTitle("Forgot password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .keyboard) {
                    Button("Done") { emailFocused = false }
                }
            }
        }
    }

    private func submit() async {
        guard email.contains("@") else {
            message = "Enter the email address for your account."
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let response = try await APIClient.shared.forgotPassword(email: email)
            message = response.error ?? "If that email has an account, a reset link is on its way."
        } catch {
            message = error.localizedDescription
        }
    }
}

// MARK: - Magic-link sign-in (own-auth recovery)

private struct MagicLinkView: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var emailFocused: Bool
    @State private var email = ""
    @State private var message = ""
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Sign in with a link")
                        .font(.psTitle)
                    Text("We email you a one-time sign-in link. It works once, then it stops working.")
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
                        Task { await submit() }
                    } label: {
                        if isSubmitting {
                            PSRingSpinner(diameter: 20, lineWidth: 2, color: .white, duration: 0.7)
                        } else {
                            Text("Email me a sign-in link")
                        }
                    }
                    .psPrimary()
                    .disabled(isSubmitting)
                    if !message.isEmpty {
                        Text(message)
                            .font(.psBody)
                            .foregroundStyle(.psMuted)
                    }
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollIndicators(.hidden)
            .onTapGesture { emailFocused = false }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.psBackground)
            .navigationTitle("Magic link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .keyboard) {
                    Button("Done") { emailFocused = false }
                }
            }
        }
    }

    private func submit() async {
        guard email.contains("@") else {
            message = "Enter the email address for your account."
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let response = try await APIClient.shared.magicLink(email: email)
            message = response.error ?? "If that email has an account, a sign-in link is on its way."
        } catch {
            message = error.localizedDescription
        }
    }
}

// MARK: - Onboarding, v4 (native full-screen form)
// Rebuilt as a native form, not a web page: WhatsApp number plus a
// date of birth picker, with inline validation, tap-to-dismiss and a
// Done toolbar button. Shown after Clerk sign-in when the server
// flags needs_onboarding. ContentView presents it full-screen; the
// form itself fills the screen either way.

struct OnboardingView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    private enum Field {
        case whatsapp
    }

    @FocusState private var focusedField: Field?
    @State private var whatsappNumber = ""
    @State private var dateOfBirth = Calendar.current.date(byAdding: .year, value: -20, to: Date()) ?? Date()
    @State private var whatsappError = ""
    @State private var dateOfBirthError = ""
    @State private var errorMessage = ""
    @State private var showError = false
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    LogoLockupView(height: 40)
                    Text("Finish setting up")
                        .font(.psTitle)
                    Text("PremiumSlots needs your WhatsApp number and date of birth to finish your account, the same as on the website.")
                        .font(.psBody)
                        .foregroundStyle(.psMuted)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("WhatsApp number")
                            .font(.psHeadline)
                        TextField("Enter your WhatsApp number", text: $whatsappNumber)
                            .textContentType(.telephoneNumber)
                            .keyboardType(.phonePad)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .whatsapp)
                            .psTextField()
                            .onChange(of: whatsappNumber) { _, _ in whatsappError = "" }
                        if !whatsappError.isEmpty {
                            Text(whatsappError)
                                .font(.psCaption)
                                .foregroundStyle(.psDanger)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Date of birth")
                            .font(.psHeadline)
                        DatePicker(
                            "Date of birth",
                            selection: $dateOfBirth,
                            in: ...Calendar.current.date(byAdding: .year, value: -13, to: Date())!,
                            displayedComponents: .date
                        )
                        .datePickerStyle(.compact)
                        .font(.psBody)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.psSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.psBorder, lineWidth: 1))
                        .onChange(of: dateOfBirth) { _, _ in dateOfBirthError = "" }
                        if !dateOfBirthError.isEmpty {
                            Text(dateOfBirthError)
                                .font(.psCaption)
                                .foregroundStyle(.psDanger)
                        }
                    }

                    Button {
                        Task { await submit() }
                    } label: {
                        if isSubmitting {
                            PSRingSpinner(diameter: 20, lineWidth: 2, color: .white, duration: 0.7)
                        } else {
                            Text("Save and continue")
                        }
                    }
                    .psPrimary()
                    .disabled(isSubmitting)
                    .padding(.top, 4)
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture { focusedField = nil }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.psBackground)
            .navigationTitle("Finish setting up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .keyboard) {
                    Button("Done") { focusedField = nil }
                }
            }
            .alert("Could not save", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .task {
                if let user = appState.user {
                    if !user.whatsapp_number.isEmpty {
                        whatsappNumber = user.whatsapp_number
                    }
                    if let saved = user.date_of_birth,
                       let parsed = OnboardingView.dateFormatter.date(from: saved) {
                        dateOfBirth = parsed
                    }
                }
            }
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_GB")
        return formatter
    }()

    private func validate() -> Bool {
        let digits = whatsappNumber.filter { $0.isNumber }
        if digits.count < 9 || digits.count > 15 {
            whatsappError = "Enter a valid WhatsApp number, 9 to 15 digits."
            return false
        }
        let age = Calendar.current.dateComponents([.year], from: dateOfBirth, to: Date()).year ?? 0
        if age < 13 {
            dateOfBirthError = "You must be at least 13 years old."
            return false
        }
        if age > 120 {
            dateOfBirthError = "Check the date of birth and try again."
            return false
        }
        return true
    }

    private func submit() async {
        focusedField = nil
        guard validate() else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let response = try await APIClient.shared.completeOnboarding(
                whatsappNumber: whatsappNumber,
                dateOfBirth: OnboardingView.dateFormatter.string(from: dateOfBirth))
            guard response.ok else {
                throw APIError.message(response.error ?? "Could not save.")
            }
            await appState.finishOnboarding()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

#Preview {
    AuthView()
        .environmentObject(AppState())
}
