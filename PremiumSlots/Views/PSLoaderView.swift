import SwiftUI

// MARK: - PremiumSlots HUD loader, v3 (Fix #1)
// Faithful SwiftUI port of the website's real loader
// (templates/partials/loader.html, "FULLSCREEN CUSTOM UIVERSE LOADER").
// It is a HUD scene, not a plain ring:
//   - full-screen #0a0a0a background (dark in both themes, as on the web)
//   - 240px ring container: outer dashed ring 20s clockwise,
//     middle ring 3s counter-clockwise with bounce easing,
//     inner ring 5s clockwise, pulsing radial core
//   - 60x60 real logo, pulsing scale 0.95-1.05 / opacity 0.75-1 over 2s
//   - 320x4px gradient progress bar, scaleX 0 to 1 from the left then
//     1 to 0 from the right over 2s
//   - "ESTABLISHING CONNECTION" in letterspaced type, #7FCDFF
//   - JetBrains Mono corner data (decorative HUD strings from the web
//     page; shown only on this loading screen, never as the app's own
//     version/build numbers)
// The parent shows this view while loading and fades it out over 0.6s
// (matching the web: fade after load + 1500ms, removed after 600ms).
// Use PSLoaderView for full-screen loads and PSRingSpinner for buttons
// and inline loading. Use ProgressView nowhere in the app.

struct PSLoaderView: View {
    @State private var outerAngle: Double = 0
    @State private var middleAngle: Double = 0
    @State private var innerAngle: Double = 0
    @State private var coreOpacity: Double = 0.3
    @State private var logoScale: CGFloat = 0.95
    @State private var logoOpacity: Double = 0.75
    @State private var gridOffset: CGFloat = 0
    @State private var barScale: CGFloat = 0
    @State private var barDraining = false

    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.04, blue: 0.04)
                .ignoresSafeArea()

            PSHudGrid(offset: gridOffset)

            VStack(spacing: 0) {
                ZStack {
                    // Outer ring: 2px dashed, 20s clockwise.
                    Circle()
                        .stroke(Color(red: 0.33, green: 0.73, blue: 0.97).opacity(0.3),
                                style: StrokeStyle(lineWidth: 2, dash: [6, 6]))
                        .rotationEffect(.degrees(outerAngle))
                    // Middle ring: top #55B7F7 / bottom #2D9CE5,
                    // 3s counter-clockwise, bounce easing.
                    Circle()
                        .trim(from: 0, to: 0.75)
                        .stroke(
                            AngularGradient(
                                gradient: Gradient(colors: [
                                    Color(red: 0.33, green: 0.73, blue: 0.97),
                                    Color(red: 0.18, green: 0.61, blue: 0.90),
                                    Color.clear
                                ]),
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round)
                        )
                        .rotationEffect(.degrees(middleAngle))
                    // Inner ring: 1px border, #7FCDFF edge, 5s clockwise.
                    Circle()
                        .trim(from: 0, to: 0.3)
                        .stroke(Color(red: 0.50, green: 0.80, blue: 1.00),
                                style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .padding(35)
                        .rotationEffect(.degrees(innerAngle))
                    // Pulsing radial core.
                    Circle()
                        .fill(
                            RadialGradient(
                                gradient: Gradient(colors: [
                                    Color(red: 0.18, green: 0.61, blue: 0.90).opacity(0.2),
                                    Color.clear
                                ]),
                                center: .center,
                                startRadius: 0,
                                endRadius: 65
                            )
                        )
                        .padding(55)
                        .opacity(coreOpacity)
                    // 60x60 real logo, pulsing.
                    RealLogoView(size: 60)
                        .scaleEffect(logoScale)
                        .opacity(logoOpacity)
                }
                .frame(width: 240, height: 240)
                .padding(.bottom, 50)

                // Progress bar: 320x4, gradient #1E85CC -> #2D9CE5 -> #7FCDFF.
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color(red: 0.18, green: 0.61, blue: 0.90).opacity(0.2))
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.12, green: 0.52, blue: 0.80),
                                         Color(red: 0.18, green: 0.61, blue: 0.90),
                                         Color(red: 0.50, green: 0.80, blue: 1.00)],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .shadow(color: Color(red: 0.18, green: 0.61, blue: 0.90), radius: 10)
                        .scaleEffect(x: barScale, y: 1,
                                     anchor: barDraining ? .trailing : .leading)
                }
                .frame(width: 320, height: 4)
                .padding(.bottom, 24)

                Text("ESTABLISHING CONNECTION")
                    .font(.system(size: 14, weight: .bold, design: .default))
                    .tracking(4.2)
                    .foregroundStyle(Color(red: 0.50, green: 0.80, blue: 1.00))
                    .shadow(color: Color(red: 0.18, green: 0.61, blue: 0.90).opacity(0.5), radius: 8)
            }

            // Corner HUD data, JetBrains Mono equivalent (SF Mono).
            VStack {
                HStack {
                    hudCorner("SYS.INIT...\nMEM: OK\nNET: SECURE")
                    Spacer()
                    hudCorner("AUTH: PENDING\nKEY: 0x9A2F\nENC: AES-256")
                }
                Spacer()
                HStack {
                    hudCorner("LOC: NAIROBI\nLAT: -1.2921\nLNG: 36.8219")
                    Spacer()
                    hudCorner("VER: 2.4.1\nBULD: 9812\nSTS: ONLINE")
                }
            }
            .padding(30)
        }
        .task {
            withAnimation(.linear(duration: 20).repeatForever(autoreverses: false)) {
                outerAngle = 360
            }
            withAnimation(.timingCurve(0.68, -0.55, 0.265, 1.55, duration: 3)
                .repeatForever(autoreverses: false)) {
                middleAngle = -360
            }
            withAnimation(.linear(duration: 5).repeatForever(autoreverses: false)) {
                innerAngle = 360
            }
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                coreOpacity = 1
                logoScale = 1.05
                logoOpacity = 1
            }
            withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
                gridOffset = 50
            }
            // Progress bar: fill from the left over 1s, drain to the
            // right over 1s, repeat (web: 2s psProgressFill).
            while !Task.isCancelled {
                barDraining = false
                barScale = 0
                withAnimation(.timingCurve(0.77, 0, 0.175, 1, duration: 1)) {
                    barScale = 1
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                barDraining = true
                withAnimation(.timingCurve(0.77, 0, 0.175, 1, duration: 1)) {
                    barScale = 0
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func hudCorner(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .regular, design: .monospaced))
            .foregroundStyle(Color(red: 0.33, green: 0.73, blue: 0.97).opacity(0.5))
            .multilineTextAlignment(.leading)
    }
}

