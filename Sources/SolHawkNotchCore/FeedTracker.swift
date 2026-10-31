import Foundation

/// Repère les NOUVEAUX tokens listés. Le premier relevé fixe l'état de départ : on n'« alerte » pas sur ce qui était déjà là.
public struct FeedTracker: Sendable {
    public private(set) var seen: Set<String> = []
    public private(set) var primed = false
    public private(set) var spotted: [Feed.Item] = []
    public private(set) var spottedUntil: Date?
    public var holdS: TimeInterval = 20
    static let maxSeen = 5000

    public init() {}

    public mutating func ingest(_ feed: Feed, now: Date) {
        if seen.count > Self.maxSeen { seen.removeAll() }
        let fresh = feed.items.filter { !seen.contains($0.mint) }
        for item in fresh { seen.insert(item.mint) }
        guard primed else { primed = true; return }
        if !fresh.isEmpty { spotted = fresh; spottedUntil = now.addingTimeInterval(holdS) }
    }

    public func activeSpotted(now: Date) -> [Feed.Item] {
        guard let until = spottedUntil, now < until else { return [] }
        return spotted
    }
}

/// Phrases affichées (françaises, sans promesse). « Passe les filtres » n'est jamais « sûr ».
public func describe(_ m: Mood) -> String {
    switch m {
    case .waiting: return "En attente des premières données"
    case .calm(let n): return n == 0 ? "Calme · 0 listé (état normal, pas un feu vert)" : "Calme · \(n) listé\(n > 1 ? "s" : "")"
    case .spotted(let passes): return passes ? "Nouveau token · passe les filtres (aucune garantie)" : "Nouveau token · à vérifier"
    case .stale(let s): return "Données du serveur périmées (il y a \(s) s)"
    case .offline: return "Serveur injoignable"
    case .tokenRejected: return "Jeton refusé · interrogation arrêtée"
    case .badConfig: return "Adresse du serveur refusée · HTTPS obligatoire (réglages)"
    case .rateLimited(let s): return "Serveur occupé · reprise dans \(s) s"
    }
}

/// Un « mint » vient du réseau : NON FIABLE. On ne l'utilise (copie, lien) que s'il a la forme d'une adresse Solana (base58, 32-44 car.).
public func isValidMint(_ s: String) -> Bool {
    guard (32...44).contains(s.count) else { return false }
    let alphabet = Set("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
    return s.allSatisfy { alphabet.contains($0) }
}

public func dexScreenerURL(mint: String) -> URL? { isValidMint(mint) ? URL(string: "https://dexscreener.com/solana/\(mint)") : nil }

/// Texte du serveur (symbole, nom) : affiché tel quel mais borné, sur une ligne, sans caractère de contrôle.
public func safeLabel(_ s: String?, max: Int = 12) -> String {
    guard let s, !s.isEmpty else { return "non lu" }
    let cleaned = String(s.unicodeScalars.filter { !$0.properties.isDefaultIgnorableCodePoint && $0.value >= 32 && $0.value != 127 }.map(Character.init))
    let t = cleaned.trimmingCharacters(in: .whitespaces)
    return t.isEmpty ? "non lu" : String(t.prefix(max))
}

/// Raisons d'abandon traduites pour l'écran (les clés viennent du serveur).
public func dropLabel(_ key: String) -> String {
    switch key {
    case "dev_spam": return "dev spammeur"
    case "no_traction": return "pas de traction"
    case "authority_active": return "autorité active"
    case "dumped": return "chute de liquidité"
    case "no_image": return "sans image"
    case "dev_holds_too_much": return "dev détient trop"
    case "dev_not_holding": return "dev a vendu"
    case "whale_holder": return "baleine"
    case "no_concentration": return "concentration non lue"
    case "risk_high": return "risque élevé"
    case "migrated": return "migré"
    default: return safeLabel(key, max: 22)
    }
}

/// Petite phrase du personnage. Ton « meme » léger, JAMAIS une promesse ni un conseil d'achat.
public func quip(_ m: Mood) -> String {
    switch m {
    case .waiting: return "Je me réveille…"
    case .calm(let n): return n == 0 ? "Rien à signaler." : "\(n) en vue. À toi de voir."
    case .spotted(let passes): return passes ? "Oh, un nouveau. Il passe les filtres… ça ne prouve rien." : "Un nouveau. Hmm, à vérifier."
    case .stale: return "Zzz… le serveur ne dit plus rien."
    case .offline: return "Plus de réseau ?"
    case .tokenRejected: return "On m'a fermé la porte (jeton)."
    case .badConfig: return "Cette adresse ne va pas. Regarde les réglages."
    case .rateLimited: return "Trop de coups d'un coup. Pause."
    }
}
