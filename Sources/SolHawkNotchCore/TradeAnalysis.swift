import Foundation

// Diagnostic de l'historique et lecture annotée d'un trade. Ce sont des PISTES tirées de tes chiffres, jamais des règles prouvées :
// avec peu de trades, tout écart peut être du hasard (on le dit). Simulation seulement : aucun ordre réel.

public enum LossCause: String, Sendable, CaseIterable {
    case vanished       // le token a disparu du flux : sortie supposée
    case gaveBack       // monté puis tout rendu
    case lateEntry      // entré après une grosse hausse
    case stopped        // sorti par le stop
    case costs          // frais et glissement lourds
    case tooShort       // trade de quelques secondes
    case slowBleed      // baisse lente sans cause plus précise
    case none           // trade gagnant ou sans cause à signaler

    public var title: String {
        switch self {
        case .vanished: return "Token disparu"
        case .gaveBack: return "Gains rendus"
        case .lateEntry: return "Entré trop tard"
        case .stopped: return "Stop touché"
        case .costs: return "Frais lourds"
        case .tooShort: return "Trop court"
        case .slowBleed: return "Baisse lente"
        case .none: return "RAS"
        }
    }
}

public struct TradeDiagnosis: Sendable, Equatable, Identifiable {
    public var id: UUID
    public var symbol: String
    public var mint: String
    public var pnlUSD: Double
    public var pnlPct: Double
    public var cause: LossCause
    public var also: [LossCause]
    public var headline: String
}

/// Cause principale d'un trade FERMÉ (priorité : disparu > rendu > tard > stop > frais > court > lent). `before` : lectures avant l'entrée.
public func diagnose(_ t: PaperTrade, before: [PricePoint] = []) -> TradeDiagnosis {
    var causes: [(LossCause, String)] = []
    let costShare = t.stakeUSD > 0 ? t.costsUSD / t.stakeUSD * 100 : 0
    let peakX = t.entryMcap > 0 ? t.peakMcap / t.entryMcap : 1
    let exitX = (t.exitMcap ?? t.lastMcap) / max(t.entryMcap, 1e-9)
    let reason = (t.exitReason ?? "").lowercased()
    if reason.contains("supposée") { causes.append((.vanished, "Le token a disparu du flux : sortie supposée, tu n'aurais pas pu vendre.")) }
    if peakX >= 1.5, exitX < peakX * 0.7 {
        causes.append((.gaveBack, "Monté jusqu'à ×\(fmt1(peakX)) après ton entrée, sorti à ×\(fmt1(exitX)) : \(Int(((1 - exitX / peakX) * 100).rounded())) % du sommet rendu."))
    }
    if let first = before.first, first.mcap > 0, t.entryMcap > 0 {
        let run = (t.entryMcap / first.mcap - 1) * 100
        if run >= 50 { causes.append((.lateEntry, "Entré après \(pct(run)) de hausse déjà faite : le gros du mouvement était peut-être passé.")) }
    }
    if reason.contains("stop") { causes.append((.stopped, "Sorti par le stop (\(t.exitReason ?? "stop")).")) }
    if costShare >= 8 { causes.append((.costs, "Frais et glissement estimés : \(fmt1(costShare)) % de la mise.")) }
    if !t.isOpen, t.holdS < 30 { causes.append((.tooShort, "Trade de \(Int(t.holdS)) s : les coûts pèsent plus que le mouvement.")) }
    if t.pnlUSD < 0, causes.isEmpty { causes.append((.slowBleed, "Baisse progressive de ×1,0 à ×\(fmt1(exitX)), sans événement net.")) }
    let main = t.pnlUSD < 0 ? causes.first : causes.first(where: { $0.0 == .gaveBack })
    return TradeDiagnosis(id: t.id, symbol: t.symbol, mint: t.mint, pnlUSD: t.pnlUSD, pnlPct: t.pnlPct,
                          cause: main?.0 ?? .none, also: causes.dropFirst().map(\.0), headline: main?.1 ?? "Rien de particulier à signaler.")
}

/// Une ligne du tableau « comment tu sors ».
public struct ExitBucket: Sendable, Equatable, Identifiable {
    public var name: String
    public var count: Int
    public var netUSD: Double
    public var id: String { name }
}

public struct HistoryDiagnosis: Sendable, Equatable {
    public var closedCount: Int
    public var worst: [TradeDiagnosis]
    public var patterns: [String]
    public var exits: [ExitBucket]
    public var holds: [ExitBucket]
    public var enoughData: Bool
}

