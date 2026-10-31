import Foundation
import Testing
@testable import SolHawkNotchCore

private let sampleJSON = """
{"updated_at":"2026-10-29T17:40:00.123456+00:00","observe_only":true,
 "stats":{"seen":51,"dropped":3,"listed":1,"watching":48,"profile":"wide","ghost":{"tracked":0},"drops":{"dev_spam":3},"blockers":{}},
 "items":[{"mint":"MintAAAA","symbol":"EYES","name":"Pulse Eyes","age_s":42,"market_cap":8200,"real_sol":5.2,
   "risk":{"score":12,"label":"faible","why":[]},
   "lights":{"mint":"green","freeze":"green","dev":"green","volume":"green","holders":"green"},"clones":[],"unknown_field":1}],
 "note":"Score de risque = heuristique non calibrée, pas une probabilité de rug."}
""".data(using: .utf8)!

private func item(lights: [String?], risk: String?) -> Feed.Item {
    let l = Feed.Lights(mint: lights[0], freeze: lights[1], dev: lights[2], volume: lights[3], holders: lights[4])
    return Feed.Item(mint: "M", symbol: nil, name: nil, ageS: nil, marketCap: nil, realSol: nil, risk: Feed.Risk(score: nil, label: risk), lights: l)
}

private struct Stub: HTTPTransport {
    var reply: Result<HTTPReply, any Error>
    final class Box: @unchecked Sendable { var calls: [(URL, [String: String])] = [] }
    let box = Box()
    func get(_ url: URL, headers: [String: String]) async throws -> HTTPReply { box.calls.append((url, headers)); return try reply.get() }
}
private struct Boom: Error, CustomStringConvertible { var description: String { "https://secret-host/leak?token=ABC" } }

@Suite struct DecodingTests {
    @Test func decodesRealShapeAndIgnoresUnknownFields() throws {
        let f = try JSONDecoder().decode(Feed.self, from: sampleJSON)
        #expect(f.stats.listed == 1 && f.stats.profile == "wide" && f.items.count == 1)
        #expect(f.items[0].risk?.label == "faible" && f.updatedAt != nil && f.note?.contains("non calibrée") == true)
    }
    @Test func missingFieldsStayNil() throws {
        let f = try JSONDecoder().decode(Feed.self, from: Data("{}".utf8))
        #expect(f.items.isEmpty && f.stats.listed == nil && f.updatedAt == nil)
    }
}

@Suite struct VerdictTests {
    @Test func onlyAllGreenAndLowRiskPasses() {
        let g = Array(repeating: Optional("green"), count: 5)
        #expect(status(of: item(lights: g, risk: "faible")) == .passesFilters)
        #expect(status(of: item(lights: g, risk: "moyen")) == .toCheck)
        #expect(status(of: item(lights: g, risk: nil)) == .toCheck)
        #expect(status(of: item(lights: ["green", "green", "green", "green", "orange"], risk: "faible")) == .toCheck)
        #expect(status(of: item(lights: ["green", "green", nil, "green", "green"], risk: "faible")) == .toCheck)
    }
}

