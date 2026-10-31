import Foundation

/// Type d'alerte. Chaque type a sa règle (activée, seuil, son) dans `AlertConfig`.
public enum AlertKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case newPassesFilters   // un nouveau token passe les filtres (≠ sûr)
    case bigDrop            // un token récent chute fort depuis son plus haut
    case positionThreshold  // une position FICTIVE franchit un seuil de gain ou de perte
    case outage             // serveur injoignable / jeton ou adresse refusés
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .newPassesFilters: return "Passe les filtres"
        case .bigDrop: return "Chute forte"
        case .positionThreshold: return "Position fictive"
        case .outage: return "Panne"
        }
    }
    public var explain: String {
        switch self {
        case .newPassesFilters: return "Un nouveau token passe les filtres. Ça ne prouve pas qu'il est sûr."
        case .bigDrop: return "Un token récent a perdu au moins le seuil depuis son plus haut."
        case .positionThreshold: return "Une position fictive dépasse le seuil, en gain ou en perte. Simulation seulement."
        case .outage: return "Plus de données fraîches, ou réglages refusés."
        }
    }
    /// Seuil réglable (en %) : seulement pour la chute et les positions.
    public var thresholdRange: ClosedRange<Double>? {
        switch self {
        case .bigDrop: return 5...95
        case .positionThreshold: return 5...500
        case .newPassesFilters, .outage: return nil
        }
    }
    public var thresholdStep: Double { self == .positionThreshold ? 10 : 5 }
}

/// Sons système autorisés (/System/Library/Sounds). Tout autre nom est refusé : on ne joue jamais un nom venu d'ailleurs.
public let alertSoundNames = ["Glass", "Ping", "Basso", "Hero", "Submarine", "Funk", "Pop", "Purr", "Sosumi", "Tink", "Blow", "Bottle", "Frog", "Morse"]

/// Le nom s'il est dans la liste autorisée, sinon nil.
public func validSoundName(_ name: String?) -> String? {
    guard let name else { return nil }
    return alertSoundNames.contains(name) ? name : nil
}

/// Règle d'un type d'alerte.
public struct AlertRule: Codable, Sendable, Equatable, Identifiable {
    public var kind: AlertKind
    public var enabled: Bool
    public var threshold: Double?   // en %, seulement si le type en a un
    public var sound: String
    public var id: String { kind.rawValue }

    public init(kind: AlertKind, enabled: Bool = true, threshold: Double? = nil, sound: String) {
        self.kind = kind; self.enabled = enabled; self.threshold = threshold; self.sound = sound
    }

    /// Valeurs par défaut : celles d'avant les règles (vert = Glass, rouge = Basso, chute à 40 %).
    public static func defaultRule(_ k: AlertKind) -> AlertRule {
        switch k {
        case .newPassesFilters: return AlertRule(kind: k, sound: "Glass")
        case .bigDrop: return AlertRule(kind: k, threshold: -signalDumpPct, sound: "Basso")
        case .positionThreshold: return AlertRule(kind: k, threshold: 50, sound: "Ping")
        case .outage: return AlertRule(kind: k, sound: "Basso")
        }
    }

    /// Remet la règle dans des bornes sûres : son autorisé, seuil borné (ou absent si le type n'en a pas).
    public func sanitized() -> AlertRule {
        var r = self
        let d = AlertRule.defaultRule(kind)
        r.sound = validSoundName(sound) ?? d.sound
        if let range = kind.thresholdRange {
            let t = threshold.flatMap { $0.isFinite ? $0 : nil } ?? d.threshold ?? range.lowerBound
            r.threshold = min(max(t, range.lowerBound), range.upperBound)
        } else {
            r.threshold = nil
        }
        return r
    }
}

/// Toutes les règles + coupure du son + heures calmes. Stocké en JSON (UserDefaults côté app).
public struct AlertConfig: Codable, Sendable, Equatable {
    public var rules: [AlertRule]
    public var muted: Bool
    public var quietHours: Bool
    public var quietStart: Int   // heure 0…23
    public var quietEnd: Int     // heure 0…23 (peut passer minuit : 23 → 7)

