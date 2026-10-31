import Foundation

/// Étiquettes de mon journal : mes propres mots pour classer un trade fictif. Aucune n'est un conseil.
public enum JournalTag: String, CaseIterable, Sendable {
    case discipline = "Discipline", fomo = "FOMO", tropTard = "Trop tard", sortieTropTot = "Sorti trop tôt", bonneIdee = "Bonne idée", chance = "Chance"

    /// Texte libre : une seule ligne de contrôle retirée, 500 caractères au plus.
    public static func clean(_ s: String) -> String {
        let kept = s.unicodeScalars.filter { ($0.value >= 32 && $0.value != 127) || $0 == "\n" }
        return String(String.UnicodeScalarView(kept)).trimmingCharacters(in: .whitespacesAndNewlines).prefix(500).description
    }
}

public enum TradeExport {
    /// Protège une cellule : guillemets doublés, et une cellule qui commence par = + - @ (ou tabulation) reçoit une apostrophe,
    /// sinon un tableur l'exécuterait comme une formule (le symbole d'un token vient du réseau : non fiable).
    static func cell(_ s: String) -> String {
        var v = s.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
        if let f = v.first, "=+-@\t".contains(f) { v = "'" + v }
        return "\"" + v.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    static func num(_ v: Double, _ digits: Int = 2) -> String { v.isFinite ? String(format: "%.\(digits)f", v) : "" }

    /// CSV de trades fictifs (tous les montants en $ fictifs). Les trades ouverts ont une sortie vide.
    public static func csv(_ rows: [(owner: String, trade: PaperTrade)]) -> String {
        let iso = ISO8601DateFormatter()
        var out = ["proprietaire,symbole,mint,ouvert,ferme,duree_s,mise_usd,entree_mcap,sortie_mcap,sommet_mcap,frais_usd,net_usd,net_pct,raison_entree,raison_sortie,etiquette,note"]
        for (owner, t) in rows.sorted(by: { $0.trade.openedAt < $1.trade.openedAt }) {
            out.append([
                cell(owner), cell(t.symbol), cell(t.mint), iso.string(from: t.openedAt), t.closedAt.map { iso.string(from: $0) } ?? "",
                num(t.holdS, 0), num(t.stakeUSD), num(t.entryMcap, 0), t.exitMcap.map { num($0, 0) } ?? "", num(t.peakMcap, 0),
                num(t.costsUSD), num(t.pnlUSD), num(t.pnlPct, 1), cell(t.entryReason), cell(t.exitReason ?? ""), cell(t.tag ?? ""), cell(t.journal ?? "")
            ].joined(separator: ","))
        }
        return out.joined(separator: "\n") + "\n"
    }
}
