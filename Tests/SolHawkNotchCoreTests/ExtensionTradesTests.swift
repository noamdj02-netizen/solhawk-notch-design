import Testing
import Foundation
@testable import SolHawkNotchCore

private final class Calls: @unchecked Sendable { var urls: [URL] = []; var methods: [String] = [] }
private struct Recorder: HTTPTransport {
    let body: String
    let calls = Calls()
    func get(_ url: URL, headers: [String: String]) async throws -> HTTPReply { calls.urls.append(url); return HTTPReply(status: 200, body: Data(body.utf8)) }
}

@Suite struct ExtensionTradesTests {
    let m1 = "FfR4XdDPVrRmq7SFhkaH4srv54uFnNW2wfi83eNPpump"
    let m2 = "DzGipWA2czLAmsFaTc7HdJYwvDvvHLTJ9tqkpbBGpmbW"
    let base = URL(string: "https://example.test")!

    func decode(_ json: String) throws -> PaperSyncReply { try JSONDecoder().decode(PaperSyncReply.self, from: Data(json.utf8)) }

    @Test func decodesRowsNewestFirstAndDropsBadOnes() throws {
        let r = try decode("""
        {"note":"SIMULATION","trades":[
          {"t":1760000000000,"side":"buy","mint":"\(m1)","symbol":"AAA","sol":1,"mc":50000,"slipPct":0.6,"costSol":0.02},
          {"t":1760000060000,"side":"sell","mint":"\(m1)","symbol":"AAA","sol":1.5,"mc":80000,"costSol":0.03,"realizedSol":0.48},
          {"t":1760000070000,"side":"short","mint":"\(m1)","sol":1,"mc":1,"costSol":0},
          {"t":1760000080000,"side":"buy","mint":"pas-un-mint","sol":1,"mc":1,"costSol":0},
          {"t":1760000090000,"side":"buy","mint":"\(m2)","sol":1,"mc":0,"costSol":0},
          {"t":1760000100000,"side":"buy","mint":"\(m2)","sol":-3,"mc":5,"costSol":0},
          {"nope":1}]}
        """)
        #expect(r.trades.map(\.side) == ["sell", "buy"])           // plus récent d'abord ; côté inconnu, mint faux, prix nul, montant négatif : écartés
        #expect(r.trades[0].realizedSol == 0.48 && r.trades[1].realizedSol == nil)
        #expect(r.note == "SIMULATION" && r.snapshot == nil)
    }

    @Test func summaryCountsRealizedGainCostsAndWins() throws {
        let r = try decode("""
        {"trades":[
          {"t":1760000000000,"side":"buy","mint":"\(m1)","sol":1,"mc":50000,"costSol":0.02},
          {"t":1760000010000,"side":"sell","mint":"\(m1)","sol":0.4,"mc":20000,"costSol":0.03,"realizedSol":-0.6},
          {"t":1760000020000,"side":"buy","mint":"\(m2)","sol":1,"mc":50000,"costSol":0.02},
          {"t":1760000030000,"side":"sell","mint":"\(m2)","sol":1.5,"mc":80000,"costSol":0.03,"realizedSol":0.5}]}
        """)
        let s = r.summary
        #expect(s.buys == 2 && s.sells == 2 && s.wins == 1)
        #expect(abs(s.realizedSol - (-0.1)) < 1e-9 && abs(s.costsSol - 0.1) < 1e-9)
        #expect(s.winRate == 50)
    }

    @Test func tradesAreCappedAndPositionsAreCapped() throws {
        let rows = (0..<600).map { #"{"t":\#(1760000000000 + $0),"side":"buy","mint":"\#(m1)","sol":1,"mc":1000,"costSol":0}"# }.joined(separator: ",")
        let pos = (0..<30).map { _ in #"{"mint":"\#(m2)","basisSol":1,"units":1}"# }.joined(separator: ",")
        let r = try decode(#"{"trades":[\#(rows)],"snapshot":{"positions":[\#(pos)],"balance":9,"startSol":10}}"#)
        #expect(r.trades.count == ExtensionLimits.maxTrades && r.trades[0].t == 1760000000599)
        #expect(r.snapshot?.positions.count == ExtensionLimits.maxPositions)
    }

    @Test func snapshotNeedsSaneNumbersAndValidMints() throws {
        let ok = try decode(#"{"snapshot":{"positions":[{"mint":"\#(m1)","symbol":"AAA","basisSol":1,"units":0.00002,"openedAt":1760000000000},{"mint":"zz","basisSol":1,"units":1}],"balance":9,"startSol":10,"costsPaid":0.02}}"#)
        #expect(ok.snapshot?.positions.map(\.mint) == [m1] && ok.snapshot?.balance == 9)
        #expect(try decode(#"{"snapshot":{"positions":[],"balance":9,"startSol":0}}"#).snapshot == nil)   // départ nul : snapshot ignoré
        #expect(try decode(#"{"snapshot":"x","trades":"y"}"#).isEmpty)
        #expect(try decode("{}").isEmpty)
    }

    @Test func openPositionValueIsUnreadWithoutAPriceNeverInvented() {
        let p = ExtensionPosition(mint: m1, symbol: "AAA", basisSol: 1, units: 0.00002)
        #expect(p.grossValueSol(mc: nil) == nil && p.grossValueSol(mc: 0) == nil && p.grossValueSol(mc: .nan) == nil && p.grossValueSol(mc: -5) == nil)
        #expect(abs((p.grossValueSol(mc: 100_000) ?? 0) - 2) < 1e-9)
    }

    @Test func routeIsAllowListedGetOnlyAndNameIsNotATradingRoute() async throws {
        let path = "/api/companion/paper-sync"
        #expect(FeedClient.allowedPaths.contains(path))
        for bad in ["buy", "sell", "trade", "sign", "key"] { #expect(!path.split(separator: "/").contains(Substring(bad))) }
        let st = Recorder(body: #"{"trades":[]}"#)
        let c = try FeedClient(baseURL: base, transport: st, tokenProvider: { "t" })
        let r = await c.fetchPaperSync()
        guard case .success(let reply) = r else { Issue.record("lecture attendue"); return }
        #expect(reply.isEmpty && st.calls.urls.map(\.path) == [path] && st.calls.urls[0].query == nil)
    }

    @Test func symbolsGoThroughSafeLabel() {
        let t = ExtensionTrade(t: 1, side: "buy", mint: m1, symbol: "A\u{202E}BCDEFGHIJKLMNOPQRSTUV", sol: 1, mc: 1)
        let shown = safeLabel(t.symbol)
        #expect(shown.count <= 12 && !shown.contains("\u{202E}"))
    }
}
