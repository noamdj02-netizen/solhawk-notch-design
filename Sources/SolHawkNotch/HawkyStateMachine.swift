import Foundation
import SolHawkNotchCore

/// Phases d'entrée et d'expression. Délègue au cœur testé (`HawkyEntryMotion`).
enum HawkyStateMachine {
    static func entry(elapsed: Double) -> HawkyEntry {
        HawkyEntryMotion.phase(elapsed: elapsed)
    }
}
