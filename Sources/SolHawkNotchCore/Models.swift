import Foundation

/// Réponse de GET /api/companion/feed. Tout est optionnel : on n'invente jamais une valeur absente (« non lu »).
public struct Feed: Decodable, Sendable, Equatable {
    public var updatedAt: Date?
    public var stats: Stats
    public var items: [Item]
    public var note: String?
    /// Prix du SOL utilisé par le serveur (pour afficher les montants en SOL). Absent = non lu.
    public var solUSD: Double?

    enum CodingKeys: String, CodingKey { case updatedAt = "updated_at", stats, items, note, solUSD = "sol_usd" }

    public init(updatedAt: Date?, stats: Stats, items: [Item], note: String?) {
        self.updatedAt = updatedAt; self.stats = stats; self.items = items; self.note = note
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try c.decodeIfPresent(String.self, forKey: .updatedAt)
        updatedAt = raw.flatMap(Feed.parseDate)
        stats = try c.decodeIfPresent(Stats.self, forKey: .stats) ?? Stats()
        items = try c.decodeIfPresent([Item].self, forKey: .items) ?? []
        note = try c.decodeIfPresent(String.self, forKey: .note)
        solUSD = (try? c.decodeIfPresent(Double.self, forKey: .solUSD)).flatMap { $0 }.flatMap { $0.isFinite && $0 > 0 && $0 < 100_000 ? $0 : nil }
    }

    static func parseDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    public struct Stats: Decodable, Sendable, Equatable {
        public var seen: Int?
        public var dropped: Int?
        public var listed: Int?
        public var watching: Int?
        public var profile: String?
        public var drops: [String: Int]?
        public var rpc: Rpc?
        public var ghost: Ghost?
        public init(seen: Int? = nil, dropped: Int? = nil, listed: Int? = nil, watching: Int? = nil, profile: String? = nil,
                    drops: [String: Int]? = nil, rpc: Rpc? = nil, ghost: Ghost? = nil) {
            self.seen = seen; self.dropped = dropped; self.listed = listed; self.watching = watching; self.profile = profile
            self.drops = drops; self.rpc = rpc; self.ghost = ghost
        }
    }

    /// Raisons d'écart du scanner, en mots simples (clés du serveur). Une clé inconnue s'affiche telle quelle, sans être inventée.
    public static let dropLabels: [String: String] = [
        "dev_spam": "dev qui lance trop de tokens", "dumped": "déjà en chute", "no_concentration": "détenteurs non lus",
        "no_image": "image absente", "authority_active": "autorités non révoquées", "migrated": "déjà migré",
        "no_traction": "pas d'élan", "dev_holds_too_much": "dev détient trop", "dev_not_holding": "dev sans tokens",
        "whale_holder": "un gros détenteur", "risk_high": "risque trop haut",
    ]

    /// Une ligne honnête pour l'état « rien ne passe » : ce que le serveur a vu et pourquoi il l'a écarté. nil si rien n'est lu.
    public static func drySummary(_ s: Stats) -> String? {
        guard let seen = s.seen, seen > 0 else { return nil }
        var parts = ["\(seen) vus"]
        if let d = s.dropped { parts.append("\(d) écartés") }
        if let w = s.watching, w > 0 { parts.append("\(w) surveillés") }
        var line = parts.joined(separator: " · ")
        let top = (s.drops ?? [:]).filter { $0.value > 0 }.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.prefix(3)
        if !top.isEmpty { line += " — surtout : " + top.map { "\($0.value) \(dropLabels[$0.key] ?? $0.key.replacingOccurrences(of: "_", with: " "))" }.joined(separator: ", ") }
        return line
    }

    /// État de la lecture RPC du scanner (voyant du serveur). `errors` > 0 ou `no_rpc` > 0 = le serveur est partiellement aveugle.
    public struct Rpc: Decodable, Sendable, Equatable {
        public var ok: Int?
        public var errors: Int?
        public var noRpc: Int?
        public var lastError: String?
        enum CodingKeys: String, CodingKey { case ok, errors, noRpc = "no_rpc", lastError = "last_error" }
    }

    public struct Ghost: Decodable, Sendable, Equatable {
        public var tracked: Int?
        public var noPrice: Int?
        enum CodingKeys: String, CodingKey { case tracked, noPrice = "no_price" }
    }

    public struct Risk: Decodable, Sendable, Equatable {
        public var score: Int?
        public var label: String?
    }

    public struct Lights: Decodable, Sendable, Equatable {
        public var mint: String?
        public var freeze: String?
        public var dev: String?
        public var volume: String?
        public var holders: String?
        public var all: [String?] { [mint, freeze, dev, volume, holders] }
    }

    public struct Item: Decodable, Sendable, Equatable, Identifiable {
        public var mint: String
        public var symbol: String?
        public var name: String?
        public var ageS: Int?
        public var marketCap: Double?
        public var realSol: Double?
        public var risk: Risk?
        public var lights: Lights?
        /// Lectures réelles de la courbe : [âge en s, market cap en $]. Absent ou vide = pas d'historique (jamais inventé).
        public var series: [[Double]]?
        /// Écart en % par rapport au plus haut vu (négatif = en baisse). Absent = non lu.
        public var fromPeakPct: Double?
        /// Image déclarée par le créateur du token (non vérifiée, décorative) + sources de secours.
        public var imageURL: String?
        public var imageAlts: [String]?
        public var id: String { mint }

        enum CodingKeys: String, CodingKey {
            case mint, symbol, name, risk, lights, series
            case fromPeakPct = "from_peak_pct"
            case imageURL = "image_url", imageAlts = "image_alts"
            case ageS = "age_s", marketCap = "market_cap", realSol = "real_sol"
        }
    }
}
