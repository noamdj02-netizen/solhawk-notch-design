import SwiftUI
import SolHawkNotchCore

/// Le personnage : Hawky (image de base + yeux dessinés en code, voir `HawkyStage`).
/// `reaction` : réaction en cours (voir `MascotReactions`) ; la pose du corps est recalculée à partir de `date`, sans minuteur.
struct MascotView: View {
    var mood: Mood
    var look: CGPoint
    var date: Date
    var hop: Double
    var sinceSpottedS: Double
    var reaction: (MascotReaction, Date)? = nil
    var sinceAppearS: Double = 99
    var dot: MascotStatus.Dot = .none

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Pose du corps pour cette image (mouvements réduits : seule l'expression change).
    private var pose: ReactionPose? {
        guard let (r, start) = reaction, let p = reactionPose(r, elapsed: date.timeIntervalSince(start)) else { return nil }
        return reduceMotion ? p.reducedMotion : p
    }

    var body: some View {
        GeometryReader { g in
            let s = min(g.size.width, g.size.height)
            let p = pose
            HawkView(mood: mood, look: look, date: date, hop: hop, sinceSpottedS: sinceSpottedS,
                     reaction: reaction?.0, sinceAppearS: sinceAppearS, reactionAge: reaction.map { date.timeIntervalSince($0.1) })
                .frame(width: g.size.width, height: g.size.height)
                .scaleEffect(x: 1 + (1 - (p?.squash ?? 1)) * 0.8, y: p?.squash ?? 1, anchor: .bottom)
                .rotationEffect(.radians(p?.tilt ?? 0), anchor: .bottom)
                .offset(y: -(p?.hop ?? 0) * s * 0.12)
        }
        .overlay(alignment: .topLeading) { StatusDot(dot: dot, date: date) }
        .accessibilityLabel(describe(mood))
    }
}

/// Petit point d'état sur la mascotte : vert (token qui passe les filtres, gain), rouge (chute, panne, perte), bleu (en cours), gris (en attente).
struct StatusDot: View {
    var dot: MascotStatus.Dot
    var date: Date
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let c = color {
            let pulse = reduceMotion || dot == .gray ? 0 : 0.5 + 0.5 * sin(date.timeIntervalSinceReferenceDate * 4)
            GeometryReader { g in
                let d = max(5, min(g.size.width, g.size.height) * 0.14)
                Circle().fill(c).frame(width: d, height: d)
                    .overlay(Circle().stroke(.black.opacity(0.55), lineWidth: 1))
                    .shadow(color: c.opacity(0.35 + 0.5 * pulse), radius: 2 + 3 * pulse)
                    .offset(x: g.size.width * 0.04, y: g.size.height * 0.04)
            }
            .allowsHitTesting(false).accessibilityHidden(true)
        }
    }

    private var color: Color? {
        switch dot {
        case .none: return nil
        case .gray: return Color(white: 0.55)
        case .green: return Color(red: 0.2, green: 0.85, blue: 0.5)
        case .red: return Color(red: 0.95, green: 0.3, blue: 0.3)
        case .blue: return Color(red: 0.35, green: 0.6, blue: 1.0)
        }
    }
}
