import Testing
import Foundation
@testable import SolHawkNotchCore

@Suite struct DrySummaryTests {
    @Test func explainsWhyNothingIsListed() {
        let s = Feed.Stats(seen: 90, dropped: 66, listed: 0, watching: 24, drops: ["dev_spam": 62, "dumped": 2, "no_concentration": 2])
        let line = Feed.drySummary(s)
        #expect(line == "90 vus · 66 écartés · 24 surveillés — surtout : 62 dev qui lance trop de tokens, 2 déjà en chute, 2 détenteurs non lus")
    }

    @Test func unknownReasonIsShownAsIs() {
        let s = Feed.Stats(seen: 3, dropped: 3, drops: ["nouvelle_porte": 3])
        #expect(Feed.drySummary(s)?.contains("3 nouvelle porte") == true)
    }

    @Test func nothingReadMeansNoSentence() {
        #expect(Feed.drySummary(Feed.Stats()) == nil)
        #expect(Feed.drySummary(Feed.Stats(seen: 0)) == nil)
    }
}

@Suite struct DroppedDecodingTests {
    @Test func decodesReasonAndLastCheckAndSkipsBadRows() throws {
        let m = "FfR4XdDPVrRmq7SFhkaH4srv54uFnNW2wfi83eNPpump"
        let json = """
        {"items":[{"mint":"\(m)","symbol":"SPM","tier":"gate:dev_spam","market_cap":6200,"checkpoints":{"5m":-12.5,"15m":null,"60m":40}},
                  {"mint":"pas-un-mint","symbol":"BAD"},{"nope":1}],"observe_only":true}
        """
        let r = try JSONDecoder().decode(DroppedReply.self, from: Data(json.utf8))
        #expect(r.items.count == 1)
        #expect(r.items[0].reason == "dev qui lance trop de tokens")
        #expect(r.items[0].lastCheck?.label == "60 min" && r.items[0].lastCheck?.pct == 40)
    }

    @Test func notMeasuredYetIsNotInvented() throws {
        let m = "FfR4XdDPVrRmq7SFhkaH4srv54uFnNW2wfi83eNPpump"
        let r = try JSONDecoder().decode(DroppedReply.self, from: Data(#"{"items":[{"mint":"\#(m)","checkpoints":{}}]}"#.utf8))
        #expect(r.items[0].lastCheck == nil && r.items[0].reason == nil)
    }

    @Test func routeIsAllowListed() {
        #expect(FeedClient.allowedPaths.contains("/api/companion/dropped"))
    }
}

@Suite struct DroppedOpensLikeAnyTokenTests {
    @Test func droppedBecomesAnItemWithItsImages() {
        let m = "FfR4XdDPVrRmq7SFhkaH4srv54uFnNW2wfi83eNPpump"
        let d = DroppedToken(mint: m, symbol: "SPM", imageURL: nil, imageAlts: ["https://images.pump.fun/coin-image/\(m)?imageSize=128x128"], marketCap: 6200)
        let it = Feed.Item(dropped: d)
        #expect(it.mint == m && it.symbol == "SPM" && it.marketCap == 6200)
        #expect(imageCandidates(it).count == 1)   // sans image déclarée, le repli reste utilisable
    }

    @Test func noImageAtAllStillGivesAnItem() {
        let it = Feed.Item(dropped: DroppedToken(mint: "FfR4XdDPVrRmq7SFhkaH4srv54uFnNW2wfi83eNPpump"))
        #expect(imageCandidates(it).isEmpty && avatarInitial(it.symbol) == "?")
    }
}

@Suite struct ChartWaitMessageTests {
    @Test func failureIsNeverShownAsLoading() {
        for f in [FetchFailure.network("x"), .server(500), .badResponse, .unauthorized, .rateLimited(retryS: 5)] {
            #expect(chartWaitMessage(failure: f, warming: true).loading == false)
        }
    }
    @Test func noFailureMeansLoading() {
        #expect(chartWaitMessage(failure: nil, warming: false) == ("Chargement des bougies…", true))
        #expect(chartWaitMessage(failure: nil, warming: true).loading == true)
    }
}

@Suite struct CandleRunTests {
    private func c(_ t: Double) -> Candle { Candle(t: t, o: 1, h: 1, l: 1, c: 1) }
    @Test func oldPointBeforeALongGapIsCutOff() {
        let cs = [c(0), c(5), c(3600), c(3605), c(3610), c(3615)]
        let r = cs.lastContinuousRun(intervalS: 5)
        #expect(r.count == 4 && r.gapS == 3595)
    }
    @Test func continuousSeriesIsKeptWhole() {
        let cs = (0..<20).map { c(Double($0) * 5) }
        #expect(cs.lastContinuousRun(intervalS: 5) == (20, nil))
    }
    @Test func tooShortRecentRunKeepsEverything() {
        let cs = [c(0), c(5), c(10), c(3600)]
        #expect(cs.lastContinuousRun(intervalS: 5) == (4, nil))
    }
}

@Suite struct AxisLabelTests {
    @Test func neighbouringTicksNeverShareTheSameText() {
        let step = 10.0
        let labels = (0...4).map { axisUSD(2_700 + Double($0) * step, step: step) }
        #expect(Set(labels).count == 5)
    }
    @Test func bigStepsKeepTheShortForm() {
        #expect(axisUSD(73_500, step: 5_000) == formatUSD(73_500))
    }
}