    public init(rules: [AlertRule] = AlertKind.allCases.map(AlertRule.defaultRule), muted: Bool = false, quietHours: Bool = false, quietStart: Int = 23, quietEnd: Int = 7) {
        self.rules = rules; self.muted = muted; self.quietHours = quietHours; self.quietStart = quietStart; self.quietEnd = quietEnd
        self = sanitized()
    }

    public static let defaults = AlertConfig()

    public subscript(kind: AlertKind) -> AlertRule {
        get { rules.first { $0.kind == kind } ?? AlertRule.defaultRule(kind) }
        set {
            let r = AlertRule(kind: kind, enabled: newValue.enabled, threshold: newValue.threshold, sound: newValue.sound).sanitized()
            if let i = rules.firstIndex(where: { $0.kind == kind }) { rules[i] = r } else { rules.append(r) }
        }
    }

    /// Une règle par type, dans l'ordre, valeurs bornées ; un type absent reprend sa valeur par défaut.
    public func sanitized() -> AlertConfig {
        var c = self
        c.rules = AlertKind.allCases.map { k in (rules.first { $0.kind == k } ?? AlertRule.defaultRule(k)).sanitized() }
        c.quietStart = min(max(quietStart, 0), 23)
        c.quietEnd = min(max(quietEnd, 0), 23)
        return c
    }

    enum CodingKeys: String, CodingKey { case rules, muted, quietHours, quietStart, quietEnd }

    /// Décodage tolérant : champ absent = valeur par défaut, type inconnu ignoré (un vieux ou un futur JSON ne casse rien).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var rules: [AlertRule] = []
        if var arr = try? c.nestedUnkeyedContainer(forKey: .rules) {
            while !arr.isAtEnd {
                if let r = try? arr.decode(AlertRule.self) { rules.append(r) } else if (try? arr.decode(Skip.self)) == nil { break }
            }
        }
        self.init(rules: rules,
                  muted: (try? c.decodeIfPresent(Bool.self, forKey: .muted)) ?? false,
                  quietHours: (try? c.decodeIfPresent(Bool.self, forKey: .quietHours)) ?? false,
                  quietStart: (try? c.decodeIfPresent(Int.self, forKey: .quietStart)) ?? 23,
                  quietEnd: (try? c.decodeIfPresent(Int.self, forKey: .quietEnd)) ?? 7)
    }

    private struct Skip: Decodable {}

    public func encoded() -> Data? { try? JSONEncoder().encode(self) }
    /// nil ou JSON illisible : valeurs par défaut.
    public static func decode(_ data: Data?) -> AlertConfig {
        guard let data, let c = try? JSONDecoder().decode(AlertConfig.self, from: data) else { return .defaults }
        return c
    }
}

/// Règles partagées entre l'app (qui les modifie) et le moteur (qui les lit). Protégé par un verrou.
public final class AlertConfigBox: @unchecked Sendable {
    public static let shared = AlertConfigBox()
    private let lock = NSLock()
    private var value = AlertConfig.defaults
    public init() {}
    public var config: AlertConfig {
        get { lock.lock(); defer { lock.unlock() }; return value }
        set { let v = newValue.sanitized(); lock.lock(); value = v; lock.unlock() }
    }
}

/// Heures calmes : vrai si l'heure de `date` est dans [start, end). Passe minuit si start > end (23 → 7). start == end : jamais.
public func inQuietHours(_ date: Date, start: Int, end: Int, calendar: Calendar = .current) -> Bool {
    let s = min(max(start, 0), 23), e = min(max(end, 0), 23)
    guard s != e else { return false }
    let h = calendar.component(.hour, from: date)
    return s < e ? (h >= s && h < e) : (h >= s || h < e)
}

/// Ce qu'on fait d'une alerte : notification ? quel son ? (le journal l'écrit toujours).
public struct AlertDecision: Sendable, Equatable {
    public var notify: Bool
    public var sound: String?
    public init(notify: Bool, sound: String?) { self.notify = notify; self.sound = sound }
}

