import SwiftUI

// MARK: - Real platform logos, v4
// The website renders each platform logo from the service icon_name
// domain (for example "primevideo.com"). The logo image here comes
// from that platform official favicon, fetched through Google favicon
// service by domain, cached on disk and in memory. Nothing here is
// drawn or invented as a logo: while a fetch is in flight, or if it
// fails, the tile shows a plain monogram in the platform real brand
// colour. No generic SF Symbol is ever used as a platform logo.
//
// Platform now carries the live icon_name as iconDomain (fed from
// APIService.platform), so the real domain is used whenever the
// platform came from the live API. The name lookup below is only a
// fallback for bundled platforms.

/// Resolves a platform name to its logo domain, brand colour and
/// monogram initials.
enum PlatformLogoResolver {
    static func domain(for name: String) -> String? {
        let lower = name.lowercased()
        if lower.contains("spotify") { return "spotify.com" }
        if lower.contains("prime") { return "primevideo.com" }
        if lower.contains("peacock") { return "peacocktv.com" }
        if lower.contains("apple") { return "tv.apple.com" }
        if lower.contains("canva") { return "canva.com" }
        if lower.contains("tidal") { return "tidal.com" }
        if lower.contains("udemy") { return "udemy.com" }
        if lower.contains("gemini") { return "gemini.google.com" }
        return nil
    }

    /// Real brand colour for the monogram fallback tile. Black-brand
    /// platforms (Peacock, Apple TV, Tidal) use a near-black tile so
    /// the white initials stay readable in Light mode too.
    static func brandColor(for name: String) -> Color {
        let lower = name.lowercased()
        if lower.contains("spotify") { return Color(hex: 0x1DB954) }
        if lower.contains("prime") { return Color(hex: 0x00A8E1) }
        if lower.contains("peacock") { return Color(hex: 0x1A1A1C) }
        if lower.contains("apple") { return Color(hex: 0x1A1A1C) }
        if lower.contains("canva") { return Color(hex: 0x00C4CC) }
        if lower.contains("tidal") { return Color(hex: 0x1A1A1C) }
        if lower.contains("udemy") { return Color(hex: 0xA435F0) }
        if lower.contains("gemini") { return Color(hex: 0x1A73E8) }
        return .psPrimary
    }

    /// Two-letter monogram from the first two words of the name.
    static func initials(for name: String) -> String {
        let words = name
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        let letters = words.prefix(2).compactMap { $0.first }
        if letters.count == 2 {
            return String(letters).uppercased()
        }
        if let first = name.first {
            return String(first).uppercased()
        }
        return "PS"
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

// MARK: - Logo image cache

/// Fetches platform favicons and caches them in memory (NSCache) and
/// on disk (caches directory), keyed by domain. A failed fetch returns
/// nil and the caller shows the monogram tile.
final class PlatformLogoCache {
    static let shared = PlatformLogoCache()

    private let memory = NSCache<NSString, UIImage>()
    private let session = URLSession(configuration: .default)
    private let folderName = "platform-logos"

    private init() {}

    func image(for domain: String) async -> UIImage? {
        let key = domain as NSString
        if let cached = memory.object(forKey: key) { return cached }
        if let disk = loadFromDisk(domain: domain) {
            memory.setObject(disk, forKey: key)
            return disk
        }
        guard let url = URL(string: "https://www.google.com/s2/favicons?domain=\(domain)&sz=128") else {
            return nil
        }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode),
                  let image = UIImage(data: data) else {
                return nil
            }
            memory.setObject(image, forKey: key)
            saveToDisk(data, domain: domain)
            return image
        } catch {
            return nil
        }
    }

    private func folderURL() -> URL? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        let folder = caches.appendingPathComponent(folderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func diskURL(for domain: String) -> URL? {
        let safe = domain
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return folderURL()?.appendingPathComponent(safe + ".png")
    }

    private func loadFromDisk(domain: String) -> UIImage? {
        guard let url = diskURL(for: domain),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return UIImage(data: data)
    }

    private func saveToDisk(_ data: Data, domain: String) {
        guard let url = diskURL(for: domain) else { return }
        try? data.write(to: url, options: [.atomic])
    }
}

// MARK: - Logo view

/// Real platform logo in a rounded tile. Shows the fetched favicon
/// when available, otherwise a monogram tile in the platform real
/// brand colour.
struct PlatformLogoView: View {
    let name: String
    let domain: String?
    var size: CGFloat = 48

    @State private var image: UIImage?

    init(platform: Platform, size: CGFloat = 48) {
        self.name = platform.name
        self.domain = platform.iconDomain ?? PlatformLogoResolver.domain(for: platform.name)
        self.size = size
    }

    init(name: String, size: CGFloat = 48) {
        self.name = name
        self.domain = PlatformLogoResolver.domain(for: name)
        self.size = size
    }

    init(domain: String, name: String, size: CGFloat = 48) {
        self.name = name
        self.domain = domain
        self.size = size
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.12)
                    .background(Color.psSurface)
            } else {
                Text(PlatformLogoResolver.initials(for: name))
                    .font(.psMonogram(for: size))
                    .foregroundStyle(.psPaper)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(PlatformLogoResolver.brandColor(for: name))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.24))
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.24)
                .stroke(Color.psBorder, lineWidth: 1)
        )
        .accessibilityLabel("\(name) logo")
        .task {
            guard let domain, image == nil else { return }
            image = await PlatformLogoCache.shared.image(for: domain)
        }
    }
}

#Preview {
    HStack(spacing: 12) {
        PlatformLogoView(platform: Platform.bundled[0])
        PlatformLogoView(platform: Platform.bundled[1])
        PlatformLogoView(platform: Platform.bundled[4])
        PlatformLogoView(name: "Unknown Platform")
    }
    .padding()
    .background(Color.psBackground)
}
