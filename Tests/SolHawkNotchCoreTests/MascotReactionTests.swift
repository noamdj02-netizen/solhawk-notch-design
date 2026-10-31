import Foundation
import Testing
@testable import SolHawkNotchCore

private func samples(_ r: MascotReaction, step: Double = 0.005) -> [(Double, ReactionPose)] {
    stride(from: 0, to: r.duration, by: step).compactMap { t in reactionPose(r, elapsed: t).map { (t, $0) } }
}

@Suite struct MascotReactionTests {
    @Test(arguments: MascotReaction.allCases)
    func startsNeutralAndEndsWithNil(_ r: MascotReaction) throws {
        let p0 = try #require(reactionPose(r, elapsed: 0))
        #expect(p0.hop == 0 && p0.tilt == 0 && p0.hatLift == 0 && p0.hatTilt == 0 && p0.squash == 1)
        // juste avant la fin : quasiment revenu au repos (pas de saut visuel quand la réaction disparaît)
        let pe = try #require(reactionPose(r, elapsed: r.duration - 0.001))
        #expect(pe.hop < 0.01 && abs(pe.tilt) < 0.01 && pe.hatLift < 0.01 && abs(pe.hatTilt) < 0.01 && abs(pe.squash - 1) < 0.01)
        #expect(reactionPose(r, elapsed: r.duration) == nil)
        #expect(reactionPose(r, elapsed: r.duration + 5) == nil)
        #expect(reactionPose(r, elapsed: -0.01) == nil)
        #expect(reactionPose(r, elapsed: .nan) == nil)
        #expect(reactionPose(r, elapsed: .infinity) == nil)
        #expect(r.duration > 0.5 && r.duration <= 1.5)
    }

    @Test(arguments: MascotReaction.allCases)
    func boundsRespectedAndSmooth(_ r: MascotReaction) {
        let s = samples(r)
        #expect(s.count > 100)
        for (_, p) in s {
            #expect((0...1).contains(p.hop) && (0...1).contains(p.hatLift))
            #expect((0.9...1.1).contains(p.squash))
            #expect(abs(p.tilt) <= ReactionPose.maxTilt && abs(p.hatTilt) <= ReactionPose.maxTilt)
        }
        // pas de saut brutal entre deux images à 200 i/s
        for (a, b) in zip(s, s.dropFirst()) {
            #expect(abs(a.1.hop - b.1.hop) < 0.05 && abs(a.1.squash - b.1.squash) < 0.02)
            #expect(abs(a.1.hatLift - b.1.hatLift) < 0.05 && abs(a.1.tilt - b.1.tilt) < 0.02)
        }
    }

    @Test func deterministic() {
        for r in MascotReaction.allCases { #expect(reactionPose(r, elapsed: 0.37) == reactionPose(r, elapsed: 0.37)) }
    }

    @Test func boughtHopsAndAdjustsTheCap() throws {
        let mid = try #require(reactionPose(.bought, elapsed: 0.5))
        #expect(mid.hatLift > 0.9 && mid.hatTilt < -0.1 && mid.face == nil)
        let maxHop = samples(.bought).map(\.1.hop).max() ?? 0
        #expect(maxHop > 0.3 && maxHop < 0.6)   // petit saut
        let air = try #require(reactionPose(.bought, elapsed: 0.24))
        #expect(air.hop > 0.4 && air.squash > 1)   // étiré en l'air
    }

    @Test func soldWinDoubleHopHappyFace() {
        let s = samples(.soldWin)
        #expect(s.allSatisfy { $0.1.face == .closed && $0.1.mouthOpen })
        // deux bosses distinctes : la hauteur retombe à 0 entre les deux
        var peaks = 0, up = false
        for (a, b) in zip(s, s.dropFirst()) {
            if b.1.hop > a.1.hop { up = true } else if up && b.1.hop < a.1.hop { peaks += 1; up = false }
        }
        #expect(peaks == 2)
        #expect(s.contains { $0.0 > 0.45 && $0.0 < 0.55 && $0.1.hop == 0 })
    }

    @Test func soldLossSlumps() throws {
        let mid = try #require(reactionPose(.soldLoss, elapsed: 0.6))
        #expect(mid.squash < 0.95 && mid.hop == 0 && mid.tilt > 0.05)
        #expect(mid.face == .sleepy)
        #expect(reactionPose(.soldLoss, elapsed: 0.2)?.face == .worried)
        #expect(samples(.soldLoss).allSatisfy { $0.1.hop == 0 && $0.1.squash <= 1 })
    }

    @Test func spottedQuickLookAndSmallHop() throws {
        let s = samples(.spotted)
        #expect(s.allSatisfy { $0.1.face == .wide })
        let maxHop = s.map(\.1.hop).max() ?? 0
        #expect(maxHop > 0.2 && maxHop <= 0.3)
        #expect(s.contains { $0.1.tilt > 0.05 } && s.contains { $0.1.tilt < -0.05 })   // regarde d'un côté puis de l'autre
    }

    @Test func reducedMotionKeepsOnlyTheFace() throws {
        let p = try #require(reactionPose(.soldWin, elapsed: 0.25)).reducedMotion
        #expect(p == ReactionPose(face: .closed, mouthOpen: true))
        #expect(try #require(reactionPose(.bought, elapsed: 0.5)).reducedMotion == ReactionPose())
    }

    @MainActor @Test func busFiresAndExpires() throws {
        let bus = MascotReactions()
        let t0 = Date(timeIntervalSinceReferenceDate: 1000)
        #expect(bus.current == nil && bus.active(at: t0) == nil)
        bus.fire(.bought, at: t0)
        let c = try #require(bus.current)
        #expect(c.0 == .bought && c.1 == t0)
        #expect(bus.active(at: t0.addingTimeInterval(0.5))?.0 == .bought)
        #expect(bus.active(at: t0.addingTimeInterval(1.3)) == nil)
        #expect(bus.active(at: t0.addingTimeInterval(-1)) == nil)
        bus.fire(.soldLoss, at: t0.addingTimeInterval(0.4))   // remplace la précédente
        #expect(bus.current?.0 == .soldLoss)
    }
}
