import SwiftUI

struct SlotCard: View {
    let platform: Platform
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.psAccent(named: platform.accent).opacity(0.16))
                    .frame(width: 56, height: 56)
                Image(systemName: platform.systemImage)
                    .font(.title2)
                    .foregroundStyle(Color.psAccent(named: platform.accent))
            }

            VStack(alignment: .leading, spacing: 4) {
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

            VStack(alignment: .trailing, spacing: 4) {
                Text(platform.formattedPrice)
                    .font(.headline)
                Text("per slot")
                    .font(.psCaption)
                    .foregroundStyle(.psMuted)
            }
        }
        .padding(14)
        .background(Color.psSurface)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }
}

#Preview {
    SlotCard(platform: Platform.bundled[1])
        .environmentObject(AppState())
        .padding()
        .background(Color.psObsidian)
}
