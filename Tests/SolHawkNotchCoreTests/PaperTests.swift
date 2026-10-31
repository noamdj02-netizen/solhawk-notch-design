import Foundation
import Testing
@testable import SolHawkNotchCore

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
private func at(_ s: Double) -> Date { t0.addingTimeInterval(s) }
private let green = Feed.Lights(mint: "green", freeze: "green", dev: "green", volume: "green", holders: "green")
private func item(_ mint: String, mcap: Double?, age: Int = 30, ok: Bool = true) -> Feed.Item {
    Feed.Item(mint: mint, symbol: "TK", name: nil, ageS: age, marketCap: mcap, realSol: 3, risk: Feed.Risk(score: 5, label: ok ? "faible" : "élevé"), lights: green, series: nil, fromPeakPct: nil)
}
private func feed(_ items: [Feed.Item]) -> Feed { Feed(updatedAt: nil, stats: .init(), items: items, note: nil) }
private func pts(_ v: [Double]) -> [PricePoint] { v.enumerated().map { PricePoint(t: Double($0.offset) * 5, mcap: $0.element) } }

@Suite struct PaperBookTests {
    @Test func buyWaitsForLatencyAndPaysSlippageAndFees() throws {
        var b = PaperBook()
        let c = CostModel()
        try b.submitBuy(mint: "M1", symbol: "AAA", stakeUSD: 10, seenMcap: 10_000, now: at(0), reason: "test")
        #expect(b.cash == 90)
        #expect(b.equity == 100)          // réservé, pas encore perdu
        b.tick(prices: ["M1": 10_000], now: at(1), costs: c)
        #expect(b.open.isEmpty)           // latence pas écoulée
        b.tick(prices: ["M1": 10_000], now: at(5), costs: c)
        let t = try #require(b.open.first)
        #expect(t.entryMcap > 10_000)     // glissement : on paie plus cher que le prix lu
        #expect(t.markUSD < 10)           // frais + glissement : la position vaut moins que la mise
        #expect(t.pnlUSD < 0)
    }

    @Test func buyCanceledWhenPriceRunsAwayAndCashRefunded() throws {
        var b = PaperBook()
        try b.submitBuy(mint: "M1", symbol: nil, stakeUSD: 10, seenMcap: 10_000, now: at(0), reason: "test")
        b.tick(prices: ["M1": 13_000], now: at(5), costs: CostModel())   // +30 % > tolérance 15 %
        #expect(b.open.isEmpty)
        #expect(b.cash == 100)
        #expect(b.canceled == 1)
    }

    @Test func orderCanceledWhenTokenHasNoPrice() throws {
        var b = PaperBook()
        try b.submitBuy(mint: "M1", symbol: nil, stakeUSD: 10, seenMcap: 10_000, now: at(0), reason: "test")
        b.tick(prices: [:], now: at(30), costs: CostModel())
        #expect(b.pending.count == 1)
        b.tick(prices: [:], now: at(61), costs: CostModel())
        #expect(b.pending.isEmpty && b.cash == 100 && b.canceled == 1)
    }

    @Test func roundTripAtSamePriceLosesMoney() throws {
        var b = PaperBook()
        let c = CostModel()
        try b.submitBuy(mint: "M1", symbol: nil, stakeUSD: 10, seenMcap: 10_000, now: at(0), reason: "t")
        b.tick(prices: ["M1": 10_000], now: at(5), costs: c)
        try b.submitSell(mint: "M1", fraction: 1, seenMcap: 10_000, now: at(6), reason: "t")
        b.tick(prices: ["M1": 10_000], now: at(10), costs: c)
        #expect(b.open.isEmpty)
        let t = try #require(b.closed.first)
        #expect(t.pnlUSD < 0)             // aller-retour au même prix = perte des coûts
        #expect(b.cash < 100)
        #expect(b.winRate == 0)
    }

