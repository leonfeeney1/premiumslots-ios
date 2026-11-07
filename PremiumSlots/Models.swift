import Foundation

// MARK: - Platform

struct Platform: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let tagline: String
    let priceKES: Int
    let slotsLeft: Int
    let duration: String
    let systemImage: String
    let accent: String
    var liveId: Int?
    /// Live site icon_name domain (e.g. "primevideo.com"), used for
    /// the real platform logo. Nil for bundled platforms.
    var iconDomain: String? = nil

    var isSoldOut: Bool { slotsLeft == 0 }
    var formattedPrice: String { "KES \(priceKES)" }

    /// Maps the live site icon_name to an SF Symbol. The site stores
    /// icon names, not SF Symbols, so unknown names fall back to a
    /// sparkle instead of failing.
    static func systemImage(for iconName: String, name: String) -> String {
        switch iconName.lowercased() {
        case "music", "spotify": return "music.note"
        case "tv", "video", "play": return "play.tv.fill"
        case "paintbrush", "design", "canva": return "paintbrush.fill"
        case "waveform", "audio": return "waveform"
        case "graduationcap", "course", "learn": return "graduationcap.fill"
        case "sparkles", "ai": return "sparkles"
        case "appletv": return "appletv.fill"
        default:
            let lower = name.lowercased()
            if lower.contains("music") || lower.contains("spotify") || lower.contains("tidal") {
                return "music.note"
            }
            if lower.contains("video") || lower.contains("tv") { return "play.tv.fill" }
            if lower.contains("course") || lower.contains("udemy") { return "graduationcap.fill" }
            if lower.contains("canva") || lower.contains("design") { return "paintbrush.fill" }
            return "sparkles"
        }
    }
}

extension Platform {
    /// Bundled catalogue, used ONLY as an offline fallback. The app
    /// never presents bundled data as live.
    static let bundled: [Platform] = [
        Platform(id: "spotify", name: "Spotify Premium Family", tagline: "Music for the whole household", priceKES: 180, slotsLeft: 0, duration: "1 month", systemImage: "music.note", accent: "green"),
        Platform(id: "prime-video", name: "Prime Video", tagline: "Films and series, on demand", priceKES: 120, slotsLeft: 10, duration: "1 month", systemImage: "play.tv.fill", accent: "blue"),
        Platform(id: "peacock", name: "Peacock TV", tagline: "Shows, films and live sport", priceKES: 110, slotsLeft: 10, duration: "1 month", systemImage: "tv.fill", accent: "yellow"),
        Platform(id: "apple-tv", name: "Apple TV", tagline: "Originals in 4K HDR", priceKES: 150, slotsLeft: 10, duration: "1 month", systemImage: "appletv.fill", accent: "black"),
        Platform(id: "canva", name: "Canva Pro", tagline: "Design tools and templates", priceKES: 115, slotsLeft: 7, duration: "1 month", systemImage: "paintbrush.fill", accent: "purple"),
        Platform(id: "tidal", name: "Tidal", tagline: "High-fidelity music streaming", priceKES: 100, slotsLeft: 7, duration: "1 month", systemImage: "waveform", accent: "cyan"),
        Platform(id: "udemy", name: "Udemy Courses", tagline: "Learn at your own pace", priceKES: 200, slotsLeft: 10, duration: "1 course", systemImage: "graduationcap.fill", accent: "red"),
        Platform(id: "gemini-plus", name: "Gemini Plus 12 Months", tagline: "AI help for a full year", priceKES: 200, slotsLeft: 10, duration: "12 months", systemImage: "sparkles", accent: "blue")
    ]

    static let liveTotalSlotsOnHomepage = 67
    static let communitySuggestions = 7
}

// MARK: - Live subscription (from the API)

struct LiveSubscription: Identifiable, Equatable {
    let id: Int
    let serviceRequested: String
    let amountDue: Int
    let mpesaCode: String?
    let status: String
    let expiryDate: String?
    let issueReported: Bool
    let accountGroup: String?
    /// Grandfathered price for this subscription, when the live site
    /// carries one (locked_price column, when present on production).
    let lockedPrice: Int?
    /// When this subscription started (API created_at).
    let createdAt: String?

    var orderStatus: OrderStatus {
        switch status {
        case "Approved": return .active
        case "Cancelled": return .issue
        default: return .pendingVerification
        }
    }

    var daysLeft: Int? {
        guard let expiryDate else { return nil }
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: expiryDate) else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: date).day
    }

    init(_ api: APISubscription) {
        id = api.id
        serviceRequested = api.service_requested
        amountDue = api.amount_due
        mpesaCode = api.mpesa_code
        status = api.status
        expiryDate = api.expiry_date
        issueReported = api.issue_reported ?? false
        accountGroup = api.account_group
        lockedPrice = api.locked_price
        createdAt = api.created_at
    }
}

// MARK: - Order (local, kept for backwards compatibility)

enum OrderStatus: String, Codable, CaseIterable {
    case pendingVerification = "Pending verification"
    case active = "Active"
    case issue = "Needs attention"

