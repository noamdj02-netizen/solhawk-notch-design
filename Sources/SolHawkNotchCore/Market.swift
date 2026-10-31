import Foundation

// Données « terminal » du serveur (lecture seule). Tout est optionnel : une donnée absente reste « non lue ».

/// Une bougie du MARKET CAP (o/h/l/c), calculée par le serveur à partir d'échantillons (≥ 1 s) ou de l'historique GeckoTerminal 1 min.
/// Pas de vrai volume : `flowSol` = variation des SOL déposés sur la courbe pendant la bougie, quand elle est lisible.
public struct Candle: Decodable, Sendable, Equatable {
    public var t: Double
    public var o: Double
    public var h: Double
    public var l: Double
    public var c: Double
    public var flowSol: Double?
    enum CodingKeys: String, CodingKey { case t, o, h, l, c, flowSol = "flow_sol" }
    public init(t: Double, o: Double, h: Double, l: Double, c: Double, flowSol: Double? = nil) { self.t = t; self.o = o; self.h = h; self.l = l; self.c = c; self.flowSol = flowSol }
}

public extension Array where Element == Candle {
    /// Nombre de bougies du dernier tronçon SANS trou : un trou de plus de `max(6 × intervalle, 60 s)` coupe. Sans ça, un vieux point
    /// d'il y a une heure et les bougies d'à l'instant étaient collés côte à côte (axe par rang) : graphique trompeur, fait de traits plats.
    /// Si le tronçon récent a moins de 2 bougies, on garde tout (rien n'est caché).
    func lastContinuousRun(intervalS: Int) -> (count: Int, gapS: Double?) {
        guard count >= 2 else { return (count, nil) }
        let limit = Swift.max(Double(intervalS) * 6, 60)
        var n = 1
        var i = count - 1
        while i > 0 {
            if self[i].t - self[i - 1].t > limit {
                return n >= 2 ? (n, self[i].t - self[i - 1].t) : (count, nil)
            }
            n += 1; i -= 1
        }
        return (count, nil)
    }
}

public struct ChartData: Decodable, Sendable, Equatable {
    public var candles: [Candle]?
    public var ema9: [Double?]?
    public var ema21: [Double?]?
    public var intervalS: Int?
    public var note: String?
    enum CodingKeys: String, CodingKey { case candles, ema9, ema21, intervalS = "interval_s", note }
}

public struct Identity: Decodable, Sendable, Equatable {
    public var name: String?
    public var symbol: String?
    public var imageURL: String?
    public var imageAlts: [String]?
    enum CodingKeys: String, CodingKey { case name, symbol, imageURL = "image_url", imageAlts = "image_alts" }
}

public struct Quote: Decodable, Sendable, Equatable {
    public var marketCap: Double?
    public var source: String?
    enum CodingKeys: String, CodingKey { case marketCap = "market_cap", source }
}

public struct ScreenReply: Decodable, Sendable, Equatable {
    public var mint: String?
    public var chart: ChartData?
    public var identity: Identity?
    public var quote: Quote?
    public var nSamples: Int?
    public var warming: Bool?
    public var error: String?
    enum CodingKeys: String, CodingKey { case mint, chart, identity, quote, warming, error, nSamples = "n_samples" }
}

/// Un « run » : token listé qui a pris au moins +X % en peu de temps (détecté APRÈS le début du mouvement).
public struct RunItem: Decodable, Sendable, Equatable, Identifiable {
    public var mint: String
    public var symbol: String?
    public var name: String?
    public var imageURL: String?
    public var imageAlts: [String]?
    public var gainPct: Double?
    public var solIn: Double?
    public var mcAtDetect: Double?
    public var mcNow: Double?
    public var sinceDetectPct: Double?
    public var ageS: Int?
    public var id: String { mint }
    enum CodingKeys: String, CodingKey {
        case mint, symbol, name
        case imageURL = "image_url", imageAlts = "image_alts", gainPct = "gain_pct", solIn = "sol_in"
        case mcAtDetect = "mc_at_detect", mcNow = "mc_now", sinceDetectPct = "since_detect_pct", ageS = "age_s"
    }
}