    @Test func partialSellKeepsPositionOpen() throws {
        var b = PaperBook()
        let c = CostModel()
        try b.submitBuy(mint: "M1", symbol: nil, stakeUSD: 10, seenMcap: 10_000, now: at(0), reason: "t")
        b.tick(prices: ["M1": 10_000], now: at(5), costs: c)
        try b.submitSell(mint: "M1", fraction: 0.5, seenMcap: 20_000, now: at(6), reason: "t")
        b.tick(prices: ["M1": 20_000], now: at(10), costs: c)
        let t = try #require(b.open.first)
        #expect(t.tookPartial)
        #expect(t.realizedUSD > 0)
        #expect(abs(t.share - t.initialShare / 2) < t.initialShare * 1e-9)
    }

    @Test func refusesDuplicateOversizeAndBadInput() throws {
        var b = PaperBook()
        try b.submitBuy(mint: "M1", symbol: nil, stakeUSD: 10, seenMcap: 1, now: at(0), reason: "t")
        #expect(throws: PaperError.alreadyOpen) { try b.submitBuy(mint: "M1", symbol: nil, stakeUSD: 10, seenMcap: 1, now: at(0), reason: "t") }
        #expect(throws: PaperError.insufficientCash) { try b.submitBuy(mint: "M2", symbol: nil, stakeUSD: 500, seenMcap: 1, now: at(0), reason: "t") }
        #expect(throws: PaperError.badAmount) { try b.submitBuy(mint: "M3", symbol: nil, stakeUSD: -1, seenMcap: 1, now: at(0), reason: "t") }
        #expect(throws: PaperError.badMint) { try b.submitBuy(mint: "", symbol: nil, stakeUSD: 1, seenMcap: 1, now: at(0), reason: "t") }
        #expect(throws: PaperError.notOpen) { try b.submitSell(mint: "M9", fraction: 1, seenMcap: 1, now: at(0), reason: "t") }
    }

    @Test func staleWriteOffIsPessimistic() throws {
        var b = PaperBook()
        let c = CostModel()
        try b.submitBuy(mint: "M1", symbol: nil, stakeUSD: 10, seenMcap: 10_000, now: at(0), reason: "t")
        b.tick(prices: ["M1": 10_000], now: at(5), costs: c)
        let mark = b.open[0].markUSD
        b.writeOffStale(now: at(5 + 601), rules: ExitRules())
        let t = try #require(b.closed.first)
        #expect(abs(t.realizedUSD - mark * 0.5) < 1e-9)
        #expect(t.exitReason?.contains("supposée") == true)
    }

    @Test func slippageGrowsWithSizeAndIsCapped() {
        let c = CostModel()
        #expect(c.slipPct(sizeUSD: 10, marketCap: 100_000) < c.slipPct(sizeUSD: 1_000, marketCap: 100_000))
        #expect(c.slipPct(sizeUSD: 1e9, marketCap: 1) == 50)
    }

    @Test func stakeTiers() {
        #expect(stakeFor(equity: 20) == 2.5)
        #expect(stakeFor(equity: 50) == 5)
        #expect(stakeFor(equity: 100) == 10)
        #expect(stakeFor(equity: 250) == 15)
    }
}

@Suite struct RobotTests {
    @Test func momentumNeedsRiseAndContinuation() {
        let it = item("M", mcap: 1)
        #expect(robotWantsEntry(.momentum, item: it, pts: pts([100, 108, 120]), salt: "x"))
        #expect(!robotWantsEntry(.momentum, item: it, pts: pts([100, 125, 120]), salt: "x"))   // retombe
        #expect(!robotWantsEntry(.momentum, item: it, pts: pts([100, 120]), salt: "x"))        // trop peu de lectures
    }

