import Foundation
import Observation

// MARK: petites réactions du personnage aux événements de l'app (dessinées en code, ~1 s, puis retour au repos)
// Ce sont des animations d'humeur : elles disent « il s'est passé quelque chose », jamais « c'est un bon trade ».

/// Événement auquel le personnage réagit. Les trades sont FICTIFS (simulation) : aucune transaction réelle.
public enum MascotReaction: Sendable, Equatable, CaseIterable {
    case bought     // ordre fictif ouvert : petit saut, il soulève sa casquette et la réajuste
    case soldWin    // position fictive fermée en gain : double saut, yeux contents
    case soldLoss   // position fictive fermée en perte : il s'affaisse, penche, yeux fatigués
    case spotted    // nouveau token repéré : coup d'œil rapide + petit saut
    case signalGreen // la barre passe au vert (un token passe les filtres) : il se redresse, content, étincelles
    case signalRed   // la barre passe au rouge (chute forte ou panne) : il sursaute, « ! » rouge

    /// Durée de la réaction en secondes ; au-delà, `reactionPose` renvoie nil.
    public var duration: Double {
        switch self {
        case .bought, .soldWin, .soldLoss: return 1.2
        case .spotted: return 0.9
        case .signalGreen, .signalRed: return 1.0
        }
    }
}

extension MascotReaction {
    /// Durée pendant laquelle l'ÉMOTION (visage, particules) reste affichée : plus longue que le mouvement du corps (`duration`),
    /// pour qu'on voie bien qu'il est content (gain), triste (perte) ou surpris.
    public var emoteDuration: Double {
        switch self {
        case .bought: return 1.6
        case .soldWin: return 2.6
        case .soldLoss: return 3.4
        case .spotted: return 1.8
        case .signalGreen: return 2.2
        case .signalRed: return 2.4
        }
    }
}

/// Expression des yeux portée par la pose d'une réaction (le rendu choisit les traits de Hawky depuis l'expression). Dit l'état de la lecture, jamais un conseil.
public enum EyeFace: Sendable, Equatable {
    case open, wide, sleepy, closed, worried
}

/// Pose à appliquer par-dessus l'animation normale. Valeurs neutres : hop 0, tilt 0, hatLift 0, hatTilt 0, squash 1.
public struct ReactionPose: Sendable, Equatable {
    /// 0…1 : hauteur du saut (relative ; la vue décide combien de pixels).
    public var hop: Double
    /// Inclinaison du corps, en radians (positif = sens horaire).
    public var tilt: Double
    /// 0…1 : chapeau soulevé (1 = levé au maximum), puis reposé.
    public var hatLift: Double
    /// Inclinaison du chapeau, en radians.
    public var hatTilt: Double
    /// 0.9…1.1 : écrasement (< 1) ou étirement (> 1) vertical.
    public var squash: Double
    /// Expression imposée pendant la réaction (nil = celle de l'humeur).
    public var face: EyeFace?
    /// Bouche ouverte imposée (contente) pendant la réaction.
    public var mouthOpen: Bool

    public init(hop: Double = 0, tilt: Double = 0, hatLift: Double = 0, hatTilt: Double = 0, squash: Double = 1,
                face: EyeFace? = nil, mouthOpen: Bool = false) {
        self.hop = hop; self.tilt = tilt; self.hatLift = hatLift; self.hatTilt = hatTilt
        self.squash = squash; self.face = face; self.mouthOpen = mouthOpen
    }

    public static let maxTilt = 0.3

    /// Version « mouvements réduits » (réglage d'accessibilité) : seule l'expression change.
    public var reducedMotion: ReactionPose { ReactionPose(face: face, mouthOpen: mouthOpen) }
}

