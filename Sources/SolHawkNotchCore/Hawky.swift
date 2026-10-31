import CoreGraphics
import Foundation

/// Parties indépendantes du rig Hawky (rendu procédural, jamais une image unique).
public enum HawkyPart: String, CaseIterable, Sendable {
    case head, hood, leftEar, rightEar
    case leftEye, rightEye, leftIris, rightIris, leftPupil, rightPupil
    case eyelids, eyebrows, mouth, leftPaw, rightPaw
}

/// Les 10 états du character sheet. Couleur / pose = lecture, jamais un conseil de trade.
public enum HawkyExpression: String, CaseIterable, Sendable {
    case idle, happy, thinking, surprise, concerned, critical
    case sleep, loading, celebration, greeting
}

public enum HawkyEntry: Equatable, Sendable {
    case hidden
    case rising(Double)
    case opening(Double)
    case glancing(Double)
    case settled
}

/// Palette verrouillée (character sheet).
public enum HawkyPalette {
    public static let ink = (r: 0x0B / 255.0, g: 0x0C / 255.0, b: 0x0E / 255.0)
    public static let cream = (r: 0xED / 255.0, g: 0xE9 / 255.0, b: 0xDF / 255.0)
    public static let orange = (r: 0xFF / 255.0, g: 0x7A / 255.0, b: 0x2F / 255.0)
    public static let green = (r: 0x22 / 255.0, g: 0xC5 / 255.0, b: 0x5E / 255.0)
    public static let red = (r: 0xEF / 255.0, g: 0x44 / 255.0, b: 0x44 / 255.0)
}

/// Fréquence du TimelineView : plus basse au repos / masqué, plus haute pendant l'entrée.
public enum HawkyPace {
    public static func interval(mood: Mood, expanded: Bool, reduceMotion: Bool, sinceAppearS: Double) -> Double {
        if reduceMotion { return 1.0 / 8.0 }
        if sinceAppearS < 1.35 { return 1.0 / 30.0 }
        if expanded { return 1.0 / 30.0 }
        switch mood {
        case .stale: return 1.0 / 8.0
        case .offline, .badConfig, .tokenRejected: return 1.0 / 12.0
        default: return 1.0 / 20.0
        }
    }
}

/// Clignements naturels : période et durée variables, parfois un double clignement.
public enum HawkyBlink {
    public static func lid(at date: Date) -> Double {
        let t = date.timeIntervalSinceReferenceDate
        let cycle = 4.2 + 0.7 * sin(t * 0.19)
        let phase = t.truncatingRemainder(dividingBy: cycle)
        let dur = 0.08 + 0.06 * (0.5 + 0.5 * sin(t * 0.29))
        if phase >= 0, phase < dur { return sin(phase / dur * .pi) }
        let slot = floor(t / cycle)
        if sin(slot * 12.7) > 0.74 {
            let p2 = phase - dur * 1.18
            if p2 > 0, p2 < dur * 0.82 { return sin(p2 / (dur * 0.82) * .pi) }
        }
        return 0
    }
}

/// Regard : yeux indépendants, micro-saccades, pupille clampée dans l'iris.
public enum HawkyLook {
    public struct Pair: Equatable, Sendable {
        public var left: CGPoint
        public var right: CGPoint
        public init(left: CGPoint, right: CGPoint) { self.left = left; self.right = right }
    }

    public static func pair(look: CGPoint, at date: Date, expression: HawkyExpression, amplitude: Double = 0.88) -> Pair {
        if expression == .sleep { return Pair(left: .zero, right: .zero) }
        let t = date.timeIntervalSinceReferenceDate
        let sacc = saccade(t)
        let mx = look.x * amplitude
        let my = look.y * amplitude * 0.72
        let left = clamp(CGPoint(
            x: mx - 0.04 + 0.02 * sin(t * 0.73) + sacc.x * 0.65,
            y: my + 0.014 * sin(t * 0.91) + sacc.y * 0.5
        ))
        let right = clamp(CGPoint(
            x: mx + 0.05 + 0.018 * sin(t * 0.73 + 0.42) + sacc.x,
            y: my + 0.012 * cos(t * 0.83) + sacc.y * 0.85
        ))
        return Pair(left: left, right: right)
    }

    public static func clamp(_ p: CGPoint, maxR: Double = 0.52) -> CGPoint {
        let r = hypot(p.x, p.y)
        guard r > maxR, r > 0 else { return p }
        let k = maxR / r
        return CGPoint(x: p.x * k, y: p.y * k)
    }

    /// Centre de pupille relatif au centre d'iris. `|offset| + pupilR ≤ irisR`.
    public static func pupilCenter(look: CGPoint, irisR: Double, pupilR: Double) -> CGPoint {
        let maxOff = max(0, irisR - pupilR) * 0.92
        let c = clamp(look, maxR: 1)
        return CGPoint(x: c.x * maxOff, y: c.y * maxOff)
    }

    /// Cible écran → regard −1…1. Pas de zone morte courte : le suivi reste lisible hors de l'encoche.
    public static func screenTarget(mouse: CGPoint, center: CGPoint, idle: Bool) -> CGPoint {
        if idle { return .zero }
        let dx = mouse.x - center.x
        let dy = -(mouse.y - center.y)
        let nx = max(-1, min(1, dx / 200))
        let ny = max(-1, min(1, dy / 160))
        return clamp(CGPoint(x: nx, y: ny * 0.78), maxR: 0.95)
    }

