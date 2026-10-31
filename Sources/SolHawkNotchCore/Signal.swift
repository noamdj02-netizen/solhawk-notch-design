import Foundation

/// Couleur de la barre repliée. Elle résume l'état d'un coup d'œil ; elle ne dit jamais « sûr » ni « achète ».
public enum BarSignal: Sendable, Equatable {
    case none
    case yellow   // un token récent est listé mais « à vérifier »
    case green    // un token récent passe les filtres (≠ sûr)
    case red      // un token listé chute fort depuis son pic, ou panne (hors ligne / jeton refusé)
}

public let signalMaxAgeS = 600          // au-delà de 10 min, un token n'allume plus la barre
public let signalDumpPct: Double = -40  // chute depuis le pic qui allume le rouge

/// Le signal affiché et le token à mettre en avant à l'ouverture (nil pour une panne ou aucun signal).
/// Priorité : rouge > vert > jaune. Un « non lu » (âge ou écart absent) n'allume jamais le vert.
public func barSignal(feed: Feed?, mood: Mood) -> (signal: BarSignal, mint: String?) {
    switch mood {
    case .offline, .tokenRejected, .badConfig: return (.red, nil)
    case .waiting: return (.none, nil)
    default: break
    }
    let recent = (feed?.items ?? []).filter { ($0.ageS ?? Int.max) <= signalMaxAgeS }
    if let d = recent.first(where: { ($0.fromPeakPct ?? 0) <= signalDumpPct }) { return (.red, d.mint) }
    if let g = recent.first(where: { status(of: $0) == .passesFilters }) { return (.green, g.mint) }
    if let y = recent.first { return (.yellow, y.mint) }
    return (.none, nil)
}

/// Visite guidée du premier lancement : courte, simple, sans promesse.
public struct TourStep: Sendable, Equatable {
    public var title: String
    public var text: String
}

public let tourSteps: [TourStep] = [
    TourStep(title: "Salut !", text: "Je surveille les nouveaux tokens pour toi. Je lis seulement : aucun achat réel, aucune clé, rien n'est envoyé."),
    TourStep(title: "La barre qui brille", text: "Vert qui clignote : un token passe les filtres. Jaune : un token à vérifier. Rouge : un token chute fort, ou une panne. « Passe les filtres » ne veut pas dire sûr."),
    TourStep(title: "Un clic, le tiroir", text: "Clique sur la barre : le tiroir s'ouvre sur le token qui brille. Clique en dehors pour le refermer."),
    TourStep(title: "Une carte = un token", text: "Market cap, SOL réels, âge, et 5 pastilles : autorité mint, freeze, créateur, volume, détenteurs. Dessous, la vraie courbe. Pas de courbe = pas encore d'historique."),
    TourStep(title: "À toi de jouer", text: "Boutons ronds : copier l'adresse, ouvrir DexScreener. Entonnoir : pourquoi des tokens sont écartés. Alertes : ce qui a sonné. Raccourci Ctrl+Option+Espace pour ouvrir. Clique sur moi pour changer de personnage."),
    TourStep(title: "Simulation", text: "« Acheter » sur une carte = achat FICTIF, rempli au prix lu quelques secondes plus tard, frais estimés compris. Trades : ton historique. Robots : des stratégies connues face à un témoin au hasard. Rien de réel, aucune promesse."),
]
