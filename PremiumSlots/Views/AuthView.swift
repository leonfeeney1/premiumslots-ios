import SwiftUI

// MARK: - Sign-in, v3 (Fix #2)
// Clerk-first, replacing the v2 placeholder own-auth login. The v2
// login cannot sign in Clerk users at all: Clerk-created accounts
// have an empty password hash, so the old email/password login
// always failed for them. The web signs customers in with Clerk
// (Clerk JS v5) and syncs into the Flask session; the app does the
// same through ClerkAuthView (WKWebView hosted Clerk).
// The own-auth recovery paths are kept as secondary options only:
// forgot/reset password and magic-link sign-in, which still work
// for accounts created with a password on the web.

struct AuthView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var showClerkSignIn = false
    @State private var showClerkSignUp = false
    @State private var showForgot = false
    @State private var showMagic = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        RealLogoView(size: 56)
                        Text("Welcome back")
                            .font(.psTitle)
                        Text("Sign in with Clerk, the same secure sign-in you use on premiumslots.tech. Your password is never visible to PremiumSlots.")
                            .font(.psBody)
                            .foregroundStyle(.psMuted)
                    }

                    Button {
                        showClerkSignIn = true
                    } label: {
                        Label("Continue with Clerk", systemImage: "person.badge.key.fill")
                    }
                    .psPrimary()

                    Button("Create an account") {
                        showClerkSignUp = true
                    }
                    .font(.psBody)
                    .frame(maxWidth: .infinity)

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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.psBackground)
            .navigationTitle("Sign in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(isPresented: $showClerkSignIn) {
                ClerkAuthView(mode: .signIn) { needsOnboarding in
                    Task { await appState.clerkSignedIn(needsOnboarding: needsOnboarding) }
                    dismiss()
                }
                .psSheetDetents()
            }
            .sheet(isPresented: $showClerkSignUp) {
                ClerkAuthView(mode: .signUp) { needsOnboarding in
                    Task { await appState.clerkSignedIn(needsOnboarding: needsOnboarding) }
                    dismiss()
                }
                .psSheetDetents()
            }
            .sheet(isPresented: $showForgot) { ForgotPasswordView().psSheetDetents() }
            .sheet(isPresented: $showMagic) { MagicLinkView().psSheetDetents() }
        }
    }
}

// MARK: - Forgot password (own-auth recovery)

private struct ForgotPasswordView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var message = ""
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
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
                    .font(.psBody)
                    .padding(12)
                    .background(Color.psSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.psBorder, lineWidth: 1))
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
                Spacer()
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.psBackground)
            .navigationTitle("Forgot password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
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
    @State private var email = ""
    @State private var message = ""
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
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
                    .font(.psBody)
                    .padding(12)
                    .background(Color.psSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.psBorder, lineWidth: 1))
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
                Spacer()
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.psBackground)
            .navigationTitle("Magic link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
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

// MARK: - Onboarding (WhatsApp + date of birth after Clerk sign-in)

struct OnboardingView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var whatsappNumber = ""
    @State private var dateOfBirth = ""
    @State private var errorMessage = ""
    @State private var showError = false
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                RealLogoView(size: 56)
                Text("Finish setting up")
                    .font(.psTitle)
                Text("PremiumSlots needs your WhatsApp number and date of birth to finish your account, the same as on the website.")
                    .font(.psBody)
                    .foregroundStyle(.psMuted)
                TextField("WhatsApp number", text: $whatsappNumber)
                    .textContentType(.telephoneNumber)
                    .keyboardType(.phonePad)
                    .autocorrectionDisabled()
                    .font(.psBody)
                    .padding(12)
                    .background(Color.psSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.psBorder, lineWidth: 1))
                TextField("Date of birth (YYYY-MM-DD)", text: $dateOfBirth)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.psBody)
                    .padding(12)
                    .background(Color.psSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.psBorder, lineWidth: 1))
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
                Spacer()
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.psBackground)
            .navigationTitle("Onboarding")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Could not save", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }

    private func submit() async {
        guard !whatsappNumber.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Enter your WhatsApp number."
            showError = true
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let response = try await APIClient.shared.completeOnboarding(
                whatsappNumber: whatsappNumber, dateOfBirth: dateOfBirth)
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
