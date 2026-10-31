import Foundation

/// Un point de la courbe réelle d'un token (lecture serveur de la courbe de liaison).
public struct SeriesPoint: Equatable, Sendable {
    public var ageS: Double
    public var marketCap: Double
}

/// Nettoie une série reçue du serveur (donnée non fiable) : paires finies, valeurs positives, ordre du temps, bornée.
/// Retourne [] si rien d'exploitable : l'interface écrit alors « pas encore d'historique » au lieu d'inventer une courbe.
public func cleanSeries(_ raw: [[Double]]?, maxPoints: Int = 60) -> [SeriesPoint] {
    guard let raw else { return [] }
    var pts: [SeriesPoint] = []
    for p in raw.prefix(500) where p.count == 2 && p[0].isFinite && p[1].isFinite && p[0] >= 0 && p[1] > 0 {
        pts.append(SeriesPoint(ageS: p[0], marketCap: p[1]))
    }
    pts.sort { $0.ageS < $1.ageS }
    return Array(pts.suffix(maxPoints))
}

/// Variation en % entre le premier et le dernier point (nil s'il y a moins de 2 points).
public func seriesChangePct(_ pts: [SeriesPoint]) -> Double? {
    guard let a = pts.first, let b = pts.last, pts.count >= 2, a.marketCap > 0 else { return nil }
    return (b.marketCap / a.marketCap - 1) * 100
}

/// « $850 », « $8,2 k », « $1,2 M » — pour l'affichage compact d'un market cap.
public func formatUSD(_ v: Double) -> String {
    guard v.isFinite, v >= 0 else { return "non lu" }
    func one(_ x: Double) -> String { String(format: "%.1f", x).replacingOccurrences(of: ".", with: ",") }
    if v < 1_000 { return "$\(Int(v.rounded()))" }
    if v < 1_000_000 { return "$\(one(v / 1_000)) k" }
    return "$\(one(v / 1_000_000)) M"
}

/// Étiquette d'axe : assez précise pour que deux graduations voisines ne portent jamais le même texte (avant : cinq fois « $2,7 k »
/// sur un token dont le market cap bouge de quelques dollars). `step` = écart entre deux graduations, en dollars.
public func axisUSD(_ v: Double, step: Double) -> String {
    guard v.isFinite, v >= 0 else { return "non lu" }
    if v >= 1_000_000 || step >= 50 { return formatUSD(v) }
    if step >= 1 {
        let n = Int(v.rounded())
        let digits = String(n)
        // espace fine tous les 3 chiffres : « 2 701 »
        var out = "", c = 0
        for ch in digits.reversed() { if c > 0, c % 3 == 0 { out.append("\u{202F}") }; out.append(ch); c += 1 }
        return "$" + String(out.reversed())
    }
    return "$" + String(format: "%.2f", v).replacingOccurrences(of: ".", with: ",")
}