@Suite struct MoodTests {
    let now = Date(timeIntervalSince1970: 1_000_000)
    func feed(age: Double, listed: Int = 0) -> Feed { Feed(updatedAt: now.addingTimeInterval(-age), stats: .init(listed: listed), items: [], note: nil) }
    @Test func waitingWithoutData() { #expect(mood(.init(feed: nil, feedReceivedAt: nil, newItems: [], lastError: nil, now: now)) == .waiting) }
    @Test func zeroListedIsCalmNotAnAllClear() {
        #expect(mood(.init(feed: feed(age: 2), feedReceivedAt: now, newItems: [], lastError: nil, now: now)) == .calm(listed: 0))
    }
    @Test func staleWhenServerFeedIsOld() {
        #expect(mood(.init(feed: feed(age: 300), feedReceivedAt: now, newItems: [], lastError: nil, now: now)) == .stale(ageS: 300))
    }
    @Test func spottedGreenOnlyIfPassesFilters() {
        let g = Array(repeating: Optional("green"), count: 5)
        let ok = item(lights: g, risk: "faible"), bad = item(lights: ["green", "green", "green", "green", "orange"], risk: "faible")
        #expect(mood(.init(feed: feed(age: 1), feedReceivedAt: now, newItems: [ok], lastError: nil, now: now)) == .spotted(passes: true))
        #expect(mood(.init(feed: feed(age: 1), feedReceivedAt: now, newItems: [bad], lastError: nil, now: now)) == .spotted(passes: false))
    }
    @Test func errorsMapToStates() {
        #expect(mood(.init(feed: nil, feedReceivedAt: nil, newItems: [], lastError: .unauthorized, now: now)) == .tokenRejected)
        #expect(mood(.init(feed: nil, feedReceivedAt: nil, newItems: [], lastError: .rateLimited(retryS: 30), now: now)) == .rateLimited(retryS: 30))
        #expect(mood(.init(feed: nil, feedReceivedAt: nil, newItems: [], lastError: .network("x"), now: now)) == .offline)
        // une erreur ponctuelle avec des données encore fraîches ne bascule pas en « hors ligne »
        #expect(mood(.init(feed: feed(age: 2), feedReceivedAt: now.addingTimeInterval(-5), newItems: [], lastError: .server(500), now: now)) == .calm(listed: 0))
    }
}

@Suite struct ClientTests {
    let base = URL(string: "https://example.test")!
    @Test func refusesInsecureRemoteButAllowsLocalHTTP() throws {
        #expect(throws: ConfigError.insecureURL) { try FeedClient(baseURL: URL(string: "http://192.0.2.1")!, transport: Stub(reply: .failure(Boom())), tokenProvider: { "t" }) }
        _ = try FeedClient(baseURL: URL(string: "http://127.0.0.1:8788")!, transport: Stub(reply: .failure(Boom())), tokenProvider: { "t" })
    }
    @Test func sendsTokenHeaderOnAllowedPathOnly() async throws {
        let st = Stub(reply: .success(HTTPReply(status: 200, body: sampleJSON)))
        let c = try FeedClient(baseURL: base, transport: st, tokenProvider: { "tok" })
        let r = await c.fetchFeed()
        guard case .success(let f) = r else { Issue.record("attendu succès"); return }
        #expect(f.items.count == 1 && st.box.calls.count == 1)
        #expect(st.box.calls[0].0.path == "/api/companion/feed" && st.box.calls[0].1["X-SolHawk-Token"] == "tok")
    }
    @Test func noTokenMeansNoRequest() async throws {
        let st = Stub(reply: .success(HTTPReply(status: 200, body: sampleJSON)))
        let c = try FeedClient(baseURL: base, transport: st, tokenProvider: { nil })
        let r = await c.fetchFeed()
        #expect(r == .failure(.unauthorized) && st.box.calls.isEmpty)
    }
    @Test func statusMapping() async throws {
        func run(_ s: Int, _ body: String = "{}") async throws -> Result<Feed, FetchFailure> {
            try await FeedClient(baseURL: base, transport: Stub(reply: .success(HTTPReply(status: s, body: Data(body.utf8)))), tokenProvider: { "t" }).fetchFeed()
        }
        let r401 = try await run(401), r403 = try await run(403), r429 = try await run(429, "{\"retry_after_s\":42}")
        let r502 = try await run(502), rBad = try await run(200, "pas du json")
        #expect(r401 == .failure(.unauthorized) && r403 == .failure(.unauthorized))
        #expect(r429 == .failure(.rateLimited(retryS: 42)))
        #expect(r502 == .failure(.server(502)))
        #expect(rBad == .failure(.badResponse))
    }
    @Test func networkErrorNeverLeaksDetails() async throws {
        let c = try FeedClient(baseURL: base, transport: Stub(reply: .failure(Boom())), tokenProvider: { "t" })
        guard case .failure(.network(let m)) = await c.fetchFeed() else { Issue.record("attendu .network"); return }
        #expect(!m.contains("secret") && !m.contains("ABC"))
    }
}

@Suite struct PollPolicyTests {
    @Test func backoffGrowsAndResets() {
        var p = PollPolicy()
        #expect(p.nextDelayS == 5)
        p.record(.failure(.network("x"))); #expect(p.nextDelayS == 10)
        p.record(.failure(.server(500))); #expect(p.nextDelayS == 20)
        for _ in 0..<20 { p.record(.failure(.network("x"))) }
        #expect(p.nextDelayS == 120)
        p.record(.success(())); #expect(p.nextDelayS == 5)
    }
    @Test func stopsAtFirst401UntilResumed() {
        var p = PollPolicy()
        p.record(.failure(.unauthorized))
        #expect(p.nextDelayS == nil)
        p.record(.success(())); #expect(p.nextDelayS == nil)   // un succès parasite ne relance pas
        p.resume(); #expect(p.nextDelayS == 5)
    }
    @Test func honorsRetryAfter() {
        var p = PollPolicy()
        p.record(.failure(.rateLimited(retryS: 30)))
        #expect(p.nextDelayS == 31)
    }
}

@Suite struct TrackerTests {
    let t0 = Date(timeIntervalSince1970: 2_000_000)
    func feed(_ mints: [String]) -> Feed {
        Feed(updatedAt: t0, stats: .init(), items: mints.map { Feed.Item(mint: $0, symbol: nil, name: nil, ageS: nil, marketCap: nil, realSol: nil, risk: nil, lights: nil) }, note: nil)
    }
    @Test func firstReadingIsBaselineNotAnAlert() {
        var tr = FeedTracker(); tr.ingest(feed(["A", "B"]), now: t0)
        #expect(tr.activeSpotted(now: t0).isEmpty)
    }
    @Test func newMintIsSpottedThenExpires() {
        var tr = FeedTracker(); tr.ingest(feed(["A"]), now: t0)
        tr.ingest(feed(["A", "B"]), now: t0.addingTimeInterval(5))
        #expect(tr.activeSpotted(now: t0.addingTimeInterval(6)).map(\.mint) == ["B"])
        #expect(tr.activeSpotted(now: t0.addingTimeInterval(40)).isEmpty)
    }
    @Test func sameMintIsNotSpottedTwice() {
        var tr = FeedTracker(); tr.ingest(feed([]), now: t0)
        tr.ingest(feed(["A"]), now: t0.addingTimeInterval(1))
        tr.ingest(feed(["A"]), now: t0.addingTimeInterval(30))
        #expect(tr.activeSpotted(now: t0.addingTimeInterval(31)).isEmpty)
    }
    @Test func zeroListedWordingIsNotAnAllClear() {
        #expect(describe(.calm(listed: 0)).contains("pas un feu vert"))
        #expect(!describe(.spotted(passes: true)).lowercased().contains("sûr"))
        #expect(describe(.spotted(passes: true)).contains("aucune garantie"))
    }
}

@Suite @MainActor struct StoreTests {
    final class Seq: HTTPTransport, @unchecked Sendable {
        var replies: [HTTPReply]; var calls = 0
        init(_ r: [HTTPReply]) { replies = r }
        func get(_ url: URL, headers: [String: String]) async throws -> HTTPReply { defer { calls += 1 }; return replies[min(calls, replies.count - 1)] }
    }
    @Test func stopsPollingAfterUnauthorizedAndResumesOnConfigChange() async throws {
        let tr = Seq([HTTPReply(status: 401, body: Data())])
        let store = FeedStore(makeClient: { try FeedClient(baseURL: URL(string: "http://127.0.0.1:1")!, transport: tr, tokenProvider: { "t" }) })
        await store.pollOnce()
        #expect(store.lastError == .unauthorized)
        #expect(store.mood(now: Date()) == .tokenRejected)
    }
    @Test func successFillsFeedAndClearsError() async throws {
        let body = Data(#"{"stats":{"listed":0},"items":[]}"#.utf8)
        let tr = Seq([HTTPReply(status: 200, body: body)])
        let store = FeedStore(makeClient: { try FeedClient(baseURL: URL(string: "http://127.0.0.1:1")!, transport: tr, tokenProvider: { "t" }) })
        await store.pollOnce()
        #expect(store.lastError == nil && store.feed?.stats.listed == 0 && store.receivedAt != nil)
    }
}

@Suite struct SafetyTests {
    @Test func mintValidationRejectsJunk() {
        #expect(isValidMint("4BtX4R6UPwnRKd4onN5CngW9CeCSmEZEFUdyN1nbbRKB"))
        #expect(!isValidMint("short"))
        #expect(!isValidMint("0OIl" + String(repeating: "a", count: 40)))   // 0, O, I, l ne sont pas en base58
        #expect(!isValidMint("https://evil.example/" + String(repeating: "a", count: 20)))
        #expect(dexScreenerURL(mint: "x y") == nil)
        #expect(dexScreenerURL(mint: "4BtX4R6UPwnRKd4onN5CngW9CeCSmEZEFUdyN1nbbRKB")?.host == "dexscreener.com")
    }
    @Test func labelsAreBoundedAndCleaned() {
        #expect(safeLabel(nil) == "non lu" && safeLabel("") == "non lu")
        #expect(safeLabel("A\nB\u{0007}C") == "ABC")
        #expect(safeLabel(String(repeating: "x", count: 50)).count == 12)
    }
    @Test func decodesServerHealth() throws {
        let j = #"{"stats":{"drops":{"dev_spam":4},"rpc":{"ok":20,"errors":0,"no_rpc":0,"last_error":null},"ghost":{"tracked":7,"no_price":0}},"items":[]}"#
        let f = try JSONDecoder().decode(Feed.self, from: Data(j.utf8))
        #expect(f.stats.drops?["dev_spam"] == 4 && f.stats.rpc?.ok == 20 && f.stats.ghost?.tracked == 7)
    }
}



@Suite("Série réelle et formats")
struct SeriesTests {
    @Test func cleanSeriesDropsGarbageAndSorts() {
        let raw: [[Double]] = [[30, 6000], [4, 5000], [10], [20, -1], [Double.nan, 5], [15, 5500]]
        let pts = cleanSeries(raw)
        #expect(pts.map(\.ageS) == [4, 15, 30])
        #expect(pts.map(\.marketCap) == [5000, 5500, 6000])
    }
    @Test func emptyOrMissingMeansNoHistory() {
        #expect(cleanSeries(nil).isEmpty)
        #expect(cleanSeries([]).isEmpty)
        #expect(seriesChangePct(cleanSeries([[4, 5000]])) == nil)
    }
    @Test func changePct() {
        let pts = cleanSeries([[4, 5000], [30, 6000]])
        #expect(abs((seriesChangePct(pts) ?? 0) - 20) < 0.001)
    }
    @Test func boundedLength() {
        let raw = (0..<400).map { [Double($0), 1000 + Double($0)] }
        #expect(cleanSeries(raw).count == 60)
    }
    @Test func formatUSD() {
        #expect(SolHawkNotchCore.formatUSD(850) == "$850")
        #expect(SolHawkNotchCore.formatUSD(8200) == "$8,2 k")
        #expect(SolHawkNotchCore.formatUSD(1_300_000) == "$1,3 M")
        #expect(SolHawkNotchCore.formatUSD(.nan) == "non lu")
    }
    @Test func itemDecodesSeries() throws {
        let json = #"{"mint":"M","series":[[4,5000],[15,5500]]}"#.data(using: .utf8)!
        let it = try JSONDecoder().decode(Feed.Item.self, from: json)
        #expect(cleanSeries(it.series).count == 2)
    }
}


@Suite("Signal de la barre et visite")
struct SignalTests {
    static let green: [String?] = Array(repeating: "green", count: 5)
    func item(_ mint: String, age: Int? = 30, lights: [String?]? = SignalTests.green, risk: String? = "faible", peak: Double? = nil) -> Feed.Item {
        Feed.Item(mint: mint, symbol: nil, name: nil, ageS: age, marketCap: nil, realSol: nil,
                  risk: Feed.Risk(score: nil, label: risk), lights: lights.map { Feed.Lights(mint: $0[0], freeze: $0[1], dev: $0[2], volume: $0[3], holders: $0[4]) },
                  series: nil, fromPeakPct: peak)
    }
    func feed(_ items: [Feed.Item]) -> Feed { Feed(updatedAt: nil, stats: Feed.Stats(), items: items, note: nil) }

