import Foundation

// Trading FICTIF. Aucun ordre réel, aucune clé, aucune signature : tout se passe dans ce fichier, en mémoire puis sur disque local.
// Le « prix » est le market cap lu dans le flux (prix = market cap ÷ offre : les rapports de prix sont identiques).

/// Coûts estimés d'un ordre. Ce sont des ESTIMATIONS, pas des mesures : le résultat affiché est « net estimé ».
public struct CostModel: Codable, Sendable, Equatable {
    /// Frais de plateforme par ordre, en % du montant (ordre de grandeur Pump.fun / PumpSwap).
    public var feePct: Double = 1.0
    /// Frais de priorité + pourboire, par ordre, en $.
    public var priorityUSD: Double = 0.05
    /// Glissement minimal par ordre, en %.
    public var baseSlipPct: Double = 0.5
    /// Profondeur supposée du marché : liquidité ≈ ce ratio × market cap (le flux ne donne pas la liquidité).
    public var depthRatio: Double = 0.15
    /// Délai entre le clic et l'exécution : l'ordre est rempli au premier prix lu APRÈS ce délai.
    public var latencyS: Double = 2
    /// Achat annulé si le prix a monté de plus que ça pendant le délai (tolérance de glissement).
    public var maxBuyDriftPct: Double = 15
    /// Ordre annulé (« non exécuté ») si le token n'a plus de prix pendant ce temps.
    public var missingTimeoutS: Double = 60

    public init() {}

    /// Glissement estimé (en %) pour un ordre de `sizeUSD` sur un token à `marketCap`. Borné à 50 %.
    public func slipPct(sizeUSD: Double, marketCap: Double) -> Double {
        guard marketCap > 0, sizeUSD > 0 else { return baseSlipPct }
        return min(50, baseSlipPct + 100 * sizeUSD / (marketCap * depthRatio))
    }
}

public enum Side: String, Codable, Sendable { case buy, sell }

public enum PaperError: Error, Equatable, Sendable {
    case badMint, badAmount, insufficientCash, alreadyOpen, notOpen, tooManyOpen, lossLimit
}

/// Ordre en attente d'exécution (simule la latence réelle : on ne paie jamais le prix vu au moment du clic).
public struct PendingOrder: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var side: Side
    public var mint: String
    public var symbol: String
    public var stakeUSD: Double      // achat : montant engagé (réservé sur le cash)
    public var fraction: Double      // vente : part de la position à vendre (0…1]
    public var submittedAt: Date
    public var seenMcap: Double?     // prix vu au clic (pour mesurer l'écart)
    public var reason: String
    public var image: String? = nil  // logo (URL filtrée), décoratif
    public var note: String? = nil   // ce qu'on savait du token au clic (dev, détenteurs…)
}

/// Une position (ouverte ou fermée). Les montants sont en $ fictifs.
public struct PaperTrade: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var mint: String
    public var symbol: String
    public var openedAt: Date
    public var seenMcap: Double?     // prix vu au clic
    public var entryMcap: Double     // prix effectif payé (glissement inclus)
    public var stakeUSD: Double      // mise engagée
    public var share: Double         // part de l'offre encore détenue
    public var initialShare: Double
    public var costsUSD: Double      // frais + glissement payés (estimés)
    public var realizedUSD: Double   // déjà encaissé par les ventes (net)
    public var lastMcap: Double
    public var lastSeen: Date
    public var peakMcap: Double
    public var tookPartial = false
    public var closedAt: Date?
    public var exitMcap: Double?
    public var exitReason: String?
    public var entryReason: String
    public var image: String? = nil
    public var entryNote: String? = nil
    public var journal: String? = nil    // ma note après coup (« ce que j'ai appris »), texte à moi
    public var tag: String? = nil        // mon étiquette (une des JournalTag)

    public var isOpen: Bool { closedAt == nil }
    /// Valeur brute actuelle de ce qui reste (avant frais de sortie).
    public var markUSD: Double { share * lastMcap }
    /// Résultat net estimé : encaissé + valeur restante − mise (les frais d'entrée sont déjà dans la mise).
    public var pnlUSD: Double { realizedUSD + markUSD - stakeUSD }
    public var pnlPct: Double { stakeUSD > 0 ? pnlUSD / stakeUSD * 100 : 0 }
    /// Multiple du prix depuis l'entrée (1,5 = +50 %).
    public var multiple: Double { entryMcap > 0 ? lastMcap / entryMcap : 1 }
    public var holdS: Double { (closedAt ?? lastSeen).timeIntervalSince(openedAt) }
}

public struct EquityPoint: Codable, Sendable, Equatable {
    public var at: Date
    public var equity: Double
}

/// Un portefeuille fictif (le tien, ou celui d'un robot).
public struct PaperBook: Codable, Sendable, Equatable {
    public var startCash: Double
    public var cash: Double
    public var trades: [PaperTrade] = []
    public var pending: [PendingOrder] = []
    public var canceled = 0                  // ordres non exécutés (prix parti, token disparu)
    public var equityCurve: [EquityPoint] = []
    public var maxOpen = 12

