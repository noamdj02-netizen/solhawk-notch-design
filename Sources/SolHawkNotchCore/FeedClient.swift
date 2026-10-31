import Foundation

public enum FetchFailure: Error, Sendable, Equatable {
    case unauthorized              // 401/403 : ne PAS réessayer (le limiteur du serveur bloque après 10 échecs)
    case rateLimited(retryS: Int)  // 429 : attendre retry_after_s
    case server(Int)
    case network(String)
    case badResponse
}

public struct HTTPReply: Sendable {
    public var status: Int
    public var body: Data
    public init(status: Int, body: Data) { self.status = status; self.body = body }
}

/// Transport injectable (tests sans réseau). Une seule méthode : GET.
public protocol HTTPTransport: Sendable {
    func get(_ url: URL, headers: [String: String]) async throws -> HTTPReply
}

public enum ConfigError: Error, Equatable { case insecureURL, badURL }

/// Client LECTURE SEULE : méthode GET uniquement, chemins sur liste blanche, jamais d'écriture ni d'ordre.
public struct FeedClient: Sendable {
    public static let allowedPaths: Set<String> = ["/api/companion/feed", "/api/companion/tracked-wallets", "/api/companion/live",
                                                   "/api/companion/screen", "/api/companion/token", "/api/companion/wallet-recent", "/api/companion/dropped", "/api/companion/wallet-flow", "/api/companion/paper-sync"]
    public let baseURL: URL
    private let transport: HTTPTransport
    private let tokenProvider: @Sendable () -> String?

    /// HTTPS obligatoire, sauf boucle locale (127.0.0.1 / localhost / ::1) pour les essais.
    public init(baseURL: URL, transport: HTTPTransport, tokenProvider: @escaping @Sendable () -> String?) throws {
        guard let host = baseURL.host, let scheme = baseURL.scheme?.lowercased() else { throw ConfigError.badURL }
        let local = ["127.0.0.1", "localhost", "::1"].contains(host)
        guard scheme == "https" || (scheme == "http" && local) else { throw ConfigError.insecureURL }
        self.baseURL = baseURL; self.transport = transport; self.tokenProvider = tokenProvider
    }

    public func fetchFeed() async -> Result<Feed, FetchFailure> { await get("/api/companion/feed") }

    /// Wallets suivis (adresses publiques et étiquettes données par l'utilisateur), sans lecture RPC.
    public func fetchWallets() async -> Result<WalletsReply, FetchFailure> { await get("/api/companion/tracked-wallets") }

    /// Wallets suivis vus dans les transactions récentes d'UN token (lecture RPC côté serveur, en cache 60 s). Mint validé.
    public func fetchWalletActivity(mint: String) async -> Result<WalletActivityReply, FetchFailure> {
        guard isValidMint(mint) else { return .failure(.badResponse) }
        return await get("/api/companion/tracked-wallets/\(mint)")
    }

    /// Ce qu'UNE adresse publique a fait récemment (lecture RPC côté serveur, cache 60 s). Adresse validée avant l'envoi.
    public func fetchWalletRecent(address: String) async -> Result<WalletRecentReply, FetchFailure> {
        guard isValidMint(address) else { return .failure(.badResponse) }
        return await get("/api/companion/wallet-recent/\(address)")
    }

    /// Achats et ventes récents des wallets de MA liste (adresses publiques, au plus 20, validées ; le serveur les relit toutes les 30 s).
    public func fetchWalletFlow(addresses: [String]) async -> Result<WalletFlowReply, FetchFailure> {
        let clean = Array(addresses.filter { isValidMint($0) }.prefix(20))
        guard !clean.isEmpty else { return .success(WalletFlowReply(status: "NO_WALLETS")) }
        return await get("/api/companion/wallet-flow", query: [URLQueryItem(name: "addresses", value: clean.joined(separator: ","))])
    }

    /// Lignes de SIMULATION de l'extension (GET seulement ; l'app n'écrit jamais là-bas).
    public func fetchPaperSync() async -> Result<PaperSyncReply, FetchFailure> { await get("/api/companion/paper-sync") }

    /// Colonnes du terminal (nouveaux, bientôt migrés, migrés) + runs, en une requête.
    public func fetchLive() async -> Result<LiveReply, FetchFailure> { await get("/api/companion/live") }

    /// Tokens écartés par les portes du serveur, avec la raison et ce qu'ils sont devenus (lecture seule).
    public func fetchDropped() async -> Result<DroppedReply, FetchFailure> { await get("/api/companion/dropped") }

    /// Bougies du market cap d'un token (intervalle en secondes : 1, 5, 15 ou 60). Mint validé.
    public func fetchScreen(mint: String, interval: Int) async -> Result<ScreenReply, FetchFailure> {
        guard isValidMint(mint), [1, 5, 15, 60].contains(interval) else { return .failure(.badResponse) }
        return await get("/api/companion/screen", query: [URLQueryItem(name: "mint", value: mint), URLQueryItem(name: "interval", value: String(interval))])
    }

    /// Fiche courte (autorités, dev, détenteurs, liens). Mint validé.
    public func fetchCard(mint: String) async -> Result<TokenCard, FetchFailure> {
        guard isValidMint(mint) else { return .failure(.badResponse) }
        return await get("/api/companion/token/\(mint)")
    }

    /// GET seulement, chemins sur liste blanche (un seul segment en plus, déjà validé, pour la lecture par token).
    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async -> Result<T, FetchFailure> {
        guard let token = tokenProvider(), !token.isEmpty else { return .failure(.unauthorized) }
        let root = path.split(separator: "/").prefix(3).joined(separator: "/")
        precondition(Self.allowedPaths.contains(path) || Self.allowedPaths.contains("/" + root))
        guard var comps = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { return .failure(.badResponse) }
        comps.path = path
        comps.queryItems = query.isEmpty ? nil : query
        guard let url = comps.url else { return .failure(.badResponse) }
        let reply: HTTPReply
        do { reply = try await transport.get(url, headers: ["X-SolHawk-Token": token, "Accept": "application/json"]) }
        catch { return .failure(.network(String(describing: type(of: error)))) }  // jamais le message complet : il pourrait contenir l'URL
        switch reply.status {
        case 200:
            do { return .success(try JSONDecoder().decode(T.self, from: reply.body)) } catch { return .failure(.badResponse) }
        case 401, 403: return .failure(.unauthorized)
        case 429:
            let s = (try? JSONSerialization.jsonObject(with: reply.body) as? [String: Any])?["retry_after_s"] as? Int
            return .failure(.rateLimited(retryS: max(1, s ?? 60)))
        default: return .failure(.server(reply.status))
        }
    }
}

/// Transport réel (URLSession). ATS standard : HTTPS ; http seulement vers la boucle locale (voir Info.plist de l'app).
public struct URLSessionTransport: HTTPTransport {
    public init() {}
    public func get(_ url: URL, headers: [String: String]) async throws -> HTTPReply {
        var req = URLRequest(url: url, timeoutInterval: 8)
        req.httpMethod = "GET"
        headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        let (data, resp) = try await URLSession(configuration: .ephemeral).data(for: req)
        return HTTPReply(status: (resp as? HTTPURLResponse)?.statusCode ?? 0, body: data)
    }
}
