import SwiftUI
import WebKit
import SolHawkNotchCore

// Page « Terminal » du grand dashboard : un token à la fois, en grand. Le graphique en direct vient de DexScreener
// (page intégrée, verrouillée sur dexscreener.com) ; l'ordre est FICTIF, comme partout dans l'app.

private let tile = RoundedRectangle(cornerRadius: 16, style: .continuous)

struct TerminalView: View {
    var store: FeedStore
    var lab: PaperLab
    var ui: UIState
    var now: Date
    @Environment(WalletStore.self) private var wallets
    @Environment(MarketStore.self) private var market

    var body: some View {
        let all = market.allItems(feed: store.feed)
        let base = all.first { $0.mint == ui.focusMint } ?? all.first
        let sel = base.map { $0.withMarketCap(market.screen($0.mint)?.quote?.marketCap ?? market.screen($0.mint)?.chart?.candles?.last?.c) }
        VStack(spacing: 10) {
        if ui.guided { GuideBanner(lab: lab, ui: ui) }
        HStack(alignment: .top, spacing: 12) {
            TokenColumns(market: market, store: store, lab: lab, ui: ui, selected: sel?.mint, now: now).frame(width: 300)
            if let it = sel {
                ScrollView {
                    VStack(spacing: 12) {
                        if let d = market.dropped.first(where: { $0.mint == it.mint }), !market.isListed(it.mint) {
                            HStack(spacing: 6) {
                                Circle().fill(.orange).frame(width: 6, height: 6)
                                Text("Écarté par le serveur : \(d.reason ?? "raison non lue"). Affiché pour comprendre, pas comme un feu vert.")
                                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4)
                        }
                        ChartPanel(item: it, market: market, lab: lab, now: now).frame(height: 520)
                        HStack(alignment: .top, spacing: 12) {
                            TokenTradesPanel(item: it, lab: lab, now: now).frame(maxWidth: .infinity)
                            WalletsOnToken(item: it, wallets: wallets, now: now).frame(width: 340)
                        }
                    }
                }.scrollIndicators(.hidden)
                ScrollView {
                    VStack(spacing: 12) {
                        OrderPanel(item: it, lab: lab, ui: ui, now: now, card: market.cards[it.mint]?.value, solUSD: market.live?.new?.solUSD ?? store.feed?.solUSD)
                        TokenCardPanel(item: it, market: market, now: now, ui: ui)
                        RobotsOnToken(item: it, lab: lab)
                    }
                }.scrollIndicators(.hidden).frame(width: 320)
            } else {
                EmptyHint(symbol: "dot.radiowaves.left.and.right", text: store.feed == nil && market.live == nil ? "Aucune donnée reçue du serveur pour l'instant." : "Choisis un token dans une colonne à gauche.")
                    .padding(20).frame(maxWidth: .infinity)
            }
        }
        }
        // colonnes toutes les 5 s, bougies du token affiché toutes les 2 s, fiche une fois par minute : seulement quand cette page est à l'écran
        .task { var n = 0; while !Task.isCancelled { await market.loadLive(); if n % 3 == 0 { await market.loadDropped() }; n += 1; try? await Task.sleep(for: .seconds(5)) } }
        .task(id: "\(sel?.mint ?? "")|\(market.interval)") {
            guard let m = sel?.mint else { return }
            // la fiche (lectures RPC côté serveur, parfois plusieurs secondes) se charge EN MÊME TEMPS que les bougies : avant, les bougies attendaient la fiche
            async let card: Void = market.loadCard(m)
            while !Task.isCancelled { await market.loadScreen(m); try? await Task.sleep(for: .seconds(2)) }
            await card
        }
    }
}

// MARK: bande de tokens (l'image d'abord, comme sur Pump.fun)