    public init(startCash: Double = 100) { self.startCash = startCash; cash = startCash }

    public var open: [PaperTrade] { trades.filter(\.isOpen) }
    public var closed: [PaperTrade] { trades.filter { !$0.isOpen } }
    public var reserved: Double { pending.filter { $0.side == .buy }.reduce(0) { $0 + $1.stakeUSD } }
    public var equity: Double { cash + reserved + open.reduce(0) { $0 + $1.markUSD } }
    public var pnlUSD: Double { equity - startCash }
    public var pnlPct: Double { startCash > 0 ? pnlUSD / startCash * 100 : 0 }
    public var winRate: Double? {
        let c = closed
        guard !c.isEmpty else { return nil }
        return Double(c.filter { $0.pnlUSD > 0 }.count) / Double(c.count) * 100
    }
    /// Pire baisse depuis un sommet de la courbe de capital, en % (valeur négative ou 0).
    public var maxDrawdownPct: Double {
        var peak = startCash, worst = 0.0
        for p in equityCurve { peak = max(peak, p.equity); if peak > 0 { worst = min(worst, (p.equity / peak - 1) * 100) } }
        return worst
    }
    /// Résultat fictif depuis le début de la journée (capital maintenant − dernier capital connu avant minuit ; à défaut, le capital de départ).
    public func dayPnlUSD(now: Date, calendar: Calendar = .current) -> Double {
        let start = calendar.startOfDay(for: now)
        let base = equityCurve.last { $0.at < start }?.equity ?? startCash
        return equity - base
    }
    /// Vrai si la perte du jour atteint `limitPct` % du capital de départ (0 = limite désactivée).
    public func lossLimitHit(limitPct: Double, now: Date, calendar: Calendar = .current) -> Bool {
        limitPct > 0 && dayPnlUSD(now: now, calendar: calendar) <= -(limitPct / 100) * startCash
    }
    /// Sorties automatiques de TES positions : stop loss (baisse du prix depuis ton entrée, en %) et prise de gain (hausse, en %).
    /// 0 = désactivé. Le prix compte, pas les frais. Un seul ordre de vente à la fois par position.
    public mutating func applyAutoExits(stopPct: Double, takeProfitPct: Double, now: Date) {
        guard stopPct > 0 || takeProfitPct > 0 else { return }
        for t in open where !pending.contains(where: { $0.mint == t.mint && $0.side == .sell }) {
            let move = (t.multiple - 1) * 100
            if stopPct > 0, move <= -stopPct {
                _ = try? submitSell(mint: t.mint, fraction: 1, seenMcap: t.lastMcap, now: now, reason: "stop loss −\(Int(stopPct)) %")
            } else if takeProfitPct > 0, move >= takeProfitPct {
                _ = try? submitSell(mint: t.mint, fraction: 1, seenMcap: t.lastMcap, now: now, reason: "prise de gain +\(Int(takeProfitPct)) %")
            }
        }
    }
    public func hasPosition(_ mint: String) -> Bool { open.contains { $0.mint == mint } || pending.contains { $0.mint == mint && $0.side == .buy } }
    public func position(_ mint: String) -> PaperTrade? { open.first { $0.mint == mint } }
    public func traded(_ mint: String) -> Bool { trades.contains { $0.mint == mint } || pending.contains { $0.mint == mint } }

    /// Place un achat fictif. Le montant est réservé tout de suite ; l'exécution se fait au prochain prix après la latence.
    @discardableResult
    public mutating func submitBuy(mint: String, symbol: String?, stakeUSD: Double, seenMcap: Double?, now: Date, reason: String, image: String? = nil, note: String? = nil) throws -> PendingOrder {
        guard !mint.isEmpty, mint.count <= 64 else { throw PaperError.badMint }
        guard stakeUSD.isFinite, stakeUSD > 0 else { throw PaperError.badAmount }
        guard !hasPosition(mint) else { throw PaperError.alreadyOpen }
        guard open.count + pending.filter({ $0.side == .buy }).count < maxOpen else { throw PaperError.tooManyOpen }
        guard cash + 1e-9 >= stakeUSD else { throw PaperError.insufficientCash }
        cash -= stakeUSD
        let o = PendingOrder(id: UUID(), side: .buy, mint: mint, symbol: safeLabel(symbol), stakeUSD: stakeUSD, fraction: 0, submittedAt: now, seenMcap: seenMcap, reason: reason, image: image, note: note)
        pending.append(o)
        return o
    }

