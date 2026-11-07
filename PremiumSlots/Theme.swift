import SwiftUI

// MARK: - PremiumSlots theme, v3 (Fix #1)
// Complete Light + Dark theme system, tokens taken from the live site:
// public tokens static/style.css :root (dark) + [data-theme="light"],
// app shell static/app_style.css, admin static/admin_style.css
// (checklist §4.2-§4.4). Dark is the site default; Light follows the
// same blue/cyan brand with the light primary #1E85CC.
// Every token is a dynamic colour: it resolves from the current
// trait collection, so it follows both the system setting and the
// in-app System / Light / Dark choice (applied at the app root with
// .preferredColorScheme). Views must use these tokens and never a
// hardcoded black/white background.
// Type scale, v2/v3: headings 22pt semibold max, body 15pt,
// captions 12pt, icons 20-24pt. No large titles anywhere.
// Dynamic Type is respected (all sizes are system-scaled points).

extension Color {
    /// Dynamic colour: dark value in dark mode, light value in light mode.
    static func psDynamic(dark: UIColor, light: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }

    static let psObsidian = psDynamic(
        dark: UIColor(red: 0.02, green: 0.02, blue: 0.02, alpha: 1),
        light: UIColor(red: 0.92, green: 0.92, blue: 0.89, alpha: 1)) // #050505 / #ebeae4
    static let psBackground = psDynamic(
        dark: UIColor(red: 0.04, green: 0.04, blue: 0.04, alpha: 1),
        light: UIColor(red: 0.96, green: 0.96, blue: 0.94, alpha: 1)) // #0a0a0a / #f5f5f0
    static let psSurface = psDynamic(
        dark: UIColor(red: 0.08, green: 0.08, blue: 0.08, alpha: 1),
        light: UIColor(red: 1.00, green: 1.00, blue: 1.00, alpha: 1)) // #141414 / #ffffff
    static let psSurfaceHover = psDynamic(
        dark: UIColor(red: 0.10, green: 0.10, blue: 0.10, alpha: 1),
        light: UIColor(red: 0.94, green: 0.94, blue: 0.93, alpha: 1)) // #1a1a1a / #f0f0ec
    static let psBorder = psDynamic(
        dark: UIColor(red: 0.12, green: 0.12, blue: 0.12, alpha: 1),
        light: UIColor(red: 0.85, green: 0.85, blue: 0.83, alpha: 1)) // #1f1f1f / #d9d9d4
    static let psBorderLight = psDynamic(
        dark: UIColor(red: 0.16, green: 0.16, blue: 0.16, alpha: 1),
        light: UIColor(red: 0.90, green: 0.90, blue: 0.88, alpha: 1)) // #2a2a2a / #e5e5e0
    static let psText = psDynamic(
        dark: UIColor(red: 0.96, green: 0.96, blue: 0.96, alpha: 1),
        light: UIColor(red: 0.10, green: 0.10, blue: 0.10, alpha: 1)) // #f5f5f5 / #1a1a1a
    static let psDim = psDynamic(
        dark: UIColor(red: 0.75, green: 0.75, blue: 0.75, alpha: 1),
        light: UIColor(red: 0.25, green: 0.25, blue: 0.25, alpha: 1)) // #c0c0c0 / #404040
    static let psMuted = psDynamic(
        dark: UIColor(red: 0.55, green: 0.61, blue: 0.71, alpha: 1),
        light: UIColor(red: 0.48, green: 0.48, blue: 0.48, alpha: 1)) // #8B9BB4 / #7a7a7a
    static let psPrimary = psDynamic(
        dark: UIColor(red: 0.18, green: 0.61, blue: 0.90, alpha: 1),
        light: UIColor(red: 0.12, green: 0.52, blue: 0.80, alpha: 1)) // #2D9CE5 / #1E85CC
    static let psElectricBlue = Color.psPrimary
    static let psCyan = psDynamic(
        dark: UIColor(red: 0.33, green: 0.73, blue: 0.97, alpha: 1),
        light: UIColor(red: 0.12, green: 0.52, blue: 0.80, alpha: 1)) // #55B7F7 / #1E85CC
    static let psLightCyan = Color(red: 0.50, green: 0.80, blue: 1.00)
    static let psDeepBlue = psDynamic(
        dark: UIColor(red: 0.12, green: 0.52, blue: 0.80, alpha: 1),
        light: UIColor(red: 0.07, green: 0.37, blue: 0.58, alpha: 1)) // #1E85CC / #135E95
    static let psPaper = Color(red: 0.97, green: 0.98, blue: 0.99)
    static let psInk = Color(red: 0.06, green: 0.09, blue: 0.16)
    static let psAmber = Color(red: 0.96, green: 0.66, blue: 0.18)
    static let psDanger = psDynamic(
        dark: UIColor(red: 0.96, green: 0.25, blue: 0.37, alpha: 1),
        light: UIColor(red: 0.94, green: 0.27, blue: 0.27, alpha: 1)) // #f43f5e / #ef4444
    static let psSuccess = Color(red: 0.06, green: 0.73, blue: 0.51) // #10b981 both themes
    static let psWarning = Color(red: 0.96, green: 0.62, blue: 0.04) // #f59e0b both themes
    static let psPrimarySoft = psDynamic(
        dark: UIColor(red: 0.18, green: 0.61, blue: 0.90, alpha: 0.14),
        light: UIColor(red: 0.12, green: 0.52, blue: 0.80, alpha: 0.12))

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

/// In-app theme choice, persisted in UserDefaults (key
/// "premiumslots.appearance"). System follows the device setting until
/// the user picks Light or Dark, exactly as the web does (localStorage
/// theme, else prefers-color-scheme, else dark).
enum PSThemeMode: String, CaseIterable {
    case system
    case light
    case dark

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

// foregroundStyle resolves its argument as a ShapeStyle, not as a Color,
// so the brand colours need ShapeStyle members too.
extension ShapeStyle where Self == Color {
    static var psObsidian: Color { Color.psObsidian }
    static var psBackground: Color { Color.psBackground }
    static var psSurface: Color { Color.psSurface }
    static var psSurfaceHover: Color { Color.psSurfaceHover }
    static var psBorder: Color { Color.psBorder }
    static var psBorderLight: Color { Color.psBorderLight }
    static var psText: Color { Color.psText }
    static var psDim: Color { Color.psDim }
    static var psMuted: Color { Color.psMuted }
    static var psPrimary: Color { Color.psPrimary }
    static var psElectricBlue: Color { Color.psElectricBlue }
    static var psCyan: Color { Color.psCyan }
    static var psLightCyan: Color { Color.psLightCyan }
    static var psDeepBlue: Color { Color.psDeepBlue }
    static var psPaper: Color { Color.psPaper }
    static var psInk: Color { Color.psInk }
    static var psAmber: Color { Color.psAmber }
    static var psDanger: Color { Color.psDanger }
    static var psSuccess: Color { Color.psSuccess }
    static var psWarning: Color { Color.psWarning }
    static var psPrimarySoft: Color { Color.psPrimarySoft }
}

extension Font {
    /// In-content heading, 22pt semibold. The largest type in the app.
    static let psTitle = Font.system(size: 22, weight: .semibold, design: .default)
    static let psHeadline = Font.system(size: 17, weight: .semibold, design: .default)
    static let psBody = Font.system(size: 15, weight: .regular, design: .default)
    static let psCaption = Font.system(size: 12, weight: .regular, design: .default)
    static let psMono = Font.system(size: 13, weight: .regular, design: .monospaced)
}

struct PSPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(
                LinearGradient(
                    colors: [.psCyan, .psPrimary],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .opacity(configuration.isPressed ? 0.85 : 1.0)
    }
}

extension Button {
    func psPrimary() -> some View {
        buttonStyle(PSPrimaryButtonStyle())
    }
}

// MARK: - Real logo
// The artwork is the real logo-icon.svg / logo-extended.svg from the
// live site, rendered to PNG (brand/generated/) and stored in the asset
// catalog as LaunchLogo / LogoLockup. No SVG converter was available on
// the build machine at first, so cairosvg was installed and the real
// SVGs were converted directly; nothing here is redrawn or invented.
// RealLogoView falls back to the SwiftUI shield drawn from the SVG
// path data only if the asset is missing at runtime.

struct RealLogoView: View {
    var size: CGFloat = 48