/// Faint 50px HUD grid, drifting 0 to 50px over 8s (web: psGridMove).
/// A simplified flat grid; the web version adds a perspective tilt.
private struct PSHudGrid: View {
    var offset: CGFloat

    var body: some View {
        GeometryReader { geo in
            Path { path in
                let step: CGFloat = 50
                var y = -step + offset.truncatingRemainder(dividingBy: step)
                while y < geo.size.height + step {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: geo.size.width, y: y))
                    y += step
                }
                var x: CGFloat = 0
                while x < geo.size.width + step {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: geo.size.height))
                    x += step
                }
            }
            .stroke(Color(red: 0.18, green: 0.61, blue: 0.90).opacity(0.15), lineWidth: 1)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Inline ring spinner (web §4.7)
// 40px circle, 4px border, track border colour, border-left #2D9CE5,
// spin 1s linear infinite. Small variants 32px/3px (0.8s), 24px/2px,
// 20px/2px. Button spinner: 14px, current colour, 0.7s.
struct PSRingSpinner: View {
    var diameter: CGFloat = 40
    var lineWidth: CGFloat = 4
    var color: Color = .psPrimary
    var duration: Double = 1

    @State private var angle: Double = 0

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.75)
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .frame(width: diameter, height: diameter)
            .rotationEffect(.degrees(angle))
            .onAppear {
                withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
                    angle = 360
                }
            }
            .accessibilityLabel("Loading")
    }
}

#Preview {
    PSLoaderView()
}
