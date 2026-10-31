import Testing
import Foundation
@testable import SolHawkNotchCore

private final class Calls: @unchecked Sendable { var urls: [URL] = [] }
private struct Recorder: HTTPTransport {
    let body: String
    let calls = Calls()
    func get(_ url: URL, headers: [String: String]) async throws -> HTTPReply { calls.urls.append(url); return HTTPReply(status: 200, body: Data(body.utf8)) }
}

@Suite struct WalletFlowTests {
    let wallet = "9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM"
    let mint = "FfR4XdDPVrRmq7SFhkaH4srv54uFnNW2wfi83eNPpump"
    let base = URL(string: "https://example.test")!

    @Test func decodesEventsAndDropsBadRows() throws {
        let json = """
        {"status":"OK","wallets":1,"unread_wallets":0,"note":"ni une recommandation ni une preuve de qualité","events":[
          {"address":"\(wallet)","mint":"\(mint)","side":"BUY","signature":"s1","block_time":1700000000,"sol":1.5,"symbol":"SPM","image_url":"https://x/y.png"},
          {"address":"\(wallet)","mint":"\(mint)","side":"RECEIVED","signature":"s2"},
          {"address":"\(wallet)","mint":"pas-un-mint","side":"SELL"},
          {"address":"pas-une-adresse","mint":"\(mint)","side":"SELL"},
          {"nope":1},
          {"address":"\(wallet)","mint":"\(mint)","side":"SELL","signature":"s3"}]}
        """
        let r = try JSONDecoder().decode(WalletFlowReply.self, from: Data(json.utf8))
        #expect(r.events.map(\.signature) == ["s1", "s3"])
        #expect(r.events[0].isBuy && !r.events[1].isBuy)
        #expect(r.events[0].sol == 1.5 && r.events[1].sol == nil)   // montant manquant : « non lu », jamais inventé
        #expect(r.note?.contains("preuve de qualité") == true)
    }

    @Test func emptyReplyStillExplainsItself() throws {
        let r = try JSONDecoder().decode(WalletFlowReply.self, from: Data("{}".utf8))
        #expect(r.events.isEmpty && r.emptyText.contains("Aucun achat ni vente"))
        #expect(WalletFlowReply(status: "STARTING").emptyText.contains("Lecture en cours"))
        #expect(WalletFlowReply(status: "RPC_NOT_CONFIGURED").emptyText.contains("RPC"))
        #expect(WalletFlowReply(status: "OK", unreadWallets: 2).emptyText.contains("2 wallets pas encore lus"))
    }

    @Test func unavailableShowsTheShortServerReasonAndNothingElse() throws {
        let r = try JSONDecoder().decode(WalletFlowReply.self, from: Data(#"{"status":"UNAVAILABLE","error":"http:429 https://x?key=ABC"}"#.utf8))
        #expect(r.emptyText.contains("motif : http:429"))
        #expect(!r.emptyText.contains("://") && !r.emptyText.contains("key=") && !r.emptyText.contains(" "+"https"))
        #expect(WalletFlowReply(status: "UNAVAILABLE").emptyText.contains("source en panne)"))
    }

    @Test func eventOpensAsAFeedItemWithoutInventedNumbers() {
        let e = WalletFlowEvent(address: wallet, mint: mint, side: "BUY", symbol: "SPM", imageURL: "https://x/y.png")
        let it = Feed.Item(flow: e)
        #expect(it.mint == mint && it.symbol == "SPM" && it.imageURL == "https://x/y.png")
        #expect(it.marketCap == nil && it.realSol == nil && it.risk == nil)
    }

    @Test func routeIsAllowListedAndQueryCarriesOnlyValidPublicAddresses() async throws {
        #expect(FeedClient.allowedPaths.contains("/api/companion/wallet-flow"))
        let st = Recorder(body: #"{"events":[]}"#)
        let c = try FeedClient(baseURL: base, transport: st, tokenProvider: { "t" })
        _ = await c.fetchWalletFlow(addresses: [wallet, "pas une adresse", "<script>"])
        #expect(st.calls.urls.count == 1)
        #expect(st.calls.urls[0].path == "/api/companion/wallet-flow")
        #expect(st.calls.urls[0].query == "addresses=\(wallet)")
    }

    @Test func noValidAddressMeansNoRequest() async throws {
        let st = Recorder(body: "{}")
        let c = try FeedClient(baseURL: base, transport: st, tokenProvider: { "t" })
        let r = await c.fetchWalletFlow(addresses: ["x"])
        #expect(st.calls.urls.isEmpty)
        guard case .success(let reply) = r else { Issue.record("attendu succès"); return }
        #expect(reply.status == "NO_WALLETS")
    }

    @Test func neverMoreThanTwentyAddresses() async throws {
        let st = Recorder(body: "{}")
        let c = try FeedClient(baseURL: base, transport: st, tokenProvider: { "t" })
        _ = await c.fetchWalletFlow(addresses: Array(repeating: wallet, count: 30))
        #expect(st.calls.urls[0].query?.split(separator: ",").count == 20)
    }
}
