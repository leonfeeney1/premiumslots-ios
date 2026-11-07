import SwiftUI

// MARK: - User sign-in / sign-up, v2
// Uses the real account on premiumslots.tech through /api/v1/auth/*.
// The password goes only to the live site over HTTPS, over the same
// Flask session the website uses. Nothing is stored on the device.

struct AuthView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var isSignUp = false
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var whatsappNumber = ""
    @State private var errorMessage = ""
    @State private var showError = false
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        RealLogoView(size: 56)
                        Text(isSignUp ? "Create your account" : "Welcome back")
                            .font(.psTitle)
                        Text("This is the same account you use on premiumslots.tech. Sign in to see your slots and wallet.")
                            .font(.psBody)
                            .foregroundStyle(.psMuted)
                    }

                    VStack(spacing: 12) {
                        if isSignUp {
                            field("Full name", text: $name, contentType: .name, autocapitalization: .words)
                            field("WhatsApp number", text: $whatsappNumber, contentType: .telephoneNumber, autocapitalization: .never, keyboard: .phonePad)
                        }
                        field("Email", text: $email, contentType: .emailAddress, autocapitalization: .never, keyboard: .emailAddress)
                        field("Password", text: $password, contentType: .password, autocapitalization: .never, secure: true)
                    }

                    Button {
                        Task { await submit() }
                    } label: {
                        if isSubmitting { ProgressView() } else { Text(isSignUp ? "Create account" : "Sign in") }
                    }
                    .psPrimary()
                    .disabled(isSubmitting)

                    Button(isSignUp ? "Already have an account? Sign in" : "New here? Create an account") {
                        isSignUp.toggle()
                    }
                    .font(.psBody)
                    .frame(maxWidth: .infinity)

                    if appState.liveState != .live {
                        Text("The live service is not reachable right now, so sign-in may fail until the /api/v1 backend is deployed.")
                            .font(.psCaption)
                            .foregroundStyle(.psAmber)
                    }
                }
                .padding(16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.psObsidian)
            .navigationTitle(isSignUp ? "Sign up" : "Sign in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
            .alert("Could not sign in", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }

    private func field(_ placeholder: String, text: Binding<String>,
                       contentType: UITextContentType,
                       autocapitalization: TextInputAutocapitalization = .sentences,
                       keyboard: UIKeyboardType = .default,
                       secure: Bool = false) -> some View {
        Group {
            if secure {
                SecureField(placeholder, text: text)
            } else {
                TextField(placeholder, text: text)
            }
        }
        .textContentType(contentType)
        .textInputAutocapitalization(autocapitalization)
        .keyboardType(keyboard)
        .autocorrectionDisabled()
        .font(.psBody)
        .padding(12)
        .background(Color.psSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.psBorder, lineWidth: 1)
        )
    }

    private func submit() async {
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanEmail.isEmpty, cleanEmail.contains("@") else {
            errorMessage = "Enter the email address for your PremiumSlots account."
            showError = true
            return
        }
        guard password.count >= 8 else {
            errorMessage = "Your password is at least 8 characters."
            showError = true
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            if isSignUp {
                guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    errorMessage = "Enter your full name."
                    showError = true
                    return
                }
                guard !whatsappNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    errorMessage = "Enter your WhatsApp number."
                    showError = true
                    return
                }
                try await appState.register(name: name, email: cleanEmail,
                                            password: password,
                                            whatsappNumber: whatsappNumber)
            } else {
                try await appState.login(email: cleanEmail, password: password)
            }
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
