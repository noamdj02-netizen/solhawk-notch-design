import Foundation
import Observation

/// Le laboratoire fictif : ton portefeuille de simulation + un portefeuille par robot, nourris par le même flux.
/// Sauvegardé dans Application Support (JSON local). Rien n'est jamais envoyé, aucun ordre réel n'existe.
@MainActor @Observable
public final class PaperLab {
    public private(set) var manual: PaperBook
    public private(set) var books: [String: PaperBook]
    public private(set) var robots: [RobotSpec]
    public var costs: CostModel { didSet { save() } }
    public var stakeUSD: Double = 10 { didSet { save() } }
    public var robotsOn: Bool = true { didSet { save() } }
    /// Limite de perte fictive du jour, en % du capital de départ (0 = aucune). Au-delà, tes achats fictifs sont bloqués jusqu'à demain.
    public var lossLimitPct: Double = 0 { didSet { save() } }
    /// Sorties automatiques de tes positions (0 = désactivé) : stop loss et prise de gain, en % du prix d'entrée.
    public var stopLossPct: Double = 0 { didSet { save() } }
    public var takeProfitPct: Double = 0 { didSet { save() } }
    /// Robots mis en pause un par un (ils gèrent encore leurs sorties, mais n'entrent plus).
    public var paused: Set<String> = [] { didSet { save() } }
    public private(set) var startedAt: Date
    /// Lectures de prix vues par l'app, par mint (pour les robots et les graphiques), bornées.
    @ObservationIgnored public private(set) var history: [String: [PricePoint]] = [:]
    public private(set) var lastTick: Date?
    /// Nom et logo vus pour chaque mint (pour afficher un token même après qu'il a quitté le flux).
    @ObservationIgnored public private(set) var meta: [String: (symbol: String?, image: String?)] = [:]

    @ObservationIgnored private let fileURL: URL?
    @ObservationIgnored private let clockOrigin = Date(timeIntervalSinceReferenceDate: 0)

    struct Saved: Codable {
        var version = 1
        var manual: PaperBook
        var books: [String: PaperBook]
        var costs: CostModel
        var stakeUSD: Double
        var robotsOn: Bool
        var paused: Set<String>?
        var lossLimitPct: Double?
        var stopLossPct: Double?
        var takeProfitPct: Double?
        var startedAt: Date
    }

    /// `fileURL` nil = rien sur disque (tests). Un fichier illisible est mis de côté (renommé), jamais effacé.
    public init(fileURL: URL?, robots: [RobotSpec] = RobotSpec.all, now: Date = Date()) {
        self.fileURL = fileURL
        self.robots = robots
        var loaded: Saved?
        if let u = fileURL, let data = try? Data(contentsOf: u) {
            let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
            loaded = try? d.decode(Saved.self, from: data)
            if loaded == nil { PaperLab.setAside(u, now: now) }
        }
        manual = loaded?.manual ?? PaperBook()
        costs = loaded?.costs ?? CostModel()
        stakeUSD = loaded?.stakeUSD ?? 10
        robotsOn = loaded?.robotsOn ?? true
        paused = loaded?.paused ?? []
        lossLimitPct = loaded?.lossLimitPct ?? 0
        stopLossPct = loaded?.stopLossPct ?? 0
        takeProfitPct = loaded?.takeProfitPct ?? 0
        startedAt = loaded?.startedAt ?? now
        var b = loaded?.books ?? [:]
        for r in robots where b[r.id] == nil { b[r.id] = PaperBook() }
        books = b
    }

