import SwiftUI

// MARK: - Grid slot card, v4 (v6: second design pass)
// Polished grid card used by the catalogue and the Home preview.
// Real platform logo on top, name, price per slot in KES and a
// stock pill. Sold-out cards show a waitlist action instead of a
// price push. Stock pill colours are flat tints, never a glowing
// dot. Low stock (5 or fewer left) reads in amber with the exact
// count, plenty of stock in the success tint, sold out in the
// danger tint. The card is one even height in the grid: the
// tagline is capped at two lines and the price block is pinned
// to the bottom, so rows line up.

struct SlotCard: View {
    let platform: Platform
    var isOnWaitlist: Bool = false
    var onWaitlistTap: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                PlatformLogoView(platform: platform, size: 56)
                Spacer()
                stockPill
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(platform.name)
                    .psTextStyle(.headline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Text(platform.tagline)
                    .psTextStyle(.caption)
                    .foregroundStyle(.psMuted)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(platform.formattedPrice)
                        .psTextStyle(.headline)
                    Text("per slot")
                        .psTextStyle(.caption)
                        .foregroundStyle(.psMuted)
                }
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .psTextStyle(.caption)
                        .foregroundStyle(.psMuted)
                        .accessibilityHidden(true)
                    Text(platform.duration)
                        .psTextStyle(.caption)
                        .foregroundStyle(.psMuted)
                    Spacer()
                    if !platform.isSoldOut, platform.slotsLeft <= 5 {
                        Text("Only \(platform.slotsLeft) left")
                            .psTextStyle(.caption)
                            .foregroundStyle(.psAmber)
                    }
                }

                if platform.isSoldOut {
                    Button {
                        onWaitlistTap?()
                    } label: {
                        Label(
                            isOnWaitlist ? "On waitlist" : "Join waitlist",
                            systemImage: isOnWaitlist ? "checkmark.circle.fill" : "bell.fill"
                        )
                        .psTextStyle(.caption)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)
                    .tint(.psCyan)
                    .accessibilityLabel(
                        isOnWaitlist
                            ? "On the waitlist for \(platform.name)"
                            : "Join the waitlist for \(platform.name)"
                    )
                } else {
                    HStack(spacing: 4) {
                        Text("Reserve")
                            .psTextStyle(.caption)
                            .foregroundStyle(.psCyan)
                        Image(systemName: "chevron.right")
                            .font(.psIconSmall)
                            .foregroundStyle(.psCyan)
                            .accessibilityHidden(true)
                    }
                    .accessibilityHidden(true)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 196, alignment: .leading)
        .background(Color.psSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.psBorder, lineWidth: 1)
        )
        .opacity(platform.isSoldOut ? 0.85 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(platform.name), \(platform.formattedPrice) per slot, " +
            (platform.isSoldOut ? "sold out" : "\(platform.slotsLeft) slots left")
        )
    }

    /// Flat tinted pill. Plenty of stock reads in the success tint,
    /// low stock in amber, sold out in the danger tint.
    private var stockPill: some View {
        Group {
            if platform.isSoldOut {
                Label("Sold out", systemImage: "xmark.circle.fill")
                    .foregroundStyle(.psDanger)
                    .background(Color.psDanger.opacity(0.12))
            } else if platform.slotsLeft <= 5 {
                Label("\(platform.slotsLeft) left", systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(.psAmber)
                    .background(Color.psAmber.opacity(0.14))
            } else {
                Label("\(platform.slotsLeft) left", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.psSuccess)
                    .background(Color.psSuccess.opacity(0.12))
            }
        }
        .psTextStyle(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .clipShape(Capsule())
    }
}

#Preview {
    HStack(spacing: 12) {
        SlotCard(platform: Platform.bundled[1])
        SlotCard(platform: Platform.bundled[0])
    }
    .padding()
    .background(Color.psBackground)
}