    @Test func greenWhenPassesFilters() {
        let r = barSignal(feed: feed([item("A")]), mood: .calm(listed: 1))
        #expect(r.signal == .green && r.mint == "A")
    }
    @Test func yellowWhenToCheck() {
        let r = barSignal(feed: feed([item("B", risk: "moyen")]), mood: .calm(listed: 1))
        #expect(r.signal == .yellow && r.mint == "B")
    }
    @Test func redOnBigDropBeatsGreen() {
        let r = barSignal(feed: feed([item("A"), item("C", peak: -55)]), mood: .calm(listed: 2))
        #expect(r.signal == .red && r.mint == "C")
    }
    @Test func redOnOutageWithoutToken() {
        #expect(barSignal(feed: nil, mood: .offline) == (.red, nil))
        #expect(barSignal(feed: nil, mood: .tokenRejected).signal == .red)
    }
    @Test func oldOrUnreadTokensDoNotLight() {
        #expect(barSignal(feed: feed([item("D", age: 4000)]), mood: .calm(listed: 1)).signal == .none)
        #expect(barSignal(feed: feed([item("E", age: nil)]), mood: .calm(listed: 1)).signal == .none)
        #expect(barSignal(feed: feed([]), mood: .calm(listed: 0)).signal == .none)
        #expect(barSignal(feed: nil, mood: .waiting).signal == .none)
    }
    @Test func unknownLightIsNeverGreen() {
        let r = barSignal(feed: feed([item("F", lights: ["green", "green", nil, "green", "green"])]), mood: .calm(listed: 1))
        #expect(r.signal == .yellow)
    }
    @Test func tourHasNoPromisesAndIsShort() {
        #expect(tourSteps.count == 6)
        for s in tourSteps { #expect(!s.text.lowercased().contains("garanti")); #expect(s.text.count < 260) }
    }
}




@Suite("Alertes")
struct AlertTests {
    static let g: [String?] = Array(repeating: "green", count: 5)
    func it(_ m: String, peak: Double? = nil) -> Feed.Item {
        Feed.Item(mint: m, symbol: "T\(m)", name: nil, ageS: 20, marketCap: 8200, realSol: nil, risk: Feed.Risk(score: nil, label: "faible"),
                  lights: Feed.Lights(mint: "green", freeze: "green", dev: "green", volume: "green", holders: "green"), series: nil, fromPeakPct: peak)
    }
    func feed(_ i: [Feed.Item]) -> Feed { Feed(updatedAt: nil, stats: Feed.Stats(), items: i, note: nil) }

