import SwiftUI

// MARK: - PremiumSlots theme
// Real brand: shield P logo in blue and cyan gradients, dark obsidian
// surfaces, electric blue and cyan accents. No emojis in the UI;
// SF Symbols only.

extension Color {
    static let psObsidian = Color(red: 0.02, green: 0.02, blue: 0.02)
    static let psSurface = Color(red: 0.04, green: 0.05, blue: 0.09)
    static let psElectricBlue = Color(red: 0.12, green: 0.52, blue: 0.80)
    static let psCyan = Color(red: 0.22, green: 0.74, blue: 0.97)
    static let psLightCyan = Color(red: 0.33, green: 0.72, blue: 0.97)
    static let psDeepBlue = Color(red: 0.08, green: 0.38, blue: 0.65)
    static let psMuted = Color(red: 0.55, green: 0.61, blue: 0.71)
    static let psPaper = Color(red: 0.97, green: 0.98, blue: 0.99)
    static let psInk = Color(red: 0.06, green: 0.09, blue: 0.16)
    static let psAmber = Color(red: 0.96, green: 0.66, blue: 0.18)

    static func psAccent(named name: String) -> Color {
        switch name {
        case "green": return .green
        case "yellow": return .yellow
        case "black": return .primary
        case "purple": return .purple
        case "cyan": return .psCyan
        case "red": return .red
        default: return .psElectricBlue
        }
    }
}

extension Font {
    static let psTitle = Font.system(size: 28, weight: .bold, design: .default)
    static let psHeadline = Font.system(size: 18, weight: .semibold, design: .default)
    static let psBody = Font.system(size: 16, weight: .regular, design: .default)
    static let psCaption = Font.system(size: 13, weight: .regular, design: .default)
}

struct PSPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                LinearGradient(
                    colors: [.psElectricBlue, .psCyan],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .opacity(configuration.isPressed ? 0.85 : 1.0)
    }
}

extension Button {
    func psPrimary() -> some View {
        buttonStyle(PSPrimaryButtonStyle())
    }
}

// MARK: - Shield P logo, drawn as a SwiftUI shape
// This is a fresh shield-and-P mark in the brand gradients. It is not a
// copy of any logo file.

struct ShieldLogoView: View {
    var size: CGFloat = 56

    var body: some View {
        ZStack {
            ShieldShape()
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.09, green: 0.13, blue: 0.19), Color(red: 0.04, green: 0.09, blue: 0.13)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    ShieldShape()
                        .stroke(
                            LinearGradient(
                                colors: [.psLightCyan, .psElectricBlue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                )
            Text("P")
                .font(.system(size: size * 0.52, weight: .black, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.white, .psLightCyan, .psElectricBlue, .psDeepBlue],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
        .frame(width: size, height: size)
        .accessibilityLabel("PremiumSlots shield logo")
    }
}

struct ShieldShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        path.move(to: CGPoint(x: w * 0.5, y: rect.minY))
        path.addLine(to: CGPoint(x: w * 0.92, y: rect.minY + h * 0.14))
        path.addLine(to: CGPoint(x: w * 0.92, y: rect.minY + h * 0.55))
        path.addCurve(
            to: CGPoint(x: w * 0.5, y: rect.minY + h * 0.98),
            control1: CGPoint(x: w * 0.92, y: rect.minY + h * 0.82),
            control2: CGPoint(x: w * 0.78, y: rect.minY + h * 0.95)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.08, y: rect.minY + h * 0.55),
            control1: CGPoint(x: w * 0.22, y: rect.minY + h * 0.95),
            control2: CGPoint(x: w * 0.08, y: rect.minY + h * 0.82)
        )
        path.addLine(to: CGPoint(x: w * 0.08, y: rect.minY + h * 0.14))
        path.closeSubpath()
        return path
    }
}