    var systemImage: String {
        switch self {
        case .pendingVerification: return "clock.fill"
        case .active: return "checkmark.circle.fill"
        case .issue: return "exclamationmark.circle.fill"
        }
    }
}

struct SlotOrder: Identifiable, Codable, Equatable {
    let id: UUID
    let platformId: String
    let platformName: String
    let amountKES: Int
    var mpesaCode: String
    var status: OrderStatus
    let createdAt: Date
    var activatedAt: Date?

    init(platform: Platform, mpesaCode: String) {
        self.id = UUID()
        self.platformId = platform.id
        self.platformName = platform.name
        self.amountKES = platform.priceKES
        self.mpesaCode = mpesaCode
        self.status = .pendingVerification
        self.createdAt = Date()
        self.activatedAt = nil
    }
}

// MARK: - App state

enum LiveState {
    case unknown
    case live
    case offline
}

@MainActor
final class AppState: ObservableObject {
    let api = APIClient.shared

    @Published var platforms: [Platform] = Platform.bundled
    @Published var liveState: LiveState = .unknown
    @Published var liveTotalSlots: Int? = Platform.liveTotalSlotsOnHomepage
    @Published var refreshMessage: String?
    @Published var isRefreshing = false
    @Published var lastRefreshAttempt: Date?

    @Published var orders: [SlotOrder] = []
    @Published var liveSubscriptions: [LiveSubscription] = []
    @Published var waitlist: Set<String> = []
    @Published var searchText = ""
    @Published var sortByPriceAscending = true
    @Published var showAvailableOnly = false

    @Published var user: APIUser?
    @Published var isLoggedIn = false
    @Published var needsOnboarding = false
    @Published var isCheckingSession = true
    @Published var walletBalance: Int?
    @Published var referralCount: Int?

    @Published var isAdminLoggedIn = false
    @Published var adminStats: AdminStatsResponse?
    @Published var adminPending: [APISubscription] = []
    @Published var adminSubscriptions: [APISubscription] = []
    @Published var adminCustomers: [APICustomer] = []
    /// Unread admin-event count for the Admin badge. Mirrored here
    /// from AdminNotifier (v4) so the badge refreshes when the
    /// notifier polls; the notifier itself lives in
    /// AdminNotificationsView.swift.
    @Published var adminUnreadCount = 0
    let adminNotifier = AdminNotifier()

    private let ordersKey = "premiumslots.orders.v1"
    private let waitlistKey = "premiumslots.waitlist.v1"
    private let adminKey = "premiumslots.admin.v2"

    init() {
        loadLocalState()
        isAdminLoggedIn = UserDefaults.standard.bool(forKey: adminKey)
        adminNotifier.onUnreadCount = { [weak self] count in
            self?.adminUnreadCount = count
        }
        if isAdminLoggedIn {
            adminNotifier.start()
        }
    }

    var platformCount: Int { platforms.count }