    @Test func fibonacciRetracementZoneWithRebound() {
        // hausse 100 → 200, repli à 145 (retracement 55 %), rebond à 150 (retracement 50 %)
        #expect(fibRebound(pts([100, 140, 200, 160, 145, 150])))
        #expect(!fibRebound(pts([100, 140, 200, 180, 185, 190])))   // repli trop faible
        #expect(!fibRebound(pts([100, 140, 200, 110, 105, 108])))   // repli trop profond
        #expect(!fibRebound(pts([100, 110, 120, 115, 112, 114])))   // pas de vraie hausse
        #expect(!fibRebound(pts([100, 140, 200, 160, 150, 145])))   // pas de rebond
    }

    @Test func dipBuyZone() {
        let it = item("M", mcap: 1)
        #expect(robotWantsEntry(.dipBuy, item: it, pts: pts([200, 120, 130]), salt: "x"))    // −35 % et rebond
        #expect(!robotWantsEntry(.dipBuy, item: it, pts: pts([200, 180, 190]), salt: "x"))   // pas assez bas
        #expect(!robotWantsEntry(.dipBuy, item: it, pts: pts([200, 80, 90]), salt: "x"))     // trop bas
    }

    @Test func listingRespectsFiltersAndAge() {
        #expect(robotWantsEntry(.onListing, item: item("M", mcap: 1, age: 60), pts: [], salt: "x"))
        #expect(!robotWantsEntry(.onListing, item: item("M", mcap: 1, age: 900), pts: [], salt: "x"))
        #expect(!robotWantsEntry(.onListing, item: item("M", mcap: 1, ok: false), pts: [], salt: "x"))
    }

    @Test func randomControlIsStableAndRoughlyOneInThree() {
        let picks = (0..<300).filter { robotWantsEntry(.random, item: item("Mint\($0)", mcap: 1), pts: [], salt: "random") }
        #expect(picks.count > 60 && picks.count < 140)
        let again = (0..<300).filter { robotWantsEntry(.random, item: item("Mint\($0)", mcap: 1), pts: [], salt: "random") }
        #expect(picks == again)
    }

    @Test func exitRules() {
        var t = PaperTrade(id: UUID(), mint: "M", symbol: "S", openedAt: at(0), seenMcap: 100, entryMcap: 100, stakeUSD: 10, share: 0.1, initialShare: 0.1,
                           costsUSD: 0, realizedUSD: 0, lastMcap: 70, lastSeen: at(10), peakMcap: 100, entryReason: "t")
        #expect(robotExit(t, rules: ExitRules(), now: at(10))?.fraction == 1)        // −30 % : stop
        t.lastMcap = 160; t.peakMcap = 160
        #expect(robotExit(t, rules: ExitRules(), now: at(10))?.fraction == 0.5)      // ×1,6 : moitié
        t.tookPartial = true; t.peakMcap = 300; t.lastMcap = 200
        #expect(robotExit(t, rules: ExitRules(), now: at(10))?.reason.contains("repli") == true)
        t.lastMcap = 290
        #expect(robotExit(t, rules: ExitRules(), now: at(10)) == nil)
        #expect(robotExit(t, rules: ExitRules(), now: at(1801))?.reason == "durée max")
    }
}

@Suite @MainActor struct PaperLabTests {
    @Test func robotsTradeOnFeedAndManualOrdersFill() {
        let lab = PaperLab(fileURL: nil, now: at(0))
        let f1 = feed([item("A", mcap: 10_000, age: 30)])
        lab.ingest(f1, now: at(0))
        #expect(lab.books["listing"]?.pending.count == 1)
        #expect(lab.buy(f1.items[0], now: at(0)).contains("envoyé"))
        lab.ingest(f1, now: at(5))
        #expect(lab.books["listing"]?.open.count == 1)
        #expect(lab.manual.open.count == 1)
        #expect(lab.buy(f1.items[0], now: at(6)).contains("Déjà"))
    }

    @Test func persistsAndSetsAsideCorruptFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("paper-\(UUID().uuidString)")
        let url = dir.appendingPathComponent("paper.json")
        let lab = PaperLab(fileURL: url, now: at(0))
        lab.buy(item("A", mcap: 10_000), now: at(0))
        let again = PaperLab(fileURL: url, now: at(1))
        #expect(again.manual.pending.count == 1)
        try Data("pas du json".utf8).write(to: url)
        let fresh = PaperLab(fileURL: url, now: at(2))
        #expect(fresh.manual.pending.isEmpty)
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(names.contains { $0.contains("illisible") })   // mis de côté, pas effacé
        try? FileManager.default.removeItem(at: dir)
    }

    @Test func formatting() {
        #expect(money(10) == "$10")
        #expect(money(2.5) == "$2,50")
        #expect(money(-1.2) == "−$1,20")
        #expect(money(3, signed: true) == "+$3,00")
        #expect(pct(-12.34) == "−12,3 %")
        #expect(pct(134.9) == "+135 %")
    }
}

@Suite struct TokenImageTests {
    private func it(_ url: String?, alts: [String]? = nil) -> Feed.Item {
        var i = Feed.Item(mint: "MintXpump", symbol: "abc", name: nil, ageS: nil, marketCap: nil, realSol: nil, risk: nil, lights: nil, series: nil, fromPeakPct: nil)
        i.imageURL = url; i.imageAlts = alts
        return i
    }
    @Test func onlyHttpsFromKnownHosts() {
        #expect(imageCandidates(it("https://images.pump.fun/coin-image/X?imageSize=128x128")).count == 1)
        #expect(imageCandidates(it("http://images.pump.fun/x")).isEmpty)                 // pas de http
        #expect(imageCandidates(it("https://tracker.example.com/pixel.png")).isEmpty)     // hôte inconnu
        #expect(imageCandidates(it("https://user:pw@ipfs.io/ipfs/Qm")).isEmpty)           // identifiants
        #expect(imageCandidates(it("https://ipfs.io:8443/ipfs/Qm")).isEmpty)              // port exotique
        #expect(imageCandidates(it("file:///etc/passwd")).isEmpty)
    }
    @Test func keepsOrderDedupesAndCaps() {
        let a = "https://gateway.pinata.cloud/ipfs/Qm1", b = "https://4everland.io/ipfs/Qm1"
        let c = imageCandidates(it(a, alts: [a, b, "https://evil.test/x", "https://ipfs.io/ipfs/1", "https://ipfs.io/ipfs/2", "https://ipfs.io/ipfs/3"]))
        #expect(c.map(\.absoluteString).prefix(2) == [a, b])
        #expect(c.count == 4)
    }
    @Test func avatarFallback() {
        #expect(avatarInitial("eyes") == "E")
        #expect(avatarInitial(nil) == "?")
        #expect(avatarHue("abc") == avatarHue("abc"))
    }
    @Test func decodesImageFields() throws {
        let json = #"{"items":[{"mint":"M","image_url":"https://images.pump.fun/a","image_alts":["https://ipfs.io/ipfs/b"]}]}"#
        let f = try JSONDecoder().decode(Feed.self, from: Data(json.utf8))
        #expect(f.items[0].imageURL == "https://images.pump.fun/a")
        #expect(f.items[0].imageAlts?.count == 1)
    }
}