struct TokenStrip: View {
    var items: [Feed.Item]
    var selected: String?
    var lab: PaperLab
    var ui: UIState

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(items) { it in
                    let on = it.mint == selected
                    let ch = change(it)
                    Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { ui.focusMint = it.mint } } label: {
                        HStack(spacing: 10) {
                            TokenAvatar(item: it, size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 5) {
                                    Text(safeLabel(it.symbol)).font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(.white).lineLimit(1)
                                    Circle().fill(status(of: it) == .passesFilters ? Color.green : Color.orange).frame(width: 6, height: 6)
                                    if lab.manual.position(it.mint) != nil { Image(systemName: "briefcase.fill").font(.system(size: 8)).foregroundStyle(.yellow) }
                                }
                                HStack(spacing: 6) {
                                    Text(it.marketCap.map(formatUSD) ?? "non lu").font(.system(size: 11, design: .rounded)).monospacedDigit().foregroundStyle(.white.opacity(0.7))
                                    if let ch { Text(pct(ch)).font(.system(size: 10, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(tone(ch)) }
                                }
                            }
                        }
                        .padding(.leading, 8).padding(.trailing, 14).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(on ? 0.11 : 0.04)))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(on ? 0.22 : 0.06), lineWidth: on ? 1 : 0.5))
                        .contentShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel("\(safeLabel(it.symbol)), \(it.marketCap.map(formatUSD) ?? "market cap non lu")")
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    /// Variation depuis la première lecture vue (app si possible, sinon série du serveur).
    func change(_ it: Feed.Item) -> Double? {
        let p = lab.points(for: it)
        guard let a = p.first?.mcap, let b = p.last?.mcap, p.count >= 2, a > 0 else { return nil }
        return (b / a - 1) * 100
    }
}

// MARK: graphique DexScreener intégré (lecture seule, navigation verrouillée)

struct DexChart: NSViewRepresentable {
    var mint: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .nonPersistent()          // pas de cookies gardés
        cfg.defaultWebpagePreferences.allowsContentJavaScript = true
        let w = WKWebView(frame: .zero, configuration: cfg)
        w.navigationDelegate = context.coordinator
        w.uiDelegate = context.coordinator
        w.setValue(false, forKey: "drawsBackground")
        load(w)
        return w
    }

    func updateNSView(_ w: WKWebView, context: Context) {
        if context.coordinator.loaded != mint { load(w); context.coordinator.loaded = mint }
    }

    private func load(_ w: WKWebView) {
        guard let base = dexScreenerURL(mint: mint), var c = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return }
        c.queryItems = [.init(name: "embed", value: "1"), .init(name: "theme", value: "dark"), .init(name: "trades", value: "1"),
                        .init(name: "info", value: "0"), .init(name: "chartTheme", value: "dark"), .init(name: "chartType", value: "usd"), .init(name: "interval", value: "1")]
        if let u = c.url { w.load(URLRequest(url: u)) }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var loaded: String?
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let u = action.request.url else { return .cancel }
            if u.scheme == "about" { return .allow }
            guard u.scheme == "https" else { return .cancel }
            // page principale : dexscreener.com uniquement ; les cadres intégrés (graphique) peuvent venir d'ailleurs, en https
            if action.targetFrame?.isMainFrame == true { return (u.host ?? "").hasSuffix("dexscreener.com") ? .allow : .cancel }
            return .allow
        }
        // aucun pop-up ni nouvelle fenêtre
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? { nil }
    }
}

// MARK: grand graphique natif (lectures) avec tes entrées / sorties et un viseur au survol

struct BigSeriesChart: View {
    var item: Feed.Item
    var lab: PaperLab
    @State private var hover: CGPoint?

    var body: some View {
        let own = lab.ownPoints(item.mint)
        let useOwn = own.count >= 2
        let pts = useOwn ? own : cleanSeries(item.series).map { PricePoint(t: $0.ageS, mcap: $0.marketCap) }
        let trades = useOwn ? lab.manual.trades.filter { $0.mint == item.mint } : []
        let entry = lab.manual.position(item.mint)?.entryMcap
        if pts.count < 2 {
            EmptyHint(symbol: "chart.xyaxis.line", text: "Pas encore assez de lectures pour ce token. La courbe se remplit toute seule (une lecture toutes les ~5 s).")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            GeometryReader { g in
                let vals = pts.map(\.mcap) + (entry.map { [$0] } ?? [])
                let lo = vals.min()!, hi = vals.max()!
                let span = max(hi - lo, hi * 0.04)
                let t0 = pts.first!.t, t1 = pts.last!.t, ts = max(t1 - t0, 1)
                let w = g.size.width - 64, h = g.size.height - 22
                let x: (Double) -> CGFloat = { 4 + ($0 - t0) / ts * (w - 8) }
                let y: (Double) -> CGFloat = { 6 + (1 - ($0 - lo) / span) * (h - 12) }
                let up = pts.last!.mcap >= pts.first!.mcap
                let c = up ? gain : loss
                ZStack(alignment: .topLeading) {
                    Canvas { ctx, _ in
                        for k in 0...4 {
                            let v = lo + span * Double(k) / 4
                            var l = Path(); l.move(to: CGPoint(x: 0, y: y(v))); l.addLine(to: CGPoint(x: w, y: y(v)))
                            ctx.stroke(l, with: .color(.white.opacity(0.05)), lineWidth: 1)
                            ctx.draw(Text(formatUSD(v)).font(.system(size: 9, design: .rounded)).foregroundStyle(.white.opacity(0.4)), at: CGPoint(x: w + 8, y: y(v)), anchor: .leading)
                        }
                        var line = Path()
                        for (i, p) in pts.enumerated() { let q = CGPoint(x: x(p.t), y: y(p.mcap)); i == 0 ? line.move(to: q) : line.addLine(to: q) }
                        var area = line
                        area.addLine(to: CGPoint(x: x(t1), y: h)); area.addLine(to: CGPoint(x: x(t0), y: h)); area.closeSubpath()
                        ctx.fill(area, with: .linearGradient(Gradient(colors: [c.opacity(0.22), c.opacity(0)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
                        ctx.stroke(line, with: .color(c), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        if let e = entry {
                            var l = Path(); l.move(to: CGPoint(x: 0, y: y(e))); l.addLine(to: CGPoint(x: w, y: y(e)))
                            ctx.stroke(l, with: .color(.yellow.opacity(0.8)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            ctx.draw(Text("ton entrée \(formatUSD(e))").font(.system(size: 9, weight: .semibold)).foregroundStyle(.yellow), at: CGPoint(x: 6, y: y(e) - 8), anchor: .leading)
                        }
                        for t in trades {
                            let ta = lab.timeAxis(t.openedAt)
                            if ta >= t0 && ta <= t1 { marker(ctx, at: CGPoint(x: x(ta), y: y(t.entryMcap)), up: true) }
                            if let ca = t.closedAt.map(lab.timeAxis), let ex = t.exitMcap, ca >= t0 && ca <= t1 { marker(ctx, at: CGPoint(x: x(ca), y: y(ex)), up: false) }
                        }
                        ctx.draw(Text(useOwn ? "il y a \(duration(ts))" : "\(duration(t0)) après création").font(.system(size: 9)).foregroundStyle(.white.opacity(0.35)), at: CGPoint(x: 4, y: h + 12), anchor: .leading)
                        ctx.draw(Text(useOwn ? "maintenant" : "dernière lecture").font(.system(size: 9)).foregroundStyle(.white.opacity(0.35)), at: CGPoint(x: w - 4, y: h + 12), anchor: .trailing)
                        if let hp = hover, hp.x <= w {
                            let tt = t0 + Double((hp.x - 4) / (w - 8)) * ts
                            if let near = pts.min(by: { abs($0.t - tt) < abs($1.t - tt) }) {
                                let q = CGPoint(x: x(near.t), y: y(near.mcap))
                                var v = Path(); v.move(to: CGPoint(x: q.x, y: 0)); v.addLine(to: CGPoint(x: q.x, y: h))
                                ctx.stroke(v, with: .color(.white.opacity(0.25)), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                                ctx.fill(Path(ellipseIn: CGRect(x: q.x - 4, y: q.y - 4, width: 8, height: 8)), with: .color(c))
                                let label = "\(formatUSD(near.mcap)) · \(useOwn ? "il y a \(duration(t1 - near.t))" : "\(duration(near.t)) après création")"
                                ctx.draw(Text(label).font(.system(size: 10, weight: .semibold, design: .rounded)).foregroundStyle(.white), at: CGPoint(x: min(max(q.x, 80), w - 80), y: max(q.y - 16, 8)), anchor: .center)
                            }
                        }
                    }
                    .onContinuousHover { phase in
                        if case .active(let p) = phase { hover = p } else { hover = nil }
                    }
                }
                .accessibilityLabel("Courbe du market cap, de \(formatUSD(pts.first!.mcap)) à \(formatUSD(pts.last!.mcap))")
            }
        }
    }

    func marker(_ ctx: GraphicsContext, at p: CGPoint, up: Bool) {
        var tri = Path()
        if up { tri.move(to: CGPoint(x: p.x, y: p.y + 4)); tri.addLine(to: CGPoint(x: p.x - 6, y: p.y + 14)); tri.addLine(to: CGPoint(x: p.x + 6, y: p.y + 14)) }
        else { tri.move(to: CGPoint(x: p.x, y: p.y - 4)); tri.addLine(to: CGPoint(x: p.x - 6, y: p.y - 14)); tri.addLine(to: CGPoint(x: p.x + 6, y: p.y - 14)) }
        tri.closeSubpath()
        ctx.fill(tri, with: .color(up ? gain : loss))
        ctx.draw(Text(up ? "A" : "V").font(.system(size: 8, weight: .bold)).foregroundStyle(.white), at: CGPoint(x: p.x, y: up ? p.y + 20 : p.y - 20))
    }
}

// MARK: panneau d'ordre (fictif)

struct OrderPanel: View {
    var item: Feed.Item
    var lab: PaperLab
    var ui: UIState
    var now: Date
    var card: TokenCard? = nil
    var solUSD: Double? = nil
    @AppStorage("strategyTag") private var strategy = "Perso"
    @AppStorage("buyPresetsSOL") private var presetsRaw = "0.1,0.2,0.5,1,3,5,10,20"
    @AppStorage("buyPresetsUSD") private var presetsUSDRaw = "5,10,25,50,100,250,500,1000"

    /// Montants des boutons d'achat (réglables) : en SOL si le prix est connu, sinon en $.
    var presets: [Double] {
        let raw = solUSD == nil ? presetsUSDRaw : presetsRaw
        let v = raw.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }.filter { $0 > 0 && $0.isFinite }.prefix(8)
        return v.isEmpty ? (solUSD == nil ? [5, 10, 25, 50] : [0.1, 0.2, 0.5, 1]) : Array(v)
    }
    func trim(_ v: Double) -> String { (v == v.rounded() ? String(Int(v)) : String(v)).replacingOccurrences(of: ".", with: ",") }
    func amount(_ usd: Double) -> String { solText(usd, solUSD: solUSD) ?? money(usd) }
    func stat(_ k: String, _ v: String, _ c: Color) -> some View {
        VStack(spacing: 2) {
            Text(k.uppercased()).font(.system(size: 8, weight: .semibold, design: .monospaced)).foregroundStyle(.white.opacity(0.4))
            Text(v).font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(c).lineLimit(1).minimumScaleFactor(0.7)
        }.frame(maxWidth: .infinity)
    }

    var body: some View {
        let pos = lab.manual.position(item.mint)
        let pending = lab.manual.pending.contains { $0.mint == item.mint }
        let ok = status(of: item) == .passesFilters
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                TokenAvatar(item: item, size: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text(safeLabel(item.symbol)).font(.system(size: 20, weight: .semibold, design: .rounded)).tracking(-0.3).foregroundStyle(.white).lineLimit(1)
                    Text(safeLabel(item.name, max: 28)).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                    HStack(spacing: 5) {
                        Circle().fill(ok ? Color.green : .orange).frame(width: 6, height: 6)
                        Text(ok ? "passe les filtres (≠ sûr)" : "à vérifier").font(.system(size: 10, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.55))
                    }
                }
            }
            HStack(alignment: .lastTextBaseline) {
                Text(item.marketCap.map(formatUSD) ?? "non lu").font(.system(size: 28, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(.white).contentTransition(.numericText())
                Text("market cap").font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
                Spacer()
                Text(item.realSol.map { "\(fmt1($0)) SOL réels" } ?? "SOL non lu").font(.system(size: 11, design: .rounded)).foregroundStyle(.white.opacity(0.6))
            }
            Divider().overlay(.white.opacity(0.07))
            // ---- panneau d'ordre façon MockApe : tout est FICTIF ----
            HStack(spacing: 8) {
                Text("Simulation").font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                Text(solText(lab.manual.cash, solUSD: solUSD) ?? money(lab.manual.cash))
                    .font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
                    .padding(.horizontal, 8).padding(.vertical, 3).background(Capsule().fill(.white.opacity(0.08))).foregroundStyle(.white.opacity(0.9))
                    .help("Solde fictif disponible")
                Spacer()
                Button(action: ui.openSettings) { Image(systemName: "gearshape").font(.system(size: 12)) }.buttonStyle(PressStyle()).foregroundStyle(.white.opacity(0.6)).help("Réglages : montants, coûts, capital de départ")
            }
            Text("Acheter \(safeLabel(item.symbol))").font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.7))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                ForEach(presets, id: \.self) { v in
                    let usd = solUSD.map { v * $0 } ?? v
                    Button {
                        let msg = lab.buy(item, now: Date(), strategy: strategy, note: cardNote(card), stake: usd)
                        ui.flash(msg)
                        if msg.contains("envoyé") { ui.onTrade?(.bought) }
                    } label: {
                        Text(solUSD == nil ? money(v) : "\(trim(v)) SOL").font(.system(size: 12, weight: .semibold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity).frame(height: 30)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(gain.opacity(usd <= lab.manual.cash ? 0.14 : 0.04)))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(gain.opacity(usd <= lab.manual.cash ? 0.45 : 0.12), lineWidth: 1))
                            .foregroundStyle(gain.opacity(usd <= lab.manual.cash ? 1 : 0.35))
                            .contentShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(PressStyle())
                    .disabled(item.marketCap == nil || usd > lab.manual.cash || pending)
                    .help(item.marketCap.map { "≈ \(money(usd)) · glissement estimé \(fmt1(lab.costs.slipPct(sizeUSD: usd, marketCap: $0))) % · rempli ~\(Int(lab.costs.latencyS)) s après le clic" } ?? "Prix non lu")
                }
            }
            if solUSD == nil { Text("Prix du SOL non lu : montants en $.").font(.system(size: 9)).foregroundStyle(.orange.opacity(0.8)) }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Ta stratégie").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                    Spacer()
                    Picker("", selection: $strategy) { ForEach(["Perso", "Mise en liste", "Momentum", "Fibonacci", "Creux"], id: \.self) { Text($0).tag($0) } }
                        .labelsHidden().frame(width: 150).controlSize(.small)
                }
                Text(strategyHelp(strategy) + " Elle est notée sur le trade pour comparer tes stratégies.").font(.system(size: 10)).foregroundStyle(.white.opacity(0.4)).fixedSize(horizontal: false, vertical: true)
            }
            Text("Vendre").font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.7))
            HStack(spacing: 0) {
                stat("Investi", pos.map { amount($0.stakeUSD) } ?? "–", .white)
                stat("Vendu", pos.map { amount($0.realizedUSD) } ?? "–", loss.opacity(0.9))
                stat("Reste", pos.map { amount($0.markUSD) } ?? "–", .white)
                stat("Gain/perte", pos.map { pct($0.pnlPct) } ?? "–", pos.map { tone($0.pnlUSD) } ?? .white)
            }
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.white.opacity(0.08), lineWidth: 1))
            HStack(spacing: 6) {
                ForEach([0.1, 0.25, 0.5, 1.0], id: \.self) { f in
                    Button {
                        let wasWin = (pos?.pnlUSD ?? 0) >= 0
                        ui.flash(lab.sell(mint: item.mint, fraction: f, seenMcap: item.marketCap, now: Date()))
                        ui.onTrade?(wasWin ? .soldWin : .soldLoss)
                    } label: {
                        Text("\(Int(f * 100)) %").font(.system(size: 12, weight: .semibold, design: .rounded))
                            .frame(maxWidth: .infinity).frame(height: 30)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(loss.opacity(pos == nil ? 0.04 : 0.14)))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(loss.opacity(pos == nil ? 0.1 : 0.45), lineWidth: 1))
                            .foregroundStyle(loss.opacity(pos == nil ? 0.35 : 1))
                            .contentShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(PressStyle()).disabled(pos == nil || pending)
                }
            }
            if pending {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Ordre en cours…").font(.system(size: 11)).foregroundStyle(.white.opacity(0.7)) }
            }
            SimBadge()
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                bigButton("Copier le CA", fill: .white.opacity(0.06), fg: .white.opacity(0.8), height: 30) { copyCA(item.mint, ui: ui) }
                Menu {
                    ForEach(openInTargets, id: \.0) { name, make in
                        Button(name) {
                            guard isValidMint(item.mint), let u = make(item.mint) else { ui.flash("Adresse invalide : lien refusé"); return }
                            NSWorkspace.shared.open(u)
                        }
                    }
                } label: {
                    Text("Ouvrir dans…").font(.system(size: 13, weight: .semibold, design: .rounded)).frame(maxWidth: .infinity).frame(height: 30)
                        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(.white.opacity(0.06))).foregroundStyle(.white.opacity(0.8))
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden)
                .help("Ouvre le token sur un autre site (pour trader en vrai, c'est là-bas, sous ta responsabilité)")
            }
        }
        .padding(16)
        .background(tile.fill(.white.opacity(0.05)))
        .overlay(tile.strokeBorder(.white.opacity(0.07), lineWidth: 0.5))
    }

    func row(_ k: String, _ v: String) -> some View {
        HStack { Text(k).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5)); Spacer(); Text(v).font(.system(size: 11, weight: .medium, design: .rounded)).monospacedDigit().foregroundStyle(.white.opacity(0.85)) }
    }

    func bigButton(_ s: String, fill: Color, fg: Color, height: CGFloat = 36, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            Text(s).font(.system(size: 13, weight: .semibold, design: .rounded)).lineLimit(1)
                .frame(maxWidth: .infinity).frame(height: height)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(fill))
                .foregroundStyle(fg)
                .contentShape(RoundedRectangle(cornerRadius: 11))
        }.buttonStyle(PressStyle())
    }
}

