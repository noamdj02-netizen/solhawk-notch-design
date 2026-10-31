import Foundation
import Observation

/// Sondage du flux. LECTURE SEULE. S'arrête au premier 401 (voir PollPolicy) ; reprend quand le jeton change.
@MainActor @Observable
public final class FeedStore {
    public private(set) var feed: Feed?
    public private(set) var receivedAt: Date?
    public private(set) var lastError: FetchFailure?
    public private(set) var tracker = FeedTracker()
    /// Journal des alertes de cette session (les plus récentes d'abord, 40 max). Pas écrit sur disque.
    public private(set) var alertLog: [(at: Date, alert: NotchAlert)] = []
    /// Appelé pour chaque nouvelle alerte (notification, son, ouverture du tiroir).
    public private(set) var alertTotal = 0   // nombre d'alertes depuis le lancement (pastille « non lues »)
    @ObservationIgnored public var onAlert: (@MainActor ([NotchAlert]) -> Void)?
    /// Appelé à chaque flux reçu (alimente le laboratoire fictif).
    @ObservationIgnored public var onFeed: (@MainActor (Feed, Date) -> Void)?
    @ObservationIgnored private var engine = AlertEngine()

    @ObservationIgnored private var policy = PollPolicy()
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let makeClient: @Sendable () throws -> FeedClient
    @ObservationIgnored private let clock: @Sendable () -> Date

    public init(makeClient: @escaping @Sendable () throws -> FeedClient, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.makeClient = makeClient; self.clock = clock
    }

    public func start() {
        guard task == nil else { return }
        task = Task { [weak self] in await self?.loop() }
    }

    public func stop() { task?.cancel(); task = nil }

    /// Client pour les autres lectures (wallets) : même adresse, même jeton. nil si la configuration est invalide.
    public func client() -> FeedClient? { try? makeClient() }

    /// Appelé quand l'utilisateur enregistre un nouveau jeton ou une nouvelle adresse.
    public func configurationChanged() {
        stop(); policy.resume(); lastError = nil; start()
    }

    public func mood(now: Date) -> Mood {
        Self.compute(feed: feed, receivedAt: receivedAt, tracker: tracker, error: lastError, now: now)
    }

    nonisolated static func compute(feed: Feed?, receivedAt: Date?, tracker: FeedTracker, error: FetchFailure?, now: Date) -> Mood {
        SolHawkNotchCore.mood(MoodInput(feed: feed, feedReceivedAt: receivedAt, newItems: tracker.activeSpotted(now: now), lastError: error, now: now))
    }

    func pollOnce() async {
        let client: FeedClient
        do { client = try makeClient() } catch { lastError = .network("configuration"); policy.record(.failure(.network("configuration"))); return }
        switch await client.fetchFeed() {
        case .success(let f):
            let now = clock()
            feed = f; receivedAt = now; lastError = nil
            tracker.ingest(f, now: now)
            policy.record(.success(()))
            onFeed?(f, now)
            raise(now: now)
        case .failure(let e):
            lastError = e
            policy.record(.failure(e))
            raise(now: clock())
        }
    }

    private func raise(now: Date) {
        let fresh = engine.evaluate(feed: feed, mood: mood(now: now))
        guard !fresh.isEmpty else { return }
        alertTotal += fresh.count
        alertLog = Array((fresh.map { (now, $0) } + alertLog).prefix(40))
        onAlert?(fresh)
    }

    private func loop() async {
        while !Task.isCancelled {
            await pollOnce()
            guard let d = policy.nextDelayS else { task = nil; return }   // 401 : on s'arrête
            try? await Task.sleep(for: .seconds(d))
        }
    }
}
