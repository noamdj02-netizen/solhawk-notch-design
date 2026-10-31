import Foundation
import Testing
@testable import SolHawkNotchCore

// Ces tests ne modifient JAMAIS AlertConfigBox.shared (partagé avec les autres tests lancés en parallèle) : la config est passée explicitement.

private func item(_ m: String, peak: Double? = nil, image: String? = nil) -> Feed.Item {
    var i = Feed.Item(mint: m, symbol: "T\(m)", name: nil, ageS: 20, marketCap: 8200, realSol: nil, risk: Feed.Risk(score: nil, label: "faible"),
                      lights: Feed.Lights(mint: "green", freeze: "green", dev: "green", volume: "green", holders: "green"), series: nil, fromPeakPct: peak)
    i.imageURL = image
    return i
}
private func feed(_ i: [Feed.Item]) -> Feed { Feed(updatedAt: nil, stats: Feed.Stats(), items: i, note: nil) }
private func config(_ edit: (inout AlertConfig) -> Void) -> AlertConfig { var c = AlertConfig.defaults; edit(&c); return c }

private let gmt: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
private func at(hour: Int, minute: Int = 0) -> Date { gmt.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: hour, minute: minute))! }

@Suite("Règles d'alerte")
struct AlertRuleTests {
    @Test func defaultsKeepPreviousBehaviour() {
        let c = AlertConfig.defaults
        #expect(c.rules.map(\.kind) == AlertKind.allCases)
        let allOn = c.rules.allSatisfy { $0.enabled }
        #expect(allOn)
        #expect(c[.bigDrop].threshold == 40)
        #expect(c[.newPassesFilters].threshold == nil && c[.outage].threshold == nil)
        #expect(c[.newPassesFilters].sound == "Glass" && c[.bigDrop].sound == "Basso")
        #expect(!c.muted && !c.quietHours)
    }

    @Test func roundTripsThroughJSON() throws {
        let c = config { $0[.bigDrop] = AlertRule(kind: .bigDrop, enabled: false, threshold: 25, sound: "Hero"); $0.muted = true; $0.quietHours = true; $0.quietStart = 22; $0.quietEnd = 6 }
        let back = AlertConfig.decode(c.encoded())
        #expect(back == c)
        #expect(back[.bigDrop].threshold == 25 && !back[.bigDrop].enabled && back[.bigDrop].sound == "Hero")
    }

    @Test func badOrMissingJSONFallsBackToDefaults() {
        #expect(AlertConfig.decode(nil) == .defaults)
        #expect(AlertConfig.decode(Data("pas du json".utf8)) == .defaults)
        // champs manquants, type inconnu, son interdit, seuil hors bornes : tout est remis d'aplomb
        let raw = #"{"rules":[{"kind":"futur","enabled":true,"sound":"Glass"},{"kind":"bigDrop","enabled":true,"threshold":900,"sound":"../../evil"}],"quietStart":40}"#
        let c = AlertConfig.decode(Data(raw.utf8))
        #expect(c.rules.map(\.kind) == AlertKind.allCases)
        #expect(c[.bigDrop].threshold == 95)
        #expect(c[.bigDrop].sound == "Basso")
        #expect(c.quietStart == 23 && c.quietEnd == 7)
        #expect(c[.positionThreshold] == AlertRule.defaultRule(.positionThreshold))
    }

    @Test func thresholdOnlyWhereRelevant() {
        let c = config { $0[.newPassesFilters] = AlertRule(kind: .newPassesFilters, threshold: 12, sound: "Pop") }
        #expect(c[.newPassesFilters].threshold == nil)
        #expect(AlertRule(kind: .positionThreshold, threshold: 1, sound: "Ping").sanitized().threshold == 5)
        #expect(AlertRule(kind: .positionThreshold, threshold: .nan, sound: "Ping").sanitized().threshold == 50)
    }

