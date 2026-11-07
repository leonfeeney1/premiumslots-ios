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

    var isSoldOut: Bool { slotsLeft == 0 }
    var formattedPrice: String { "KES \(priceKES)" }
}

extension Platform {
    /// Bundled catalogue. Per-platform prices and stock were last fully
    /// verified on 3 Nov 2026. The live homepage on 7 Nov 2026 showed
    /// 67 slots in rotation and 7 community suggestions, so the bundled
    /// per-platform figures may already be behind the live site. The app
    /// labels this date in the catalogue and tries a live refresh.
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

    /// Homepage total shown on premiumslots.tech on 7 Nov 2026.
    /// Shown separately from the bundled per-platform figures above.
    static let liveTotalSlotsOnHomepage = 67
    static let communitySuggestions = 7
    static let stockVerifiedDate = "3 Nov 2026"
    static let homepageCheckedDate = "7 Nov 2026"
}

// MARK: - Order

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

@MainActor
final class AppState: ObservableObject {
    @Published var platforms: [Platform] = Platform.bundled
    @Published var orders: [SlotOrder] = []
    @Published var waitlist: Set<String> = []
    @Published var searchText = ""
    @Published var sortByPriceAscending = true
    @Published var showAvailableOnly = false
    @Published var liveTotalSlots: Int? = Platform.liveTotalSlotsOnHomepage
    @Published var refreshMessage: String?
    @Published var isRefreshing = false
    @Published var lastRefreshAttempt: Date?

    private let ordersKey = "premiumslots.orders.v1"
    private let waitlistKey = "premiumslots.waitlist.v1"

    init() {
        loadLocalState()
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

    func joinWaitlist(platformId: String) {
        waitlist.insert(platformId)
        saveLocalState()
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

    /// Tries to read the live homepage total. The homepage is
    /// JavaScript-rendered, so per-platform rows cannot be parsed from a
    /// plain text fetch. If parsing fails, bundled data stays in place
    /// and the caller is told so plainly.
    func refreshLiveTotal() async {
        guard let url = URL(string: "https://premiumslots.tech") else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        lastRefreshAttempt = Date()
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let text = String(data: data, encoding: .utf8) else {
                refreshMessage = "Live refresh did not return readable text. Showing bundled stock from \(Platform.stockVerifiedDate)."
                return
            }
            let pattern = #"(\d+)\s+slots in rotation"#
            if let match = try NSRegularExpression(pattern: pattern).firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 1), in: text),
               let total = Int(text[range]) {
                liveTotalSlots = total
                refreshMessage = "Live total updated from premiumslots.tech just now. Per-platform stock is still the bundled list from \(Platform.stockVerifiedDate)."
            } else {
                refreshMessage = "Live site reached, but per-platform rows could not be parsed from it. Showing bundled stock from \(Platform.stockVerifiedDate)."
            }
        } catch {
            refreshMessage = "Live refresh failed. Showing bundled stock from \(Platform.stockVerifiedDate)."
        }
    }

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