// MARK: tes trades sur ce token (avec l'analyse) et les robots qui l'ont pris

struct TokenTradesPanel: View {
    var item: Feed.Item
    var lab: PaperLab
    var now: Date

    var body: some View {
        let mine = lab.manual.trades.filter { $0.mint == item.mint }.reversed()
        Panel(title: "Tes trades sur \(safeLabel(item.symbol))", trailing: mine.isEmpty ? nil : "\(mine.count)") {
            if mine.isEmpty {
                EmptyHint(symbol: "hand.tap", text: "Aucun trade fictif sur ce token. Quand tu en fais un, l'app le relit pour toi : entrée tard ou non, coûts, sortie par rapport au plus haut.")
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(mine.prefix(4))) { t in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(t.isOpen ? "En cours" : "Fermé").font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                                Text(t.openedAt, format: .dateTime.hour().minute()).font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
                                Spacer()
                                Text(pct(t.pnlPct)).font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(tone(t.pnlUSD))
                            }
                            NotesList(notes: review(t, before: lab.pointsBefore(t)))
                        }
                        .padding(10).background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(.white.opacity(0.03)))
                    }
                }
            }
        }
    }
}

struct NotesList: View {
    var notes: [TradeNote]
    var body: some View {
        if notes.isEmpty {
            Text("Rien de particulier à signaler sur ce trade.").font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(notes) { n in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: n.tone == .good ? "checkmark.circle.fill" : n.tone == .bad ? "exclamationmark.triangle.fill" : "info.circle.fill")
                            .font(.system(size: 10)).foregroundStyle(n.tone == .good ? gain : n.tone == .bad ? Color.orange : .white.opacity(0.5))
                        Text(n.text).font(.system(size: 11)).foregroundStyle(.white.opacity(0.75)).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

struct RobotsOnToken: View {
    var item: Feed.Item
    var lab: PaperLab
    var body: some View {
        let hits = lab.robots.compactMap { r -> (RobotSpec, PaperTrade)? in
            guard let t = lab.books[r.id]?.trades.last(where: { $0.mint == item.mint }) else { return nil }
            return (r, t)
        }
        Panel(title: "Robots sur ce token") {
            if hits.isEmpty {
                EmptyHint(symbol: "cpu", text: "Aucun robot n'a pris ce token : aucune de leurs règles ne s'est déclenchée.")
            } else {
                VStack(spacing: 8) {
                    ForEach(hits, id: \.0.id) { r, t in
                        HStack(alignment: .top, spacing: 10) {
                            RobotAvatar(kind: r.kind, size: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack { Text(r.name).font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(.white); Spacer(); Text(pct(t.pnlPct)).font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(tone(t.pnlUSD)) }
                                Text("Entré : \(t.entryReason)").font(.system(size: 10)).foregroundStyle(.white.opacity(0.55)).fixedSize(horizontal: false, vertical: true)
                                if let e = t.exitReason { Text("Sorti : \(e)").font(.system(size: 10)).foregroundStyle(.white.opacity(0.4)) }
                            }
                        }
                    }
                }
            }
        }
    }
}

/// Avatar d'un robot : une pastille de couleur avec son symbole (dessinée en code, pas d'image).
struct RobotAvatar: View {
    var kind: RobotKind
    var size: CGFloat = 32
    var body: some View {
        let (sym, color): (String, Color) = {
            switch kind {
            case .onListing: return ("flag.checkered", Color(red: 0.35, green: 0.6, blue: 1))
            case .momentum: return ("bolt.fill", Color(red: 1, green: 0.72, blue: 0.2))
            case .fibRetrace: return ("function", Color(red: 0.72, green: 0.5, blue: 1))
            case .dipBuy: return ("arrow.uturn.up", Color(red: 0.25, green: 0.85, blue: 0.75))
            case .random: return ("dice.fill", Color.white.opacity(0.6))
            }
        }()
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).fill(color.opacity(0.18))
            .overlay(Image(systemName: sym).font(.system(size: size * 0.45, weight: .semibold)).foregroundStyle(color))
            .overlay(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).strokeBorder(color.opacity(0.35), lineWidth: 0.5))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// Sites où ouvrir un token (adresse déjà validée). Pour trader en vrai, c'est sur ces sites, sous la responsabilité de l'utilisateur.
let openInTargets: [(String, @Sendable (String) -> URL?)] = [
    ("Pump.fun", { URL(string: "https://pump.fun/coin/\($0)") }),
    ("GMGN", { URL(string: "https://gmgn.ai/sol/token/\($0)") }),
    ("Birdeye", { URL(string: "https://birdeye.so/token/\($0)?chain=solana") }),
    ("DexScreener", { URL(string: "https://dexscreener.com/solana/\($0)") }),
    // Formats d'adresse non vérifiés (relevés de documentation tierce) : si la page ne s'ouvre pas sur le token, cherche-le par son CA.
    ("Axiom", { URL(string: "https://axiom.trade/t/\($0)") }),
    ("Photon", { URL(string: "https://photon-sol.tinyastro.io/en/lp/\($0)") }),
    ("Solscan", { URL(string: "https://solscan.io/token/\($0)") }),
]
