import SwiftUI
import SolHawkNotchCore

/// Point d'entrée historique : le faucon autocollant est remplacé par Hawky (character sheet).
struct HawkView: View {
    var mood: Mood
    var look: CGPoint
    var date: Date
    var hop: Double = 0
    var sinceSpottedS: Double = 99
    var reaction: MascotReaction? = nil
    var sinceAppearS: Double = 99
    var reactionAge: Double? = nil

    var body: some View {
        HawkyView(
            mood: mood, look: look, date: date, hop: hop,
            sinceSpottedS: sinceSpottedS, reaction: reaction, sinceAppearS: sinceAppearS, reactionAge: reactionAge
        )
    }

    static func blink(_ d: Date) -> Double { HawkyBlink.lid(at: d) }
}