    @Test func firstFeedDoesNotAlertButNewTokenDoes() {
        var e = AlertEngine()
        #expect(e.evaluate(feed: feed([it("A")]), mood: .calm(listed: 1)).isEmpty)
        let r = e.evaluate(feed: feed([it("A"), it("B")]), mood: .calm(listed: 2))
        #expect(r.count == 1 && r[0].kind == .green && r[0].mint == "B")
        #expect(e.evaluate(feed: feed([it("A"), it("B")]), mood: .calm(listed: 2)).isEmpty)   // pas deux fois
    }
    @Test func dropAlertsOnce() {
        var e = AlertEngine()
        _ = e.evaluate(feed: feed([it("A")]), mood: .calm(listed: 1))
        #expect(e.evaluate(feed: feed([it("A", peak: -50)]), mood: .calm(listed: 1)).first?.kind == .red)
        #expect(e.evaluate(feed: feed([it("A", peak: -60)]), mood: .calm(listed: 1)).isEmpty)
    }
    @Test func outageAlertsOncePerOutage() {
        var e = AlertEngine()
        #expect(e.evaluate(feed: nil, mood: .offline).count == 1)
        #expect(e.evaluate(feed: nil, mood: .offline).isEmpty)
        _ = e.evaluate(feed: feed([]), mood: .calm(listed: 0))
        #expect(e.evaluate(feed: nil, mood: .offline).count == 1)
    }
    @Test func wordingHasNoAdvice() {
        var e = AlertEngine()
        _ = e.evaluate(feed: feed([]), mood: .calm(listed: 0))
        let a = e.evaluate(feed: feed([it("Z")]), mood: .calm(listed: 1)).first!
        #expect(!(a.title + a.body).lowercased().contains("achète"))
        #expect(a.body.contains("pas") )
    }
    @Test func everyDropKeyExplained() {
        for k in ["dev_spam", "no_traction", "authority_active", "dumped", "no_image", "risk_high"] { #expect(!dropExplain(k).hasPrefix("Motif reçu")) }
        #expect(dropExplain("bidule").hasPrefix("Motif reçu"))
    }
}


@Suite("Adresse refusée")
struct BadConfigTests {
    @Test func configurationFailureIsItsOwnState() {
        let m = mood(MoodInput(feed: nil, feedReceivedAt: nil, newItems: [], lastError: .network("configuration"), now: Date()))
        #expect(m == .badConfig)
        #expect(describe(m).contains("HTTPS"))
        #expect(barSignal(feed: nil, mood: m).signal == .red)
    }
    @Test func plainNetworkErrorStaysOffline() {
        let m = mood(MoodInput(feed: nil, feedReceivedAt: nil, newItems: [], lastError: .network("timeout"), now: Date()))
        #expect(m == .offline)
    }
}
