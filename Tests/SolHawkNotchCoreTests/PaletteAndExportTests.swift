import Testing
import Foundation
@testable import SolHawkNotchCore

@Suite struct PaletteAndExportTests {
    let toks = [PaletteToken(mint: "DemoEyes11111111111111111111111111111111111", symbol: "EYES", name: "Pulse Eyes"),
                PaletteToken(mint: "DemoWave11111111111111111111111111111111111", symbol: "WAVE", name: "Wave")]

    @Test func emptyQueryListsPages() {
        let r = Palette.search("", tokens: toks)
        #expect(r.count == Palette.pages.count)
        #expect(r.allSatisfy { if case .page = $0.kind { return true } else { return false } })
    }
    @Test func findsTokenBySymbolAndAccents() {
        #expect(Palette.search("eye", tokens: toks).first?.id == "t:DemoEyes11111111111111111111111111111111111")
        #expect(Palette.search("RÉGLAGES", tokens: toks).first?.id == "p:settings")
    }
    @Test func pastedKnownMintOpensTokenUnknownOpensDex() {
        #expect(Palette.search(toks[0].mint, tokens: toks).first?.kind == .token(toks[0].mint))
        let unknown = "So11111111111111111111111111111111111111112"
        #expect(Palette.search(unknown, tokens: toks).first?.kind == .pastedMint(unknown))
    }
    @Test func garbageIsNotAMint() {
        #expect(Palette.search("0OIl" + String(repeating: "x", count: 40), tokens: toks).allSatisfy { if case .pastedMint = $0.kind { return false } else { return true } })
    }
    @Test func glossaryReachable() {
        #expect(Palette.search("glissement", tokens: toks).contains { $0.id == "g:Glissement" })
        #expect(Glossary.meaning(of: "stop") != nil)
    }
    @Test func hintsAndStreak() {
        #expect(Glossary.hint(for: "Pire baisse") != nil && Glossary.hint(for: "Positions ouvertes") == nil)
        func tr(_ pnl: Double, _ s: Double) -> PaperTrade {
            PaperTrade(id: UUID(), mint: "M", symbol: "S", openedAt: Date(timeIntervalSince1970: s), seenMcap: 1, entryMcap: 1, stakeUSD: 10, share: 0, initialShare: 1, costsUSD: 0, realizedUSD: 10 + pnl,
                       lastMcap: 1, lastSeen: Date(timeIntervalSince1970: s + 1), peakMcap: 1, closedAt: Date(timeIntervalSince1970: s + 1), exitMcap: 1, exitReason: "x", entryReason: "Clic")
        }
        #expect(longestLosingStreak([tr(-1, 1), tr(-1, 2), tr(2, 3), tr(-1, 4), tr(-1, 5), tr(-1, 6)]) == 3)
        #expect(longestLosingStreak([]) == 0)
    }
    @Test func csvEscapesAndNeutralizesFormulas() {
        var t = PaperTrade(id: UUID(), mint: "M", symbol: "=HYPERLINK(\"x\")", openedAt: Date(timeIntervalSince1970: 0), seenMcap: 100, entryMcap: 100, stakeUSD: 10, share: 0, initialShare: 1,
                           costsUSD: 0.4, realizedUSD: 9, lastMcap: 90, lastSeen: Date(timeIntervalSince1970: 60), peakMcap: 110, closedAt: Date(timeIntervalSince1970: 60), exitMcap: 90, exitReason: "Stop, \"-25 %\"", entryReason: "Clic")
        t.journal = "ligne1\nligne2"; t.tag = "FOMO"
        let csv = TradeExport.csv([("Moi", t)])
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: true)
        #expect(lines.count == 2)
        #expect(lines[1].contains("\"'=HYPERLINK(\"\"x\"\")\""))
        #expect(lines[1].contains("\"Stop, \"\"-25 %\"\"\""))
        #expect(lines[1].contains("ligne1 ligne2"))
    }
}

private let jt0 = Date(timeIntervalSince1970: 1_700_000_000)
private func at(_ s: Double) -> Date { jt0.addingTimeInterval(s) }
private let jgreen = Feed.Lights(mint: "green", freeze: "green", dev: "green", volume: "green", holders: "green")
private func item(_ mint: String, mcap: Double?) -> Feed.Item {
    Feed.Item(mint: mint, symbol: "TK", name: nil, ageS: 30, marketCap: mcap, realSol: 3, risk: Feed.Risk(score: 5, label: "faible"), lights: jgreen, series: nil, fromPeakPct: nil)
}
private func feed(_ items: [Feed.Item]) -> Feed { Feed(updatedAt: nil, stats: .init(), items: items, note: nil) }

@Suite @MainActor struct JournalTests {
    @Test func journalOnManualTradeSurvivesReloadAndRejectsUnknownTag() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("journal-\(UUID().uuidString)")
        let url = dir.appendingPathComponent("paper.json")
        let lab = PaperLab(fileURL: url, now: at(0))
        lab.buy(item("A", mcap: 10_000), now: at(0))
        lab.ingest(feed([item("A", mcap: 10_000)]), now: at(5))
        let id = try #require(lab.manual.open.first?.id)
        #expect(lab.setJournal(UUID(), note: "x", tag: nil) == false)
        #expect(lab.setJournal(id, note: "entré trop vite\u{7}", tag: "FOMO"))
        #expect(lab.manual.open.first?.journal == "entré trop vite" && lab.manual.open.first?.tag == "FOMO")
        #expect(lab.setJournal(id, note: "ok", tag: "pas une étiquette"))
        #expect(lab.manual.open.first?.tag == nil)
        let again = PaperLab(fileURL: url, now: at(9))
        #expect(again.manual.open.first?.journal == "ok")
        try? FileManager.default.removeItem(at: dir)
    }
    @Test func cleanBoundsText() {
        #expect(JournalTag.clean("a\u{7}b  ") == "ab")
        #expect(JournalTag.clean(String(repeating: "x", count: 900)).count == 500)
    }
}