    public static func defaultURL() -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return base.appendingPathComponent("SolHawkNotch", isDirectory: true).appendingPathComponent("paper.json")
    }

    // MARK: flux

    public func ingest(_ feed: Feed?, now: Date) {
        let px = prices(from: feed)
        let t = now.timeIntervalSince(clockOrigin)
        for it in feed?.items ?? [] where meta[it.mint] == nil || meta[it.mint]?.image == nil {
            meta[it.mint] = (it.symbol, imageCandidates(it).first?.absoluteString)
        }
        if meta.count > 3000 { meta.removeAll() }
        for (m, p) in px {
            var h = history[m] ?? []
            if h.last.map({ t - $0.t >= 1 }) ?? true { h.append(PricePoint(t: t, mcap: p)) }
            history[m] = Array(h.suffix(240))
        }
        if robotsOn { runRobots(feed: feed, prices: px, now: now) }
        manual.tick(prices: px, now: now, costs: costs)
        manual.writeOffStale(now: now, rules: ExitRules())
        manual.applyAutoExits(stopPct: stopLossPct, takeProfitPct: takeProfitPct, now: now)
        lastTick = now
        save()
    }

    /// Prix venant d'ailleurs que le flux principal (colonnes du terminal, bougies) : met à jour tes positions et tes ordres
    /// sur ces tokens. Les robots, eux, ne suivent que le flux principal.
    public func updatePrices(_ px: [String: Double], now: Date) {
        guard !px.isEmpty else { return }
        let t = now.timeIntervalSince(clockOrigin)
        for (m, p) in px where p.isFinite && p > 0 && (manual.traded(m) || history[m] != nil) {
            var h = history[m] ?? []
            if h.last.map({ t - $0.t >= 1 }) ?? true { h.append(PricePoint(t: t, mcap: p)) }
            history[m] = Array(h.suffix(240))
        }
        manual.tick(prices: px, now: now, costs: costs)
        manual.applyAutoExits(stopPct: stopLossPct, takeProfitPct: takeProfitPct, now: now)
        save()
    }

    /// Lectures utilisables pour un token : celles de l'app si assez nombreuses, sinon la série du serveur.
    public func points(for item: Feed.Item) -> [PricePoint] {
        let own = history[item.mint] ?? []
        if own.count >= 3 { return own }
        let srv = cleanSeries(item.series).map { PricePoint(t: $0.ageS, mcap: $0.marketCap) }
        return srv.count > own.count ? srv : own
    }

    /// Lectures de l'app avant l'entrée d'un trade (pour l'analyse « entré tard ? »). Vide après un redémarrage.
    public func pointsBefore(_ t: PaperTrade) -> [PricePoint] {
        let cut = t.openedAt.timeIntervalSince(clockOrigin)
        return (history[t.mint] ?? []).filter { $0.t < cut }.suffix(24).map { $0 }
    }

    /// Lectures de l'app pour un token (axe : secondes depuis l'origine fixe, comme les dates des trades).
    public func ownPoints(_ mint: String) -> [PricePoint] { history[mint] ?? [] }
    public func timeAxis(_ d: Date) -> Double { d.timeIntervalSince(clockOrigin) }

    /// Tokens vus mais pas achetés par toi.
    public func missed(limit: Int = 8) -> [Missed] { missedTokens(history: history, traded: { self.manual.traded($0) }, limit: limit) }

    private func runRobots(feed: Feed?, prices px: [String: Double], now: Date) {
        for r in robots {
            guard var b = books[r.id] else { continue }
            for t in b.open where !b.pending.contains(where: { $0.mint == t.mint }) {
                if let (f, why) = robotExit(t, rules: r.exits, now: now) {
                    _ = try? b.submitSell(mint: t.mint, fraction: f, seenMcap: px[t.mint], now: now, reason: why)
                }
            }
            for item in feed?.items ?? [] where !paused.contains(r.id) && !b.traded(item.mint) {
                guard let p = px[item.mint], robotWantsEntry(r.kind, item: item, pts: points(for: item), salt: r.id) else { continue }
                _ = try? b.submitBuy(mint: item.mint, symbol: item.symbol, stakeUSD: stakeFor(equity: b.equity), seenMcap: p, now: now, reason: robotWhy(r.kind, item: item, pts: points(for: item)), image: imageCandidates(item).first?.absoluteString)
            }
            b.tick(prices: px, now: now, costs: costs)
            b.writeOffStale(now: now, rules: r.exits)
            books[r.id] = b
        }
    }

    // MARK: tes ordres fictifs

    /// Achat fictif depuis une carte. Retourne le texte à afficher (succès ou raison du refus).
    @discardableResult
    public func buy(_ item: Feed.Item, now: Date, strategy: String = "Perso", note: String? = nil, stake: Double? = nil) -> String {
        let stakeUSD = stake ?? self.stakeUSD
        if manual.lossLimitHit(limitPct: lossLimitPct, now: now) { return Self.explain(PaperError.lossLimit) }
        do {
            try manual.submitBuy(mint: item.mint, symbol: item.symbol, stakeUSD: stakeUSD, seenMcap: item.marketCap, now: now,
                                 reason: String(strategy.prefix(24)), image: imageCandidates(item).first?.absoluteString, note: note.map { String($0.prefix(160)) })
            save()
            return "Ordre fictif de \(money(stakeUSD)) envoyé · rempli dans ~\(Int(costs.latencyS)) s"
        } catch { return Self.explain(error) }
    }

    @discardableResult
    public func sell(mint: String, fraction: Double, seenMcap: Double?, now: Date) -> String {
        do {
            try manual.submitSell(mint: mint, fraction: fraction, seenMcap: seenMcap, now: now, reason: fraction >= 1 ? "vente manuelle" : "vente partielle")
            save()
            return fraction >= 1 ? "Vente fictive envoyée" : "Vente fictive de \(Int(fraction * 100)) % envoyée"
        } catch { return Self.explain(error) }
    }

    public static func explain(_ e: Error) -> String {
        switch e as? PaperError {
        case .insufficientCash: return "Pas assez de capital fictif"
        case .alreadyOpen: return "Déjà en position (ou ordre en cours)"
        case .notOpen: return "Aucune position sur ce token"
        case .tooManyOpen: return "Trop de positions ouvertes"
        case .badAmount: return "Montant invalide"
        case .badMint: return "Adresse invalide"
        case .lossLimit: return "Limite de perte du jour atteinte : achats fictifs bloqués jusqu'à demain"
        case nil: return "Ordre refusé"
        }
    }

    /// Remise à zéro : l'ancien fichier est archivé à côté (aucune donnée effacée).
    public func reset(now: Date, startCash: Double = 100) {
        if let u = fileURL { PaperLab.setAside(u, now: now, tag: "archive") }
        manual = PaperBook(startCash: max(1, min(1_000_000, startCash.isFinite ? startCash : 100)))
        books = Dictionary(uniqueKeysWithValues: robots.map { ($0.id, PaperBook()) })
        startedAt = now
        save()
    }

    // MARK: journal

    /// Note et étiquette d'un trade (le tien ou celui d'un robot). Texte borné, sans caractère de contrôle. Rien d'autre n'est modifié.
    @discardableResult
    public func setJournal(_ id: UUID, note: String, tag: String?) -> Bool {
        let n = JournalTag.clean(note)
        let t = tag.flatMap { JournalTag(rawValue: $0)?.rawValue }
        if let i = manual.trades.firstIndex(where: { $0.id == id }) {
            manual.trades[i].journal = n.isEmpty ? nil : n; manual.trades[i].tag = t; save(); return true
        }
        for key in books.keys {
            if let i = books[key]?.trades.firstIndex(where: { $0.id == id }) {
                books[key]?.trades[i].journal = n.isEmpty ? nil : n; books[key]?.trades[i].tag = t; save(); return true
            }
        }
        return false
    }

    // MARK: disque

    private func save() {
        guard let u = fileURL else { return }
        let s = Saved(manual: manual, books: books, costs: costs, stakeUSD: stakeUSD, robotsOn: robotsOn, paused: paused, lossLimitPct: lossLimitPct, stopLossPct: stopLossPct, takeProfitPct: takeProfitPct, startedAt: startedAt)
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        guard let data = try? e.encode(s) else { return }
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: u, options: .atomic)
    }

    private static func setAside(_ u: URL, now: Date, tag: String = "illisible") {
        let stamp = Int(now.timeIntervalSince1970)
        let dest = u.deletingPathExtension().appendingPathExtension("\(tag)-\(stamp).json")
        try? FileManager.default.moveItem(at: u, to: dest)
    }
}