/// Famille de sortie d'après la raison écrite par l'app.
public func exitFamily(_ reason: String?) -> String {
    let r = (reason ?? "").lowercased()
    if r.contains("supposée") { return "Token disparu" }
    if r.contains("stop") { return "Stop" }
    if r.contains("prise de gain") || r.contains("×1,5") || r.contains("partielle") { return "Prise de gain" }
    if r.contains("durée") || r.contains("temps") || r.contains("30 min") { return "Durée max" }
    if r.contains("manuelle") { return "Vente manuelle" }
    return "Autre"
}

public func diagnoseHistory(_ trades: [PaperTrade], before: (PaperTrade) -> [PricePoint] = { _ in [] }, worstCount: Int = 3) -> HistoryDiagnosis {
    let closed = trades.filter { !$0.isOpen }
    let all = closed.map { diagnose($0, before: before($0)) }
    let losers = all.filter { $0.pnlUSD < 0 }
    let worst = Array(losers.sorted { $0.pnlUSD < $1.pnlUSD }.prefix(worstCount))
    var patterns: [String] = []
    func count(_ c: LossCause) -> Int { losers.filter { $0.cause == c || $0.also.contains(c) }.count }
    if !losers.isEmpty {
        let n = losers.count
        let late = count(.lateEntry), gave = count(.gaveBack), stop = count(.stopped), cost = count(.costs), vanish = count(.vanished)
        if late > 0 { patterns.append("\(late) de tes \(n) pertes : entrée après une hausse de 50 % ou plus.") }
        if gave > 0 { patterns.append("\(gave) de tes \(n) pertes avaient pourtant dépassé ×1,5 : une vente partielle en hausse aurait sécurisé une partie.") }
        if stop > 0 { patterns.append("\(stop) pertes sont des sorties par le stop.") }
        if vanish > 0 { patterns.append("\(vanish) perte(s) viennent d'un token disparu du flux (sortie supposée).") }
        if cost > 0 { patterns.append("\(cost) perte(s) sont lourdes en frais et glissement : une mise plus petite aide sur les tokens peu liquides.") }
    }
    let wins = closed.filter { $0.pnlUSD > 0 }
    let gross = wins.reduce(0) { $0 + $1.pnlUSD }, lost = -closed.filter { $0.pnlUSD < 0 }.reduce(0) { $0 + $1.pnlUSD }
    let costs = closed.reduce(0) { $0 + $1.costsUSD }
    if gross + lost > 0, costs > 0 { patterns.append("Frais et glissement estimés : \(money(costs)), soit \(Int((costs / (gross + lost) * 100).rounded())) % de tout ce que tu as gagné et perdu en valeur absolue.") }

    var byExit: [String: ExitBucket] = [:]
    for t in closed { let k = exitFamily(t.exitReason); var b = byExit[k] ?? ExitBucket(name: k, count: 0, netUSD: 0); b.count += 1; b.netUSD += t.pnlUSD; byExit[k] = b }
    func holdBucket(_ s: Double) -> String { s < 60 ? "moins de 1 min" : s < 300 ? "1 à 5 min" : s < 1800 ? "5 à 30 min" : "plus de 30 min" }
    var byHold: [String: ExitBucket] = [:]
    for t in closed { let k = holdBucket(t.holdS); var b = byHold[k] ?? ExitBucket(name: k, count: 0, netUSD: 0); b.count += 1; b.netUSD += t.pnlUSD; byHold[k] = b }
    let order = ["moins de 1 min", "1 à 5 min", "5 à 30 min", "plus de 30 min"]
    return HistoryDiagnosis(closedCount: closed.count, worst: worst, patterns: patterns,
                            exits: byExit.values.sorted { $0.netUSD < $1.netUSD },
                            holds: order.compactMap { byHold[$0] }, enoughData: closed.count >= 30)
}

// MARK: lecture annotée du graphique

public struct ChartNote: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable { case entry, peak, exit, giveBack, outflow }
    public var kind: Kind
    public var time: Double          // secondes (axe des bougies : epoch)
    public var price: Double         // market cap
    public var label: String         // court, sur le graphique
    public var detail: String        // phrase complète, sous le graphique
    public var tone: NoteTone
    public var id: String { "\(kind.rawValue)-\(Int(time))" }
}

