import Testing
import Foundation
@testable import SolHawkNotchCore

@Suite struct HawkyActingTests {
    @Test func everyParticleStaysOnTheImage() {
        for e in HawkyExpression.allCases {
            for age in [nil, 0.0, 0.3, 0.9, 1.6, 3.0] as [Double?] {
                for t in stride(from: 0.0, to: 12.0, by: 0.37) {
                    for p in HawkyActing.particles(e, age: age, t: t) {
                        #expect(p.x > -0.05 && p.x < 1.05, "\(e) x=\(p.x)")
                        #expect(p.y > -0.2 && p.y < 0.8, "\(e) y=\(p.y)")
                        #expect(p.alpha >= 0 && p.alpha <= 1.0001)
                        #expect(p.size >= -1e-9 && p.size < 0.2)
                    }
                }
            }
        }
    }

    @Test func celebrationBurstsThenFades() {
        #expect(HawkyActing.particles(.celebration, age: 0.4, t: 0).isEmpty == false)
        #expect(HawkyActing.particles(.celebration, age: 2.6, t: 0).isEmpty)
    }

    @Test func winBillsRiseAndLossBillsFall() {
        func ys(_ e: HawkyExpression, _ a: Double) -> [Double] { HawkyActing.particles(e, age: a, t: 0).filter { $0.kind == .bill }.map(\.y) }
        #expect(!ys(.celebration, 0.5).isEmpty && !ys(.concerned, 0.5).isEmpty)
        // gain : un billet donné monte ; perte : il descend
        let up1 = HawkyActing.bills(rising: true, age: 0.4).first!.y, up2 = HawkyActing.bills(rising: true, age: 0.8).first!.y
        let dn1 = HawkyActing.bills(rising: false, age: 0.4).first!.y, dn2 = HawkyActing.bills(rising: false, age: 0.8).first!.y
        #expect(up2 < up1 && dn2 > dn1)
        #expect(HawkyActing.particles(.celebration, age: nil, t: 5).allSatisfy { $0.kind != .bill })
        #expect(HawkyActing.particles(.concerned, age: 3.2, t: 5).allSatisfy { $0.kind != .bill })
    }

    @Test func sadnessDropsTears() {
        let kinds = HawkyActing.particles(.concerned, age: nil, t: 1.4).map(\.kind)
        #expect(kinds.allSatisfy { $0 == .tear })     // sans âge (humeur seule) : pas de billets
        #expect(kinds.count == 2)
    }

    @Test func calmHasNoParticlesAndFollowsTheCursor() {
        #expect(HawkyActing.particles(.idle, age: nil, t: 3).isEmpty)
        #expect(HawkyActing.gaze(.idle, at: 3) == nil)
        #expect(HawkyActing.gaze(.happy, at: 3) == nil)
    }

    @Test func imposedGazeStaysInsideTheEye() {
        for e in [HawkyExpression.thinking, .concerned, .loading] {
            for t in stride(from: 0.0, to: 10.0, by: 0.2) {
                let g = HawkyActing.gaze(e, at: t)!
                #expect(hypot(g.x, g.y) <= 1.0, "\(e) t=\(t)")
            }
        }
    }

    @Test func poseSadAndHappyDiffer() {
        let sad = HawkyPose.of(.concerned, blink: 0, entry: .settled)
        let angry = HawkyPose.of(.critical, blink: 0, entry: .settled)
        let joy = HawkyPose.of(.celebration, blink: 0, entry: .settled)
        #expect(sad.slant > 0.5 && angry.slant < -0.5)
        #expect(joy.arcs == 1)
        #expect(HawkyPose.of(.idle, blink: 0, entry: .settled).arcs == 0)
    }

    @MainActor @Test func emoteOutlastsTheBodyMotion() {
        let bus = MascotReactions()
        let t0 = Date(timeIntervalSinceReferenceDate: 1000)
        bus.fire(.soldLoss, at: t0)
        #expect(bus.activeEmote(at: t0.addingTimeInterval(2.5))?.0 == .soldLoss)
        #expect(bus.activeEmote(at: t0.addingTimeInterval(4.0)) == nil)
    }
}
