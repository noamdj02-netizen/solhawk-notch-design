import CoreGraphics
import Foundation
import Testing
@testable import SolHawkNotchCore

@Suite struct HawkyTests {
    @Test func allPartsAndExpressionsExist() {
        #expect(HawkyPart.allCases.count == 15)
        #expect(HawkyExpression.allCases.count == 10)
        #expect(Set(HawkyExpression.allCases.map(\.rawValue)) == [
            "idle", "happy", "thinking", "surprise", "concerned",
            "critical", "sleep", "loading", "celebration", "greeting"
        ])
    }

    @Test func paletteMatchesSheet() {
        #expect(near(HawkyPalette.ink.r, 0x0B / 255.0))
        #expect(near(HawkyPalette.cream.g, 0xE9 / 255.0))
        #expect(near(HawkyPalette.orange.r, 1))
        #expect(near(HawkyPalette.green.g, 0xC5 / 255.0))
        #expect(near(HawkyPalette.red.r, 0xEF / 255.0))
    }

    @Test func moodMapsWithoutChangingBusinessMeaning() {
        let settled = HawkyEntry.settled
        #expect(HawkyResolve.expression(mood: .calm(listed: 0), sinceSpottedS: 9, reaction: nil, entry: settled) == .idle)
        #expect(HawkyResolve.expression(mood: .waiting, sinceSpottedS: 9, reaction: nil, entry: settled) == .idle)
        #expect(HawkyResolve.expression(mood: .stale(ageS: 80), sinceSpottedS: 9, reaction: nil, entry: settled) == .sleep)
        #expect(HawkyResolve.expression(mood: .rateLimited(retryS: 4), sinceSpottedS: 9, reaction: nil, entry: settled) == .loading)
        #expect(HawkyResolve.expression(mood: .offline, sinceSpottedS: 9, reaction: nil, entry: settled) == .critical)
        #expect(HawkyResolve.expression(mood: .tokenRejected, sinceSpottedS: 9, reaction: nil, entry: settled) == .critical)
        #expect(HawkyResolve.expression(mood: .badConfig, sinceSpottedS: 9, reaction: nil, entry: settled) == .critical)
        #expect(HawkyResolve.expression(mood: .spotted(passes: true), sinceSpottedS: 0.2, reaction: nil, entry: settled) == .surprise)
        #expect(HawkyResolve.expression(mood: .spotted(passes: true), sinceSpottedS: 1.0, reaction: nil, entry: settled) == .thinking)
        #expect(HawkyResolve.expression(mood: .spotted(passes: true), sinceSpottedS: 5, reaction: nil, entry: settled) == .happy)
        #expect(HawkyResolve.expression(mood: .spotted(passes: false), sinceSpottedS: 5, reaction: nil, entry: settled) == .concerned)
    }

    @Test func celebrationOnlyFromConfirmedWinReaction() {
        let settled = HawkyEntry.settled
        #expect(HawkyResolve.expression(mood: .calm(listed: 3), sinceSpottedS: 9, reaction: .soldWin, entry: settled) == .celebration)
        #expect(HawkyResolve.expression(mood: .spotted(passes: true), sinceSpottedS: 5, reaction: nil, entry: settled) != .celebration)
        #expect(HawkyResolve.expression(mood: .calm(listed: 1), sinceSpottedS: 9, reaction: .soldLoss, entry: settled) == .concerned)
        #expect(HawkyResolve.expression(mood: .calm(listed: 1), sinceSpottedS: 9, reaction: .bought, entry: settled) == .happy)
        #expect(HawkyResolve.expression(mood: .calm(listed: 1), sinceSpottedS: 9, reaction: .spotted, entry: settled) == .surprise)
    }

    @Test func entrySequenceThenGreeting() {
        #expect(HawkyEntryMotion.phase(elapsed: 0) == .hidden)
        if case .rising(let u) = HawkyEntryMotion.phase(elapsed: 0.2) { #expect(u > 0 && u < 1) } else { Issue.record("attendu rising") }
        if case .opening = HawkyEntryMotion.phase(elapsed: 0.55) { } else { Issue.record("attendu opening") }
        if case .glancing = HawkyEntryMotion.phase(elapsed: 0.95) { } else { Issue.record("attendu glancing") }
        #expect(HawkyEntryMotion.phase(elapsed: 1.4) == .settled)
        #expect(HawkyResolve.expression(mood: .calm(listed: 0), sinceSpottedS: 9, reaction: nil, entry: .rising(0.4)) == .greeting)
        #expect(HawkyEntryMotion.riseY(0) > HawkyEntryMotion.riseY(1))
        #expect(HawkyEntryMotion.glanceLook(0.2).x < 0)
        #expect(HawkyEntryMotion.glanceLook(0.55).x > 0)
    }

    @Test func pupilsStayInsideIris() {
        let irisR = 10.0, pupilR = 4.0
        let looks = stride(from: -1.2, through: 1.2, by: 0.15).flatMap { x in
            stride(from: -1.2, through: 1.2, by: 0.15).map { y in CGPoint(x: x, y: y) }
        }
        for look in looks {
            let p = HawkyLook.pupilCenter(look: look, irisR: irisR, pupilR: pupilR)
            #expect(hypot(p.x, p.y) + pupilR <= irisR + 1e-9)
        }
        let edge = HawkyLook.clamp(CGPoint(x: 4, y: 0), maxR: 0.52)
        #expect(abs(hypot(edge.x, edge.y) - 0.52) < 1e-9)
        let left = HawkyLook.screenTarget(mouse: CGPoint(x: 0, y: 400), center: CGPoint(x: 400, y: 400), idle: false)
        let right = HawkyLook.screenTarget(mouse: CGPoint(x: 800, y: 400), center: CGPoint(x: 400, y: 400), idle: false)
        #expect(left.x < -0.5 && right.x > 0.5)
        #expect(HawkyLook.screenTarget(mouse: CGPoint(x: 800, y: 400), center: CGPoint(x: 400, y: 400), idle: true) == .zero)
    }

    @Test func eyesIndependentAndSleepIgnoresCursor() {
        let date = Date(timeIntervalSinceReferenceDate: 40)
        let pair = HawkyLook.pair(look: CGPoint(x: 0.8, y: -0.3), at: date, expression: .idle)
        #expect(pair.left != pair.right)
        #expect(hypot(pair.left.x, pair.left.y) <= 0.53)
        #expect(hypot(pair.right.x, pair.right.y) <= 0.53)
        let asleep = HawkyLook.pair(look: CGPoint(x: 1, y: 1), at: date, expression: .sleep)
        #expect(asleep.left == .zero && asleep.right == .zero)
    }

    @Test func blinkStaysUnitAndVaries() {
        let samples = (0..<80).map { i in
            HawkyBlink.lid(at: Date(timeIntervalSinceReferenceDate: Double(i) * 0.25))
        }
        #expect(samples.allSatisfy { (0...1).contains($0) })
        #expect(samples.contains { $0 > 0.5 })
        #expect(samples.contains { $0 == 0 })
    }

    @Test func paceSlowsWhenIdleCollapsed() {
        let slow = HawkyPace.interval(mood: .stale(ageS: 80), expanded: false, reduceMotion: false, sinceAppearS: 10)
        let fast = HawkyPace.interval(mood: .calm(listed: 2), expanded: true, reduceMotion: false, sinceAppearS: 10)
        let entry = HawkyPace.interval(mood: .waiting, expanded: false, reduceMotion: false, sinceAppearS: 0.2)
        let reduced = HawkyPace.interval(mood: .calm(listed: 2), expanded: true, reduceMotion: true, sinceAppearS: 10)
        #expect(slow > fast)
        #expect(entry <= 1.0 / 30.0 + 1e-9)
        #expect(reduced >= 1.0 / 8.0 - 1e-9)
    }

    @Test func sleepPoseClosesEyes() {
        let p = HawkyPose.of(.sleep, blink: 0, entry: .settled)
        #expect(p.lid == 1 && p.zzz == 1 && p.mouth == .none)
        let g = HawkyPose.of(.greeting, blink: 0, entry: .rising(0.2))
        #expect(g.lid == 1)
        let open = HawkyPose.of(.greeting, blink: 0, entry: .opening(1))
        #expect(open.lid == 0)
        let win = HawkyPose.of(.celebration, blink: 0, entry: .settled)
        #expect(win.sparkle == 1 && win.mouth == .grin)
    }
}

private func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }
