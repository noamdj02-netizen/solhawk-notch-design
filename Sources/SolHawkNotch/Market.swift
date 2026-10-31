import SwiftUI
import SolHawkNotchCore

// Données du terminal : colonnes (/live), bougies (/screen) et fiches (/token/<mint>). Lecture seule, à la demande :
// les colonnes toutes les 5 s et les bougies du token affiché toutes les 2 s, seulement quand le Terminal est à l'écran.

@MainActor @Observable
final class MarketStore {
    private(set) var live: LiveReply?
    private(set) var liveAt: Date?
    private(set) var liveError: FetchFailure?
    private(set) var dropped: [DroppedToken] = []
    private(set) var screens: [String: (at: Date, value: ScreenReply)] = [:]
    private(set) var flow: WalletFlowReply?
    private(set) var flowAt: Date?
    private(set) var flowFailure: FetchFailure?
    private(set) var extTrades: PaperSyncReply?
    private(set) var extTradesAt: Date?
    private(set) var extTradesFailure: FetchFailure?
    private(set) var screenFailures: [String: FetchFailure] = [:]
    private(set) var screenMs: [String: Int] = [:]      // durée de la dernière lecture des bougies (pour voir d'où vient la lenteur)
    private(set) var cards: [String: (at: Date, value: TokenCard?)] = [:]
    var interval: Int = UserDefaults.standard.object(forKey: "chartInterval") as? Int ?? 5 {
        didSet { UserDefaults.standard.set(interval, forKey: "chartInterval") }
    }
    @ObservationIgnored var onPrices: (([String: Double], Date) -> Void)?
    @ObservationIgnored private let client: () -> FeedClient?

    init(client: @escaping () -> FeedClient?) { self.client = client }

    func loadLive() async {
        guard let c = client() else { liveError = .network("configuration"); return }
        switch await c.fetchLive() {
        case .success(let l):
            live = l; liveAt = Date(); liveError = nil
            onPrices?(prices(from: l), Date())
        case .failure(let e): liveError = e
        }
    }

    /// Tokens écartés : au plus une lecture toutes les 15 s (liste courte, côté serveur en cache).
    func loadDropped() async {
        guard let c = client() else { return }
        if case .success(let r) = await c.fetchDropped() { dropped = r.items }
    }

    /// Flux des achats/ventes des wallets de MA liste (envoyés en GET, adresses publiques seulement). Au plus une lecture toutes les 15 s.
    func loadFlow(addresses: [String]) async {
        guard let c = client() else { return }
        switch await c.fetchWalletFlow(addresses: addresses) {
        case .success(let r): flow = r; flowAt = Date(); flowFailure = nil
        case .failure(let e): flowFailure = e
        }
    }

    /// Trades fictifs de l'extension (GET). Appelé seulement quand l'onglet Trades est à l'écran.
    func loadExtTrades() async {
        guard let c = client() else { return }
        switch await c.fetchPaperSync() {
        case .success(let r): extTrades = r; extTradesAt = Date(); extTradesFailure = nil
        case .failure(let e): extTradesFailure = e
        }
    }

    func loadScreen(_ mint: String) async {
        guard let c = client(), isValidMint(mint) else { return }
        let k = key(mint)
        let started = Date()
        let reply = await c.fetchScreen(mint: mint, interval: interval)
        screenMs[k] = Int(Date().timeIntervalSince(started) * 1000)
        switch reply {
        case .success(let s):
            screenFailures[k] = nil
            screens[k] = (Date(), s)
            if screens.count > 60 { screens = screens.filter { Date().timeIntervalSince($0.value.at) < 120 } }
            if let m = s.quote?.marketCap ?? s.chart?.candles?.last?.c { onPrices?([mint: m], Date()) }
        case .failure(let e):
            screenFailures[k] = e   // sans ça, l'écran restait sur « Chargement… » pour toujours quand le serveur ne répondait pas
        }
    }

    /// Fiche : au plus une lecture par minute et par token (côté serveur, elle coûte des lectures RPC).
    func loadCard(_ mint: String) async {
        guard isValidMint(mint), let c = client() else { return }
        if let hit = cards[mint], Date().timeIntervalSince(hit.at) < 60 { return }
        switch await c.fetchCard(mint: mint) {
        case .success(let card): cards[mint] = (Date(), card)
        case .failure: cards[mint] = (Date(), nil)
        }
    }

    func screen(_ mint: String) -> ScreenReply? { screens[key(mint)]?.value }
    func screenDuration(_ mint: String) -> Int? { screenMs[key(mint)] }
    func screenFailure(_ mint: String) -> FetchFailure? { screenFailures[key(mint)] }
    func screenAt(_ mint: String) -> Date? { screens[key(mint)]?.at }
    private func key(_ mint: String) -> String { "\(mint)|\(interval)" }

    /// Vrai si le token est dans une colonne du serveur (donc pas seulement parmi les écartés).
    func isListed(_ mint: String) -> Bool {
        [live?.new?.items, live?.soon?.items, live?.migrated?.items].contains { ($0 ?? []).contains { $0.mint == mint } }
    }

    /// Tous les tokens connus (colonnes + runs), pour retrouver celui qui est sélectionné.
    func allItems(feed: Feed?) -> [Feed.Item] {
        var seen = Set<String>(), out: [Feed.Item] = []
        let cols = [live?.new?.items, feed?.items, live?.soon?.items, live?.migrated?.items].compactMap { $0 }.flatMap { $0 }
        for it in cols + (live?.runs?.items ?? []).map(Feed.Item.init(run:)) + dropped.map(Feed.Item.init(dropped:)) + (flow?.events ?? []).map(Feed.Item.init(flow:)) where seen.insert(it.mint).inserted { out.append(it) }
        return out
    }
}

/// Résumé de la fiche gardé dans le trade au moment du clic (pour le relire après coup).
func cardNote(_ c: TokenCard?) -> String? {
    guard let c else { return nil }
    var parts: [String] = []
    if let d = c.devPct { parts.append("dev \(fmt1(d)) %") }
    if let t = c.top10Pct { parts.append("top 10 \(fmt1(t)) %") }
    if let h = c.holders { parts.append("\(h) détenteurs") }
    if let a = c.authorities {
        let ok = a.mint == "renounced" && a.freeze == "renounced"
        parts.append(ok ? "autorités renoncées" : "autorités : mint \(a.mint ?? "non lu"), freeze \(a.freeze ?? "non lu")")
    }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
}
