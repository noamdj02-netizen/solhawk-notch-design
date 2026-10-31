import Foundation

/// « Passe les filtres » n'est PAS « sûr ». Un feu non vert ou inconnu n'est jamais compté comme bon.
public enum ItemStatus: Sendable, Equatable {
    case passesFilters   // 5 feux verts ET risque « faible »
    case toCheck         // au moins un feu orange / inconnu, ou risque non faible / non lu
}

public func status(of item: Feed.Item) -> ItemStatus {
    guard let lights = item.lights, lights.all.count == 5, lights.all.allSatisfy({ $0 == "green" }) else { return .toCheck }
    return item.risk?.label?.lowercased() == "faible" ? .passesFilters : .toCheck
}
