import Foundation

// Wallets SUIVIS : adresses publiques et étiquettes fournies par l'utilisateur (non vérifiées).
// Un wallet suivi qui achète n'est ni une recommandation ni une preuve de qualité.

public struct WalletSeen: Decodable, Sendable, Equatable {
    public var mint: String
    public var side: String?
    public var blockTime: Int?
    enum CodingKeys: String, CodingKey { case mint, side, blockTime = "block_time" }
}

public struct TrackedWalletRow: Decodable, Sendable, Equatable, Identifiable {
    public var address: String
    public var label: String?
    public var emoji: String?
    public var category: String?
    public var elite: Bool?
    public var influence: Int?
    public var recent: [WalletSeen]?
    // champs de la lecture par token
    public var buys: Int?
    public var sells: Int?
    public var received: Int?
    public var sent: Int?
    public var lastBlockTime: Int?
    public var id: String { address }
    enum CodingKeys: String, CodingKey {
        case address, label, emoji, category, elite, influence, recent, buys, sells, received, sent
        case lastBlockTime = "last_block_time"
    }
}

public struct WalletRegistry: Decodable, Sendable, Equatable {
    public var count: Int?
    public var elite: Int?
    public var error: String?
}

public struct WalletsReply: Decodable, Sendable, Equatable {
    public var registry: WalletRegistry?
    public var wallets: [TrackedWalletRow]?
}

public struct WalletActivity: Decodable, Sendable, Equatable {
    public var status: String?
    public var label: String?
    public var wallets: [TrackedWalletRow]?
    public var txRead: Int?
    enum CodingKeys: String, CodingKey { case status, label, wallets, txRead = "tx_read" }
}

public struct WalletActivityReply: Decodable, Sendable, Equatable {
    public var activity: WalletActivity?
}

/// Mouvement de token d'une adresse (échantillon récent : jamais un historique complet).
public struct WalletMove: Decodable, Sendable, Equatable, Identifiable {
    public var mint: String
    public var side: String?
    public var blockTime: Int?
    public var id: String { "\(mint)-\(blockTime ?? 0)-\(side ?? "")" }
    enum CodingKeys: String, CodingKey { case mint, side, blockTime = "block_time" }
}

public struct WalletRecent: Decodable, Sendable, Equatable {
    public var status: String?
    public var label: String?
    public var moves: [WalletMove]?
    public var txRead: Int?
    enum CodingKeys: String, CodingKey { case status, label, moves, txRead = "tx_read" }
}

public struct WalletRecentReply: Decodable, Sendable, Equatable {
    public var activity: WalletRecent?
}

public func shortAddress(_ a: String) -> String { a.count > 10 ? "\(a.prefix(4))…\(a.suffix(4))" : a }

public func categoryLabel(_ c: String?) -> String {
    switch c {
    case "trader": return "trader"
    case "dev": return "dev"
    case "exchange": return "plateforme d'échange"
    case "protocol": return "protocole"
    case "possible_mint": return "probablement un token"
    default: return "non classé"
    }
}

public func sideLabel(_ s: String?) -> String {
    switch s {
    case "BUY": return "achat"
    case "SELL": return "vente"
    case "RECEIVED": return "reçu sans l'avoir demandé"
    case "SENT": return "envoyé"
    default: return "mouvement indéterminé"
    }
}

/// Motif 5×5 symétrique dérivé de l'adresse (avatar généré : un wallet n'a pas de photo).
public func identicon(_ address: String) -> (cells: [Bool], hue: Double) {
    let h = stableHash(address)
    var cells = [Bool](repeating: false, count: 25)
    for row in 0..<5 { for col in 0..<3 {
        let on = (h >> UInt64(row * 3 + col)) & 1 == 1
        cells[row * 5 + col] = on; cells[row * 5 + (4 - col)] = on
    } }
    return (cells, Double((h >> 20) % 360) / 360)
}

/// Emoji fourni par l'utilisateur, nettoyé (court, sans caractères de contrôle). Vide = pas d'emoji.
public func safeEmoji(_ s: String?) -> String {
    guard let s else { return "" }
    let t = String(s.unicodeScalars.filter { !$0.properties.isDefaultIgnorableCodePoint || $0.value == 0x200D }.map(Character.init))
    return t.count <= 2 ? t : String(t.prefix(2))
}