@Suite struct ReviewTests {
    private func trade(entry: Double = 100, peak: Double = 100, exit: Double? = 100, costs: Double = 0.2, hold: Double = 120, seen: Double? = 100) -> PaperTrade {
        var t = PaperTrade(id: UUID(), mint: "M", symbol: "S", openedAt: at(0), seenMcap: seen, entryMcap: entry, stakeUSD: 10, share: 0, initialShare: 0.1,
                           costsUSD: costs, realizedUSD: exit.map { 10 * $0 / entry } ?? 0, lastMcap: exit ?? entry, lastSeen: at(hold), peakMcap: peak, entryReason: "t")
        if let exit { t.closedAt = at(hold); t.exitMcap = exit } else { t.share = 0.1 }
        return t
    }
    @Test func flagsLeftOnTheTable() {
        let n = review(trade(peak: 300, exit: 110))
        #expect(n.contains { $0.tone == .bad && $0.text.contains("×3,0") })
    }
    @Test func praisesExitNearTop() {
        #expect(review(trade(peak: 200, exit: 190)).contains { $0.tone == .good && $0.text.contains("proche du plus haut") })
    }
    @Test func flagsLateEntryCostsAndBigLoss() {
        let n = review(trade(entry: 200, exit: 140, costs: 1.0, seen: 180), before: pts([100, 150, 190]))
        #expect(n.contains { $0.text.contains("hausse déjà faite") })
        #expect(n.contains { $0.text.contains("Frais et glissement") })
        #expect(n.contains { $0.text.contains("plus de 25 %") })
        #expect(n.contains { $0.text.contains("au-dessus du prix vu") })
    }
    @Test func shortTradeAndNoAdviceWords() {
        let n = review(trade(hold: 10))
        #expect(n.contains { $0.text.contains("moins de 30 s") })
        for x in n { #expect(!x.text.lowercased().contains("achète")); #expect(!x.text.lowercased().contains("garanti")) }
    }
    @Test func robotReasons() {
        #expect(robotWhy(.momentum, item: item("M", mcap: 1), pts: pts([100, 110, 120])).contains("+20"))
        #expect(robotWhy(.fibRetrace, item: item("M", mcap: 1), pts: pts([100, 140, 200, 160, 145, 150])).contains("×2,0"))
        #expect(robotWhy(.random, item: item("M", mcap: 1), pts: []).contains("hasard") || robotWhy(.random, item: item("M", mcap: 1), pts: []).contains("sort"))
    }
    @Test func missedSortsByBiggestMove() {
        let h = ["A": pts([100, 110, 300]), "B": pts([100, 90, 95]), "C": pts([100, 50, 20]), "D": pts([100, 200])]
        let m = missedTokens(history: h, traded: { $0 == "A" })
        #expect(m.map(\.mint) == ["C", "B"])   // A acheté, D trop peu de lectures
        #expect(m[0].changePct == -80)
    }
}

@Suite struct WalletTests {
    @Test func decodesListingAndActivity() throws {
        let list = #"{"registry":{"count":2,"elite":1},"wallets":[{"address":"AAAA1111BBBB2222CCCC3333DDDD4444EEEE5555","label":"Ansem","emoji":"🐸","category":"trader","elite":true,"influence":2,"recent":[{"mint":"M","side":"BUY","block_time":1700000000}]}]}"#
        let r = try JSONDecoder().decode(WalletsReply.self, from: Data(list.utf8))
        #expect(r.wallets?.first?.recent?.first?.side == "BUY")
        let act = #"{"activity":{"status":"OK","label":"1 wallet","tx_read":30,"wallets":[{"address":"X","buys":1,"sells":0,"last_block_time":5}]}}"#
        let a = try JSONDecoder().decode(WalletActivityReply.self, from: Data(act.utf8))
        #expect(a.activity?.wallets?.first?.buys == 1 && a.activity?.txRead == 30)
    }
    @Test func identiconIsStableAndSymmetric() {
        let a = identicon("AAAA1111"), b = identicon("AAAA1111")
        #expect(a.cells == b.cells && a.hue == b.hue)
        for r in 0..<5 { for c in 0..<5 { #expect(a.cells[r * 5 + c] == a.cells[r * 5 + (4 - c)]) } }
        #expect(identicon("ZZZZ9999").cells != a.cells || identicon("ZZZZ9999").hue != a.hue)
    }
    @Test func labelsAreHonest() {
        #expect(sideLabel("RECEIVED").contains("sans"))
        #expect(categoryLabel("possible_mint").contains("token"))
        #expect(shortAddress("AAAA1111BBBB2222") == "AAAA…2222")
        #expect(safeEmoji("🐸🐸🐸🐸").count <= 2)
    }
    @Test func walletActivityRejectsBadMintWithoutCalling() async {
        struct NoCall: HTTPTransport { func get(_ url: URL, headers: [String: String]) async throws -> HTTPReply { Issue.record("appel inattendu"); return HTTPReply(status: 500, body: Data()) } }
        let c = try! FeedClient(baseURL: URL(string: "https://x.test")!, transport: NoCall(), tokenProvider: { "t" })
        let r = await c.fetchWalletActivity(mint: "../../admin")
        #expect(r == .failure(.badResponse))
    }
}

@Suite struct MarketTests {
    @Test func decodesScreenAndLive() throws {
        let screen = #"{"mint":"M","chart":{"candles":[{"t":1,"o":10,"h":12,"l":9,"c":11,"flow_sol":0.5,"n":3}],"ema9":[null],"ema21":[null],"interval_s":5},"quote":{"market_cap":11,"source":"dex"},"identity":{"symbol":"S","image_url":"https://images.pump.fun/x"},"n_samples":3,"warming":true}"#
        let s = try JSONDecoder().decode(ScreenReply.self, from: Data(screen.utf8))
        #expect(s.chart?.candles?.first?.flowSol == 0.5 && s.quote?.marketCap == 11)
        let live = #"{"new":{"items":[{"mint":"A","market_cap":5}]},"soon":{"items":[{"mint":"B","market_cap":7}]},"migrated":{"items":[]},"runs":{"items":[{"mint":"C","gain_pct":35,"mc_now":9,"age_s":20}]},"positions":{},"sim":{}}"#
        let l = try JSONDecoder().decode(LiveReply.self, from: Data(live.utf8))
        #expect(prices(from: l) == ["A": 5, "B": 7, "C": 9])
        #expect(Feed.Item(run: l.runs!.items![0]).marketCap == 9)
    }
    @Test func socialLinksAreFiltered() {
        #expect(safeSocialURL(Social(kind: "twitter", url: "https://x.com/abc")) != nil)
        #expect(safeSocialURL(Social(kind: "twitter", url: "https://evil.com/x.com")) == nil)
        #expect(safeSocialURL(Social(kind: "telegram", url: "https://t.me/grp")) != nil)
        #expect(safeSocialURL(Social(kind: "website", url: "javascript:alert(1)")) == nil)
        #expect(safeSocialURL(Social(kind: "website", url: "http://site.com")) == nil)
        #expect(safeSocialURL(Social(kind: "website", url: "https://u:p@site.com")) == nil)
        #expect(safeSocialURL(Social(kind: "other", url: "https://site.com")) == nil)
    }
    @Test func screenAndCardRejectBadInputWithoutCalling() async {
        struct NoCall: HTTPTransport { func get(_ url: URL, headers: [String: String]) async throws -> HTTPReply { Issue.record("appel inattendu"); return HTTPReply(status: 500, body: Data()) } }
        let c = try! FeedClient(baseURL: URL(string: "https://x.test")!, transport: NoCall(), tokenProvider: { "t" })
        #expect(await c.fetchScreen(mint: "bad/../x", interval: 5) == .failure(.badResponse))
        #expect(await c.fetchScreen(mint: "6zuDiAw3NviBwcLZfTztHJgtCmeNWfyFxYVoXtNYpump", interval: 7) == .failure(.badResponse))
        #expect(await c.fetchCard(mint: "nope") == .failure(.badResponse))
    }
    @Test func screenBuildsQueryOnAllowedPath() async {
        final class Rec: HTTPTransport, @unchecked Sendable {
            var urls: [URL] = []
            func get(_ url: URL, headers: [String: String]) async throws -> HTTPReply { urls.append(url); return HTTPReply(status: 200, body: Data("{}".utf8)) }
        }
        let r = Rec()
        let c = try! FeedClient(baseURL: URL(string: "https://x.test")!, transport: r, tokenProvider: { "t" })
        _ = await c.fetchScreen(mint: "6zuDiAw3NviBwcLZfTztHJgtCmeNWfyFxYVoXtNYpump", interval: 15)
        #expect(r.urls.first?.absoluteString == "https://x.test/api/companion/screen?mint=6zuDiAw3NviBwcLZfTztHJgtCmeNWfyFxYVoXtNYpump&interval=15")
    }
}

@Suite @MainActor struct ExtraPriceTests {
    @Test func positionsOutsideMainFeedGetFilledAndMarked() {
        let lab = PaperLab(fileURL: nil, now: at(0))
        lab.buy(item("SOON", mcap: 10_000), now: at(0))
        lab.ingest(feed([]), now: at(5))                      // flux principal sans ce token
        #expect(lab.manual.open.isEmpty && lab.manual.pending.count == 1)
        lab.updatePrices(["SOON": 10_000], now: at(6))        // prix venu de la colonne « bientôt migrés »
        #expect(lab.manual.open.count == 1)
        lab.updatePrices(["SOON": 15_000], now: at(12))
        #expect((lab.manual.open.first?.multiple ?? 0) > 1.4)
    }
}

@Suite @MainActor struct StrategyTests {
    @Test func tagAndNoteTravelToTradeAndStatsGroup() {
        let lab = PaperLab(fileURL: nil, now: at(0))
        lab.buy(item("A", mcap: 10_000), now: at(0), strategy: "Momentum", note: "dev 3 %")
        lab.ingest(feed([item("A", mcap: 10_000)]), now: at(5))
        let t = lab.manual.open.first
        #expect(t?.entryReason == "Momentum" && t?.entryNote == "dev 3 %")
        lab.sell(mint: "A", fraction: 1, seenMcap: 20_000, now: at(6))
        lab.ingest(feed([item("A", mcap: 20_000)]), now: at(10))
        let s = strategyStats(lab.manual.trades)
        #expect(s.count == 1 && s[0].name == "Momentum" && s[0].wins == 1 && s[0].netUSD > 0)
    }
}

@Suite @MainActor struct PausedRobotTests {
    @Test func pausedRobotDoesNotEnter() {
        let lab = PaperLab(fileURL: nil, now: at(0))
        lab.paused = ["listing"]
        lab.ingest(feed([item("A", mcap: 10_000, age: 30)]), now: at(0))
        #expect(lab.books["listing"]?.pending.isEmpty == true)
        lab.paused = []
        lab.ingest(feed([item("B", mcap: 10_000, age: 30)]), now: at(1))
        #expect(lab.books["listing"]?.pending.count == 1)
    }
}

@Suite struct SocialPreviewTests {
    @Test func parsesTelegramPage() {
        let html = #"<html><meta property="og:title" content="Stable Inu &amp; Co"><meta property="og:description" content="Le groupe officiel"><div class="tgme_page_extra">12 345 members, 300 online</div></html>"#
        let p = parsePreview(html: html)
        #expect(p.title == "Stable Inu & Co" && p.text == "Le groupe officiel" && p.members?.contains("12 345") == true)
    }
    @Test func parsesTweetOEmbedWithoutTags() {
        let json = Data(#"{"author_name":"Hughman","html":"<blockquote><p>Je suis juste <a href='x'>chill</a></p></blockquote>"}"#.utf8)
        let p = parseTweetOEmbed(json: json)
        #expect(p?.title == "Hughman" && p?.text == "Je suis juste chill")
    }
    @Test func previewOnlyForSafeLinks() {
        #expect(previewURL(for: Social(kind: "telegram", url: "https://t.me/grp")) != nil)
        #expect(previewURL(for: Social(kind: "twitter", url: "https://x.com/user")) == nil)
        #expect(previewURL(for: Social(kind: "twitter", url: "https://x.com/user/status/123"))?.host == "publish.twitter.com")
        #expect(previewURL(for: Social(kind: "website", url: "https://site.com")) == nil)
        #expect(previewURL(for: Social(kind: "telegram", url: "https://evil.com/t.me")) == nil)
    }
}

@Suite struct LossLimitTests {
    @Test func limitOffNeverBlocks() {
        let b = PaperBook(startCash: 100)
        #expect(!b.lossLimitHit(limitPct: 0, now: Date()))
    }
    @Test func blocksWhenDayLossReachesLimit() {
        var b = PaperBook(startCash: 100)
        b.cash = 85          // −15 $ depuis le départ, aucun point avant aujourd'hui
        #expect(b.lossLimitHit(limitPct: 10, now: Date()))
        #expect(!b.lossLimitHit(limitPct: 20, now: Date()))
    }
    @Test func baselineIsYesterdaysLastEquity() {
        var b = PaperBook(startCash: 100)
        let now = Date(), yesterday = now.addingTimeInterval(-86_400 * 1.5)
        b.equityCurve = [EquityPoint(at: yesterday, equity: 60)]
        b.cash = 58          // −40 $ depuis le départ, mais seulement −2 $ aujourd'hui
        #expect(!b.lossLimitHit(limitPct: 10, now: now))
    }
}

@Suite struct AutoExitTests {
    func book(entry: Double, last: Double) -> PaperBook {
        var b = PaperBook(startCash: 100)
        let t = PaperTrade(id: UUID(), mint: "M", symbol: "T", openedAt: Date(), seenMcap: entry, entryMcap: entry, stakeUSD: 10, share: 1, initialShare: 1,
                           costsUSD: 0, realizedUSD: 0, lastMcap: last, lastSeen: Date(), peakMcap: max(entry, last), entryReason: "test")
        b.trades = [t]
        return b
    }
    @Test func stopLossSellsOnDrop() {
        var b = book(entry: 100, last: 70)
        b.applyAutoExits(stopPct: 25, takeProfitPct: 0, now: Date())
        #expect(b.pending.count == 1 && b.pending[0].reason.contains("stop loss"))
    }
    @Test func takeProfitSellsOnRise() {
        var b = book(entry: 100, last: 160)
        b.applyAutoExits(stopPct: 0, takeProfitPct: 50, now: Date())
        #expect(b.pending.count == 1 && b.pending[0].reason.contains("prise de gain"))
    }
    @Test func offByDefaultAndNoDoubleOrder() {
        var b = book(entry: 100, last: 10)
        b.applyAutoExits(stopPct: 0, takeProfitPct: 0, now: Date())
        #expect(b.pending.isEmpty)
        b.applyAutoExits(stopPct: 25, takeProfitPct: 0, now: Date())
        b.applyAutoExits(stopPct: 25, takeProfitPct: 0, now: Date())
        #expect(b.pending.count == 1)
    }
}

@Suite struct ViewFilterTests {
    func item(_ m: Double?, sol: Double? = nil, age: Int? = nil) -> Feed.Item {
        var s = "{\"mint\":\"M\""
        if let m { s += ",\"market_cap\":\(m)" }
        if let sol { s += ",\"real_sol\":\(sol)" }
        if let age { s += ",\"age_s\":\(age)" }
        return try! JSONDecoder().decode(Feed.Item.self, from: Data((s + "}").utf8))
    }
    @Test func rangeKeepsInsideOnly() {
        let f = ViewFilter(minMcap: 20, maxMcap: 10_000)
        #expect(f.apply([item(5), item(500), item(20_000)]).map(\.marketCap) == [500])
    }
    @Test func unreadNeverPassesActiveFilter() {
        #expect(ViewFilter(minMcap: 1).apply([item(nil)]).isEmpty)
        #expect(ViewFilter().apply([item(nil)]).count == 1)
    }
    @Test func ageAndSol() {
        let f = ViewFilter(minSol: 3, maxAgeMin: 10)
        #expect(f.apply([item(1, sol: 5, age: 300), item(1, sol: 5, age: 900), item(1, sol: 1, age: 60)]).count == 1)
    }
}
