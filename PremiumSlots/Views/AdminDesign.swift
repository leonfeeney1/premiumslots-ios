import SwiftUI

// MARK: - Admin design system, v6
// One coherent system for every admin screen: the same KPI tiles,
// cards, section headers, spacing, typography, skeleton loading,
// empty and error states, full-screen backgrounds and cache-first
// loading. Every admin root view uses these instead of one-off
// styling, so no screen is left in the old look.
// Brand: void black #050505 / #0a0a0a dark, light #F8FAFC paper,
// primary #2D9CE5, hover #55B7F7, muted #8B9BB4, real shield logo.
// Typography is the v5 PSTextStyle scale in Theme.swift only: body
// 15pt everywhere, no ad-hoc system sizes. No emojis, SF Symbols
// only. No fake data: every number comes from the live API or is
// honestly shown as not available yet.

// MARK: - Full screen
// Content always starts below the notch and Dynamic Island and
// only scrolls under it once the user scrolls. That means: never
// put ignoresSafeArea on content. The background colour alone may
// extend edge to edge, which is what this modifier does, and the
// frame fills the screen so nothing is letterboxed or inset.

extension View {
    /// Edge-to-edge background with content kept inside the safe
    /// area. Apply to the outermost Group of every admin root view.
    func adminScreenBackground() -> some View {
        background(Color.psBackground.ignoresSafeArea())
    }

    /// Fill the whole screen. Apply to loading, empty and error
    /// states so they centre on the full screen, not a small box.
    func adminFullScreenFrame() -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Cache first
// Admin screens show their last good data immediately, then
// refresh live. The cache holds raw response bytes in UserDefaults
// under one key per screen, never a password or a vault secret.
// A cached copy is only ever shown as the last saved copy while
// the live refresh runs; the screen still reports a live failure
// with retry instead of silently serving stale data as live.

enum AdminCache {
    static func save(_ data: Data, key: String) {
        UserDefaults.standard.set(data, forKey: "premiumslots.admin.cache.\(key)")
        UserDefaults.standard.set(Date(), forKey: "premiumslots.admin.cache.\(key).date")
    }

    static func load(key: String) -> Data? {
        UserDefaults.standard.data(forKey: "premiumslots.admin.cache.\(key)")
    }

    static func savedDate(key: String) -> Date? {
        UserDefaults.standard.object(forKey: "premiumslots.admin.cache.\(key).date") as? Date
    }

    static func savedDateText(key: String) -> String? {
        guard let date = savedDate(key: key) else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Skeleton loading
// Placeholder rows shown immediately on first load, before any
// network answer. Never a blank screen, never a lone spinner.
// The bars pulse gently; they carry no numbers, so nothing fake
// is ever shown while loading.

struct AdminSkeletonView: View {
    var lines = 4
    var title: String

    @State private var pulsing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.psBody)
                .foregroundStyle(.psMuted)
            ForEach(0..<lines, id: \.self) { index in
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.psSurfaceHover)
                    .frame(maxWidth: .infinity, minHeight: index == 0 ? 72 : 56)
            }
        }
        .psScreenPadding()
        .opacity(pulsing ? 0.55 : 1.0)
        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulsing)
        .onAppear { pulsing = true }
        .accessibilityLabel("Loading \(title.lowercased())")
    }
}

/// Two-column skeleton KPI grid, used on the dashboard and on
/// analytics while the first live response is still coming in.
struct AdminSkeletonKPIGrid: View {
    @State private var pulsing = false

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.psSurfaceHover)
                    .frame(maxWidth: .infinity, minHeight: 76)
            }
        }
        .opacity(pulsing ? 0.55 : 1.0)
        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulsing)
        .onAppear { pulsing = true }
        .accessibilityLabel("Loading figures")
    }
}

// MARK: - KPI tile and metric states

/// One KPI tile: label, value, icon and tint. When the value is
/// nil the tile honestly says the metric is not available yet
/// instead of showing 0, which would be a fake number.
struct AdminKPITile: View {
    let label: String
    let value: String?
    let systemImage: String
    var tint: Color = .psPrimary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.psCaption)
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
                Text(label)
                    .font(.psCaption)
                    .foregroundStyle(.psMuted)
                    .lineLimit(1)
            }
            if let value {
                Text(value)
                    .font(.psTitle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                Text("Not available yet")
                    .font(.psBody)
                    .foregroundStyle(.psMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.psSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.psBorder, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

/// Two-column grid of KPI tiles, the one grid every admin screen
/// uses for its headline figures.
struct AdminKPIGrid<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            content
        }
    }
}

/// Honest unavailable text for a single metric inside a card.
/// Use it instead of 0, a dash that looks like a value, or blank.
struct AdminUnavailableText: View {
    var body: some View {
        Text("Not available yet")
            .font(.psBody)
            .foregroundStyle(.psMuted)
    }
}

/// Small note line under a section, for backend notes such as a
/// filter that does not change revenue. Shown only when present.
struct AdminNoteText: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.psCaption)
            .foregroundStyle(.psMuted)
    }
}

// MARK: - Admin deep links (item 14)
// Every admin notification carries a kind and a ref_id from the
// live feed: new_subscription and issue_reported point at a
// subscription id, new_ticket at a ticket id, and
// wallet_deposit_pending at a wallet deposit id. A notification
// tap must open that destination inside the admin navigation,
// never sit dead. Unknown kinds fall back to the notifications
// list itself, which is always a real screen.

enum AdminNotificationDestination: Hashable, Identifiable {
    case subscription(Int)
    case ticket(Int)
    case deposit(Int)

    var id: String {
        switch self {
        case .subscription(let value): return "subscription-\(value)"
        case .ticket(let value): return "ticket-\(value)"
        case .deposit(let value): return "deposit-\(value)"
        }
    }

    var title: String {
        switch self {
        case .subscription(let value): return "Order #\(value)"
        case .ticket(let value): return "Ticket #\(value)"
        case .deposit(let value): return "Deposit #\(value)"
        }
    }

    static func from(notification: AdminNotification) -> AdminNotificationDestination? {
        guard let refId = notification.ref_id else { return nil }
        switch notification.kind {
        case "new_subscription", "issue_reported":
            return .subscription(refId)
        case "new_ticket":
            return .ticket(refId)
        case "wallet_deposit_pending":
            return .deposit(refId)
        default:
            return nil
        }
    }
}