/// Un achat ou une vente d'un wallet de MA liste, vu par le serveur (GET /api/companion/wallet-flow). Lecture seule.
public struct WalletFlowEvent: Decodable, Sendable, Equatable, Identifiable {
    public var address: String
    public var mint: String
    public var side: String            // « BUY » ou « SELL » seulement (le serveur ne renvoie pas le reste)
    public var signature: String?
    public var blockTime: Double?
    public var sol: Double?            // SOL qui ont bougé (frais compris) ; nil = non lu
    public var symbol: String?
    public var name: String?
    public var imageURL: String?
    public var imageAlts: [String]?
    public var id: String { "\(signature ?? "")-\(mint)-\(address)" }
    enum CodingKeys: String, CodingKey {
        case address, mint, side, signature, blockTime = "block_time", sol, symbol, name, imageURL = "image_url", imageAlts = "image_alts"
    }
    public init(address: String, mint: String, side: String, signature: String? = nil, blockTime: Double? = nil, sol: Double? = nil,
                symbol: String? = nil, name: String? = nil, imageURL: String? = nil, imageAlts: [String]? = nil) {
        self.address = address; self.mint = mint; self.side = side; self.signature = signature; self.blockTime = blockTime; self.sol = sol
        self.symbol = symbol; self.name = name; self.imageURL = imageURL; self.imageAlts = imageAlts
    }
    public var isBuy: Bool { side == "BUY" }
}

public struct WalletFlowReply: Decodable, Sendable, Equatable {
    public var status: String?
    public var events: [WalletFlowEvent]
    public var wallets: Int?
    public var unreadWallets: Int?
    public var note: String?
    public var error: String?          // motif court du serveur (http:429…), jamais d'URL

    public init(status: String? = nil, events: [WalletFlowEvent] = [], wallets: Int? = nil, unreadWallets: Int? = nil, note: String? = nil, error: String? = nil) {
        self.status = status; self.events = events; self.wallets = wallets; self.unreadWallets = unreadWallets; self.note = note; self.error = error
    }

    enum CodingKeys: String, CodingKey { case status, events, wallets, unreadWallets = "unread_wallets", note, error }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = try? c.decodeIfPresent(String.self, forKey: .status)
        wallets = try? c.decodeIfPresent(Int.self, forKey: .wallets)
        unreadWallets = try? c.decodeIfPresent(Int.self, forKey: .unreadWallets)
        note = try? c.decodeIfPresent(String.self, forKey: .note)
        error = (try? c.decodeIfPresent(String.self, forKey: .error)).flatMap { $0 }.map { String($0.filter { $0.isLetter || $0.isNumber || ":-_".contains($0) }.prefix(40)) }
        let raw = (try? c.decodeIfPresent([Failable].self, forKey: .events)) ?? nil
        // une ligne illisible, un mint ou une adresse invalide, ou un côté autre qu'achat/vente est ignoré
        events = (raw ?? []).compactMap { $0.value }.filter { isValidMint($0.mint) && isValidMint($0.address) && ($0.side == "BUY" || $0.side == "SELL") }
    }
    private struct Failable: Decodable { let value: WalletFlowEvent?; init(from d: Decoder) throws { value = try? WalletFlowEvent(from: d) } }

    /// Phrase d'état quand la liste est vide : dit pourquoi, sans inventer.
    public var emptyText: String {
        switch status {
        case "STARTING"?: return "Lecture en cours… (le serveur relit tes wallets toutes les 30 s)"
        case "RPC_NOT_CONFIGURED"?: return "Le serveur n'a pas de lecture de transactions (RPC non configuré)."
        case "UNAVAILABLE"?: return "Lecture des wallets impossible pour l'instant (source en panne\(error.map { ", motif : \($0)" } ?? "")). Nouvel essai en cours."
        case "NO_WALLETS"?: return "Aucun wallet à lire."
        default:
            if let u = unreadWallets, u > 0 { return "Aucun achat ni vente vu. \(u) wallet\(u > 1 ? "s" : "") pas encore lu\(u > 1 ? "s" : "")." }
            return "Aucun achat ni vente récent vu dans l'échantillon (les transactions neuves apparaissent ici toutes les 30 s)."
        }
    }
}

public extension Feed.Item {
    /// Un token vu dans le flux d'un wallet s'ouvre comme les autres (graphique, fiche) : rien d'inventé.
    init(flow e: WalletFlowEvent) {
        self.init(mint: e.mint, symbol: e.symbol, name: e.name, ageS: nil, marketCap: nil, realSol: nil, risk: nil, lights: nil, series: nil, fromPeakPct: nil)
        imageURL = e.imageURL; imageAlts = e.imageAlts
    }
}