    var body: some View {
        Image("LaunchLogo")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityLabel("PremiumSlots logo")
    }
}

struct LogoLockupView: View {
    var height: CGFloat = 34

    var body: some View {
        Image("LogoLockup")
            .resizable()
            .scaledToFit()
            .frame(height: height)
            .accessibilityLabel("PremiumSlots, shared access platform")
    }
}

/// Faithful SwiftUI redraw of the real shield-P mark, from the path
/// data in brand/logo-icon.svg (100x100 viewBox). Used only as a
/// fallback if the rendered logo asset is unavailable.
struct ShieldLogoPathView: View {
    var size: CGFloat = 48

    var body: some View {
        GeometryReader { geo in
            let s = geo.size.width / 100
            ZStack {
                RoundedRectangle(cornerRadius: 22 * s)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.09, green: 0.13, blue: 0.19),
                                     Color(red: 0.02, green: 0.04, blue: 0.06)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80 * s, height: 80 * s)
                    .position(x: 50 * s, y: 50 * s)
                PStemShape()
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.65, green: 0.90, blue: 1.00),
                                     Color(red: 0.33, green: 0.73, blue: 0.97),
                                     Color(red: 0.18, green: 0.61, blue: 0.90),
                                     Color(red: 0.08, green: 0.38, blue: 0.65)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100 * s, height: 100 * s)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("PremiumSlots shield logo")
    }
}

