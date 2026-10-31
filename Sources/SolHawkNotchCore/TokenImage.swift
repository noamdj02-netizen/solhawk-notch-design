import Foundation

/// Hôtes d'images acceptés. L'image vient du créateur du token (donnée non fiable) : on ne charge que du https,
/// depuis des hôtes connus (CDN Pump.fun, passerelles IPFS), pour ne pas laisser n'importe quel serveur savoir que tu regardes ce token.
public let imageHosts: Set<String> = ["images.pump.fun", "gateway.pinata.cloud", "4everland.io", "ipfs.io", "cf-ipfs.com", "dweb.link"]
public let imageMaxBytes = 2_000_000

/// Sources d'image à essayer, dans l'ordre, filtrées (https + hôte connu, sans identifiants ni port exotique). Au plus 4.
public func imageCandidates(_ item: Feed.Item) -> [URL] { imageCandidates(raw: [item.imageURL].compactMap { $0 } + (item.imageAlts ?? [])) }

public func imageCandidates(raw list: [String]) -> [URL] {
    var out: [URL] = []
    for raw in list {
        guard raw.count <= 512, let u = URL(string: raw), u.scheme == "https", let h = u.host?.lowercased(),
              imageHosts.contains(h), u.user == nil, u.password == nil, u.port == nil || u.port == 443 else { continue }
        if !out.contains(u) { out.append(u) }
        if out.count == 4 { break }
    }
    return out
}

/// Initiale et teinte stable (pour l'avatar de remplacement quand il n'y a pas d'image).
public func avatarInitial(_ symbol: String?) -> String {
    guard let symbol, !symbol.isEmpty else { return "?" }
    let s = safeLabel(symbol).trimmingCharacters(in: .whitespaces)
    return s.first.map { String($0).uppercased() } ?? "?"
}

public func avatarHue(_ mint: String) -> Double { Double(stableHash(mint) % 360) / 360 }
