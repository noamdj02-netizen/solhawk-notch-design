import Foundation

/// Petite ligne d'état à côté de la mascotte + couleur de son point : ce qui se passe, en quelques mots.
/// Jamais un conseil de trade : « passe les filtres » ne veut pas dire « sûr ». Les ventes et achats sont FICTIFS.
public struct MascotStatus: Equatable, Sendable {
    public enum Dot: Sendable { case none, gray, green, red, blue }
    public var dot: Dot
    public var text: String
    public init(dot: Dot, text: String) { self.dot = dot; self.text = text }
}

/// Réaction en cours d'abord (elle dure quelques secondes), puis les pannes, puis la couleur de la barre, puis l'humeur.
public func mascotStatus(mood: Mood, signal: BarSignal, reaction: MascotReaction?) -> MascotStatus {
    if let reaction {
        switch reaction {
        case .bought: return MascotStatus(dot: .blue, text: "Achat fictif passé")
        case .soldWin: return MascotStatus(dot: .green, text: "Vente fictive : gain")
        case .soldLoss: return MascotStatus(dot: .red, text: "Vente fictive : perte")
        case .spotted: return MascotStatus(dot: .green, text: "Nouveau token repéré")
        case .signalGreen: return MascotStatus(dot: .green, text: "Un token passe les filtres")
        case .signalRed: return MascotStatus(dot: .red, text: "Attention : forte chute ou panne")
        }
    }
    switch mood {
    case .offline: return MascotStatus(dot: .red, text: "Serveur injoignable")
    case .tokenRejected: return MascotStatus(dot: .red, text: "Jeton refusé")
    case .badConfig: return MascotStatus(dot: .red, text: "Adresse à corriger")
    case .rateLimited: return MascotStatus(dot: .blue, text: "Trop de requêtes, pause")
    case .stale: return MascotStatus(dot: .gray, text: "Données anciennes")
    case .waiting: return MascotStatus(dot: .gray, text: "Lecture en cours")
    case .spotted: return MascotStatus(dot: .green, text: "Nouveau token")
    case .calm(let n):
        switch signal {
        case .green: return MascotStatus(dot: .green, text: "Un token passe les filtres")
        case .red: return MascotStatus(dot: .red, text: "Un token chute fort")
        case .yellow: return MascotStatus(dot: .gray, text: "À vérifier")
        case .none: return MascotStatus(dot: .none, text: n == 0 ? "Rien à signaler" : "\(n) token\(n > 1 ? "s" : "") en vue")
        }
    }
}