    @discardableResult
    public mutating func submitSell(mint: String, fraction: Double, seenMcap: Double?, now: Date, reason: String) throws -> PendingOrder {
        guard let t = position(mint) else { throw PaperError.notOpen }
        guard fraction.isFinite, fraction > 0, fraction <= 1 else { throw PaperError.badAmount }
        if pending.contains(where: { $0.mint == mint && $0.side == .sell }) { throw PaperError.alreadyOpen }
        let o = PendingOrder(id: UUID(), side: .sell, mint: mint, symbol: t.symbol, stakeUSD: 0, fraction: fraction, submittedAt: now, seenMcap: seenMcap, reason: reason)
        pending.append(o)
        return o
    }

    /// Avance le temps : met à jour les prix, exécute les ordres arrivés à échéance, note la courbe de capital.
    /// `prices` : market cap lu par mint (seulement les tokens présents dans le flux et avec un prix).
    public mutating func tick(prices: [String: Double], now: Date, costs: CostModel) {
        for i in trades.indices where trades[i].isOpen {
            if let p = prices[trades[i].mint], p > 0, p.isFinite {
                trades[i].lastMcap = p; trades[i].lastSeen = now; trades[i].peakMcap = max(trades[i].peakMcap, p)
            }
        }
        var still: [PendingOrder] = []
        for o in pending {
            let waited = now.timeIntervalSince(o.submittedAt)
            guard waited >= costs.latencyS else { still.append(o); continue }
            guard let p = prices[o.mint], p > 0, p.isFinite else {
                if waited >= costs.missingTimeoutS { cancel(o) } else { still.append(o) }
                continue
            }
            switch o.side {
            case .buy: fillBuy(o, mcap: p, now: now, costs: costs)
            case .sell: fillSell(o, mcap: p, now: now, costs: costs)
            }
        }
        pending = still
        let e = equity
        if equityCurve.last.map({ abs($0.equity - e) > 1e-6 || now.timeIntervalSince($0.at) >= 60 }) ?? true {
            equityCurve.append(EquityPoint(at: now, equity: e))
            if equityCurve.count > 600 { equityCurve.removeFirst(equityCurve.count - 600) }
        }
    }

    private mutating func cancel(_ o: PendingOrder) {
        if o.side == .buy { cash += o.stakeUSD }
        canceled += 1
    }

    private mutating func fillBuy(_ o: PendingOrder, mcap: Double, now: Date, costs: CostModel) {
        if let seen = o.seenMcap, seen > 0, (mcap / seen - 1) * 100 > costs.maxBuyDriftPct { cancel(o); return }   // prix parti trop haut : non exécuté
        let fee = o.stakeUSD * costs.feePct / 100 + costs.priorityUSD
        let net = max(0, o.stakeUSD - fee)
        let slip = costs.slipPct(sizeUSD: net, marketCap: mcap)
        let entry = mcap * (1 + slip / 100)
        let share = net / entry
        trades.append(PaperTrade(id: o.id, mint: o.mint, symbol: o.symbol, openedAt: now, seenMcap: o.seenMcap, entryMcap: entry, stakeUSD: o.stakeUSD,
                                 share: share, initialShare: share, costsUSD: fee + net * slip / (100 + slip), realizedUSD: 0,
                                 lastMcap: mcap, lastSeen: now, peakMcap: mcap, entryReason: o.reason, image: o.image, entryNote: o.note))
    }

    private mutating func fillSell(_ o: PendingOrder, mcap: Double, now: Date, costs: CostModel) {
        guard let i = trades.firstIndex(where: { $0.mint == o.mint && $0.isOpen }) else { canceled += 1; return }
        let sellShare = trades[i].share * o.fraction
        let gross = sellShare * mcap
        let slip = costs.slipPct(sizeUSD: gross, marketCap: mcap)
        let afterSlip = gross * (1 - slip / 100)
        let fee = afterSlip * costs.feePct / 100 + costs.priorityUSD
        let proceeds = max(0, afterSlip - fee)
        trades[i].share -= sellShare
        trades[i].realizedUSD += proceeds
        trades[i].costsUSD += (gross - afterSlip) + fee
        trades[i].lastMcap = mcap; trades[i].lastSeen = now
        cash += proceeds
        if o.fraction >= 1 - 1e-9 || trades[i].share <= trades[i].initialShare * 1e-6 {
            trades[i].share = 0; trades[i].closedAt = now; trades[i].exitMcap = mcap; trades[i].exitReason = o.reason
        } else {
            trades[i].tookPartial = true
        }
    }
}

/// Mise selon le capital (mêmes paliers que l'agent fictif du serveur).
public func stakeFor(equity: Double) -> Double {
    if equity < 30 { return 2.5 }
    if equity < 70 { return 5 }
    if equity >= 200 { return 15 }
    return 10
}

/// Cours du flux, par mint : seulement les valeurs exploitables (le reste = « non lu », jamais inventé).
public func prices(from feed: Feed?) -> [String: Double] {
    var out: [String: Double] = [:]
    for it in feed?.items ?? [] { if let m = it.marketCap, m.isFinite, m > 0 { out[it.mint] = m } }
    return out
}