    static func saccade(_ t: Double) -> CGPoint {
        let period = 2.35
        let slot = floor(t / period)
        let local = t.truncatingRemainder(dividingBy: period)
        guard local < 0.12 else { return .zero }
        let fade = sin(local / 0.12 * .pi)
        return CGPoint(x: sin(slot * 19.1) * 0.04 * fade, y: cos(slot * 13.7) * 0.025 * fade)
    }
}

public enum HawkyEntryMotion {
    public static func phase(elapsed: Double) -> HawkyEntry {
        if elapsed < 0.06 { return .hidden }
        if elapsed < 0.42 { return .rising(min(1, (elapsed - 0.06) / 0.36)) }
        if elapsed < 0.70 { return .opening(min(1, (elapsed - 0.42) / 0.28)) }
        if elapsed < 1.28 { return .glancing(min(1, (elapsed - 0.70) / 0.58)) }
        return .settled
    }

    /// Décalage Y (positif = bas), avec léger ressort.
    public static func riseY(_ u: Double) -> Double {
        let x = min(1, max(0, u))
        let s = 1 - pow(1 - x, 3)
        let over = sin(x * .pi) * 0.10
        return (1 - s) * 0.46 - over * 0.14
    }

    public static func glanceLook(_ u: Double) -> CGPoint {
        if u < 0.38 { return CGPoint(x: -0.52 * sin(u / 0.38 * .pi), y: 0.04) }
        if u < 0.78 { return CGPoint(x: 0.52 * sin((u - 0.38) / 0.40 * .pi), y: 0.03) }
        let v = min(1, (u - 0.78) / 0.22)
        return CGPoint(x: 0.16 * (1 - v), y: 0)
    }
}

public enum HawkyResolve {
    /// Mapping Mood + réaction + entrée. Ne change pas le sens de Mood.
    public static func expression(
        mood: Mood,
        sinceSpottedS: Double,
        reaction: MascotReaction?,
        entry: HawkyEntry
    ) -> HawkyExpression {
        switch entry {
        case .hidden, .rising, .opening, .glancing: return .greeting
        case .settled: break
        }
        if let reaction {
            switch reaction {
            case .soldWin: return .celebration
            case .soldLoss: return .concerned
            case .bought: return .happy
            case .spotted: return .surprise
            case .signalGreen: return .happy
            case .signalRed: return .critical
            }
        }
        switch mood {
        case .waiting: return .idle
        case .stale: return .sleep
        case .rateLimited: return .loading
        case .tokenRejected, .offline, .badConfig: return .critical
        case .calm: return .idle
        case .spotted(let passes):
            if sinceSpottedS < 0.5 { return .surprise }
            if sinceSpottedS < 2.0 { return .thinking }
            return passes ? .happy : .concerned
        }
    }
}

public struct HawkyPose: Equatable, Sendable {
    public var lid: Double
    public var eyeScale: Double
    public var brow: Double
    public var mouth: Mouth
    public var sparkle: Double
    public var zzz: Double
    public var spin: Double
    /// Paupière du bas qui remonte (sourire des yeux), 0…1.
    public var lidBottom: Double = 0
    /// Inclinaison des paupières : + = coins extérieurs vers le bas (triste), − = coins extérieurs vers le haut (sévère). −1…1.
    public var slant: Double = 0
    /// Yeux fermés en arc « ^^ » (très content), 0…1.
    public var arcs: Double = 0
    /// Taille de la pupille (1 = normale ; < 1 = pupille serrée, > 1 = dilatée).
    public var pupil: Double = 1
    public enum Mouth: String, Sendable, Equatable { case none, smile, frown, oh, line, grin }

    public static func of(_ e: HawkyExpression, blink: Double, entry: HawkyEntry) -> HawkyPose {
        var lid = blink
        var eyeScale = 1.0
        var brow = 0.0
        var mouth: Mouth = .line
        var sparkle = 0.0
        var zzz = 0.0
        var spin = 0.0
        var lidBottom = 0.0, slant = 0.0, arcs = 0.0, pupil = 1.0
        switch e {
        case .idle:
            mouth = .line
        case .happy:
            mouth = .smile
            eyeScale = 0.97
            brow = 0.12
            lidBottom = 0.30
        case .thinking:
            mouth = .line
            brow = 0.38
            lid = max(lid, 0.16)
            slant = -0.2
        case .surprise:
            mouth = .oh
            eyeScale = 1.10
            brow = 0.52
            lid = min(lid, 0.04)
            pupil = 0.78
        case .concerned:
            mouth = .frown
            brow = -0.32
            lid = max(lid, 0.22)
            slant = 0.9
            lidBottom = 0.10
        case .critical:
            mouth = .line
            brow = -0.52
            eyeScale = 0.94
            lid = max(lid, 0.24)
            slant = -0.85
            pupil = 0.8
        case .sleep:
            lid = 1
            mouth = .none
            zzz = 1
            arcs = 0
        case .loading:
            mouth = .line
            lid = max(lid, 0.06)
            spin = 1
        case .celebration:
            mouth = .grin
            sparkle = 1
            brow = 0.22
            eyeScale = 0.95
            arcs = 1
        case .greeting:
            mouth = .smile
            brow = 0.18
            switch entry {
            case .hidden, .rising: lid = 1
            case .opening(let u): lid = max(lid, 1 - u)
            default: break
            }
        }
        var pose = HawkyPose(lid: lid, eyeScale: eyeScale, brow: brow, mouth: mouth, sparkle: sparkle, zzz: zzz, spin: spin)
        pose.lidBottom = lidBottom; pose.slant = slant; pose.arcs = arcs; pose.pupil = pupil
        return pose
    }
}