    @Test func soundAllowList() {
        #expect(alertSoundNames.count == 14)
        for s in alertSoundNames { #expect(validSoundName(s) == s) }
        #expect(validSoundName("glass") == nil)            // la casse compte : le nom exact du fichier système
        #expect(validSoundName("/System/Library/Sounds/Glass.aiff") == nil)
        #expect(validSoundName(nil) == nil)
    }
}

@Suite("Moteur d'alerte et règles")
struct AlertEngineRuleTests {
    @Test func disabledPassRuleIsSilentAndStillTracked() {
        var e = AlertEngine()
        let off = config { $0[.newPassesFilters].enabled = false }
        _ = e.evaluate(feed: feed([]), mood: .calm(listed: 0), config: off)
        #expect(e.evaluate(feed: feed([item("A")]), mood: .calm(listed: 1), config: off).isEmpty)
        // réactivée : A a déjà été vu, il ne sonne pas après coup ; B oui
        let r = e.evaluate(feed: feed([item("A"), item("B")]), mood: .calm(listed: 2), config: .defaults)
        #expect(r.map(\.mint) == ["B"] && r[0].type == .newPassesFilters)
    }

    @Test func dropThresholdIsConfigurable() {
        var e = AlertEngine()
        let c = config { $0[.bigDrop].threshold = 25 }
        _ = e.evaluate(feed: feed([item("A")]), mood: .calm(listed: 1), config: c)
        let r = e.evaluate(feed: feed([item("A", peak: -30, image: "https://x/y.png")]), mood: .calm(listed: 1), config: c)
        #expect(r.count == 1 && r[0].type == .bigDrop && r[0].kind == .red && r[0].image == "https://x/y.png" && r[0].symbol == "TA")
        // seuil par défaut (40) : -30 ne sonne pas
        var d = AlertEngine()
        _ = d.evaluate(feed: feed([item("A")]), mood: .calm(listed: 1), config: .defaults)
        #expect(d.evaluate(feed: feed([item("A", peak: -30)]), mood: .calm(listed: 1), config: .defaults).isEmpty)
        #expect(d.evaluate(feed: feed([item("A", peak: -41)]), mood: .calm(listed: 1), config: .defaults).count == 1)
    }

    @Test func disabledOutageStaysSilentButIsTracked() {
        var e = AlertEngine()
        let off = config { $0[.outage].enabled = false }
        #expect(e.evaluate(feed: nil, mood: .offline, config: off).isEmpty)
        #expect(e.evaluate(feed: nil, mood: .offline, config: .defaults).isEmpty)   // même coupure : pas d'alerte en retard
        _ = e.evaluate(feed: feed([]), mood: .calm(listed: 0), config: .defaults)
        let r = e.evaluate(feed: nil, mood: .offline, config: .defaults)
        #expect(r.count == 1 && r[0].type == .outage && r[0].mint == nil)
    }

    @Test func alertTypeInferredForLegacyInit() {
        #expect(NotchAlert(kind: .red, mint: nil, title: "x", body: "y").type == .outage)
        #expect(NotchAlert(kind: .red, mint: "M", title: "x", body: "y").type == .bigDrop)
        #expect(NotchAlert(kind: .green, mint: "M", title: "x", body: "y").type == .newPassesFilters)
    }
}

@Suite("Positions fictives")
struct PositionAlertTests {
    @Test func firesOncePerCrossingAndRearms() {
        let up = [(mint: "A", symbol: "AAA", pnlPct: 60.0)]
        var r = positionCrossings(open: up, threshold: 50, alreadyFired: [])
        #expect(r.alerts.count == 1 && r.alerts[0].kind == .green && r.alerts[0].type == .positionThreshold && r.fired == ["A+"])
        r = positionCrossings(open: [(mint: "A", symbol: "AAA", pnlPct: 80.0)], threshold: 50, alreadyFired: r.fired)
        #expect(r.alerts.isEmpty && r.fired == ["A+"])                      // toujours au-dessus : une seule fois
        r = positionCrossings(open: [(mint: "A", symbol: "AAA", pnlPct: 10.0)], threshold: 50, alreadyFired: r.fired)
        #expect(r.alerts.isEmpty && r.fired.isEmpty)                        // retombé : réarmé
        r = positionCrossings(open: up, threshold: 50, alreadyFired: r.fired)
        #expect(r.alerts.count == 1)                                        // nouveau franchissement
    }