public struct Runs: Decodable, Sendable, Equatable {
    public var items: [RunItem]?
    public var rule: String?
    public var note: String?
}

/// Réponse de /api/companion/live (seules les parties utiles à l'app sont lues).
public struct LiveReply: Decodable, Sendable, Equatable {
    public var new: Feed?
    public var soon: Feed?
    public var migrated: Feed?
    public var runs: Runs?
}

/// Un token ÉCARTÉ par une porte du serveur (suivi fantôme). Tout est optionnel : une valeur absente = « non lu ».
public struct DroppedToken: Decodable, Sendable, Equatable, Identifiable {
    public var mint: String
    public var symbol: String?
    public var name: String?
    public var imageURL: String?
    public var imageAlts: [String]?
    public var tier: String?
    public var marketCap: Double?
    public var checkpoints: [String: Double?]?
    public var id: String { mint }
    enum CodingKeys: String, CodingKey { case mint, symbol, name, imageURL = "image_url", imageAlts = "image_alts", tier, marketCap = "market_cap", checkpoints }

    public init(mint: String, symbol: String? = nil, name: String? = nil, imageURL: String? = nil, imageAlts: [String]? = nil, tier: String? = nil,
                marketCap: Double? = nil, checkpoints: [String: Double?]? = nil) {
        self.mint = mint; self.symbol = symbol; self.name = name; self.imageURL = imageURL; self.imageAlts = imageAlts; self.tier = tier
        self.marketCap = marketCap; self.checkpoints = checkpoints
    }

    /// Raison de l'écart en mots simples (« gate:dev_spam » → « dev qui lance trop de tokens »).
    public var reason: String? {
        guard let t = tier, t.hasPrefix("gate:") else { return nil }
        let key = String(t.dropFirst(5))
        return Feed.dropLabels[key] ?? key.replacingOccurrences(of: "_", with: " ")
    }

    /// Ce que le token est devenu au dernier point de contrôle lu (+60, sinon +15, sinon +5 min). nil = pas encore mesuré.
    public var lastCheck: (label: String, pct: Double)? {
        for k in ["60m", "15m", "5m"] { if let v = checkpoints?[k] ?? nil, v.isFinite { return (k.replacingOccurrences(of: "m", with: " min"), v) } }
        return nil
    }
}

public struct DroppedReply: Decodable, Sendable, Equatable {
    public var items: [DroppedToken]

    public init(items: [DroppedToken]) { self.items = items }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let raw = (try? c.decodeIfPresent([FailableDropped].self, forKey: .items)) ?? nil
        items = (raw ?? []).compactMap { $0.value }.filter { isValidMint($0.mint) }
    }
    enum CodingKeys: String, CodingKey { case items }
    /// Une ligne illisible est ignorée sans faire échouer toute la liste.
    private struct FailableDropped: Decodable { let value: DroppedToken?; init(from d: Decoder) throws { value = try? DroppedToken(from: d) } }
}

public struct Social: Decodable, Sendable, Equatable, Identifiable {
    public var kind: String?
    public var url: String?
    public var id: String { url ?? UUID().uuidString }
}

/// Fiche courte d'un token (GET /api/companion/token/<mint>).
public struct TokenCard: Decodable, Sendable, Equatable {
    public struct Authorities: Decodable, Sendable, Equatable { public var mint: String?; public var freeze: String? }
    public var mint: String?
    public var symbol: String?
    public var name: String?
    public var imageURL: String?
    public var authorities: Authorities?
    public var devPct: Double?
    public var top10Pct: Double?
    public var holders: Int?
    public var ageS: Int?
    public var marketCap: Double?
    public var liquidityUSD: Double?
    public var socials: [Social]?
    public var sources: [String]?
    public var readAt: String?
    enum CodingKeys: String, CodingKey {
        case mint, symbol, name, authorities, holders, socials, sources
        case imageURL = "image_url", devPct = "dev_pct", top10Pct = "top10_pct", ageS = "age_s"
        case marketCap = "market_cap", liquidityUSD = "liquidity_usd", readAt = "read_at"
    }
}

