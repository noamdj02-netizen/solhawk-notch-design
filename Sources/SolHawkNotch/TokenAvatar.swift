import AppKit
import ImageIO
import SwiftUI
import SolHawkNotchCore

/// Cache des logos de tokens. https + hôtes connus seulement (filtrés dans le cœur), sans cookies, taille bornée,
/// décodé en vignette (une image piégée ne peut pas faire exploser la mémoire). Échec = initiale colorée, jamais d'erreur affichée.
@MainActor
final class LogoCache {
    static let shared = LogoCache()
    private var images: [URL: NSImage] = [:]
    private var failed: Set<URL> = []
    private var inflight: [URL: Task<NSImage?, Never>] = [:]
    private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.httpCookieAcceptPolicy = .never; c.httpShouldSetCookies = false
        c.timeoutIntervalForRequest = 6; c.timeoutIntervalForResource = 10
        c.httpAdditionalHeaders = ["Accept": "image/*"]
        return URLSession(configuration: c)
    }()

    func cached(_ urls: [URL]) -> NSImage? { urls.lazy.compactMap { self.images[$0] }.first }

    func load(_ urls: [URL]) async -> NSImage? {
        for u in urls where !failed.contains(u) {
            if let i = images[u] { return i }
            let task = inflight[u] ?? Task { await Self.fetch(u, session: session) }
            inflight[u] = task
            let img = await task.value
            inflight[u] = nil
            if let img { images[u] = img; if images.count > 400 { images.removeAll() }; return img }
            failed.insert(u)
        }
        return nil
    }

    nonisolated private static func fetch(_ u: URL, session: URLSession) async -> NSImage? {
        guard let (data, resp) = try? await session.data(from: u), let http = resp as? HTTPURLResponse, http.statusCode == 200,
              (http.mimeType ?? "").hasPrefix("image/"), data.count <= imageMaxBytes,
              let src = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                                                    kCGImageSourceThumbnailMaxPixelSize: 128,
                                                                    kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary)
        else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}

/// Logo rond du token ; à défaut, son initiale sur une teinte stable.
struct TokenAvatar: View {
    var mint: String
    var symbol: String?
    var urls: [URL]
    var size: CGFloat = 22
    @State private var image: NSImage?

    init(item: Feed.Item, size: CGFloat = 22) { mint = item.mint; symbol = item.symbol; urls = imageCandidates(item); self.size = size }
    init(mint: String, symbol: String?, image: String?, size: CGFloat = 22) {
        self.mint = mint; self.symbol = symbol; self.size = size
        urls = imageCandidates(raw: image.map { [$0] } ?? [])
    }

    var body: some View {
        ZStack {
            if let img = image ?? LogoCache.shared.cached(urls) {
                Image(nsImage: img).resizable().interpolation(.high).aspectRatio(contentMode: .fill).transition(.opacity)
            } else {
                Circle().fill(Color(hue: avatarHue(mint), saturation: 0.45, brightness: 0.55))
                Text(avatarInitial(symbol)).font(.system(size: size * 0.46, weight: .bold, design: .rounded)).foregroundStyle(.white.opacity(0.92))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
        .task(id: urls) {
            guard !urls.isEmpty, image == nil else { return }
            let img = await LogoCache.shared.load(urls)
            withAnimation(.easeOut(duration: 0.2)) { image = img }
        }
        .accessibilityHidden(true)
    }
}

/// Pile de logos (barre de l'encoche) : jusqu'à 3, qui se chevauchent comme dans la Dynamic Island.
struct AvatarStack: View {
    var items: [Feed.Item]
    var size: CGFloat = 16
    var body: some View {
        HStack(spacing: -size * 0.38) {
            ForEach(items.prefix(3)) { TokenAvatar(item: $0, size: size).overlay(Circle().strokeBorder(.black, lineWidth: 1.5)) }
        }
    }
}
