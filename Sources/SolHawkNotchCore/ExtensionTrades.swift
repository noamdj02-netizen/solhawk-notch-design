import Foundation

// Lignes de SIMULATION de l'extension Chrome (panneau « mise fictive »), relues en GET sur /api/companion/paper-sync.
// Portefeuille fictif SÉPARÉ de celui de l'app (SOL, pas USD) : jamais mélangé à PaperBook. Aucun ordre, aucune écriture, rien n'est envoyé.
// Données NON FIABLES : mint validé, nombres finis, tailles bornées, textes passés par safeLabel à l'affichage.

public enum ExtensionLimits {
    public static let maxTrades = 500
    public static let maxPositions = 20
}

public struct ExtensionTrade: Decodable, Sendable, Equatable, Identifiable {
    public var t: Double                // millisecondes depuis 1970
    public var side: String             // « buy » ou « sell » seulement
    public var mint: String
    public var symbol: String?
    public var sol: Double              // SOL payés (achat) ou reçus nets (vente)
    public var mc: Double               // market cap lu au remplissage
    public var slipPct: Double?
    public var costSol: Double          // coûts ESTIMÉS (frais, priorité, glissement)
    public var realizedSol: Double?     // vente seulement : net reçu − part du coût d'entrée
    public var id: String { "\(Int(t))-\(side)-\(mint)" }
    public var isBuy: Bool { side == "buy" }
    public var date: Date { Date(timeIntervalSince1970: t / 1000) }

    public init(t: Double, side: String, mint: String, symbol: String? = nil, sol: Double, mc: Double, slipPct: Double? = nil, costSol: Double = 0, realizedSol: Double? = nil) {
        self.t = t; self.side = side; self.mint = mint; self.symbol = symbol; self.sol = sol; self.mc = mc; self.slipPct = slipPct; self.costSol = costSol; self.realizedSol = realizedSol
    }

    /// Une ligne n'est gardée que si tout est lisible, fini et plausible.
    var isSane: Bool {
        (side == "buy" || side == "sell") && isValidMint(mint) && [t, sol, mc, costSol].allSatisfy { $0.isFinite && $0 >= 0 } && mc > 0
            && (slipPct ?? 0).isFinite && (realizedSol ?? 0).isFinite
    }
}

public struct ExtensionPosition: Decodable, Sendable, Equatable, Identifiable {
    public var mint: String
    public var symbol: String?
    public var basisSol: Double
    public var units: Double
    public var openedAt: Double?
    public var id: String { mint }
    public init(mint: String, symbol: String? = nil, basisSol: Double, units: Double, openedAt: Double? = nil) {
        self.mint = mint; self.symbol = symbol; self.basisSol = basisSol; self.units = units; self.openedAt = openedAt
    }
    var isSane: Bool { isValidMint(mint) && basisSol.isFinite && units.isFinite && basisSol >= 0 && units >= 0 }

    /// Valeur brute (avant coûts de sortie) = unités × market cap lu. nil si aucun prix lu : « non lu », jamais une valeur inventée.
    public func grossValueSol(mc: Double?) -> Double? {
        guard let mc, mc.isFinite, mc > 0 else { return nil }
        let v = units * mc
        return v.isFinite ? v : nil
    }
}

public struct ExtensionSnapshot: Decodable, Sendable, Equatable {
    public var positions: [ExtensionPosition]
    public var balance: Double
    public var startSol: Double
    public var costsPaid: Double
    public var at: Double?
    public init(positions: [ExtensionPosition] = [], balance: Double, startSol: Double, costsPaid: Double = 0, at: Double? = nil) {
        self.positions = positions; self.balance = balance; self.startSol = startSol; self.costsPaid = costsPaid; self.at = at
    }
    enum CodingKeys: String, CodingKey { case positions, balance, startSol, costsPaid, at }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        balance = try c.decode(Double.self, forKey: .balance)
        startSol = try c.decode(Double.self, forKey: .startSol)
        costsPaid = (try? c.decodeIfPresent(Double.self, forKey: .costsPaid)) ?? 0
        at = (try? c.decodeIfPresent(Double.self, forKey: .at)) ?? nil
        // une position illisible est ignorée sans faire échouer le reste
        positions = (((try? c.decodeIfPresent([Failable<ExtensionPosition>].self, forKey: .positions)) ?? nil) ?? []).compactMap { $0.value }
    }
}

private struct Failable<T: Decodable>: Decodable { let value: T?; init(from d: Decoder) throws { value = try? T(from: d) } }

/// Totaux en SOL tirés des lignes reçues. Gain/perte RÉALISÉ seulement (ventes) ; les positions ouvertes sont valorisées à part, si un prix est lu.
public struct ExtensionSummary: Sendable, Equatable {
    public var buys = 0
    public var sells = 0
    public var wins = 0
    public var realizedSol = 0.0
    public var costsSol = 0.0
    public var winRate: Double? { sells > 0 ? Double(wins) / Double(sells) * 100 : nil }
}

public struct PaperSyncReply: Decodable, Sendable, Equatable {
    public var trades: [ExtensionTrade]       // du plus récent au plus ancien
    public var snapshot: ExtensionSnapshot?
    public var note: String?

    public init(trades: [ExtensionTrade] = [], snapshot: ExtensionSnapshot? = nil, note: String? = nil) {
        self.trades = trades; self.snapshot = snapshot; self.note = note
    }

    enum CodingKeys: String, CodingKey { case trades, snapshot, note }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        note = try? c.decodeIfPresent(String.self, forKey: .note)
        let raw = ((try? c.decodeIfPresent([Failable<ExtensionTrade>].self, forKey: .trades)) ?? nil) ?? []
        // une ligne illisible ou invalide est ignorée ; au plus 500 lignes, les plus récentes d'abord
        trades = Array(raw.compactMap { $0.value }.filter { $0.isSane }.sorted { $0.t > $1.t }.prefix(ExtensionLimits.maxTrades))
        if var s = (try? c.decodeIfPresent(ExtensionSnapshot.self, forKey: .snapshot)) ?? nil, s.balance.isFinite, s.startSol.isFinite, s.startSol > 0 {
            s.positions = Array(s.positions.filter { $0.isSane }.prefix(ExtensionLimits.maxPositions))
            snapshot = s
        } else {
            snapshot = nil
        }
    }

    public var isEmpty: Bool { trades.isEmpty && (snapshot?.positions.isEmpty ?? true) }

    public var summary: ExtensionSummary {
        var s = ExtensionSummary()
        for t in trades {
            s.costsSol += t.costSol
            if t.isBuy { s.buys += 1 } else {
                s.sells += 1
                if let r = t.realizedSol { s.realizedSol += r; if r > 0 { s.wins += 1 } }
            }
        }
        return s
    }
}
