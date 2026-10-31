import Foundation

/// Quand interroger. Règle de sécurité : après un 401, ON S'ARRÊTE (sinon on déclenche le blocage 5 min du serveur
/// pour toute la machine : plugin et 3e écran compris). Reprise seulement quand l'utilisateur donne un nouveau jeton.
public struct PollPolicy: Sendable, Equatable {
    public var baseIntervalS: Double = 5
    public var maxBackoffS: Double = 120
    public private(set) var stopped = false
    private var failures = 0
    private var holdS: Double = 0

    public init() {}

    public mutating func record(_ result: Result<Void, FetchFailure>) {
        switch result {
        case .success: failures = 0; holdS = 0
        case .failure(.unauthorized): stopped = true
        case .failure(.rateLimited(let s)): holdS = Double(s)
        case .failure: failures += 1; holdS = 0
        }
    }

    public mutating func resume() { stopped = false; failures = 0; holdS = 0 }

    /// Délai avant le prochain appel ; nil = ne plus interroger.
    public var nextDelayS: Double? {
        if stopped { return nil }
        if holdS > 0 { return holdS + 1 }
        return min(maxBackoffS, baseIntervalS * pow(2, Double(min(failures, 6))))
    }
}
