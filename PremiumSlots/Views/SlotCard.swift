import SwiftUI

struct SlotCard: View {
    let platform: Platform

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.psAccent(named: platform.accent).opacity(0.16))
                    .frame(width: 48, height: 48)
                Image(systemName: platform.systemImage)
                    .font(.system(size: 22))
                    .foregroundStyle(Color.psAccent(named: platform.accent))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(platform.name)
                    .font(.psHeadline)
                    .lineLimit(1)
                Text(platform.tagline)
                    .font(.psCaption)
                    .foregroundStyle(.psMuted)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if platform.isSoldOut {
                        Label("Sold out", systemImage: "xmark.circle.fill")
                            .font(.psCaption)
                            .foregroundStyle(.red)
                    } else {
                        Label("\(platform.slotsLeft) left", systemImage: "checkmark.circle.fill")
                            .font(.psCaption)
                            .foregroundStyle(.green)
                    }
                    Text("·")
                        .foregroundStyle(.psMuted)
                    Text(platform.duration)
                        .font(.psCaption)
                        .foregroundStyle(.psMuted)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(platform.formattedPrice)
                    .font(.system(size: 16, weight: .semibold))
                Text("per slot")
                    .font(.psCaption)
                    .foregroundStyle(.psMuted)
            }
        }
        .padding(12)
        .background(Color.psSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.psBorder, lineWidth: 1)
        )
    }
}

#Preview {
    SlotCard(platform: Platform.bundled[1])
        .padding()
        .background(Color.psObsidian)
}