/// « $10 », « $2,50 », « −$1,20 ».
public func money(_ v: Double, signed: Bool = false) -> String {
    guard v.isFinite else { return "non lu" }
    let a = abs(v)
    let body = a >= 1000 ? formatUSD(a) : "$" + (a.rounded() == a && a >= 10 ? String(Int(a)) : String(format: "%.2f", a).replacingOccurrences(of: ".", with: ","))
    if v < 0 { return "−" + body }
    return signed ? "+" + body : body
}

public func pct(_ v: Double) -> String {
    guard v.isFinite else { return "non lu" }
    return (v >= 0 ? "+" : "−") + String(format: abs(v) >= 100 ? "%.0f %%" : "%.1f %%", abs(v)).replacingOccurrences(of: ".", with: ",")
}

/// Résultats par stratégie (étiquette choisie à l'achat), trades fermés seulement.
public struct StrategyStat: Sendable, Equatable, Identifiable {
    public var name: String
    public var count: Int
    public var wins: Int
    public var netUSD: Double
    public var winRate: Double { count > 0 ? Double(wins) / Double(count) * 100 : 0 }
    public var id: String { name }
}

public func strategyStats(_ trades: [PaperTrade]) -> [StrategyStat] {
    var by: [String: StrategyStat] = [:]
    for t in trades where !t.isOpen {
        var s = by[t.entryReason] ?? StrategyStat(name: t.entryReason, count: 0, wins: 0, netUSD: 0)
        s.count += 1; s.wins += t.pnlUSD > 0 ? 1 : 0; s.netUSD += t.pnlUSD
        by[t.entryReason] = s
    }
    return by.values.sorted { $0.netUSD > $1.netUSD }
}

/// « 0,92 SOL » à partir d'un montant en $ et du prix du SOL (nil = prix non lu).
public func solText(_ usd: Double, solUSD: Double?) -> String? {
    guard let p = solUSD, p > 0, usd.isFinite else { return nil }
    let v = usd / p
    let s = abs(v) >= 100 ? String(format: "%.0f", v) : abs(v) >= 10 ? String(format: "%.1f", v) : String(format: "%.2f", v)
    return s.replacingOccurrences(of: ".", with: ",") + " SOL"
}
