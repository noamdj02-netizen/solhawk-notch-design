import Foundation

// Explications en mots simples. Ce sont des PISTES tirées des chiffres du trade, pas des règles prouvées.

/// Pourquoi un robot entre (texte court affiché dans son journal).
public func robotWhy(_ kind: RobotKind, item: Feed.Item, pts: [PricePoint]) -> String {
    switch kind {
    case .onListing:
        return "passe les 5 filtres" + (item.ageS.map { ", \($0 < 90 ? "\($0) s" : "\($0 / 60) min") après la création" } ?? "")
    case .momentum:
        guard pts.count >= 3, pts[pts.count - 3].mcap > 0 else { return "hausse rapide" }
        return "\(pct((pts[pts.count - 1].mcap / pts[pts.count - 3].mcap - 1) * 100)) sur les 3 dernières lectures"
    case .fibRetrace:
        guard let hi = pts.indices.max(by: { pts[$0].mcap < pts[$1].mcap }), hi > 0 else { return "repli dans la zone 38–62 %" }
        let low = pts[..<hi].map(\.mcap).min() ?? 0, high = pts[hi].mcap, c = pts[pts.count - 1].mcap
        guard high > low, low > 0 else { return "repli dans la zone 38–62 %" }
        return "hausse ×\(fmt1(high / low)), repli de \(Int(((high - c) / (high - low) * 100).rounded())) %, puis rebond"
    case .dipBuy:
        guard let peak = pts.map(\.mcap).max(), peak > 0, let c = pts.last?.mcap else { return "creux puis rebond" }
        return "à \(pct((c / peak - 1) * 100)) du plus haut, puis rebond"
    case .random:
        return "tiré au sort (étalon)"
    }
}

public enum NoteTone: String, Sendable { case good, bad, info }

public struct TradeNote: Sendable, Equatable, Identifiable {
    public var tone: NoteTone
    public var text: String
    public var id: String { text }
}

/// Lecture d'un trade fermé (ou ouvert). `before` : lectures de prix AVANT l'entrée (même axe de temps que `PricePoint.t`).
public func review(_ t: PaperTrade, before: [PricePoint] = []) -> [TradeNote] {
    var out: [TradeNote] = []
    let costShare = t.stakeUSD > 0 ? t.costsUSD / t.stakeUSD * 100 : 0
    if !t.isOpen { out.append(TradeNote(tone: t.pnlUSD > 0 ? .good : .bad, text: "Résultat net estimé : \(money(t.pnlUSD, signed: true)) (\(pct(t.pnlPct)))")) }
    if costShare >= 5 { out.append(TradeNote(tone: .bad, text: "Frais et glissement estimés : \(fmt1(costShare)) % de la mise. Une mise plus petite sur un token peu liquide glisse moins.")) }
    if let first = before.first, first.mcap > 0, t.entryMcap > 0 {
        let run = (t.entryMcap / first.mcap - 1) * 100
        if run >= 50 { out.append(TradeNote(tone: .bad, text: "Entrée après \(pct(run)) de hausse déjà faite : le gros du mouvement était peut-être passé.")) }
    }
    if let seen = t.seenMcap, seen > 0 {
        let drift = (t.entryMcap / seen - 1) * 100
        if drift >= 5 { out.append(TradeNote(tone: .info, text: "Prix payé \(pct(drift)) au-dessus du prix vu au clic (délai + glissement).")) }
    }
    let peakX = t.entryMcap > 0 ? t.peakMcap / t.entryMcap : 1
    if !t.isOpen, let exit = t.exitMcap, t.entryMcap > 0 {
        let exitX = exit / t.entryMcap
        if peakX >= 1.5, exitX < peakX * 0.7 {
            out.append(TradeNote(tone: .bad, text: "Le prix est monté jusqu'à ×\(fmt1(peakX)) après ton entrée ; tu es sorti à ×\(fmt1(exitX)). Une vente partielle en hausse aurait sécurisé une partie."))
        } else if peakX >= 1.5, exitX >= peakX * 0.85 {
            out.append(TradeNote(tone: .good, text: "Sortie proche du plus haut (×\(fmt1(exitX)) pour un sommet à ×\(fmt1(peakX)))."))
        }
        if exitX <= 0.75 { out.append(TradeNote(tone: .bad, text: "Perte de plus de 25 % sur le prix : un seuil de sortie écrit avant d'entrer limite ce cas.")) }
    }
    if t.isOpen, t.multiple <= 0.75 { out.append(TradeNote(tone: .bad, text: "Position à \(pct((t.multiple - 1) * 100)) : tu avais prévu de sortir où ?")) }
    if !t.isOpen, t.holdS < 30 { out.append(TradeNote(tone: .info, text: "Trade de moins de 30 s : les coûts pèsent plus que le mouvement.")) }
    if (t.exitReason ?? "").contains("supposée") { out.append(TradeNote(tone: .bad, text: "Le token a disparu du flux : impossible de vendre, perte supposée.")) }
    return out
}

/// Un token vu mais pas acheté, et ce qu'il est devenu depuis que l'app l'a vu.
public struct Missed: Sendable, Equatable, Identifiable {
    public var mint: String
    public var firstMcap: Double
    public var lastMcap: Double
    public var peakMcap: Double
    public var changePct: Double { firstMcap > 0 ? (lastMcap / firstMcap - 1) * 100 : 0 }
    public var peakPct: Double { firstMcap > 0 ? (peakMcap / firstMcap - 1) * 100 : 0 }
    public var id: String { mint }
}

/// Tokens vus (au moins 3 lectures) jamais achetés, triés par plus forte variation (hausse ou baisse).
public func missedTokens(history: [String: [PricePoint]], traded: (String) -> Bool, limit: Int = 8) -> [Missed] {
    history.compactMap { mint, pts -> Missed? in
        guard pts.count >= 3, !traded(mint), let f = pts.first?.mcap, let l = pts.last?.mcap, f > 0 else { return nil }
        return Missed(mint: mint, firstMcap: f, lastMcap: l, peakMcap: pts.map(\.mcap).max() ?? l)
    }
    .sorted { abs($0.changePct) > abs($1.changePct) }
    .prefix(limit).map { $0 }
}

public func fmt1(_ v: Double) -> String { String(format: "%.1f", v).replacingOccurrences(of: ".", with: ",") }