/// Règle désactivée : rien. Heures calmes : ni notification ni son. Son coupé : notification seule. Le son est toujours un nom autorisé.
public func decideDelivery(_ kind: AlertKind, config: AlertConfig, notifyPref: Bool, now: Date, calendar: Calendar = .current) -> AlertDecision {
    let rule = config[kind]
    guard rule.enabled else { return AlertDecision(notify: false, sound: nil) }
    if config.quietHours, inQuietHours(now, start: config.quietStart, end: config.quietEnd, calendar: calendar) { return AlertDecision(notify: false, sound: nil) }
    return AlertDecision(notify: notifyPref, sound: config.muted ? nil : validSoundName(rule.sound))
}

/// Une alerte à montrer (notification, son, ouverture du tiroir). Elle dit ce qui s'est passé, jamais « achète » ni « sûr ».
public struct NotchAlert: Sendable, Equatable, Identifiable {
    public var id: String { "\(type.rawValue)-\(mint ?? "systeme")-\(title)" }
    public var kind: BarSignal        // couleur : .green ou .red (le jaune ne sonne pas : trop bruyant)
    public var mint: String?
    public var title: String
    public var body: String
    public var type: AlertKind
    public var symbol: String?        // pour l'avatar dans l'historique (déjà nettoyé)
    public var image: String?         // logo, décoratif

    public init(kind: BarSignal, mint: String?, title: String, body: String, type: AlertKind? = nil, symbol: String? = nil, image: String? = nil) {
        self.kind = kind; self.mint = mint; self.title = title; self.body = body
        self.type = type ?? (mint == nil ? .outage : kind == .red ? .bigDrop : .newPassesFilters)
        self.symbol = symbol; self.image = image
    }
}

/// Décide quand alerter. Une alerte par token et par type ; une alerte de panne par coupure (rearmée au retour des données).
/// Les règles (activée, seuil) viennent de `AlertConfigBox.shared` par défaut. Un type désactivé reste suivi :
/// le réactiver ne fait pas sonner d'anciens tokens.
public struct AlertEngine: Sendable {
    private var green: Set<String> = []
    private var red: Set<String> = []
    private var outage = false
    private var primed = false   // le premier flux reçu n'alerte pas : ce n'est pas du « nouveau »

    public init() {}

    public mutating func evaluate(feed: Feed?, mood: Mood) -> [NotchAlert] {
        evaluate(feed: feed, mood: mood, config: AlertConfigBox.shared.config)
    }

    public mutating func evaluate(feed: Feed?, mood: Mood, config: AlertConfig) -> [NotchAlert] {
        var out: [NotchAlert] = []
        switch mood {
        case .offline, .tokenRejected, .badConfig:
            if !outage {
                outage = true
                if config[.outage].enabled {
                    out.append(NotchAlert(kind: .red, mint: nil, title: mood == .offline ? "Serveur injoignable" : mood == .badConfig ? "Adresse refusée" : "Jeton refusé",
                                          body: mood == .offline ? "Plus de données fraîches : l'état affiché n'est pas à jour." : mood == .badConfig ? "HTTPS est obligatoire (http seulement pour 127.0.0.1). Corrige dans les réglages." : "Mets à jour le jeton dans les réglages.",
                                          type: .outage))
                }
            }
            return out
        case .waiting: return out
        default: outage = false
        }
        guard let feed else { return out }
        let recent = feed.items.filter { ($0.ageS ?? Int.max) <= signalMaxAgeS }
        if green.count > 5000 { green.removeAll() }   // borné : au-delà de 10 min un token n'alerte plus de toute façon
        if red.count > 5000 { red.removeAll() }
        let firstFeed = !primed
        primed = true
        let drop = config[.bigDrop], pass = config[.newPassesFilters]
        let dropAt = -(drop.threshold ?? -signalDumpPct)
        for it in recent {
            let name = safeLabel(it.symbol, max: 12)
            if let d = it.fromPeakPct, d <= dropAt, !red.contains(it.mint) {
                red.insert(it.mint)
                if drop.enabled {
                    out.append(NotchAlert(kind: .red, mint: it.mint, title: "\(name) chute", body: String(format: "%.0f %% depuis son plus haut. À regarder, pas un conseil.", d),
                                          type: .bigDrop, symbol: name, image: it.imageURL))
                }
            }
            if status(of: it) == .passesFilters, !green.contains(it.mint) {
                green.insert(it.mint)
                if !firstFeed, pass.enabled {
                    let mc = it.marketCap.map { formatUSD($0) } ?? "MC non lu"
                    out.append(NotchAlert(kind: .green, mint: it.mint, title: "\(name) passe les filtres", body: "\(mc). Ça ne prouve pas qu'il est sûr.",
                                          type: .newPassesFilters, symbol: name, image: it.imageURL))
                }
            }
        }
        if firstFeed { for it in recent where status(of: it) == .passesFilters { green.insert(it.mint) } }
        return out
    }
}

