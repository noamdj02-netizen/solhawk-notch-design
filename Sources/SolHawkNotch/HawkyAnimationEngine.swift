import CoreGraphics
import Foundation
import SwiftUI
import SolHawkNotchCore

/// Ressorts, respiration, entrée, clignement. Pas de minuteur propre : le TimelineView parent fournit `date`.
enum HawkyAnimationEngine {
    static let pupilSpring = Animation.interactiveSpring(response: 0.20, dampingFraction: 0.88)
    static let headSpring = Animation.interactiveSpring(response: 0.34, dampingFraction: 0.86)
    static let entrySpring = Animation.spring(response: 0.46, dampingFraction: 0.72)

    struct Snapshot: Equatable {
        var expression: HawkyExpression
        var entry: HawkyEntry
        var pose: HawkyPose
        var leftLook: CGPoint
        var rightLook: CGPoint
        var breath: Double
        var rise: Double
        var bob: Double
        var opacity: Double
        var tilt: Double
    }

    static func snapshot(
        mood: Mood,
        look: CGPoint,
        date: Date,
        hop: Double,
        sinceSpottedS: Double,
        reaction: MascotReaction?,
        sinceAppearS: Double,
        hovering: Bool,
        reduceMotion: Bool
    ) -> Snapshot {
        let entry = reduceMotion ? HawkyEntry.settled : HawkyStateMachine.entry(elapsed: sinceAppearS)
        var expression = HawkyEmotionController.expression(
            mood: mood, sinceSpottedS: sinceSpottedS, reaction: reaction, entry: entry
        )
        if let forced = forcedExpression() { expression = forced }
        let blink = reduceMotion ? 0 : HawkyBlink.lid(at: date)
        let pose = HawkyPose.of(expression, blink: blink, entry: entry)

        var cursor = look
        if reduceMotion { cursor = .zero }
        if case .glancing(let u) = entry { cursor = HawkyEntryMotion.glanceLook(u) }
        if expression == .sleep { cursor = .zero }
        else if !reduceMotion, forcedLook() == nil, let acted = HawkyActing.gaze(expression, at: date.timeIntervalSinceReferenceDate) { cursor = acted }
        let eyes = HawkyLook.pair(look: cursor, at: date, expression: expression)

        var opacity = 1.0, rise = 0.0
        if !reduceMotion {
            switch entry {
            case .hidden:
                opacity = 0; rise = 0.46
            case .rising(let u):
                opacity = min(1, u * 1.4)
                rise = HawkyEntryMotion.riseY(u)
            default: break
            }
        }

        let t = date.timeIntervalSinceReferenceDate
        let breath = (reduceMotion || expression == .critical) ? 1.0 : 1 + 0.014 * sin(t * 1.28)
        let bob: Double
        if reduceMotion {
            bob = 0
        } else {
            bob = sin(t * (expression == .sleep ? 1.05 : 1.55)) * 0.012 - hop * 0.10
        }
        let tilt = reduceMotion ? 0 : cursor.x * 5.2 + (hovering ? 1.6 : 0)

        return Snapshot(
            expression: expression, entry: entry, pose: pose,
            leftLook: eyes.left, rightLook: eyes.right,
            breath: breath, rise: rise, bob: bob, opacity: opacity, tilt: tilt
        )
    }

    /// Essais visuels : `SOLHAWK_HAWKY_EXPR=celebration` force l'expression (idle, happy, thinking, surprise, concerned, critical, sleep, loading, celebration, greeting).
    static func forcedExpression() -> HawkyExpression? {
        guard let raw = ProcessInfo.processInfo.environment["SOLHAWK_HAWKY_EXPR"] else { return nil }
        return HawkyExpression.allCases.first { "\($0)" == raw }
    }

    /// Essais visuels : `SOLHAWK_HAWKY_AGE=0.9` force l'âge de la réaction (étoiles, billets, larmes à ce moment-là).
    static func forcedAge() -> Double? {
        ProcessInfo.processInfo.environment["SOLHAWK_HAWKY_AGE"].flatMap { Double($0) }
    }

    /// Essais visuels : `SOLHAWK_HAWKY_LOOK=0.9,0` force le regard (snapshots gauche/droite).
    static func forcedLook() -> CGPoint? {
        guard let raw = ProcessInfo.processInfo.environment["SOLHAWK_HAWKY_LOOK"] else { return nil }
        let p = raw.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard p.count >= 1 else { return nil }
        return HawkyLook.clamp(CGPoint(x: p[0], y: p.count > 1 ? p[1] : 0), maxR: 1)
    }
}
