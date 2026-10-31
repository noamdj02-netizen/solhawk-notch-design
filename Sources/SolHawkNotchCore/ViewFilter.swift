import Foundation

/// Filtres d'AFFICHAGE du Terminal (rien à voir avec les filtres du serveur) : ils ne changent que ce que tu vois.
/// 0 = pas de limite. Une valeur non lue (nil) ne passe jamais un filtre actif : « non lu » n'est pas « bon ».
public struct ViewFilter: Equatable, Sendable {
    public var minMcap: Double = 0
    public var maxMcap: Double = 0
    public var minSol: Double = 0
    public var maxAgeMin: Double = 0
    public init(minMcap: Double = 0, maxMcap: Double = 0, minSol: Double = 0, maxAgeMin: Double = 0) {
        self.minMcap = minMcap; self.maxMcap = maxMcap; self.minSol = minSol; self.maxAgeMin = maxAgeMin
    }

    public var isActive: Bool { minMcap > 0 || maxMcap > 0 || minSol > 0 || maxAgeMin > 0 }

    public func passes(_ it: Feed.Item) -> Bool {
        if minMcap > 0 { guard let m = it.marketCap, m >= minMcap else { return false } }
        if maxMcap > 0 { guard let m = it.marketCap, m <= maxMcap else { return false } }
        if minSol > 0 { guard let s = it.realSol, s >= minSol else { return false } }
        if maxAgeMin > 0 { guard let a = it.ageS, Double(a) <= maxAgeMin * 60 else { return false } }
        return true
    }

    public func apply(_ items: [Feed.Item]) -> [Feed.Item] { isActive ? items.filter(passes) : items }
}
