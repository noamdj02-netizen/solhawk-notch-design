import Foundation

/// Recherche universelle (⌘K ou « / ») : pages, tokens listés, adresse collée, mots du glossaire.
public struct PaletteItem: Equatable, Sendable, Identifiable {
    public enum Kind: Equatable, Sendable { case page(String), token(String), pastedMint(String), term(String) }
    public var kind: Kind
    public var title: String
    public var subtitle: String
    public var id: String {
        switch kind { case .page(let p): return "p:\(p)"; case .token(let m): return "t:\(m)"; case .pastedMint(let m): return "m:\(m)"; case .term(let t): return "g:\(t)" }
    }
}

public struct PaletteToken: Sendable { public var mint: String; public var symbol: String?; public var name: String?
    public init(mint: String, symbol: String?, name: String?) { self.mint = mint; self.symbol = symbol; self.name = name } }

public enum Palette {
    public static let pages: [(id: String, title: String, hint: String, words: String)] = [
        ("live", "Terminal", "tokens en direct, graphique, ordre fictif", "direct terminal pulse tokens"),
        ("trades", "Trades", "ton historique et son diagnostic", "trades historique journal export"),
        ("robots", "Robots", "les agents fictifs face au témoin", "robots agents bots"),
        ("wallets", "Wallets suivis", "les adresses que tu regardes", "wallets portefeuilles suivis"),
        ("alerts", "Alertes", "règles, sons, heures calmes", "alertes notifications sons"),
        ("settings", "Réglages", "serveur, simulation, démarrage", "reglages parametres serveur")
    ]

    static func fold(_ s: String) -> String { s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil) }

    /// Résultats classés : adresse collée valide d'abord, puis pages, tokens (symbole exact > début > contient), puis termes. Au plus `limit`.
    public static func search(_ raw: String, tokens: [PaletteToken], limit: Int = 8) -> [PaletteItem] {
        let q = fold(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        var out: [PaletteItem] = []
        let rawTrim = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if isValidMint(rawTrim) {
            if let t = tokens.first(where: { $0.mint == rawTrim }) {
                out.append(PaletteItem(kind: .token(t.mint), title: safeLabel(t.symbol), subtitle: "ouvrir dans le Terminal · \(shortMint(t.mint))"))
            } else {
                out.append(PaletteItem(kind: .pastedMint(rawTrim), title: "Adresse " + shortMint(rawTrim), subtitle: "pas dans le flux · ouvrir DexScreener (lecture seule)"))
            }
        }
        if q.isEmpty {
            return Array((out + pages.map { PaletteItem(kind: .page($0.id), title: $0.title, subtitle: $0.hint) }).prefix(limit))
        }
        for p in pages where fold(p.title).contains(q) || fold(p.words).contains(q) { out.append(PaletteItem(kind: .page(p.id), title: p.title, subtitle: p.hint)) }
        func rank(_ t: PaletteToken) -> Int? {
            let s = fold(t.symbol ?? ""), n = fold(t.name ?? "")
            if s == q { return 0 }; if s.hasPrefix(q) { return 1 }; if n.hasPrefix(q) { return 2 }
            if s.contains(q) || n.contains(q) { return 3 }
            if q.count >= 6, t.mint.lowercased().hasPrefix(q) { return 4 }
            return nil
        }
        let found = tokens.compactMap { t in rank(t).map { ($0, t) } }.sorted { $0.0 < $1.0 }
        for (_, t) in found where !out.contains(where: { $0.id == "t:\(t.mint)" }) {
            out.append(PaletteItem(kind: .token(t.mint), title: safeLabel(t.symbol), subtitle: safeLabel(t.name, max: 24) + " · " + shortMint(t.mint)))
        }
        for g in Glossary.terms where fold(g.term).contains(q) { out.append(PaletteItem(kind: .term(g.term), title: g.term, subtitle: g.meaning)) }
        return Array(out.prefix(limit))
    }

    public static func shortMint(_ m: String) -> String { m.count > 12 ? "\(m.prefix(4))…\(m.suffix(4))" : m }
}

/// Mots du métier en phrases courtes. Descriptions générales : aucune ne prédit rien sur un token précis.
public enum Glossary {
    public static let terms: [(term: String, meaning: String)] = [
        ("Market cap", "Prix d'un token × nombre de tokens. Sur Pump.fun, c'est la seule « cote » : ce n'est pas de l'argent réellement déposé."),
        ("SOL réels", "SOL vraiment déposés dans la courbe de liaison. Peu de SOL = quelques ordres suffisent à faire bouger le prix."),
        ("Courbe de liaison", "Le mécanisme de Pump.fun avant la migration : le prix suit une formule, pas un carnet d'ordres."),
        ("Migration", "Quand la courbe est pleine, le token passe sur un vrai marché (PumpSwap). Ça ne dit rien de sa qualité."),
        ("Dev", "Le créateur du token. Part du dev élevée ou ventes du dev = risque classique."),
        ("Top 10", "Part de l'offre détenue par les 10 plus gros portefeuilles. Plus c'est concentré, plus une vente peut faire chuter."),
        ("Mint / freeze", "Autorités du token : « mint » peut créer de nouveaux tokens, « freeze » peut bloquer des portefeuilles. Révoquées = plus risquées à abuser."),
        ("Glissement", "Écart entre le prix vu et le prix payé, dû à ta taille et à la profondeur. Ici : estimé, jamais mesuré."),
        ("Latence", "Délai entre ton clic et l'exécution. Ici l'ordre fictif est rempli au prix lu environ 2 s plus tard."),
        ("Stop", "Vente automatique fictive quand le prix baisse d'un pourcentage choisi."),
        ("Prise de gain", "Vente (souvent d'une partie) quand le prix a monté d'un multiple choisi."),
        ("Facteur de profit", "Gains cumulés ÷ pertes cumulées. Sous 1 : tu perds plus que tu ne gagnes."),
        ("Drawdown", "Pire baisse du capital depuis un sommet, en %."),
        ("Échantillon", "Nombre de trades derrière un chiffre. Sous 30, un taux de réussite peut n'être que du hasard.")
    ]
    /// Définition à montrer au survol d'un libellé de l'écran (nil = pas de mot du métier dedans).
    public static func hint(for label: String) -> String? {
        let l = label.lowercased()
        let keys: [(String, String)] = [("market cap", "Market cap"), ("sol réels", "SOL réels"), ("courbe", "Courbe de liaison"), ("migr", "Migration"),
                                        ("dev", "Dev"), ("top 10", "Top 10"), ("mint", "Mint / freeze"), ("freeze", "Mint / freeze"), ("glissement", "Glissement"),
                                        ("latence", "Latence"), ("stop", "Stop"), ("prise de gain", "Prise de gain"), ("facteur", "Facteur de profit"),
                                        ("baisse", "Drawdown"), ("réussite", "Échantillon"), ("échantillon", "Échantillon"), ("série", "Échantillon")]
        for (k, term) in keys where l.contains(k) { return meaning(of: term) }
        return nil
    }
    public static func meaning(of term: String) -> String? { terms.first { $0.term.lowercased() == term.lowercased() }?.meaning }
}
