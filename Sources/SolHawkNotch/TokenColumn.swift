import SwiftUI
import SolHawkNotchCore

/// Une colonne = une carte carrée (l'identité du token) + dessous son graphique réel.
struct TokenColumn: View {
    var item: Feed.Item
    var ui: UIState
    var solUSD: Double? = nil
    @Environment(PaperLab.self) private var lab
    @Environment(MarketStore.self) private var market

    var body: some View {
        VStack(spacing: 8) {
            TokenSquare(item: item, ui: ui).aspectRatio(1, contentMode: .fit).zIndex(1)
            SparkCard(points: cleanSeries(item.series), entry: lab.manual.position(item.mint)?.entryMcap)
            TradeStrip(item: item, lab: lab, ui: ui, solUSD: solUSD)
        }
        .frame(width: ui.fullScreen ? 236 : 172)
        .task(id: item.mint) { await market.loadCard(item.mint) }   // une lecture de fiche par token (liens X / Telegram)
    }
}

private let card = RoundedRectangle(cornerRadius: 18, style: .continuous)

struct TokenSquare: View {
    var item: Feed.Item
    var ui: UIState
    @State private var hover = false

    var body: some View {
        let ok = status(of: item) == .passesFilters
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 6) {
                TokenAvatar(item: item, size: 20)
                Text(safeLabel(item.symbol)).font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(.white).lineLimit(1)
                Spacer(minLength: 4)
                if ui.fullScreen {
                    Text(ok ? "passe les filtres" : "à vérifier")
                        .font(.system(size: 9, weight: .semibold, design: .rounded)).lineLimit(1).fixedSize()
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill((ok ? Color.green : Color.orange).opacity(0.18)))
                        .foregroundStyle(ok ? Color.green : Color.orange)
                } else {
                    // tiroir étroit : pastille seule (le texte est dans l'aide et pour VoiceOver)
                    Image(systemName: ok ? "checkmark.seal.fill" : "exclamationmark.circle.fill")
                        .font(.system(size: 13)).foregroundStyle(ok ? Color.green : Color.orange)
                        .help(ok ? "Passe les filtres (≠ sûr)" : "À vérifier")
                        .accessibilityLabel(ok ? "passe les filtres" : "à vérifier")
                }
            }
            Spacer(minLength: 6)
            Text(item.marketCap.map(formatUSD) ?? "non lu")
                .font(.system(size: 28, weight: .semibold, design: .rounded)).monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
                .foregroundStyle(.white)
            HStack(spacing: 0) {
                Text("market cap").font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.45))
                Spacer(minLength: 4)
                SocialDots(mint: item.mint)
            }.padding(.bottom, 8)
            Text(item.realSol.map { String(format: "%.1f SOL réels", $0).replacingOccurrences(of: ".", with: ",") } ?? "SOL non lu")
                .font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.75))
            Text(item.ageS.map(ageText) ?? "âge non lu").font(.system(size: 10)).foregroundStyle(.white.opacity(0.45)).padding(.top, 1)
            Spacer(minLength: 6)
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    ForEach(Array((item.lights?.all ?? Array(repeating: nil, count: 5)).enumerated()), id: \.offset) { _, l in
                        Circle().fill(color(l)).frame(width: 6, height: 6)
                    }
                }
                Spacer(minLength: 0)
                iconButton("doc.on.doc", help: "Copier l'adresse") { copy() }
                iconButton("arrow.up.right", help: "Ouvrir sur DexScreener") { openDex() }
            }
        }
        .padding(14)
        .background(card.fill(.white.opacity(hover ? 0.10 : 0.06)))
        .overlay(card.strokeBorder(.white.opacity(hover ? 0.14 : 0.08), lineWidth: 0.5))
        .scaleEffect(hover ? 1.01 : 1)
        .onHover { hover = $0 }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: hover)
    }

    func iconButton(_ symbol: String, help: String, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
                .frame(width: 24, height: 24).background(Circle().fill(.white.opacity(0.10))).foregroundStyle(.white.opacity(0.85))
        }.buttonStyle(PressStyle()).help(help).accessibilityLabel(help)
    }

    func ageText(_ s: Int) -> String { s < 90 ? "\(s) s" : "\(s / 60) min" }

    func copy() { copyCA(item.mint, ui: ui) }
    func openDex() { openDexScreener(item.mint, ui: ui) }

    func color(_ l: String?) -> Color {
        switch l { case "green": return .green; case "orange": return .orange; case "red": return .red; default: return .gray.opacity(0.6) }
    }
}

/// Graphique réel du market cap (une lecture serveur de la courbe par point). Moins de 2 points = on l'écrit, on ne dessine rien d'inventé.
struct SparkCard: View {
    var points: [SeriesPoint]
    var entry: Double? = nil      // ton prix d'entrée fictif : ligne pointillée
    @State private var hover: CGFloat?