    var filteredPlatforms: [Platform] {
        var list = platforms
        if showAvailableOnly { list = list.filter { !$0.isSoldOut } }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            list = list.filter {
                $0.name.localizedCaseInsensitiveContains(query)
                || $0.tagline.localizedCaseInsensitiveContains(query)
            }
        }
        list.sort { sortByPriceAscending ? $0.priceKES < $1.priceKES : $0.priceKES > $1.priceKES }
        return list
    }

    func platform(id: String) -> Platform? {
        platforms.first { $0.id == id }
    }

    // MARK: - live catalogue

    /// Fetches the live catalogue from /api/v1/services. On success the
    /// bundled list is replaced and the app is live. On failure the
    /// bundled list stays, labelled with its verification date, and the
    /// app says plainly that it is offline.
    func refreshCatalogue() async {
        isRefreshing = true
        defer { isRefreshing = false }
        lastRefreshAttempt = Date()
        do {
            let response = try await api.services()
            platforms = response.services.map { $0.platform }
            liveTotalSlots = response.slots_in_rotation
            liveState = .live
            refreshMessage = nil
        } catch {
            liveState = .offline
            refreshMessage = "Saved catalogue"
            await refreshLiveTotal()
        }
    }

    /// Homepage-total fallback, as in v1: the only live figure parseable
    /// from a plain fetch. Kept only so the offline state still shows a
    /// fresh total when the API is not deployed yet.
    func refreshLiveTotal() async {
        guard let url = URL(string: "https://premiumslots.tech") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let text = String(data: data, encoding: .utf8) else { return }
            let pattern = #"(\d+)\s+slots in rotation"#
            if let match = try NSRegularExpression(pattern: pattern).firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 1), in: text),
               let total = Int(text[range]) {
                liveTotalSlots = total
            }
        } catch {
            // Unreachable: bundled total stays.
        }
    }

    // MARK: - auth (Clerk, v3)
    // The v2 own-auth login/register are gone: Clerk-created accounts
    // have an empty password hash, so that login could never sign
    // them in. Customers sign in with Clerk (ClerkAuthView) and the
    // session is the 7-day Flask session cookie, checked on launch
    // with GET /api/v1/auth/me. There is no refresh endpoint on the
    // server; if the session has expired, /me returns 401 and the
    // app routes back to sign-in.

    /// Called on launch: re-validate the stored Flask session.
    /// Sets isLoggedIn from the live answer, never from a stored flag.
    func checkSession() async {
        isCheckingSession = true
        defer { isCheckingSession = false }
        await refreshMe()
        if isLoggedIn {
            needsOnboarding = user?.needs_onboarding ?? false
            await refreshMySubscriptions()
        }
    }

    /// Called after the Clerk web view completes sign-in and the
    /// Flask session cookie has been copied into shared storage.
    func clerkSignedIn(needsOnboarding: Bool) async {
        isLoggedIn = true
        self.needsOnboarding = needsOnboarding
        await refreshMe()
        self.needsOnboarding = user?.needs_onboarding ?? needsOnboarding
        await refreshMySubscriptions()
    }

    func finishOnboarding() async {
        needsOnboarding = false
        await refreshMe()
    }

    func logout() async {
        try? await api.logout()
        // Sign-out must clear both sessions: the Flask cookie and
        // the Clerk session in the web view's cookie store.
        await ClerkSessionStore.clearAll()
        isLoggedIn = false
        needsOnboarding = false
        user = nil
        liveSubscriptions = []
        walletBalance = nil
    }

    func refreshMe() async {
        do {
            user = try await api.me()
            walletBalance = user?.wallet_balance
            referralCount = user?.referral_count
            isLoggedIn = true
        } catch {
            isLoggedIn = false
        }
    }

    // MARK: - buying

    func submitOrder(platform: Platform, mpesaCode: String) async throws -> RequestResponse {
        let response = try await api.submitRequest(serviceName: platform.name,
                                                   mpesaCode: mpesaCode)
        guard response.ok else { throw APIError.message(response.error ?? "Order failed.") }
        await refreshMySubscriptions()
        return response
    }

    func refreshMySubscriptions() async {
        guard isLoggedIn else { return }
        do {
            liveSubscriptions = try await api.mySubscriptions().map(LiveSubscription.init)
        } catch {
            liveSubscriptions = []
        }
    }

    func refreshWallet() async {
        guard isLoggedIn else { return }
        do {
            let wallet = try await api.wallet()
            walletBalance = wallet.wallet_balance
        } catch {
            // Keep the last known balance.
        }
    }

    // MARK: - local orders / waitlist (offline fallback)

    func joinWaitlist(platformId: String) {
        waitlist.insert(platformId)
        saveLocalState()
        if let platform = platform(id: platformId), isLoggedIn {
            Task { try? await api.joinWaitlist(serviceName: platform.name) }
        }
    }

    func leaveWaitlist(platformId: String) {
        waitlist.remove(platformId)
        saveLocalState()
    }

    func placeOrder(platform: Platform, mpesaCode: String) -> SlotOrder {
        let order = SlotOrder(platform: platform, mpesaCode: mpesaCode)
        orders.insert(order, at: 0)
        saveLocalState()
        return order
    }

    func updateOrderStatus(id: UUID, status: OrderStatus) {
        guard let index = orders.firstIndex(where: { $0.id == id }) else { return }
        orders[index].status = status
        if status == .active { orders[index].activatedAt = Date() }
        saveLocalState()
    }

    // MARK: - admin

    func adminLogin(password: String) async throws {
        try await api.adminLogin(password: password)
        isAdminLoggedIn = true
        UserDefaults.standard.set(true, forKey: adminKey)
        await refreshAdmin()
        adminNotifier.start()
    }

    func adminLogout() async {
        try? await api.adminLogout()
        isAdminLoggedIn = false
        UserDefaults.standard.set(false, forKey: adminKey)
        adminStats = nil
        adminPending = []
        adminSubscriptions = []
        adminCustomers = []
        adminNotifier.stop()
        adminUnreadCount = 0
    }

    func refreshAdmin() async {
        guard isAdminLoggedIn else { return }
        do {
            adminStats = try await api.adminStats()
            adminPending = try await api.adminSubscriptions(status: "Pending")
            adminSubscriptions = try await api.adminSubscriptions()
            adminCustomers = try await api.adminCustomers()
        } catch {
            // Admin needs the live API; the views show that state.
        }
    }

    // MARK: - local persistence

    private func loadLocalState() {
        if let data = UserDefaults.standard.data(forKey: ordersKey),
           let decoded = try? JSONDecoder().decode([SlotOrder].self, from: data) {
            orders = decoded
        }
        if let data = UserDefaults.standard.data(forKey: waitlistKey),
           let decoded = try? JSONDecoder().decode(Set<String>.self, from: data) {
            waitlist = decoded
        }
    }

    private func saveLocalState() {
        if let data = try? JSONEncoder().encode(orders) {
            UserDefaults.standard.set(data, forKey: ordersKey)
        }
        if let data = try? JSONEncoder().encode(waitlist) {
            UserDefaults.standard.set(data, forKey: waitlistKey)
        }
    }
}
