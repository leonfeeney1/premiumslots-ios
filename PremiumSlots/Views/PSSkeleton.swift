import SwiftUI

// MARK: - Skeleton loading, v6
// Placeholder shapes shown immediately on a first load, so no screen
// you own ever starts blank. A skeleton is a pulsing surface shape,
// never a spinner alone and never fake data: it carries no text, no
// numbers and no names, and it is replaced by the real content (or
// by a real error state with retry) as soon as the load settles.
// Light and Dark both use the surface hover token, so the shapes
// stay visible in either theme. No emojis, SF Symbols only.

/// One pulsing placeholder block.
struct PSSkeletonBlock: View {
    var height: CGFloat = 16
    var cornerRadius: CGFloat = 8

    @State private var pulsing = false

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color.psSurfaceHover)
            .frame(height: height)
            .opacity(pulsing ? 0.5 : 1.0)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                ) {
                    pulsing = true
                }
            }
            .accessibilityHidden(true)
    }
}

/// One placeholder card: a logo tile plus two text lines, shaped
/// like a slot card or a list row card.
struct PSSkeletonCard: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.psSurfaceHover)
                .frame(width: 52, height: 52)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                PSSkeletonBlock(height: 15)
                    .frame(width: 140)
                PSSkeletonBlock(height: 12)
                    .frame(width: 190)
                PSSkeletonBlock(height: 12)
                    .frame(width: 90)
            }
            Spacer()
        }
        .padding(14)
        .background(Color.psSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.psBorder, lineWidth: 1)
        )
        .accessibilityHidden(true)
    }
}

/// Grid of placeholder cards, shaped like the catalogue grid.
struct PSSkeletonGrid: View {
    var count = 6

    var body: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ],
            spacing: 12
        ) {
            ForEach(0..<count, id: \.self) { _ in
                PSSkeletonCard()
            }
        }
        .accessibilityLabel("Loading")
    }
}

/// Placeholder stat tiles, shaped like the Home stat row.
struct PSSkeletonStats: View {
    var count = 3

    var body: some View {
        HStack(spacing: 12) {
            ForEach(0..<count, id: \.self) { _ in
                VStack(spacing: 8) {
                    PSSkeletonBlock(height: 20)
                        .frame(width: 48)
                    PSSkeletonBlock(height: 11)
                        .frame(width: 72)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.psSurface)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.psBorder, lineWidth: 1)
                )
            }
        }
        .accessibilityHidden(true)
    }
}

/// Placeholder list rows for List based screens.
struct PSSkeletonRows: View {
    var count = 4

    var body: some View {
        VStack(spacing: 12) {
            ForEach(0..<count, id: \.self) { _ in
                PSSkeletonCard()
            }
        }
        .accessibilityLabel("Loading")
    }
}