/// Flèches à poser sur les bougies d'un trade : entrée, sommet, sortie, gains rendus, et le plus gros reflux de SOL de la courbe entre le sommet et la sortie
/// (seulement si les bougies donnent le flux). `candles` : bougies du market cap, les plus anciennes d'abord.
public func chartNotes(for t: PaperTrade, candles: [Candle], now: Date = Date()) -> [ChartNote] {
    var out: [ChartNote] = []
    let t0 = t.openedAt.timeIntervalSince1970
    let t1 = (t.closedAt ?? now).timeIntervalSince1970
    out.append(ChartNote(kind: .entry, time: t0, price: t.entryMcap, label: "Entrée \(formatUSD(t.entryMcap))",
                         detail: "Entrée à \(formatUSD(t.entryMcap))" + (t.seenMcap.map { " (vu à \(formatUSD($0)) au clic)" } ?? "") + ".", tone: .info))
    let inside = candles.filter { $0.t >= t0 - 1 && $0.t <= t1 + 1 }
    var peak: (time: Double, price: Double)?
    if let hi = inside.max(by: { $0.h < $1.h }), t.entryMcap > 0, hi.h >= t.entryMcap * 1.05 {
        peak = (hi.t, hi.h)
        let x = hi.h / t.entryMcap
        out.append(ChartNote(kind: .peak, time: hi.t, price: hi.h, label: "Sommet ×\(fmt1(x))",
                             detail: "Sommet à \(formatUSD(hi.h)) (×\(fmt1(x)) ton entrée), \(durationText(hi.t - t0)) après l'entrée.", tone: .good))
    }
    if let c = t.closedAt, let ex = t.exitMcap {
        let x = t.entryMcap > 0 ? ex / t.entryMcap : 1
        out.append(ChartNote(kind: .exit, time: c.timeIntervalSince1970, price: ex, label: "Sortie ×\(fmt1(x))",
                             detail: "Sortie à \(formatUSD(ex)) (×\(fmt1(x))) : \(t.exitReason ?? "raison non lue").", tone: x >= 1 ? .good : .bad))
        if let p = peak, ex < p.price * 0.85, p.time < c.timeIntervalSince1970 {
            out.append(ChartNote(kind: .giveBack, time: (p.time + c.timeIntervalSince1970) / 2, price: (p.price + ex) / 2,
                                 label: "−\(Int(((1 - ex / p.price) * 100).rounded())) % rendus",
                                 detail: "Entre le sommet et ta sortie, le prix a perdu \(Int(((1 - ex / p.price) * 100).rounded())) %.", tone: .bad))
            let after = inside.filter { $0.t >= p.time && $0.t <= c.timeIntervalSince1970 + 1 }
            if let worst = after.compactMap({ c in c.flowSol.map { (c, $0) } }).min(by: { $0.1 < $1.1 }), worst.1 <= -1 {
                out.append(ChartNote(kind: .outflow, time: worst.0.t, price: worst.0.l, label: "−\(fmt1(abs(worst.1))) SOL",
                                     detail: "Plus gros reflux de SOL de la courbe pendant la baisse : \(fmt1(worst.1)) SOL sur une bougie (les acheteurs partent, les vendeurs sortent).", tone: .bad))
            }
        }
    }
    return out.sorted { $0.time < $1.time }
}

func durationText(_ s: Double) -> String {
    let s = max(0, s)
    if s < 90 { return "\(Int(s)) s" }
    if s < 5400 { return "\(Int((s / 60).rounded())) min" }
    return "\(fmt1(s / 3600)) h"
}

extension PaperLab {
    /// Tous les trades fictifs : les tiens (« Moi ») et ceux des robots (nom du robot).
    public func allTrades() -> [(owner: String, trade: PaperTrade)] {
        var out = manual.trades.map { ("Moi", $0) }
        for r in robots { out += (books[r.id]?.trades ?? []).map { (r.name, $0) } }
        return out
    }
    public func trade(_ id: UUID) -> (owner: String, trade: PaperTrade)? { allTrades().first { $0.trade.id == id } }
}

/// Plus longue suite de pertes d'affilée (trades fermés, dans l'ordre de fermeture).
public func longestLosingStreak(_ trades: [PaperTrade]) -> Int {
    var best = 0, cur = 0
    for t in trades.filter({ !$0.isOpen }).sorted(by: { ($0.closedAt ?? .distantPast) < ($1.closedAt ?? .distantPast) }) {
        if t.pnlUSD < 0 { cur += 1; best = max(best, cur) } else { cur = 0 }
    }
    return best
}