/// Positions FICTIVES : une alerte quand une position franchit +seuil ou -seuil, une fois par franchissement.
/// `fired` = franchissements en cours (« mint+ » / « mint- ») ; repasser sous le seuil réarme l'alerte. L'appelant garde `fired`.
public func positionCrossings(open: [(mint: String, symbol: String, pnlPct: Double)], threshold: Double, alreadyFired: Set<String>) -> (alerts: [NotchAlert], fired: Set<String>) {
    guard threshold.isFinite, threshold > 0 else { return ([], []) }
    var alerts: [NotchAlert] = [], fired: Set<String> = []
    for p in open where p.pnlPct.isFinite {
        let up = p.pnlPct >= threshold
        guard up || p.pnlPct <= -threshold else { continue }
        let key = "\(p.mint)\(up ? "+" : "-")"
        fired.insert(key)
        if alreadyFired.contains(key) { continue }
        let name = safeLabel(p.symbol, max: 12)
        alerts.append(NotchAlert(kind: up ? .green : .red, mint: p.mint,
                                 title: "\(name) \(up ? "+" : "")\(String(format: "%.0f", p.pnlPct)) % (fictif)",
                                 body: "Ta position fictive a franchi \(up ? "+" : "-")\(String(format: "%.0f", threshold)) %. Simulation seulement, pas un conseil.",
                                 type: .positionThreshold, symbol: name))
    }
    return (alerts, fired)
}

/// Seulement les nouvelles alertes de positions (voir `positionCrossings` pour l'ensemble à garder).
public func positionAlerts(open: [(mint: String, symbol: String, pnlPct: Double)], threshold: Double, alreadyFired: Set<String>) -> [NotchAlert] {
    positionCrossings(open: open, threshold: threshold, alreadyFired: alreadyFired).alerts
}

/// Ce que chaque motif d'abandon veut dire, en mots simples (affiché dans l'entonnoir).
public func dropExplain(_ key: String) -> String {
    switch key {
    case "dev_spam": return "Le créateur a lancé beaucoup d'autres tokens : souvent une usine à tokens."
    case "no_traction": return "Pas assez de SOL réels déposés dans la courbe après le temps d'observation."
    case "authority_active": return "Le créateur peut encore créer (mint) ou geler (freeze) des jetons."
    case "dumped": return "La liquidité réelle a fortement baissé depuis son plus haut."
    case "no_image": return "Pas d'image : métadonnées incomplètes, on n'affiche pas."
    case "dev_holds_too_much": return "Le créateur garde une très grosse part de l'offre."
    case "dev_not_holding": return "Le créateur a déjà vendu sa part."
    case "whale_holder": return "Un seul portefeuille détient une grosse part."
    case "no_concentration": return "Répartition des détenteurs non lue : on ne devine pas."
    case "risk_high": return "Le score de risque (heuristique non calibrée) dépasse le seuil."
    case "migrated": return "Le token a quitté la courbe pour un marché ouvert."
    default: return "Motif reçu du serveur, sans explication connue."
    }
}
