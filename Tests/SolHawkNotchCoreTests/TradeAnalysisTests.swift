import Testing
import Foundation
@testable import SolHawkNotchCore

@Suite struct TradeAnalysisTests {
    static let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    static func trade(entry: Double = 10_000, exit: Double, peak: Double? = nil, reason: String = "vente manuelle", hold: Double = 120,
                      stake: Double = 10, costs: Double = 0.3, strategy: String = "Perso") -> PaperTrade {
        let proceeds = stake * exit / entry
        return PaperTrade(id: UUID(), mint: "M", symbol: "TOK", openedAt: t0, seenMcap: entry, entryMcap: entry, stakeUSD: stake,
                          share: 0, initialShare: 1, costsUSD: costs, realizedUSD: proceeds, lastMcap: exit, lastSeen: t0.addingTimeInterval(hold),
                          peakMcap: peak ?? max(entry, exit), tookPartial: false, closedAt: t0.addingTimeInterval(hold), exitMcap: exit,
                          exitReason: reason, entryReason: strategy)
    }

    @Test func gaveBackGainsIsDetected() {
        let d = diagnose(Self.trade(exit: 8_000, peak: 25_000))
        #expect(d.cause == .gaveBack && d.pnlUSD < 0)
        #expect(d.headline.contains("×2,5"))
    }

    @Test func lateEntryUsesThePriceBefore() {
        let before = [PricePoint(t: 0, mcap: 4_000), PricePoint(t: 30, mcap: 9_000)]
        let d = diagnose(Self.trade(exit: 8_000), before: before)
        #expect(d.cause == .lateEntry)
    }

    @Test func vanishedTokenComesFirst() {
        let d = diagnose(Self.trade(exit: 4_000, peak: 20_000, reason: "plus de prix : sortie supposée à −50 %"))
        #expect(d.cause == .vanished && d.also.contains(.gaveBack))
    }

    @Test func winnersAreNotBlamed() {
        let d = diagnose(Self.trade(exit: 15_000, peak: 16_000))
        #expect(d.cause == .none)
    }

    @Test func historyFindsTheWorstAndCountsPatterns() {
        let trades = [
            Self.trade(exit: 8_000, peak: 25_000),
            Self.trade(exit: 7_000, reason: "stop loss −25 %"),
            Self.trade(exit: 14_000, reason: "prise de gain +40 %"),
        ]
        let h = diagnoseHistory(trades)
        #expect(h.closedCount == 3 && !h.enoughData)
        #expect(h.worst.count == 2 && h.worst[0].pnlUSD <= h.worst[1].pnlUSD)
        #expect(h.patterns.contains { $0.contains("dépassé ×1,5") })
        #expect(Set(h.exits.map(\.name)).isSuperset(of: ["Stop", "Prise de gain"]))
        #expect(h.exits.reduce(0) { $0 + $1.count } == 3)
    }

    @Test func chartNotesMarkEntryPeakExitAndOutflow() {
        let base = Self.t0.timeIntervalSince1970
        let candles = [
            Candle(t: base, o: 10_000, h: 10_500, l: 9_900, c: 10_400, flowSol: 1),
            Candle(t: base + 30, o: 10_400, h: 25_000, l: 10_300, c: 24_000, flowSol: 6),
            Candle(t: base + 60, o: 24_000, h: 24_100, l: 15_000, c: 15_500, flowSol: -4.2),
            Candle(t: base + 90, o: 15_500, h: 15_800, l: 8_000, c: 8_200, flowSol: -1.5),
        ]
        let notes = chartNotes(for: Self.trade(exit: 8_000, peak: 25_000, hold: 90), candles: candles)
        let kinds = Set(notes.map(\.kind))
        #expect(kinds == [.entry, .peak, .exit, .giveBack, .outflow])
        #expect(notes.first(where: { $0.kind == .outflow })?.label.contains("4,2") == true)
        #expect(notes.map(\.time) == notes.map(\.time).sorted())
    }

    @Test func noFlowNoOutflowNote() {
        let base = Self.t0.timeIntervalSince1970
        let candles = [Candle(t: base, o: 10_000, h: 25_000, l: 9_900, c: 24_000), Candle(t: base + 60, o: 24_000, h: 24_000, l: 8_000, c: 8_200)]
        let notes = chartNotes(for: Self.trade(exit: 8_000, peak: 25_000, hold: 60), candles: candles)
        #expect(!notes.contains { $0.kind == .outflow })
    }
}
