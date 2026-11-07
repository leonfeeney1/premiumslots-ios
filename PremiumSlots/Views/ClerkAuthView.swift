import SwiftUI
import WebKit

// MARK: - Clerk authentication, v4
// Full-screen hosted Clerk flow. The Clerk iOS SDK is still not used:
// it would need an SPM dependency that cannot be verified on this
// Linux machine, so the hosted WKWebView route stays. The flow is:
//   1. The web view loads /auth/login (or /auth/register).
//   2. Clerk runs there, and the site hides social buttons when the
//      user agent carries "PremiumSlotsApp", as the Capacitor shell
//      does, so the web view signs in with email only.
//   3. Clerk redirects to /auth/clerk_sync, which sets the Flask
//      session cookie in the web view's cookie store.
//   4. The app copies that cookie into URLSession's shared cookie
//      storage, then verifies the session with the session check.
//   5. If WhatsApp or date of birth is missing, the server flags
//      needs_onboarding and the app shows the native onboarding form.
// Presented as a fullScreenCover from AuthView, never as a sheet, so
// the sign-in page fills the screen. A native header sits above the
// web view with the real logo, the flow title, and a close button
// that dismisses the flow. While the first page loads, the HUD loader
// shows over the web area with a native progress bar under the
// header. A failed load shows a native error state with a Retry
// button instead of a blank page. The site header, navigation, and
// footer are hidden inside the web view so only the sign-in form
// shows. Sign-out clears both the Clerk session and the Flask cookie.
// Admin stays separate: the Admin area uses the password-only admin
// sign-in session, exactly as on the web. There is no Clerk admin
// role to route on.

struct ClerkAuthView: View {
    enum Mode {
        case signIn
        case signUp
    }

    let mode: Mode
    var onSignedIn: (Bool) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss

    @State private var isLoadingPage = true
    @State private var loadProgress = 0.0
    @State private var hasLoadedOnce = false
    @State private var loadError = ""
    @State private var isFinishing = false
    @State private var reloadID = 0

    private var startURL: URL {
        URL(string: mode == .signIn
            ? "https://premiumslots.tech/auth/login"
            : "https://premiumslots.tech/auth/register")!
    }

    private var title: String {
        mode == .signIn ? "Sign in" : "Create account"
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if isLoadingPage {
                ProgressView(value: loadProgress)
                    .tint(.psCyan)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .accessibilityLabel("Loading sign-in page")
            }

            ZStack {
                ClerkWebView(
                    url: startURL,
                    reloadID: reloadID,
                    onSyncComplete: { handleSyncComplete() },
                    onLoadStateChange: { loading in
                        isLoadingPage = loading
                        if !loading { hasLoadedOnce = true }
                    },
                    onProgress: { loadProgress = $0 },
                    onLoadFailed: { message in
                        loadError = message
                    }
                )

                if isLoadingPage && !hasLoadedOnce {
                    PSLoaderView()
                }

                if !loadError.isEmpty {
                    errorState
                }

                if isFinishing {
                    Color.psBackground.opacity(0.6).ignoresSafeArea()
                    VStack(spacing: 16) {
                        PSRingSpinner()
                        Text("Finishing sign-in...")
                            .font(.psBody)
                            .foregroundStyle(.psMuted)
                    }
                }
            }
        }
        .background(Color.psBackground)
    }

    private var header: some View {
        HStack(spacing: 12) {
            RealLogoView(size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.psHeadline)
                Text("Secure sign-in on the PremiumSlots website")
                    .font(.psCaption)
                    .foregroundStyle(.psMuted)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.psMuted)
                    .frame(width: 44, height: 44)
                    .background(Color.psSurface)
                    .clipShape(Circle())
            }
            .accessibilityLabel("Close sign-in")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var errorState: some View {
        PSErrorState(message: loadError) {
            retry()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.psBackground)
    }

    private func retry() {
        loadError = ""
        isLoadingPage = true
        loadProgress = 0
        reloadID += 1
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
    let reloadID: Int
    var onSyncComplete: () -> Void
    var onLoadStateChange: (Bool) -> Void
    var onProgress: (Double) -> Void
    var onLoadFailed: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSyncComplete: onSyncComplete,
                    onLoadStateChange: onLoadStateChange,
                    onProgress: onProgress,
                    onLoadFailed: onLoadFailed)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Hide the site header, navigation, and footer inside the
        // sign-in page so only the sign-in form shows. Clerk itself
        // renders inside plain containers, so this leaves the form
        // untouched.
        let hideChrome = WKUserScript(
            source: "var s=document.createElement('style');s.textContent='header,nav,footer{display:none !important}';document.documentElement.appendChild(s);",
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true)
        config.userContentController.addUserScript(hideChrome)
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        // The site hides Clerk social buttons when the request comes
        // from the app (g.is_app), matching the Capacitor shell.
        if let agent = webView.value(forKey: "userAgent") as? String {
            webView.customUserAgent = agent + " PremiumSlotsApp"
        }
        context.coordinator.attachProgress(to: webView)
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if context.coordinator.lastReloadID != reloadID {
            context.coordinator.lastReloadID = reloadID
            uiView.reload()
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var onSyncComplete: () -> Void
        var onLoadStateChange: (Bool) -> Void
        var onProgress: (Double) -> Void
        var onLoadFailed: (String) -> Void
        var lastReloadID = 0
        private var didComplete = false
        private var progressObservation: NSKeyValueObservation?

        init(onSyncComplete: @escaping () -> Void,
             onLoadStateChange: @escaping (Bool) -> Void,
             onProgress: @escaping (Double) -> Void,
             onLoadFailed: @escaping (String) -> Void) {
            self.onSyncComplete = onSyncComplete
            self.onLoadStateChange = onLoadStateChange
            self.onProgress = onProgress
            self.onLoadFailed = onLoadFailed
        }

        func attachProgress(to webView: WKWebView) {
            progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] _, change in
                if let value = change.newValue {
                    self?.onProgress(value)
                }
            }
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
