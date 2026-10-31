import Foundation

/// Ce que le personnage exprime. Pas de « tout va bien » sans donnée fraîche et lue.
public enum Mood: Sendable, Equatable {
    case waiting                 // pas encore de donnée
    case calm(listed: Int)       // donnée fraîche ; 0 listé est un état normal, pas un feu vert
    case spotted(passes: Bool)   // un NOUVEAU token listé ; passes = passe les filtres (sinon à vérifier)
    case stale(ageS: Int)        // flux serveur périmé
    case offline                 // injoignable / erreur réseau
    case tokenRejected           // 401/403 : on arrête d'interroger
    case badConfig               // adresse refusée (HTTPS obligatoire) : on n'envoie rien
    case rateLimited(retryS: Int)
}

public struct MoodInput: Sendable {
    public var feed: Feed?
    public var feedReceivedAt: Date?
    public var newItems: [Feed.Item]
    public var lastError: FetchFailure?
    public var now: Date
    public init(feed: Feed?, feedReceivedAt: Date?, newItems: [Feed.Item], lastError: FetchFailure?, now: Date) {
        self.feed = feed; self.feedReceivedAt = feedReceivedAt; self.newItems = newItems; self.lastError = lastError; self.now = now
    }
}

public let staleAfterS: TimeInterval = 60   // le serveur réécrit le flux toutes les ~2 s

public func mood(_ i: MoodInput) -> Mood {
    switch i.lastError {
    case .network(let why)? where why == "configuration": return .badConfig
    case .unauthorized?: return .tokenRejected
    case .rateLimited(let s)?: return .rateLimited(retryS: s)
    case .network?, .server?, .badResponse?: if i.feed == nil || i.feedReceivedAt.map({ i.now.timeIntervalSince($0) > staleAfterS }) ?? true { return .offline }
    case nil: break
    }
    guard let feed = i.feed else { return .waiting }
    let ref = feed.updatedAt ?? i.feedReceivedAt
    if let ref, i.now.timeIntervalSince(ref) > staleAfterS { return .stale(ageS: Int(i.now.timeIntervalSince(ref))) }
    if let first = i.newItems.first { return .spotted(passes: i.newItems.allSatisfy { status(of: $0) == .passesFilters } && status(of: first) == .passesFilters) }
    return .calm(listed: feed.stats.listed ?? feed.items.count)
}