/// Pose de la réaction `r`, `elapsed` secondes après son déclenchement. nil avant 0 et après `r.duration`.
/// Fonction pure et déterministe (la vue la recalcule à chaque image du TimelineView parent, aucun minuteur).
public func reactionPose(_ r: MascotReaction, elapsed t: Double) -> ReactionPose? {
    guard t.isFinite, t >= 0, t < r.duration else { return nil }
    var p = ReactionPose()
    switch r {
    case .bought:
        let j = jump(t, start: 0.08, air: 0.32, height: 0.45)
        p.hop = j.hop; p.squash = 1 + j.squash
        // soulève la casquette, la tient, la repose puis elle se cale (petite oscillation amortie)
        let lift = smoothstep(0.12, 0.38, t) * (1 - smoothstep(0.66, 0.92, t))
        p.hatLift = lift
        p.hatTilt = -0.22 * lift + 0.07 * settle((t - 0.88) / 0.3, freq: 1.5)
        p.tilt = 0.05 * bump((t - 0.1) / 0.9)
    case .soldWin:
        let a = jump(t, start: 0.08, air: 0.34, height: 0.8)
        let b = jump(t, start: 0.62, air: 0.3, height: 0.55)
        p.hop = a.hop + b.hop; p.squash = 1 + a.squash + b.squash
        let lag = jump(t - 0.05, start: 0.08, air: 0.34, height: 0.8).hop + jump(t - 0.05, start: 0.62, air: 0.3, height: 0.55).hop
        p.hatLift = 0.3 * lag   // le chapeau « flotte » un instant quand le corps redescend
        p.tilt = 0.1 * sin(2 * .pi * t / 0.55) * bump(t / r.duration)
        p.hatTilt = 0.5 * p.tilt
        p.face = .closed        // yeux en arcs ^^ : content
        p.mouthOpen = true
    case .soldLoss:
        let s = smoothstep(0, 0.35, t) * (1 - smoothstep(0.85, 1.2, t))
        p.squash = 1 - 0.08 * s
        p.tilt = 0.12 * s
        p.hatTilt = 0.15 * s    // le chapeau glisse de travers
        p.face = t < 0.5 ? .worried : .sleepy
    case .spotted:
        let j = jump(t, start: 0.08, air: 0.22, height: 0.3)
        p.hop = j.hop; p.squash = 1 + j.squash
        p.hatLift = 0.3 * jump(t - 0.04, start: 0.08, air: 0.22, height: 0.3).hop
        p.tilt = 0.14 * sin(2 * .pi * t / 0.45) * bump(t / r.duration)   // coup d'œil gauche-droite
        p.face = .wide
    case .signalGreen:
        let j = jump(t, start: 0.08, air: 0.30, height: 0.55)
        p.hop = j.hop; p.squash = 1 + j.squash
        p.tilt = 0.08 * sin(2 * .pi * t / 0.4) * bump(t / r.duration)
        p.face = .open
        p.mouthOpen = true
    case .signalRed:
        // sursaut puis tremblement : il a peur
        p.squash = 1 + 0.05 * smoothstep(0, 0.12, t) * (1 - smoothstep(0.4, 0.9, t))
        p.tilt = 0.06 * sin(2 * .pi * t / 0.35) * bump(t / r.duration)
        p.hop = 0.25 * jump(t, start: 0.04, air: 0.16, height: 1).hop
        p.face = .worried
    }
    p.hop = clamp(p.hop, 0, 1)
    p.hatLift = clamp(p.hatLift, 0, 1)
    p.squash = clamp(p.squash, 0.9, 1.1)
    p.tilt = clamp(p.tilt, -ReactionPose.maxTilt, ReactionPose.maxTilt)
    p.hatTilt = clamp(p.hatTilt, -ReactionPose.maxTilt, ReactionPose.maxTilt)
    return p
}

// MARK: courbes (toutes continues, nulles aux bords)

/// Un saut façon ressort : accroupi (0,08 s) → vol en parabole (étiré) → atterrissage écrasé qui rebondit et se calme (0,25 s).
/// Renvoie la hauteur (0…height) et l'écart d'écrasement (à ajouter à 1).
private func jump(_ t: Double, start: Double, air: Double, height: Double) -> (hop: Double, squash: Double) {
    let crouch = 0.08, land = 0.25
    if t >= start - crouch && t < start {
        return (0, -0.06 * sin(.pi * (t - (start - crouch)) / crouch))
    }
    if t >= start && t < start + air {
        let u = (t - start) / air
        return (height * 4 * u * (1 - u), 0.05 * height * sin(.pi * u))
    }
    if t >= start + air && t < start + air + land {
        return (0, -0.07 * settle((t - start - air) / land, freq: 1.2))
    }
    return (0, 0)
}

/// Oscillation amortie sur u ∈ [0, 1] : 0 au début, 0 à la fin, 0 en dehors.
private func settle(_ u: Double, freq: Double) -> Double {
    guard u > 0, u < 1 else { return 0 }
    return exp(-2.5 * u) * sin(2 * .pi * freq * u) * (1 - u)
}

/// Bosse douce sur u ∈ [0, 1] (0 aux bords et en dehors).
private func bump(_ u: Double) -> Double { u <= 0 || u >= 1 ? 0 : sin(.pi * u) }

private func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
    let u = clamp((x - a) / (b - a), 0, 1)
    return u * u * (3 - 2 * u)
}

private func clamp(_ x: Double, _ lo: Double, _ hi: Double) -> Double { min(max(x, lo), hi) }

// MARK: bus de réactions (le reste de l'app appelle `fire`, les vues lisent `current`)

/// Dernière réaction déclenchée. Pas de minuteur : les vues calculent la pose à partir de la date de leur TimelineView.
@MainActor @Observable
public final class MascotReactions {
    public private(set) var current: (MascotReaction, Date)?

    public init() {}

    /// Déclenche une réaction (remplace celle en cours).
    public func fire(_ r: MascotReaction, at date: Date = Date()) { current = (r, date) }

    /// La réaction dont l'émotion est encore affichée à `date` (jusqu'à `emoteDuration`), sinon nil. Le mouvement du corps, lui, s'arrête à `duration`.
    public func activeEmote(at date: Date) -> (MascotReaction, Date)? {
        guard let (r, start) = current else { return nil }
        let e = date.timeIntervalSince(start)
        return e >= 0 && e < r.emoteDuration ? (r, start) : nil
    }

    /// La réaction encore en cours à `date`, sinon nil.
    public func active(at date: Date) -> (MascotReaction, Date)? {
        guard let (r, start) = current else { return nil }
        let e = date.timeIntervalSince(start)
        return e >= 0 && e < r.duration ? (r, start) : nil
    }
}
