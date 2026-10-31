import SwiftUI
import SolHawkNotchCore

/// Montage du rig Hawky : PNG 3D (HawkyPeek) + iris SwiftUI dans le même cadre, ou visage procédural.
struct HawkyRenderer: View {
    var mood: Mood
    var look: CGPoint
    var date: Date
    var hop: Double = 0
    var sinceSpottedS: Double = 99
    var reaction: MascotReaction? = nil
    var sinceAppearS: Double = 99
    /// Secondes depuis le début de la réaction en cours (pour les étoiles, larmes…), nil si on ne sait pas.
    var reactionAge: Double? = nil

    @State private var hoverLook: CGPoint?
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { g in
            let size = g.size
            let cursor = resolvedLook
            let snap = HawkyAnimationEngine.snapshot(
                mood: mood, look: cursor, date: date, hop: hop,
                sinceSpottedS: sinceSpottedS, reaction: reaction,
                sinceAppearS: sinceAppearS, hovering: hovering, reduceMotion: reduceMotion
            )
            ZStack {
                HawkyStage(
                    expression: snap.expression, pose: snap.pose,
                    leftLook: snap.leftLook, rightLook: snap.rightLook, date: date,
                    age: reduceMotion ? nil : (HawkyAnimationEngine.forcedAge() ?? reactionAge)
                )
                .aspectRatio(HawkyLayout.peekAspect, contentMode: .fit)
                .frame(width: size.width, height: size.height, alignment: .bottom)
            }
            .scaleEffect(x: 1, y: snap.breath, anchor: .bottom)
            .rotationEffect(.degrees(snap.tilt), anchor: .bottom)
            .offset(y: snap.rise * HawkyLayout.scale(in: size) + snap.bob * HawkyLayout.scale(in: size))
            .opacity(snap.opacity)
            .animation(reduceMotion ? nil : HawkyAnimationEngine.headSpring, value: snap.tilt)
            .onContinuousHover { phase in
                switch phase {
                case .active(let p):
                    hovering = true
                    let origin = HawkyLayout.origin(in: size)
                    let s = max(HawkyLayout.scale(in: size), 1)
                    let dx = (p.x - origin.x) / (s * 0.32)
                    let dy = (p.y - origin.y) / (s * 0.32)
                    hoverLook = HawkyLook.clamp(CGPoint(x: dx, y: dy), maxR: 0.95)
                case .ended:
                    hovering = false
                    hoverLook = nil
                }
            }
        }
        .onHover { hovering = $0 }
        .scaleEffect(hovering && !reduceMotion ? 1.04 : 1, anchor: .bottom)
        .animation(HawkyAnimationEngine.headSpring, value: hovering)
        .accessibilityLabel(describe(mood))
    }

    private var resolvedLook: CGPoint {
        if let forced = HawkyAnimationEngine.forcedLook() { return forced }
        if reduceMotion { return .zero }
        if let hoverLook { return hoverLook }
        return look
    }
}
