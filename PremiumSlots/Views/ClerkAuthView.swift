import SwiftUI
import WebKit

// MARK: - Clerk authentication, v3 (Fix #2)
// Approach: hosted Clerk in a WKWebView (checklist §3.6 Option B).
//
// Why not the Clerk iOS SDK (Option A)? The SDK would need a Swift
// Package Manager dependency (clerk/clerk-ios) added to the Xcode
// project, and on this Linux machine there is no Swift toolchain and
// no way to verify the package resolves, the module imports, or the
// build still passes. Adding an unverifiable SPM dependency risks
// breaking the Actions build that currently goes green first try.
// The WKWebView route uses the site's real Clerk sign-in page, which
// is the exact flow the web uses, and it works with zero new client
// dependencies:
//   1. The web view loads /auth/login (or /auth/register).
//   2. Clerk JS v5 runs there (the site hides social buttons when the
//      user agent carries "PremiumSlotsApp", as the Capacitor shell
//      does, so the web view signs in with email only).
//   3. Clerk redirects to /auth/clerk_sync, which sets the Flask
//      session cookie in the web view's cookie store.
//   4. The app copies that cookie into URLSession's shared cookie
//      storage, then verifies the session with GET /api/v1/auth/me.
//   5. If WhatsApp or date of birth is missing, the server flags
//      needs_onboarding and the app shows the native onboarding form.
// Sign-out clears both the Clerk session and the Flask cookie
// (checklist §3.6): the Flask cookie via POST /api/v1/auth/logout,
// and the web view cookies via ClerkSessionStore.clearAll().
// Admin stays separate: the Admin tab uses the password-only
// /api/v1/admin/login session, exactly as on the web. There is no
// Clerk admin role to route on.

struct ClerkAuthView: View {
    enum Mode {
        case signIn
        case signUp
    }

    let mode: Mode
    var onSignedIn: (Bool) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss

    @State private var isLoadingPage = true
    @State private var loadError = ""
    @State private var showError = false
    @State private var isFinishing = false

    private var startURL: URL {
        URL(string: mode == .signIn
            ? "https://premiumslots.tech/auth/login"
            : "https://premiumslots.tech/auth/register")!
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ClerkWebView(
                    url: startURL,
                    onSyncComplete: { handleSyncComplete() },
                    onLoadStateChange: { isLoadingPage = $0 },
                    onLoadFailed: { message in
                        loadError = message
                        showError = true
                    }
                )
                if isLoadingPage || isFinishing {
                    Color.psBackground.opacity(0.6).ignoresSafeArea()
                    VStack(spacing: 16) {
                        PSRingSpinner()
                        Text(isFinishing ? "Finishing sign-in..." : "Loading secure portal...")
                            .font(.psBody)
                            .foregroundStyle(.psMuted)
                    }
                }
            }
            .background(Color.psBackground)
            .navigationTitle(mode == .signIn ? "Sign in" : "Create account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
            .alert("Could not load sign-in", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(loadError)
            }
        }
    }

    private func handleSyncComplete() {
        guard !isFinishing else { return }
        isFinishing = true
        Task {
            do {
                try await ClerkSessionStore.syncCookiesToSharedStorage()
                let user = try await APIClient.shared.me()
                await MainActor.run {
                    isFinishing = false
                    onSignedIn(user.needs_onboarding ?? false)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isFinishing = false
                    loadError = "Sign-in did not complete. Please try again."
                    showError = true
                }
            }
        }
    }
}

/// Cookie bridge between the WKWebView store and URLSession.
/// WKWebView keeps its own cookie jar; the API client uses
/// HTTPCookieStorage.shared, so the Flask session cookie must be
/// copied across after Clerk sync, and cleared from both on sign-out.
enum ClerkSessionStore {
    // WKWebsiteDataStore.httpCookieStore is MainActor-isolated in the
    // Swift 6 SDK: accessing it from a nonisolated async context is a
    // warning in Swift 5 mode and an error in Swift 6 mode, so both
    // entry points hop to the main actor. Callers already await them.
    @MainActor
    static func syncCookiesToSharedStorage() async throws {
        let store = WKWebsiteDataStore.default().httpCookieStore
        let cookies = await withCheckedContinuation { continuation in
            store.getAllCookies { continuation.resume(returning: $0) }
        }
        let shared = HTTPCookieStorage.shared
        for cookie in cookies where cookie.domain.contains("premiumslots.tech") {
            if let properties = cookie.properties,
               let fresh = HTTPCookie(properties: properties) {
                shared.setCookie(fresh)
            }
        }
    }

    @MainActor
    static func clearAll() async {
        let store = WKWebsiteDataStore.default().httpCookieStore
        let cookies = await withCheckedContinuation { continuation in
            store.getAllCookies { continuation.resume(returning: $0) }
        }
        for cookie in cookies {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                store.delete(cookie) { continuation.resume() }
            }
        }
        let shared = HTTPCookieStorage.shared
        for cookie in shared.cookies ?? [] where cookie.domain.contains("premiumslots.tech") {
            shared.deleteCookie(cookie)
        }
    }
}

private struct ClerkWebView: UIViewRepresentable {
    let url: URL
    var onSyncComplete: () -> Void
    var onLoadStateChange: (Bool) -> Void
    var onLoadFailed: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSyncComplete: onSyncComplete,
                    onLoadStateChange: onLoadStateChange,
                    onLoadFailed: onLoadFailed)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        // The site hides Clerk social buttons when the request comes
        // from the app (g.is_app), matching the Capacitor shell.
        if let agent = webView.value(forKey: "userAgent") as? String {
            webView.customUserAgent = agent + " PremiumSlotsApp"
        }
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        var onSyncComplete: () -> Void
        var onLoadStateChange: (Bool) -> Void
        var onLoadFailed: (String) -> Void
        private var didComplete = false

        init(onSyncComplete: @escaping () -> Void,
             onLoadStateChange: @escaping (Bool) -> Void,
             onLoadFailed: @escaping (String) -> Void) {
            self.onSyncComplete = onSyncComplete
            self.onLoadStateChange = onLoadStateChange
            self.onLoadFailed = onLoadFailed
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            onLoadStateChange(true)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onLoadStateChange(false)
            guard let url = webView.url, !didComplete else { return }
            // Clerk sync has run when the browser lands back on the
            // homepage or the onboarding page after /auth/clerk_sync.
            let path = url.path
            if path == "/" || path == "/auth/onboarding" || path.isEmpty {
                didComplete = true
                onSyncComplete()
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            onLoadStateChange(false)
            onLoadFailed(error.localizedDescription)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            onLoadStateChange(false)
            onLoadFailed(error.localizedDescription)
        }
    }
}

#Preview {
    ClerkAuthView(mode: .signIn)
}
