import Foundation
import SolHawkNotchCore

/// Humeur métier → expression Hawky. Ne change pas le sens de Mood / Feed.
enum HawkyEmotionController {
    static func expression(
        mood: Mood,
        sinceSpottedS: Double,
        reaction: MascotReaction?,
        entry: HawkyEntry
    ) -> HawkyExpression {
        HawkyResolve.expression(mood: mood, sinceSpottedS: sinceSpottedS, reaction: reaction, entry: entry)
    }
}
