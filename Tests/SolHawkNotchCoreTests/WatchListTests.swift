import Testing
import Foundation
@testable import SolHawkNotchCore

@Suite struct WatchListTests {
    static func addr(_ n: Int) -> String { String(repeating: "A", count: 30) + String(format: "%02d", n % 100).replacingOccurrences(of: "0", with: "B") + "C" }

    @Test func importsLinesWithLabelsInSeveralFormats() {
        var l = WatchList()
        let a = Self.addr(1), b = Self.addr(2), c = Self.addr(3)
        let r = l.importText("\(a) Baleine\n\(b),Ami Zed\n  \n\(c)\tNoir; ok\ncoucou pas une adresse", group: .traders)
        #expect(r.added == 3 && r.invalid == 1)
        #expect(l.wallets.first { $0.address == a }?.label == "Baleine")
        #expect(l.wallets.first { $0.address == b }?.label == "Ami Zed")
        #expect(l.wallets.first { $0.address == c }?.label.hasPrefix("Noir") == true)
    }
    @Test func dedupesAndKeepsLimits() {
        var l = WatchList()
        _ = l.add(address: Self.addr(1), label: "x", group: .traders)
        #expect(l.add(address: Self.addr(1), label: "y", group: .devs).duplicates == 1)
        for i in 2..<60 { l.add(address: Self.addr(i) + String(repeating: "D", count: i % 3), label: "", group: .traders) }
        #expect(l.wallets(in: .traders).count <= 50)
        var d = WatchList()
        var over = 0
        for i in 0..<25 { over += d.add(address: String(repeating: "E", count: 30) + String(Array("ABCDEFGHJKLMNPQRSTUVWXYZ")[i % 24]) + String(i / 24 + 1) + "Q", label: "", group: .devs).overLimit }
        #expect(d.wallets(in: .devs).count == 20 && over == 5)
    }
    @Test func importsJSONAndRejectsGarbage() {
        var l = WatchList()
        let a = Self.addr(7), b = Self.addr(8)
        let r = l.importText("[\"\(a)\", {\"address\":\"\(b)\",\"name\":\"Zed\"}, \"nope\"]", group: .devs)
        #expect(r.added == 2 && l.wallets(in: .devs).count == 2)
        #expect(l.add(address: "<script>", label: "x", group: .traders).invalid == 1)
    }
    @Test func labelIsCleanedAndExportRoundTrips() {
        var l = WatchList()
        l.add(address: Self.addr(5), label: "  Très\u{0007}long \(String(repeating: "z", count: 60))", group: .traders)
        #expect(l.wallets[0].label.count <= 24 && !l.wallets[0].label.contains("\u{0007}"))
        var m = WatchList()
        m.importText(l.exportText(), group: .traders)
        #expect(m.wallets.count == 1 && m.wallets[0].address == l.wallets[0].address)
    }
    @Test func fileRoundTrip() {
        let f = WatchListFile(url: FileManager.default.temporaryDirectory.appendingPathComponent("wl-\(UUID().uuidString).json"))
        var l = WatchList(); l.add(address: Self.addr(9), label: "a", group: .traders)
        f.save(l)
        #expect(f.load() == l)
        try? FileManager.default.removeItem(at: f.url)
    }
}

@Suite struct WalletRecentClientTests {
    struct NoCall: HTTPTransport { func get(_ url: URL, headers: [String: String]) async throws -> HTTPReply { Issue.record("appel inattendu"); return HTTPReply(status: 500, body: Data()) } }
    struct Fixed: HTTPTransport {
        var seen: @Sendable (URL) -> Void
        func get(_ url: URL, headers: [String: String]) async throws -> HTTPReply {
            seen(url)
            return HTTPReply(status: 200, body: Data(#"{"activity":{"status":"OK","moves":[{"mint":"M","side":"BUY","block_time":5}],"tx_read":3}}"#.utf8))
        }
    }
    @Test func badAddressIsRefusedBeforeAnyCall() async {
        let c = try! FeedClient(baseURL: URL(string: "https://x.test")!, transport: NoCall(), tokenProvider: { "t" })
        #expect(await c.fetchWalletRecent(address: "../../admin") == .failure(.badResponse))
    }
    @Test func decodesMovesAndUsesAllowedPath() async {
        let addr = WatchListTests.addr(1)
        let box = LockedBox()
        let c = try! FeedClient(baseURL: URL(string: "https://x.test")!, transport: Fixed(seen: { box.set($0.path) }), tokenProvider: { "t" })
        let r = await c.fetchWalletRecent(address: addr)
        guard case .success(let v) = r else { Issue.record("échec"); return }
        #expect(v.activity?.moves?.first?.side == "BUY" && v.activity?.txRead == 3)
        #expect(box.value == "/api/companion/wallet-recent/\(addr)")
    }
}

final class LockedBox: @unchecked Sendable {
    private let l = NSLock(); private var v = ""
    var value: String { l.lock(); defer { l.unlock() }; return v }
    func set(_ s: String) { l.lock(); v = s; l.unlock() }
}
