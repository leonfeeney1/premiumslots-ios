import Foundation

// MARK: - Customer notification deep links, v6
// Every customer notification must navigate somewhere real when
// tapped. The server sends NotificationQueue rows with kind, title,
// body and an optional web link, plus derived rows (negative ids in
// per-source bands, see backend/api_v1.py my_notifications) that
// carry no link at all. Most links are nil or "/", so the
// destination is inferred from the kind, the title and the body,
// never guessed from a single field:
//   - a subscription id is recovered from a derived id band, or by
//     matching the service name in the title or body against the
//     customer's own subscriptions (live data only, never invented)
//   - a ticket id is read from "Ticket #12" style text
//   - wallet, catalogue, dashboard, gift cards, help and wishlist
//     come from the kind or the web link path
// When nothing can be pinned down, the link falls back to My Slots
// for subscription kinds and Home for everything else, so a tap
// always lands somewhere useful and never does nothing.
// Delivery is a NotificationCenter post: NotificationsRootView is
// pushed from several places (Home bell, Dashboard, Settings), and
// ContentView is the one place that owns the tab bar, so it is the
// one place that can switch tabs and present sheets.

enum PSDeepLink: Equatable, Identifiable {
    case subscription(Int)
    case mySlots
    case ticket(Int?)
    case wallet
    case catalogue
    case dashboard
    case giftCards(String?)
    case help
    case wishlist
    case home

    var id: String {
        switch self {
        case .subscription(let subId): return "subscription-\(subId)"
        case .mySlots: return "my-slots"
        case .ticket(let ticketId): return "ticket-\(ticketId ?? 0)"
        case .wallet: return "wallet"
        case .catalogue: return "catalogue"
        case .dashboard: return "dashboard"
        case .giftCards(let code): return "gift-cards-\(code ?? "")"
        case .help: return "help"
        case .wishlist: return "wishlist"
        case .home: return "home"
        }
    }

    /// Resolve a notification to its destination. Subscriptions are
    /// the customer's own live list, passed in by the caller.
    static func from(
        notification: NtfNotification,
        subscriptions: [LiveSubscription]
    ) -> PSDeepLink {
        // Derived rows: negative ids in per-source bands.
        // -1m subscriptions, -2m expiry, -3m deposits, -4m tickets.
        if let id = notification.id, id < 0 {
            let bandId = -id
            if bandId > 2000000 && bandId < 3000000 {
                return .subscription(bandId - 2000000)
            }
            if bandId > 1000000 && bandId < 2000000 {
                return .subscription(bandId - 1000000)
            }
            if bandId > 4000000 && bandId < 5000000 {
                return .ticket(bandId - 4000000)
            }
            if bandId > 3000000 && bandId < 4000000 {
                return .wallet
            }
        }

        // Explicit web link, when the server sent one.
        if let link = notification.link, !link.isEmpty {
            switch link {
            case "/wallet": return .wallet
            case "/gift-cards": return .giftCards(nil)
            case "/my-tickets": return .ticket(ticketId(from: notificationText(notification)))
            case "/wishlist": return .wishlist
            case "/help": return .help
            case "/store": return .catalogue
            case "/": return .home
            default: break
            }
            if link.hasPrefix("/gift-cards?code=") {
                let code = String(link.dropFirst("/gift-cards?code=".count))
                    .components(separatedBy: "&").first ?? ""
                return .giftCards(code.isEmpty ? nil : code)
            }
            if link.hasPrefix("/subscription/") {
                let tail = link.dropFirst("/subscription/".count)
                if let subId = Int(tail) {
                    return .subscription(subId)
                }
            }
        }

        let text = notificationText(notification)
        let kind = notification.kindKey ?? ""

        // Gift cards: the code travels with the notification when
        // the text carries one (v7: GIFT-XXXX-XXXX in the title or
        // body), so the verify sheet opens prefilled.
        if kind.contains("gift") || text.lowercased().contains("gift card") {
            return .giftCards(giftCardCode(from: text))
        }

        // Ticket first: "Ticket #12 received" names its ticket.
        if kind.contains("ticket") || text.lowercased().contains("ticket") {
            return .ticket(ticketId(from: text))
        }
        if kind == "wallet" || text.lowercased().contains("wallet deposit") {
            return .wallet
        }
        if kind == "referral" || kind == "achievement" {
            return .dashboard
        }
        if kind == "system" && text.lowercased().contains("waitlist") {
            return .catalogue
        }

        // Subscription kinds: match the service name in the text
        // against the customer's own subscriptions.
        if let match = subscriptionMatch(in: text, subscriptions: subscriptions) {
            return .subscription(match)
        }
        if kind.contains("subscription") || kind.contains("order")
            || kind.contains("expiry") || kind.contains("renewal") {
            return .mySlots
        }
        return .home
    }

    private static func notificationText(_ notification: NtfNotification) -> String {
        [notification.title, notification.bodyText]
            .compactMap { $0 }
            .joined(separator: " ")
    }

    /// Digits after a "#" in the text, for "Ticket #12" style copy.
    private static func ticketId(from text: String) -> Int? {
        guard let hash = text.firstIndex(of: "#") else { return nil }
        let rest = text[text.index(after: hash)...]
        let digits = rest.prefix(while: { $0.isNumber })
        return Int(digits)
    }

    /// A GIFT-XXXX-XXXX code in the text, for gift-card
    /// notifications, so the verify sheet opens prefilled.
    private static func giftCardCode(from text: String) -> String? {
        guard let range = text.range(of: "GIFT-") else { return nil }
        let tail = String(text[range.lowerBound...])
        let code = tail.prefix(14)
        guard code.count == 14 else { return nil }
        return String(code)
    }

    /// First subscription whose service name (or first word of it)
    /// appears in the notification text.
    private static func subscriptionMatch(
        in text: String,
        subscriptions: [LiveSubscription]
    ) -> Int? {
        let lower = text.lowercased()
        for sub in subscriptions {
            let name = sub.serviceRequested.lowercased()
            if !name.isEmpty && lower.contains(name) {
                return sub.id
            }
            let firstWord = name.split(separator: " ").first.map(String.init) ?? ""
            if firstWord.count > 3 && lower.contains(firstWord) {
                return sub.id
            }
        }
        return nil
    }
}

extension Notification.Name {
    static let psDeepLink = Notification.Name("premiumslots.deepLink")
}

enum PSDeepLinkRouter {
    /// Post a deep link for ContentView to handle.
    static func post(_ link: PSDeepLink) {
        NotificationCenter.default.post(name: .psDeepLink, object: link)
    }
}
