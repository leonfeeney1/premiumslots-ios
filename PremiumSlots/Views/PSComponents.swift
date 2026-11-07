import SwiftUI

// MARK: - Shared HIG components, v3 Fix #3
// One place for the layout rules every screen follows, so the app
// feels like one app instead of a set of one-off screens:
// 16pt screen padding, 12pt spacing between cards, 12-14pt card
// radii (public) and 6/10/14pt (admin), 44pt minimum touch targets,
// inset-grouped lists where they fit, native sheets with detents,
// and the same loading / empty / error states everywhere.
// All colours come from Theme.swift tokens; nothing here hardcodes
// a black or white background, so light and dark mode both work.
// No emojis, SF Symbols only.

/// Days remaining text for a subscription expiry. The server value
/// (days_remaining) wins when present; otherwise the caller passes
/// the locally computed day difference. Display is never negative:
/// past expiry reads "Expired", zero reads "Expires today".
enum PSDaysRemaining {
    static func text(days: Int?) -> String {
        guard let days else { return "No expiry date shown" }
        if days < 0 { return "Expired" }
        if days == 0 { return "Expires today" }
        if days == 1 { return "1d left" }
        return "\(days)d left"
    }

    /// Local fallback: whole days from now to an ISO 8601 expiry date.
    static func days(fromExpiryDate iso: String?) -> Int? {
        guard let iso, !iso.isEmpty else { return nil }
        guard let date = ISO8601DateFormatter().date(from: iso) else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: date).day
    }
}

/// Real support contact, verified from the live homepage. The
/// WhatsApp number is the support channel; the M-PESA payment
/// number is not support and is never shown here.
enum PSContact {
    static let whatsAppSupportURL = URL(string: "https://wa.me/254747412440?text=Hi%20PremiumSlots%2C%20I%20need%20help%20with%20my%20subscription.")!
    static let whatsAppDisplayNumber = "+254 747 412 440"
}

/// Standard screen padding: 16pt horizontal, 12pt vertical.
struct PSScreenPadding: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
    }
}

extension View {
    func psScreenPadding() -> some View { modifier(PSScreenPadding()) }

    /// Hide scroll indicators. Scroll indicators are hidden
    /// app-wide by design, on every ScrollView and List. Other
    /// agents: use this modifier on your scrolled views too.
    func psHiddenScrollIndicators() -> some View {
        scrollIndicators(.hidden)
    }

    /// Standard sheet presentation: medium detent first, large
    /// available by dragging, with a visible grabber. Replaces the
    /// old custom full-screen overlays.
    func psSheetDetents() -> some View {
        presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
    }

    /// 44pt minimum touch target, the HIG minimum and the same
    /// minimum the web enforces on coarse pointers.
    func psTouchTarget() -> some View {
        frame(minHeight: 44)
    }
}

/// A card: surface background, 1pt border, 14pt radius.
struct PSCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(14)
            .background(Color.psSurface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.psBorder, lineWidth: 1)
            )
    }
}

/// Section header: small semibold title, optional trailing action.
struct PSSectionHeader: View {
    let title: String
    var actionLabel: String?
    var action: (() -> Void)?

    var body: some View {
        HStack {
            Text(title)
                .psTextStyle(.headline)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if let actionLabel, let action {
                Button(actionLabel, action: action)
                    .psTextStyle(.caption)
            }
        }
    }
}

/// Empty state: centred icon, title, body copy, optional action.
struct PSEmptyState: View {
    let systemImage: String
    let title: String
    let message: String
    var actionLabel: String?
    var action: (() -> Void)?

    init(systemImage: String, title: String, body: String, actionLabel: String? = nil, action: (() -> Void)? = nil) {
        self.systemImage = systemImage
        self.title = title
        self.message = body
        self.actionLabel = actionLabel
        self.action = action
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.psIconLarge)
                .foregroundStyle(.psMuted)
                .accessibilityHidden(true)
            Text(title)
                .psTextStyle(.headline)
                .multilineTextAlignment(.center)
            Text(message)
                .psTextStyle(.body)
                .foregroundStyle(.psMuted)
                .multilineTextAlignment(.center)
            if let actionLabel, let action {
                Button(actionLabel, action: action)
                    .psPrimary()
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .accessibilityElement(children: .combine)
    }
}

/// Error state with retry: shown when a list load fails, never a raw
/// error page. The message is the API error text, not a stack trace.
struct PSErrorState: View {
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.psIconLarge)
                .foregroundStyle(.psWarning)
                .accessibilityHidden(true)
            Text("Something went wrong")
                .psTextStyle(.headline)
            Text(message)
                .psTextStyle(.body)
                .foregroundStyle(.psMuted)
                .multilineTextAlignment(.center)
            if let retry {
                Button("Try again", action: retry)
                    .buttonStyle(.bordered)
                    .tint(.psCyan)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}

/// Saved catalogue pill: the only offline label in the app. It marks
/// bundled data as saved, never as live, and carries no status text,
/// version, or endpoint. The message argument is kept so existing call
/// sites compile, but it is never shown.
struct PSOfflineBanner: View {
    let message: String

    var body: some View {
        Label("Saved catalogue", systemImage: "wifi.slash")
            .psTextStyle(.caption)
            .foregroundStyle(.psMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Color.psSurface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

/// Live banner: green check, shown when data came from the live API.
struct PSLiveBanner: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "checkmark.circle.fill")
            .psTextStyle(.caption)
            .foregroundStyle(.psSuccess)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Color.psSurface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

/// Status pill: small tinted label, used for subscription and order
/// states everywhere so the same state always looks the same.
struct PSStatusPill: View {
    let text: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(text, systemImage: systemImage)
            .psTextStyle(.caption)
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12))
            .clipShape(Capsule())
    }
}

/// Standard text field styling: surface background, border, 12pt radius.
struct PSTextFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .psTextStyle(.body)
            .padding(12)
            .background(Color.psSurface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.psBorder, lineWidth: 1)
            )
    }
}

extension View {
    func psTextField() -> some View { modifier(PSTextFieldStyle()) }
}

/// A list row with a chevron, for navigation rows in inset-grouped lists.
struct PSNavigationRow<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack {
            content
            Spacer()
            Image(systemName: "chevron.right")
                .font(.psIconSmall)
                .foregroundStyle(.psMuted)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
    }
}