    var body: some View {
        let change = seriesChangePct(points)
        let tint: Color = (change ?? 0) >= 0 ? .green : .orange
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Courbe").font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.45))
                Spacer()
                if let change {
                    Text(String(format: "%+.0f %%", change)).font(.system(size: 10, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(tint)
                }
            }
            if points.count >= 2 {
                Canvas { ctx, size in draw(ctx, size, tint) }.frame(height: 50)
                    .onContinuousHover { phase in if case .active(let p) = phase { hover = p.x } else { hover = nil } }
                Text("\(points.count) lectures du serveur").font(.system(size: 8)).foregroundStyle(.white.opacity(0.35))
            } else {
                Spacer(minLength: 0)
                Text("pas encore d'historique").font(.system(size: 10)).foregroundStyle(.white.opacity(0.5)).frame(maxWidth: .infinity, alignment: .center)
                Spacer(minLength: 0)
            }
        }
        .padding(10).frame(height: 84)
        .background(card.fill(.white.opacity(0.04)))
        .overlay(card.strokeBorder(.white.opacity(0.06), lineWidth: 0.5))
    }

    func draw(_ ctx: GraphicsContext, _ size: CGSize, _ tint: Color) {
        let vals = points.map(\.marketCap) + (entry.map { [$0] } ?? [])
        let lo = vals.min() ?? 0, hi = vals.max() ?? 1
        let t0 = points.first!.ageS, t1 = points.last!.ageS
        let span = max(hi - lo, hi * 0.02), tspan = max(t1 - t0, 1)
        func pt(_ p: SeriesPoint) -> CGPoint {
            CGPoint(x: 4 + (p.ageS - t0) / tspan * (size.width - 8), y: size.height - 3 - (p.marketCap - lo) / span * (size.height - 6))
        }
        var line = Path()
        for (i, p) in points.enumerated() { i == 0 ? line.move(to: pt(p)) : line.addLine(to: pt(p)) }
        var area = line
        area.addLine(to: CGPoint(x: size.width - 4, y: size.height)); area.addLine(to: CGPoint(x: 4, y: size.height)); area.closeSubpath()
        ctx.fill(area, with: .linearGradient(Gradient(colors: [tint.opacity(0.28), tint.opacity(0)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
        ctx.stroke(line, with: .color(tint), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
        if let e = entry {
            let y = size.height - 3 - (e - lo) / span * (size.height - 6)
            var l = Path(); l.move(to: CGPoint(x: 0, y: y)); l.addLine(to: CGPoint(x: size.width, y: y))
            ctx.stroke(l, with: .color(.yellow.opacity(0.8)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            ctx.draw(Text("ton entrée").font(.system(size: 7, weight: .semibold)).foregroundStyle(.yellow.opacity(0.9)), at: CGPoint(x: size.width - 4, y: y < 10 ? y + 7 : y - 6), anchor: .trailing)
        }
        let last = pt(points.last!)
        ctx.fill(Path(ellipseIn: CGRect(x: last.x - 3, y: last.y - 3, width: 6, height: 6)), with: .color(tint))
        if let hx = hover, let near = points.min(by: { abs(pt($0).x - hx) < abs(pt($1).x - hx) }) {
            let q = pt(near)
            var v = Path(); v.move(to: CGPoint(x: q.x, y: 0)); v.addLine(to: CGPoint(x: q.x, y: size.height))
            ctx.stroke(v, with: .color(.white.opacity(0.3)), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
            ctx.fill(Path(ellipseIn: CGRect(x: q.x - 3.5, y: q.y - 3.5, width: 7, height: 7)), with: .color(.white))
            ctx.draw(Text("\(formatUSD(near.marketCap)) · \(duration(near.ageS))").font(.system(size: 9, weight: .semibold, design: .rounded)).foregroundStyle(.white),
                     at: CGPoint(x: min(max(q.x, 52), size.width - 52), y: q.y < 14 ? q.y + 12 : q.y - 10), anchor: .center)
        }
    }
}

/// Copie l'adresse (validée en base58 32–44 caractères : donnée du serveur, non fiable).
@MainActor func copyCA(_ mint: String, ui: UIState) {
    guard isValidMint(mint) else { ui.flash("Adresse invalide : non copiée"); return }
    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(mint, forType: .string)
    ui.flash("CA copié")
}

@MainActor func openDexScreener(_ mint: String, ui: UIState) {
    guard let url = dexScreenerURL(mint: mint) else { ui.flash("Adresse invalide : lien refusé"); return }
    NSWorkspace.shared.open(url)
}
