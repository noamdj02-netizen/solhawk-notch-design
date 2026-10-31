import Foundation

// Robots FICTIFS : chacun applique une stratégie connue sur les mêmes données, avec les mêmes coûts.
// Un témoin « au hasard » sert d'étalon : un robot qui ne le bat pas n'a rien démontré.

public struct PricePoint: Codable, Sendable, Equatable {
    public var t: Double      // secondes (axe du temps, origine libre)
    public var mcap: Double
    public init(t: Double, mcap: Double) { self.t = t; self.mcap = mcap }
}

public enum RobotKind: String, Codable, Sendable, CaseIterable {
    case onListing, momentum, fibRetrace, dipBuy, random
}

public struct ExitRules: Codable, Sendable, Equatable {
    public var stopPct: Double = -25          // vend tout si le prix tombe à −25 % de l'entrée
    public var halfAtMultiple: Double = 1.5   // vend la moitié à ×1,5
    public var trailPct: Double = -30         // après la moitié : vend le reste à −30 % du plus haut
    public var maxHoldS: Double = 1800        // vend tout après 30 min
    public var staleS: Double = 600           // plus de prix pendant 10 min : sortie supposée
    public var staleHaircutPct: Double = 50   // … à −50 % du dernier prix (hypothèse prudente, pas une mesure)
    public init() {}
}

public struct RobotSpec: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var blurb: String
    public var kind: RobotKind
    public var exits = ExitRules()

    public static let all: [RobotSpec] = [
        RobotSpec(id: "listing", name: "Mise en liste", blurb: "Entre quand un token passe tous les filtres (moins de 10 min).", kind: .onListing),
        RobotSpec(id: "momentum", name: "Momentum", blurb: "Entre si le prix a pris +15 % sur les 3 dernières lectures et monte encore.", kind: .momentum),
        RobotSpec(id: "fib", name: "Retracement Fibonacci", blurb: "Après une hausse ×1,5, attend un repli entre 38,2 % et 61,8 % puis un rebond.", kind: .fibRetrace),
        RobotSpec(id: "dip", name: "Achat du creux", blurb: "Entre à −25 / −45 % du plus haut quand le prix rebondit.", kind: .dipBuy),
        RobotSpec(id: "random", name: "Témoin au hasard", blurb: "Entre sur 1 token sur 3, tiré au sort. Étalon : à battre.", kind: .random),
    ]
}

/// Faut-il entrer ? Fonction pure (testée). `pts` : lectures du prix, de la plus ancienne à la plus récente.
public func robotWantsEntry(_ kind: RobotKind, item: Feed.Item, pts: [PricePoint], salt: String) -> Bool {
    switch kind {
    case .onListing:
        return status(of: item) == .passesFilters && (item.ageS ?? .max) <= 600
    case .momentum:
        guard pts.count >= 3 else { return false }
        let a = pts[pts.count - 3].mcap, b = pts[pts.count - 2].mcap, c = pts[pts.count - 1].mcap
        return a > 0 && (c / a - 1) * 100 >= 15 && c > b
    case .fibRetrace:
        return fibRebound(pts)
    case .dipBuy:
        guard pts.count >= 3, let peak = pts.map(\.mcap).max(), peak > 0 else { return false }
        let c = pts[pts.count - 1].mcap, b = pts[pts.count - 2].mcap
        let drop = (c / peak - 1) * 100
        return drop <= -25 && drop >= -45 && c > b
    case .random:
        return stableHash(item.mint + "|" + salt) % 3 == 0
    }
}

/// Zone de retracement 38,2 %–61,8 % d'une hausse d'au moins ×1,5, suivie d'un rebond (dernier point au-dessus du précédent).
public func fibRebound(_ pts: [PricePoint]) -> Bool {
    guard pts.count >= 5 else { return false }
    guard let hi = pts.indices.max(by: { pts[$0].mcap < pts[$1].mcap }), hi > 0, hi < pts.count - 2 else { return false }
    let low = pts[..<hi].map(\.mcap).min() ?? 0, high = pts[hi].mcap
    guard low > 0, high / low >= 1.5 else { return false }
    let c = pts[pts.count - 1].mcap, b = pts[pts.count - 2].mcap
    let retrace = (high - c) / (high - low)
    return retrace >= 0.382 && retrace <= 0.618 && c > b
}

/// Hachage stable (FNV-1a) : le tirage du témoin ne change pas d'un lancement à l'autre.
func stableHash(_ s: String) -> UInt64 {
    var h: UInt64 = 0xcbf29ce484222325
    for b in s.utf8 { h ^= UInt64(b); h = h &* 0x100000001b3 }
    return h
}

/// Sortie décidée par les règles (nil = on garde). Fraction à vendre + raison.
public func robotExit(_ t: PaperTrade, rules: ExitRules, now: Date) -> (fraction: Double, reason: String)? {
    if t.multiple <= 1 + rules.stopPct / 100 { return (1, "stop \(Int(rules.stopPct)) %") }
    if !t.tookPartial, t.multiple >= rules.halfAtMultiple { return (0.5, "moitié à ×\(String(format: "%.1f", rules.halfAtMultiple).replacingOccurrences(of: ".", with: ","))") }
    if t.tookPartial, t.peakMcap > 0, (t.lastMcap / t.peakMcap - 1) * 100 <= rules.trailPct { return (1, "repli \(Int(rules.trailPct)) % du plus haut") }
    if now.timeIntervalSince(t.openedAt) >= rules.maxHoldS { return (1, "durée max") }
    return nil
}

extension PaperBook {
    /// Token sans prix depuis trop longtemps : on ne peut pas vendre, on suppose une sortie à perte (dit dans la raison).
    public mutating func writeOffStale(now: Date, rules: ExitRules) {
        for i in trades.indices where trades[i].isOpen && now.timeIntervalSince(trades[i].lastSeen) >= rules.staleS {
            guard !pending.contains(where: { $0.mint == trades[i].mint }) else { continue }
            let value = trades[i].markUSD * (1 - rules.staleHaircutPct / 100)
            cash += value
            trades[i].realizedUSD += value
            trades[i].costsUSD += trades[i].markUSD - value
            trades[i].share = 0; trades[i].closedAt = now; trades[i].exitMcap = trades[i].lastMcap
            trades[i].exitReason = "plus de prix : sortie supposée à −\(Int(rules.staleHaircutPct)) %"
        }
    }
}
