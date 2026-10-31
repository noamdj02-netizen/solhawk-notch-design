import SwiftUI
import SolHawkNotchCore

// Achat rapide en SOL sur les cartes du Direct, et petites icônes X / Telegram / site avec aperçu au survol.
// Tout est FICTIF ou en lecture seule : aucun ordre réel, les liens s'ouvrent dans le navigateur.

/// « 0.05, 0.1 » → [0.05, 0.1] (valeurs positives et finies, au plus `max`).
func parseAmounts(_ raw: String, max: Int, fallback: [Double]) -> [Double] {
    let v = raw.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")) }
        .filter { $0 > 0 && $0.isFinite }.prefix(max)
    return v.isEmpty ? fallback : Array(v)
}

func trimNumber(_ v: Double) -> String {
    (v == v.rounded() ? String(Int(v)) : String(v)).replacingOccurrences(of: ".", with: ",")
}

/// Une rangée de petits boutons « 0,05 · 0,1 · 0,5 · 1 » (SOL) : un clic = un achat fictif de ce montant.
struct QuickBuyRow: View {
    var item: Feed.Item
    var lab: PaperLab
    var ui: UIState
    var solUSD: Double?
    var count: Int = 4
    @AppStorage("quickPresetsSOL") private var solRaw = "0.05,0.1,0.5,1"
    @AppStorage("quickPresetsUSD") private var usdRaw = "5,10,25,50"
    @AppStorage("strategyTag") private var strategy = "Perso"

    var presets: [Double] {
        solUSD == nil ? parseAmounts(usdRaw, max: count, fallback: [5, 10, 25, 50]) : parseAmounts(solRaw, max: count, fallback: [0.05, 0.1, 0.5, 1])
    }

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 4) {
                ForEach(presets, id: \.self) { v in
                    let usd = solUSD.map { v * $0 } ?? v
                    let can = item.marketCap != nil && usd <= lab.manual.cash
                    Button {
                        let m = lab.buy(item, now: Date(), strategy: strategy, note: nil, stake: usd)
                        ui.flash(m)
                        if m.contains("envoyé") { ui.onTrade?(.bought) }
                    } label: {
                        Text(solUSD == nil ? "$\(trimNumber(v))" : trimNumber(v))
                            .font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity).frame(height: 26)
                            .background(Capsule().fill(gain.opacity(can ? 0.18 : 0.05)))
                            .overlay(Capsule().strokeBorder(gain.opacity(can ? 0.4 : 0.1), lineWidth: 0.5))
                            .foregroundStyle(gain.opacity(can ? 1 : 0.35))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(PressStyle())
                    .disabled(!can)
                    .help(item.marketCap == nil ? "Prix non lu : impossible de simuler"
                          : "Achat FICTIF de \(trimNumber(v)) \(solUSD == nil ? "$" : "SOL") (≈ \(money(usd))), rempli ~\(Int(lab.costs.latencyS)) s après le clic")
                    .accessibilityLabel("Acheter \(trimNumber(v)) \(solUSD == nil ? "dollars" : "SOL"), simulation")
                }
            }
            Text(solUSD == nil ? "achat fictif en $" : "achat fictif en SOL").font(.system(size: 8, weight: .medium)).foregroundStyle(.white.opacity(0.35))
        }
    }
}

/// Bulle d'aperçu d'un lien (tweet, groupe Telegram, site) : contenu public de la page, non vérifié.
struct PreviewBubble: View {
    var social: Social
    var preview: SocialPreview?
    var loading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if loading {
                HStack(spacing: 6) { ProgressView().controlSize(.mini); Text("Lecture de l'aperçu…").font(.system(size: 10)).foregroundStyle(.white.opacity(0.5)) }
            } else if let p = preview {
                if let t = p.title { Text(t).font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(.white).lineLimit(2) }
                if let m = p.members { Text(m).font(.system(size: 10, weight: .medium)).foregroundStyle(gain) }
                if let x = p.text { Text(x).font(.system(size: 10)).foregroundStyle(.white.opacity(0.75)).lineLimit(6).fixedSize(horizontal: false, vertical: true) }
            } else {
                Text(social.kind == "twitter" ? "Profil X : pas d'aperçu sans compte (seuls les tweets en ont un). Clique pour ouvrir."
                     : social.kind == "website" ? "Site : clique pour l'ouvrir dans ton navigateur." : "Aperçu indisponible.")
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.55)).fixedSize(horizontal: false, vertical: true)
            }
            Text("Contenu public de la page, non vérifié.").font(.system(size: 8)).foregroundStyle(.white.opacity(0.3))
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(white: 0.1)).shadow(color: .black.opacity(0.6), radius: 14, y: 6))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
    }
}

/// Petites icônes X / Telegram / site d'un token : survol = aperçu qui flotte, clic = ouvre dans le navigateur.
/// Les liens viennent de la fiche du token (déclarés par le créateur, non vérifiés).
struct SocialDots: View {
    var mint: String
    @Environment(MarketStore.self) private var market
    @State private var hovered: String?
    @State private var preview: SocialPreview?
    @State private var loading = false

    var body: some View {
        let socials = (market.cards[mint]?.value?.socials ?? []).filter { safeSocialURL($0) != nil }
        HStack(spacing: 4) {
            ForEach(socials) { s in
                if let url = safeSocialURL(s) {
                    let kind = s.kind ?? ""
                    Button { NSWorkspace.shared.open(url) } label: {
                        Image(systemName: kind == "twitter" ? "at" : kind == "telegram" ? "paperplane.fill" : "globe")
                            .font(.system(size: 9, weight: .semibold))
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(.white.opacity(hovered == url.absoluteString ? 0.2 : 0.1)))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel(kind == "twitter" ? "Ouvrir X" : kind == "telegram" ? "Ouvrir Telegram" : "Ouvrir le site")
                    .onHover { on in
                        if on { hovered = url.absoluteString; Task { await show(s) } }
                        else if hovered == url.absoluteString { hovered = nil }
                    }
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if let h = hovered, let s = socials.first(where: { safeSocialURL($0)?.absoluteString == h }) {
                PreviewBubble(social: s, preview: preview, loading: loading)
                    .frame(width: 236).offset(y: 26).allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.12), value: hovered)
    }

    func show(_ s: Social) async {
        guard let u = previewURL(for: s) else { preview = nil; loading = false; return }
        if let c = PreviewCache.shared.cached(u) { preview = c; loading = false; return }
        loading = true; preview = nil
        let p = await PreviewCache.shared.load(u, kind: s.kind ?? "")
        if hovered == safeSocialURL(s)?.absoluteString { preview = p; loading = false }
    }
}

/// Explication d'une étiquette de stratégie, en une phrase.
func strategyHelp(_ s: String) -> String {
    switch s {
    case "Mise en liste": return "Tu entres dès que le token passe les filtres, juste après sa mise en liste."
    case "Momentum": return "Tu suis la hausse : tu achètes un token qui monte déjà."
    case "Fibonacci": return "Tu achètes le rebond après un repli de 38 à 62 % depuis le plus haut."
    case "Creux": return "Tu achètes la baisse (−25 à −45 % du plus haut) en pariant sur un rebond."
    default: return "Ton choix à toi, sans règle. L'étiquette sert juste à comparer plus tard."
    }
}