    @Test func lossSideAndWording() {
        let a = positionAlerts(open: [(mint: "B", symbol: "BBB", pnlPct: -55), (mint: "C", symbol: "CCC", pnlPct: 3)], threshold: 50, alreadyFired: [])
        #expect(a.count == 1 && a[0].mint == "B" && a[0].kind == .red)
        let text = (a[0].title + a[0].body).lowercased()
        #expect(text.contains("fictif") && !text.contains("achète") && !text.contains("vends") && !text.contains("sûr"))
        #expect(positionAlerts(open: [(mint: "B", symbol: "BBB", pnlPct: -55)], threshold: 50, alreadyFired: ["B-"]).isEmpty)
    }

    @Test func ignoresBadInputs() {
        #expect(positionAlerts(open: [(mint: "A", symbol: "A", pnlPct: .nan)], threshold: 50, alreadyFired: []).isEmpty)
        #expect(positionAlerts(open: [(mint: "A", symbol: "A", pnlPct: 999)], threshold: 0, alreadyFired: []).isEmpty)
    }
}

@Suite("Heures calmes et livraison")
struct QuietHoursTests {
    @Test func sameDayWindow() {
        #expect(inQuietHours(at(hour: 13), start: 12, end: 14, calendar: gmt))
        #expect(inQuietHours(at(hour: 12), start: 12, end: 14, calendar: gmt))
        #expect(!inQuietHours(at(hour: 14), start: 12, end: 14, calendar: gmt))
        #expect(!inQuietHours(at(hour: 9), start: 12, end: 14, calendar: gmt))
    }
    @Test func wrapsMidnight() {
        #expect(inQuietHours(at(hour: 23, minute: 30), start: 22, end: 7, calendar: gmt))
        #expect(inQuietHours(at(hour: 0), start: 22, end: 7, calendar: gmt))
        #expect(inQuietHours(at(hour: 6, minute: 59), start: 22, end: 7, calendar: gmt))
        #expect(!inQuietHours(at(hour: 7), start: 22, end: 7, calendar: gmt))
        #expect(!inQuietHours(at(hour: 15), start: 22, end: 7, calendar: gmt))
    }
    @Test func emptyWindowNeverQuiet() {
        for h in 0..<24 { #expect(!inQuietHours(at(hour: h), start: 5, end: 5, calendar: gmt)) }
    }

    @Test func deliveryRespectsRuleMuteAndQuietHours() {
        let noon = at(hour: 12)
        #expect(decideDelivery(.bigDrop, config: .defaults, notifyPref: true, now: noon, calendar: gmt) == AlertDecision(notify: true, sound: "Basso"))
        #expect(decideDelivery(.bigDrop, config: .defaults, notifyPref: false, now: noon, calendar: gmt) == AlertDecision(notify: false, sound: "Basso"))
        let muted = config { $0.muted = true }
        #expect(decideDelivery(.bigDrop, config: muted, notifyPref: true, now: noon, calendar: gmt) == AlertDecision(notify: true, sound: nil))
        let off = config { $0[.bigDrop].enabled = false }
        #expect(decideDelivery(.bigDrop, config: off, notifyPref: true, now: noon, calendar: gmt) == AlertDecision(notify: false, sound: nil))
        let quiet = config { $0.quietHours = true; $0.quietStart = 11; $0.quietEnd = 13 }
        #expect(decideDelivery(.outage, config: quiet, notifyPref: true, now: noon, calendar: gmt) == AlertDecision(notify: false, sound: nil))
        #expect(decideDelivery(.outage, config: quiet, notifyPref: true, now: at(hour: 14), calendar: gmt).sound == "Basso")
        let custom = config { $0[.newPassesFilters].sound = "Frog" }
        #expect(decideDelivery(.newPassesFilters, config: custom, notifyPref: true, now: noon, calendar: gmt).sound == "Frog")
    }
}