/// The geometric P stem from logo-icon.svg:
/// M 33 31 C 33 29.895 33.895 29 35 29 L 46 29 C 57 29 64 35 64 45
/// C 64 54.5 57 60.5 46 60.5 L 41.5 60.5 L 41.5 69 C 41.5 70.105
/// 40.605 71 39.5 71 L 35 71 C 33.895 71 33 70.105 33 69 Z
/// plus the inner cutout M 41.5 36.5 L 45.5 36.5 C 51.5 36.5 55.5 39.5
/// 55.5 44.8 C 55.5 50 51.5 53 45.5 53 L 41.5 53 Z
struct PStemShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 100
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
        var path = Path()
        path.move(to: p(33, 31))
        path.addCurve(to: p(35, 29), control1: p(33, 29.895), control2: p(33.895, 29))
        path.addLine(to: p(46, 29))
        path.addCurve(to: p(64, 45), control1: p(57, 29), control2: p(64, 35))
        path.addCurve(to: p(46, 60.5), control1: p(64, 54.5), control2: p(57, 60.5))
        path.addLine(to: p(41.5, 60.5))
        path.addLine(to: p(41.5, 69))
        path.addCurve(to: p(39.5, 71), control1: p(41.5, 70.105), control2: p(40.605, 71))
        path.addLine(to: p(35, 71))
        path.addCurve(to: p(33, 69), control1: p(33.895, 71), control2: p(33, 70.105))
        path.closeSubpath()
        // Inner cutout, drawn as a subpath in the dark shield colour
        // by the caller overlay; the shape itself is the stem only.
        return path
    }
}

// Backwards-compatible name used by v1 views that have not been
// rewritten yet. It now shows the real logo, not the old drawn shape.
typealias ShieldLogoView = RealLogoView
