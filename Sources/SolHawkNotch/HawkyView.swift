import SwiftUI
import SolHawkNotchCore

/// Point d'entrée du personnage procédural : délègue au renderer (yeux séparés du visage).
struct HawkyView: View {
    var mood: Mood
    var look: CGPoint
    var date: Date
    var hop: Double = 0
    var sinceSpottedS: Double = 99
    var reaction: MascotReaction? = nil
    var sinceAppearS: Double = 99
    var reactionAge: Double? = nil

    var body: some View {
        HawkyRenderer(
            mood: mood, look: look, date: date, hop: hop,
            sinceSpottedS: sinceSpottedS, reaction: reaction, sinceAppearS: sinceAppearS, reactionAge: reactionAge
        )
    }
}