/// Lien social sûr à ouvrir : https seulement ; Twitter = x.com/twitter.com, Telegram = t.me ; pas d'identifiants ni de port.
public func safeSocialURL(_ s: Social) -> URL? {
    guard let raw = s.url, raw.count <= 300, let u = URL(string: raw), u.scheme == "https", let host = u.host?.lowercased(),
          u.user == nil, u.password == nil, u.port == nil || u.port == 443 else { return nil }
    switch s.kind {
    case "twitter": return ["x.com", "www.x.com", "twitter.com", "www.twitter.com", "mobile.twitter.com"].contains(host) ? u : nil
    case "telegram": return ["t.me", "telegram.me"].contains(host) ? u : nil
    case "website": return u
    default: return nil
    }
}

extension Feed.Item {
    /// Construit un élément à partir d'un run (même affichage que les autres colonnes).
    public init(run r: RunItem) {
        self.init(mint: r.mint, symbol: r.symbol, name: r.name, ageS: nil, marketCap: r.mcNow, realSol: nil, risk: nil, lights: nil, series: nil, fromPeakPct: nil)
        imageURL = r.imageURL; imageAlts = r.imageAlts
    }

    /// Un token écarté s'ouvre comme les autres (graphique, fiche) : même affichage, rien d'inventé.
    public init(dropped d: DroppedToken) {
        self.init(mint: d.mint, symbol: d.symbol, name: d.name, ageS: nil, marketCap: d.marketCap, realSol: nil, risk: nil, lights: nil, series: nil, fromPeakPct: nil)
        imageURL = d.imageURL; imageAlts = d.imageAlts
    }

    /// Élément minimal (pour afficher un token qui n'est plus dans les colonnes).
    public static func minimal(mint: String, symbol: String?, image: String?) -> Feed.Item {
        var i = Feed.Item(mint: mint, symbol: symbol, name: nil, ageS: nil, marketCap: nil, realSol: nil, risk: nil, lights: nil, series: nil, fromPeakPct: nil)
        i.imageURL = image
        return i
    }

    /// Même token, market cap remplacé par une lecture plus récente (bougie, cotation).
    public func withMarketCap(_ m: Double?) -> Feed.Item {
        var c = self
        if let m, m.isFinite, m > 0 { c.marketCap = m }
        return c
    }
}

/// Prix exploitables de toutes les colonnes du terminal (pour mettre à jour tes positions fictives).
public func prices(from live: LiveReply) -> [String: Double] {
    var out: [String: Double] = [:]
    for f in [live.new, live.soon, live.migrated] { out.merge(prices(from: f)) { a, _ in a } }
    for r in live.runs?.items ?? [] { if let m = r.mcNow, m.isFinite, m > 0, out[r.mint] == nil { out[r.mint] = m } }
    return out
}

/// Texte à montrer quand il n'y a pas encore de bougies : dit la vérité (échec de lecture ≠ « chargement »).
public func chartWaitMessage(failure: FetchFailure?, warming: Bool) -> (text: String, loading: Bool) {
    switch failure {
    case .unauthorized?: return ("Jeton refusé : remets-le dans les Réglages.", false)
    case .rateLimited(let s)?: return ("Serveur occupé, nouvel essai dans \(s) s.", false)
    case .server(let c)?: return ("Le serveur répond avec une erreur (\(c)). Nouvel essai en cours.", false)
    case .network?: return ("Serveur injoignable ou trop lent. Nouvel essai en cours.", false)
    case .badResponse?: return ("Réponse illisible du serveur. Nouvel essai en cours.", false)
    case nil:
        return warming ? ("Le serveur commence à suivre ce token : les bougies arrivent en quelques secondes.", true) : ("Chargement des bougies…", true)
    }
}
