import SwiftUI
import SolHawkNotchCore

// Terminal v2 : colonnes à gauche, bougies au centre, ordre fictif + fiche à droite.

private let tile = RoundedRectangle(cornerRadius: 16, style: .continuous)

enum Column: String, CaseIterable, Identifiable {
    case new = "Nouveaux", soon = "Bientôt migrés", migrated = "Migrés", runs = "Ont pété"
    var id: String { rawValue }
    var symbol: String {
        switch self { case .new: return "sparkles"; case .soon: return "hourglass"; case .migrated: return "checkmark.seal"; case .runs: return "flame" }
    }
}

// MARK: colonnes

struct TokenColumns: View {
    var market: MarketStore
    var store: FeedStore
    var lab: PaperLab
    var ui: UIState
    var selected: String?
    var now: Date
    @AppStorage("terminalColumn") private var colRaw = Column.new.rawValue
    @State private var peek: Column?
    @State private var showFilters = false
    @AppStorage("vfMinMcap") private var vfMinM = ""
    @AppStorage("vfMaxMcap") private var vfMaxM = ""
    @AppStorage("vfMinSol") private var vfMinS = ""
    @AppStorage("vfMaxAge") private var vfMaxA = ""
    @AppStorage("vfOnlyPassing") private var vfOnly = false
    private var vf: ViewFilterReader { ViewFilterReader(minM: vfMinM, maxM: vfMaxM, minS: vfMinS, maxA: vfMaxA, onlyPassing: vfOnly) }

    func rawItems(_ c: Column) -> [Feed.Item] {
        switch c {
        case .new: return market.live?.new?.items ?? store.feed?.items ?? []
        case .soon: return market.live?.soon?.items ?? []
        case .migrated: return market.live?.migrated?.items ?? []
        case .runs: return (market.live?.runs?.items ?? []).map(Feed.Item.init(run:))
        }
    }
    func items(_ c: Column) -> [Feed.Item] { vf.apply(rawItems(c)) }

    var body: some View {
        let col = Column(rawValue: colRaw) ?? .new
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                ForEach(Column.allCases) { c in
                    let n = items(c).count
                    Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { colRaw = c.rawValue } } label: {
                        VStack(spacing: 3) {
                            Image(systemName: c.symbol).font(.system(size: 11, weight: .semibold))
                            Text(n > 0 ? "\(n)" : "–").font(.system(size: 9, weight: .semibold, design: .rounded)).monospacedDigit()
                        }
                        .frame(maxWidth: .infinity).frame(height: 40)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(col == c ? 0.12 : 0.03)))
                        .foregroundStyle(col == c ? .white : .white.opacity(0.55))
                        .contentShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(PressStyle())
                    .help(c.rawValue)
                    .accessibilityLabel("\(c.rawValue), \(n)")
                    .onHover { peek = $0 ? c : (peek == c ? nil : peek) }
                }
            }
            HStack {
                Text(col.rawValue).font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                Spacer()
                Button { showFilters.toggle() } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "line.3.horizontal.decrease.circle\(vf.isActive ? ".fill" : "")")
                        if vf.isActive { Text("actifs").font(.system(size: 9, weight: .semibold)) }
                    }
                    .font(.system(size: 13)).foregroundStyle(vf.isActive ? Color.yellow : .white.opacity(0.6))
                }
                .buttonStyle(.plain).help("Filtres d'affichage (market cap, SOL, âge)")
                .popover(isPresented: $showFilters, arrowEdge: .bottom) { FilterPopover() }
            }
            if col == .runs, let rule = market.live?.runs?.rule {
                Text("\(rule). Détecté après le début du mouvement.").font(.system(size: 9)).foregroundStyle(.white.opacity(0.4)).fixedSize(horizontal: false, vertical: true)
            }
            ZStack(alignment: .top) {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        let rows = items(col)
                        if rows.isEmpty {
                            EmptyHint(symbol: col.symbol, text: market.live == nil ? (market.liveError == nil ? "Chargement…" : "Colonnes non lues (serveur injoignable ou ancienne version).")
                                      : vf.isActive && !rawItems(col).isEmpty ? "\(rawItems(col).count) token(s) cachés par tes filtres d'affichage (icône en haut à droite)."
                                      : col == .new ? "Aucun token ne passe les filtres du serveur pour l'instant." + (market.live?.new.flatMap { Feed.drySummary($0.stats) }.map { " Le serveur a regardé : \($0)." } ?? "") + " « Bientôt migrés » et « Migrés » se remplissent séparément."
                                      : "Rien dans cette colonne pour l'instant.")
                        }
                        if rows.isEmpty, col == .new, market.live != nil, !market.dropped.isEmpty { DroppedList(items: market.dropped, selected: selected) { select(Feed.Item(dropped: $0)) } }
                        ForEach(rows) { it in TokenRow(item: it, column: col, run: market.live?.runs?.items?.first { $0.mint == it.mint }, selected: it.mint == selected, inPosition: lab.manual.position(it.mint) != nil) { select(it) } }
                    }
                }
                .scrollIndicators(.hidden)
                if let p = peek, p != col { PeekCard(column: p, items: Array(items(p).prefix(3))).transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top))) }
            }
            .animation(.easeOut(duration: 0.15), value: peek)
        }
        .padding(12)
        .background(tile.fill(.white.opacity(0.04)))
        .overlay(tile.strokeBorder(.white.opacity(0.06), lineWidth: 0.5))
    }

    func select(_ it: Feed.Item) { withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { ui.focusMint = it.mint } }
}

/// Aperçu des 3 premiers d'une colonne au survol de son onglet.
struct PeekCard: View {
    var column: Column
    var items: [Feed.Item]
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(text: "\(column.rawValue) · les 3 premiers")
            if items.isEmpty { Text("Vide pour l'instant.").font(.system(size: 10)).foregroundStyle(.white.opacity(0.5)) }
            ForEach(items) { it in
                HStack(spacing: 8) {
                    TokenAvatar(item: it, size: 26)
                    Text(safeLabel(it.symbol)).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                    Spacer()
                    Text(it.marketCap.map(formatUSD) ?? "non lu").font(.system(size: 11, design: .rounded)).monospacedDigit().foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(white: 0.1)).shadow(color: .black.opacity(0.6), radius: 18, y: 8))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
        .allowsHitTesting(false)
    }
}

struct TokenRow: View {
    var item: Feed.Item
    var column: Column
    var run: RunItem?
    var selected: Bool
    var inPosition: Bool
    var action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                TokenAvatar(item: item, size: 40)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(safeLabel(item.symbol)).font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(.white).lineLimit(1)
                        if item.lights != nil { Circle().fill(status(of: item) == .passesFilters ? Color.green : .orange).frame(width: 6, height: 6) }
                        if inPosition { Image(systemName: "briefcase.fill").font(.system(size: 8)).foregroundStyle(.yellow) }
                    }
                    Text(subtitle).font(.system(size: 10)).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(item.marketCap.map(formatUSD) ?? "non lu").font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(.white.opacity(0.9))
                    if let r = run, let g = r.sinceDetectPct { Text("\(pct(g)) depuis").font(.system(size: 9, weight: .semibold, design: .rounded)).foregroundStyle(tone(g)) }
                    else if let s = item.realSol { Text("\(fmt1(s)) SOL").font(.system(size: 9, design: .rounded)).foregroundStyle(.white.opacity(0.45)) }
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(selected ? 0.12 : hover ? 0.06 : 0.02)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(selected ? 0.2 : 0), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(PressStyle())
        .onHover { hover = $0 }
        .accessibilityLabel("\(safeLabel(item.symbol)), \(item.marketCap.map(formatUSD) ?? "market cap non lu")")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    var subtitle: String {
        if let r = run { return "+\(Int(r.gainPct ?? 0)) % en run · \(r.ageS.map { "il y a \(duration(Double($0)))" } ?? "")" }
        let age = item.ageS.map { "\(duration(Double($0)))" } ?? "âge non lu"
        return "\(safeLabel(item.name, max: 18)) · \(age)"
    }
}

// MARK: bougies natives

struct CandleChart: View {
    var candles: [Candle]
    var ema9: [Double?]
    var ema21: [Double?]
    var trades: [PaperTrade]
    var entry: Double?
    var notes: [ChartNote] = []          // flèches de lecture (entrée, sommet, sortie, gains rendus, reflux de SOL)
    var gapS: Double = 60                // un trou plus long qu'ça entre deux bougies est marqué d'un trait pointillé (l'axe est par rang, pas par heure)
    @Binding var visible: Int
    @State private var hover: CGPoint?
    @State private var pinchBase: Int?
    @State private var panBack = 0          // bougies reculées dans le temps (glisser vers la droite)
    @State private var panStart = 0

    var body: some View {
        let count = max(10, min(visible, candles.count))
        let back = min(max(0, panBack), max(0, candles.count - count))
        let shown = Array(candles.dropLast(back).suffix(count))
        let off = candles.count - shown.count
        let e9 = Array(ema9.dropLast(back).suffix(shown.count)), e21 = Array(ema21.dropLast(back).suffix(shown.count))
        GeometryReader { g in
            let axisW: CGFloat = 70
            let w = g.size.width - axisW, hAll = g.size.height - 18
            let flowH = hAll * 0.16, h = hAll - flowH - 6
            let lo0 = shown.map(\.l).min() ?? 0, hi0 = shown.map(\.h).max() ?? 1
            let lo = min(lo0, entry ?? lo0), hi = max(hi0, entry ?? hi0)
            let span = max(hi - lo, hi * 0.01)
            // peu de bougies : on garde une largeur de bougie normale (au plus 1/60 de la largeur) et on colle la dernière à droite,
            // au lieu d'étirer 4 bougies sur tout l'écran (barres plates illisibles)
            let slots = max(shown.count, 60)
            let step = w / CGFloat(slots)
            let cw = max(1.5, min(step * 0.68, 14))
            let pad = CGFloat(slots - shown.count) * step
            let x: (Int) -> CGFloat = { pad + CGFloat($0) * step + step / 2 }
            let y: (Double) -> CGFloat = { 4 + (1 - ($0 - lo) / span) * (h - 8) }
            let maxFlow = max(shown.compactMap { $0.flowSol.map(abs) }.max() ?? 0, 0.0001)
            Canvas { ctx, _ in
                for k in 0...4 {
                    let v = lo + span * Double(k) / 4
                    var l = Path(); l.move(to: CGPoint(x: 0, y: y(v))); l.addLine(to: CGPoint(x: w, y: y(v)))
                    ctx.stroke(l, with: .color(.white.opacity(0.05)), lineWidth: 1)
                    ctx.draw(Text(axisUSD(v, step: span / 4)).font(.system(size: 9, design: .rounded)).foregroundStyle(.white.opacity(0.4)), at: CGPoint(x: w + 8, y: y(v)), anchor: .leading)
                }
                for i in shown.indices.dropFirst() where shown[i].t - shown[i - 1].t > gapS {
                    var sep = Path(); sep.move(to: CGPoint(x: x(i) - step / 2, y: 0)); sep.addLine(to: CGPoint(x: x(i) - step / 2, y: h))
                    ctx.stroke(sep, with: .color(.white.opacity(0.3)), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    ctx.draw(Text("trou \(duration(shown[i].t - shown[i - 1].t))").font(.system(size: 8)).foregroundStyle(.white.opacity(0.4)), at: CGPoint(x: x(i) - step / 2 + 4, y: 8), anchor: .leading)
                }
                if shown.count > 1, shown.count < 60 {
                    var line = Path()
                    for (i, c) in shown.enumerated() { let q = CGPoint(x: x(i), y: y(c.c)); if i == 0 { line.move(to: q) } else { line.addLine(to: q) } }
                    ctx.stroke(line, with: .color(.white.opacity(0.3)), lineWidth: 1)
                }
                for (i, c) in shown.enumerated() {
                    let up = c.c >= c.o
                    let col = up ? gain : loss
                    var wick = Path(); wick.move(to: CGPoint(x: x(i), y: y(c.h))); wick.addLine(to: CGPoint(x: x(i), y: y(c.l)))
                    ctx.stroke(wick, with: .color(col.opacity(0.8)), lineWidth: 1)
                    let top = y(max(c.o, c.c)), bot = y(min(c.o, c.c))
                    ctx.fill(Path(roundedRect: CGRect(x: x(i) - cw / 2, y: top, width: cw, height: max(1, bot - top)), cornerRadius: min(1.5, cw / 4)), with: .color(col))
                    if let f = c.flowSol {
                        let bh = CGFloat(abs(f) / maxFlow) * flowH
                        ctx.fill(Path(CGRect(x: x(i) - cw / 2, y: hAll - bh, width: cw, height: bh)), with: .color((f >= 0 ? gain : loss).opacity(0.45)))
                    }
                }
                for (series, color) in [(e9, Color.yellow.opacity(0.85)), (e21, Color(red: 0.7, green: 0.55, blue: 1).opacity(0.85))] {
                    var p = Path(); var started = false
                    for (i, v) in series.enumerated() { guard let v else { continue }; let q = CGPoint(x: x(i), y: y(v)); if started { p.addLine(to: q) } else { p.move(to: q); started = true } }
                    ctx.stroke(p, with: .color(color), lineWidth: 1.2)
                }
                if let e = entry {
                    var l = Path(); l.move(to: CGPoint(x: 0, y: y(e))); l.addLine(to: CGPoint(x: w, y: y(e)))
                    ctx.stroke(l, with: .color(.yellow.opacity(0.85)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    ctx.draw(Text("ton entrée \(formatUSD(e))").font(.system(size: 9, weight: .semibold)).foregroundStyle(.yellow), at: CGPoint(x: 6, y: y(e) < 14 ? y(e) + 9 : y(e) - 8), anchor: .leading)
                }
                // tes trades fictifs : A à l'entrée, V à la sortie (placés sur la bougie de leur heure)
                if let t0 = shown.first?.t, let t1 = shown.last?.t {
                    let iv = shown.count > 1 ? (t1 - t0) / Double(shown.count - 1) : 60
                    func idx(_ d: Date) -> Int? { let s = d.timeIntervalSince1970; guard s >= t0 - iv, s <= t1 + iv else { return nil }; return min(shown.count - 1, max(0, Int(((s - t0) / iv).rounded()))) }
                    for t in trades {
                        if let i = idx(t.openedAt) { marker(ctx, CGPoint(x: x(i), y: y(shown[i].l) + 6), up: true) }
                        if let d = t.closedAt, let i = idx(d) { marker(ctx, CGPoint(x: x(i), y: y(shown[i].h) - 6), up: false) }
                    }
                }
                if !notes.isEmpty, let t0 = shown.first?.t, let t1 = shown.last?.t {
                    let iv = shown.count > 1 ? (t1 - t0) / Double(shown.count - 1) : 60
                    func pos(_ n: ChartNote) -> CGPoint? {
                        guard n.time >= t0 - iv, n.time <= t1 + iv else { return nil }
                        return CGPoint(x: min(w - 4, max(4, x(0) + CGFloat((n.time - t0) / iv) * step)), y: y(n.price))
                    }
                    func col(_ n: ChartNote) -> Color { n.tone == .good ? gain : n.tone == .bad ? loss : .yellow }
                    if let p = notes.first(where: { $0.kind == .peak }).flatMap(pos), let e = notes.first(where: { $0.kind == .exit }).flatMap(pos) {
                        var arrow = Path(); arrow.move(to: p); arrow.addLine(to: e)
                        ctx.stroke(arrow, with: .color(loss.opacity(0.7)), style: StrokeStyle(lineWidth: 1.4, dash: [5, 4]))
                        let a = atan2(e.y - p.y, e.x - p.x)
                        var head = Path(); head.move(to: e)
                        head.addLine(to: CGPoint(x: e.x - 9 * cos(a - 0.45), y: e.y - 9 * sin(a - 0.45)))
                        head.addLine(to: CGPoint(x: e.x - 9 * cos(a + 0.45), y: e.y - 9 * sin(a + 0.45))); head.closeSubpath()
                        ctx.fill(head, with: .color(loss.opacity(0.85)))
                    }
                    var placed: [CGRect] = []   // étiquettes déjà posées : on décale les suivantes pour qu'elles ne se chevauchent pas
                    for n in notes {
                        guard let p = pos(n) else { continue }
                        let c = col(n)
                        let off: CGSize
                        switch n.kind {
                        case .entry: off = CGSize(width: -10, height: 34)
                        case .peak: off = CGSize(width: 0, height: -30)
                        case .exit: off = CGSize(width: 0, height: 34)
                        case .giveBack: off = CGSize(width: 46, height: -2)
                        case .outflow: off = CGSize(width: 0, height: 56)
                        }
                        let r = ctx.resolve(Text(n.label).font(.system(size: 10, weight: .semibold, design: .rounded)).foregroundStyle(.white))
                        let sz = r.measure(in: CGSize(width: 220, height: 30))
                        var lc = CGPoint(x: min(w - sz.width / 2 - 8, max(sz.width / 2 + 8, p.x + off.width)), y: min(h - 12, max(14, p.y + off.height)))
                        func boxAt(_ c: CGPoint) -> CGRect { CGRect(x: c.x - sz.width / 2 - 6, y: c.y - sz.height / 2 - 3, width: sz.width + 12, height: sz.height + 6) }
                        var tries = 0
                        while tries < 6, placed.contains(where: { $0.insetBy(dx: -3, dy: -3).intersects(boxAt(lc)) }) {
                            lc.y = lc.y + (lc.y < h / 2 ? 1 : -1) * (sz.height + 10); tries += 1
                        }
                        if n.kind != .giveBack {
                            var leader = Path(); leader.move(to: p); leader.addLine(to: CGPoint(x: lc.x, y: lc.y + (lc.y > p.y ? -sz.height / 2 - 3 : sz.height / 2 + 3)))
                            ctx.stroke(leader, with: .color(c.opacity(0.75)), lineWidth: 1)
                            ctx.fill(Path(ellipseIn: CGRect(x: p.x - 4.5, y: p.y - 4.5, width: 9, height: 9)), with: .color(c))
                            ctx.stroke(Path(ellipseIn: CGRect(x: p.x - 4.5, y: p.y - 4.5, width: 9, height: 9)), with: .color(.black.opacity(0.6)), lineWidth: 1)
                        }
                        let box = boxAt(lc); placed.append(box)
                        ctx.fill(Path(roundedRect: box, cornerRadius: 7), with: .color(.black.opacity(0.82)))
                        ctx.stroke(Path(roundedRect: box, cornerRadius: 7), with: .color(c.opacity(0.8)), lineWidth: 1)
                        ctx.draw(r, at: lc)
                    }
                }
                if let hp = hover, hp.x < w, !shown.isEmpty {
                    let i = min(shown.count - 1, max(0, Int((hp.x - pad) / step)))
                    let c = shown[i]
                    var v = Path(); v.move(to: CGPoint(x: x(i), y: 0)); v.addLine(to: CGPoint(x: x(i), y: hAll))
                    ctx.stroke(v, with: .color(.white.opacity(0.22)), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    var hl = Path(); hl.move(to: CGPoint(x: 0, y: hp.y)); hl.addLine(to: CGPoint(x: w, y: hp.y))
                    if hp.y < h { ctx.stroke(hl, with: .color(.white.opacity(0.12)), style: StrokeStyle(lineWidth: 1, dash: [2, 3])) }
                    let when = Date(timeIntervalSince1970: c.t).formatted(.dateTime.hour().minute().second())
                    let txt = "O \(formatUSD(c.o))  H \(formatUSD(c.h))  L \(formatUSD(c.l))  C \(formatUSD(c.c))\(c.flowSol.map { "  flux \($0 >= 0 ? "+" : "")\(fmt1($0)) SOL" } ?? "")  ·  \(when)"
                    ctx.draw(Text(txt).font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(.white.opacity(0.85)), at: CGPoint(x: 6, y: 10), anchor: .leading)
                }
                if let a = shown.first, let b = shown.last {
                    ctx.draw(Text(Date(timeIntervalSince1970: a.t).formatted(.dateTime.hour().minute())).font(.system(size: 9)).foregroundStyle(.white.opacity(0.35)), at: CGPoint(x: max(4, pad + 4), y: hAll + 10), anchor: .leading)
                    ctx.draw(Text(Date(timeIntervalSince1970: b.t).formatted(.dateTime.hour().minute())).font(.system(size: 9)).foregroundStyle(.white.opacity(0.35)), at: CGPoint(x: w - 4, y: hAll + 10), anchor: .trailing)
                }
                _ = off
            }
            .onContinuousHover { phase in if case .active(let p) = phase { hover = p } else { hover = nil } }
            .gesture(MagnifyGesture().onChanged { v in
                let base = pinchBase ?? visible
                if pinchBase == nil { pinchBase = visible }
                visible = min(240, max(15, Int(Double(base) / v.magnification)))
            }.onEnded { _ in pinchBase = nil })
            .gesture(DragGesture(minimumDistance: 6).onChanged { v in
                // glisser vers la droite = remonter dans le passé ; vers la gauche = revenir au présent
                let perCandle = max(1, (g.size.width - 70) / CGFloat(max(shown.count, 60)))
                let maxBack = max(0, candles.count - count)
                panBack = min(maxBack, max(0, panStart + Int((v.translation.width / perCandle).rounded())))
            }.onEnded { _ in panStart = panBack })
            .onTapGesture(count: 2) { panBack = 0; panStart = 0 }
        }
        .accessibilityLabel("Bougies du market cap, \(candles.count) bougies")
    }

    func marker(_ ctx: GraphicsContext, _ p: CGPoint, up: Bool) {
        var tri = Path()
        if up { tri.move(to: CGPoint(x: p.x, y: p.y)); tri.addLine(to: CGPoint(x: p.x - 6, y: p.y + 10)); tri.addLine(to: CGPoint(x: p.x + 6, y: p.y + 10)) }
        else { tri.move(to: CGPoint(x: p.x, y: p.y)); tri.addLine(to: CGPoint(x: p.x - 6, y: p.y - 10)); tri.addLine(to: CGPoint(x: p.x + 6, y: p.y - 10)) }
        tri.closeSubpath()
        ctx.fill(tri, with: .color(up ? gain : loss))
        ctx.draw(Text(up ? "A" : "V").font(.system(size: 8, weight: .heavy)).foregroundStyle(.white), at: CGPoint(x: p.x, y: up ? p.y + 16 : p.y - 16))
    }
}

/// Panneau graphique : en-tête du token, choix de l'intervalle et de la source, bougies ou DexScreener.
struct ChartPanel: View {
    var item: Feed.Item
    var market: MarketStore
    var lab: PaperLab
    var now: Date
    @AppStorage("chartSourceV2") private var source = "candles"   // nouvelle clé : l'ancienne pouvait valoir « series »
    @AppStorage("chartVisible") private var visible = 90

    var body: some View {
        let scr = market.screen(item.mint)
        let candles = scr?.chart?.candles ?? []
        let last = scr?.quote?.marketCap ?? candles.last?.c ?? item.marketCap
        let first = candles.suffix(max(10, min(visible, candles.count))).first?.o
        let ch: Double? = (first != nil && last != nil && first! > 0) ? (last! / first! - 1) * 100 : nil
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                TokenAvatar(item: item, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(safeLabel(item.symbol)).font(.system(size: 18, weight: .semibold, design: .rounded)).foregroundStyle(.white).lineLimit(1)
                        Text(safeLabel(item.name, max: 24)).font(.system(size: 11)).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
                    }
                    HStack(spacing: 8) {
                        Text(last.map(formatUSD) ?? "non lu").font(.system(size: 22, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(.white).contentTransition(.numericText()).lineLimit(1).fixedSize()
                        if let ch { Text(pct(ch)).font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(tone(ch)).lineLimit(1).fixedSize() }
                        Text("market cap").font(.system(size: 10)).foregroundStyle(.white.opacity(0.4)).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Picker("", selection: $source) { Text("Bougies").tag("candles"); Text("DexScreener").tag("dex") }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 190).controlSize(.small)
            }
            if source == "candles" {
                // deuxième ligne : dans la colonne centrale, tout sur une ligne faisait passer les noms et les « 1 min » à la ligne
                HStack(spacing: 10) {
                    Spacer(minLength: 0)
                    HStack(spacing: 2) {
                        ForEach([(1, "1 s"), (5, "5 s"), (15, "15 s"), (60, "1 min")], id: \.0) { iv, label in
                            Button(label) { market.interval = iv; Task { await market.loadScreen(item.mint) } }
                                .buttonStyle(.plain).font(.system(size: 10, weight: .semibold, design: .rounded)).lineLimit(1).fixedSize()
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Capsule().fill(.white.opacity(market.interval == iv ? 0.16 : 0)))
                                .foregroundStyle(.white.opacity(market.interval == iv ? 1 : 0.5))
                        }
                    }.padding(2).background(Capsule().fill(.white.opacity(0.05)))
                    HStack(spacing: 6) {
                        Button { visible = min(240, visible + 30) } label: { Image(systemName: "minus.magnifyingglass") }.help("Dézoomer")
                        Button { visible = max(15, visible - 30) } label: { Image(systemName: "plus.magnifyingglass") }.help("Zoomer (ou pince sur le trackpad)")
                    }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                }
            }
            if source == "dex" {
                if dexScreenerURL(mint: item.mint) != nil { DexChart(mint: item.mint).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous)) }
                else { EmptyHint(symbol: "exclamationmark.triangle", text: "Adresse non reconnue : graphique externe indisponible.").frame(maxWidth: .infinity, maxHeight: .infinity) }
            } else if candles.count >= 2 {
                CandleChart(candles: candles, ema9: scr?.chart?.ema9 ?? [], ema21: scr?.chart?.ema21 ?? [],
                            trades: lab.manual.trades.filter { $0.mint == item.mint }, entry: lab.manual.position(item.mint)?.entryMcap, gapS: max(Double(market.interval) * 6, 60), visible: $visible)
                HStack(spacing: 12) {
                    legend(.yellow, "EMA 9"); legend(Color(red: 0.7, green: 0.55, blue: 1), "EMA 21"); legend(gain.opacity(0.6), "flux net SOL")
                    Spacer()
                    Text(scr?.chart?.note ?? "Bougies du market cap, calculées par le serveur.").font(.system(size: 9)).foregroundStyle(.white.opacity(0.35)).lineLimit(1)
                    if let ms = market.screenDuration(item.mint) { Text("serveur \(ms) ms").font(.system(size: 9)).foregroundStyle(.white.opacity(0.35)) }
                    if let at = market.screenAt(item.mint) { Text("lu il y a \(duration(now.timeIntervalSince(at)))").font(.system(size: 9)).foregroundStyle(.white.opacity(0.35)) }
                }
            } else {
                let wait = chartWaitMessage(failure: market.screenFailure(item.mint), warming: scr?.warming == true)
                VStack(spacing: 8) {
                    if isValidMint(item.mint) && wait.loading { ProgressView().controlSize(.small) }
                    Text(isValidMint(item.mint) ? wait.text : "Adresse non reconnue : pas de bougies.")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5)).multilineTextAlignment(.center)
                    if isValidMint(item.mint), !wait.loading {
                        Button("Réessayer") { Task { await market.loadScreen(item.mint) } }.buttonStyle(.plain)
                            .font(.system(size: 10, weight: .semibold)).padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Capsule().fill(.white.opacity(0.12))).foregroundStyle(.white.opacity(0.8))
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(14)
        .background(tile.fill(.white.opacity(0.05)))
        .overlay(tile.strokeBorder(.white.opacity(0.07), lineWidth: 0.5))
    }

    func legend(_ c: Color, _ s: String) -> some View {
        HStack(spacing: 4) { RoundedRectangle(cornerRadius: 1).fill(c).frame(width: 10, height: 2); Text(s).font(.system(size: 9)).foregroundStyle(.white.opacity(0.45)) }
    }
}

// MARK: fiche du token

struct TokenCardPanel: View {
    var item: Feed.Item
    var market: MarketStore
    var now: Date
    var ui: UIState

    var body: some View {
        let hit = market.cards[item.mint]
        Panel(title: "Fiche du token", trailing: hit.map { "lu il y a \(duration(now.timeIntervalSince($0.at)))" }) {
            if isValidMint(item.mint) {
                HStack(spacing: 6) {
                    Text(item.mint).font(.system(size: 9, design: .monospaced)).foregroundStyle(.white.opacity(0.7)).textSelection(.enabled)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button { copyCA(item.mint, ui: ui) } label: { Image(systemName: "doc.on.doc").font(.system(size: 10)) }
                        .buttonStyle(PressStyle()).foregroundStyle(.white.opacity(0.7)).help("Copier l'adresse complète (CA)")
                    Button { openDexScreener(item.mint, ui: ui) } label: { Image(systemName: "arrow.up.right.square").font(.system(size: 10)) }
                        .buttonStyle(PressStyle()).foregroundStyle(.white.opacity(0.7)).help("Ouvrir sur DexScreener (navigateur)")
                }
            }
            if !isValidMint(item.mint) {
                Text("Adresse non reconnue : fiche indisponible.").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
            } else if let h = hit, let c = h.value {
                VStack(alignment: .leading, spacing: 7) {
                    row("Part du dev", c.devPct.map { "\(fmt1($0)) %" }, warn: (c.devPct ?? 0) > 10)
                    row("Top 10 détenteurs", c.top10Pct.map { "\(fmt1($0)) %" }, warn: (c.top10Pct ?? 0) > 40)
                    row("Détenteurs", c.holders.map(String.init), warn: false)
                    row("Autorité mint", authority(c.authorities?.mint), warn: c.authorities?.mint == "active")
                    row("Autorité freeze", authority(c.authorities?.freeze), warn: c.authorities?.freeze == "active")
                    row("Liquidité", c.liquidityUSD.map(formatUSD), warn: false)
                    let socials = (c.socials ?? []).filter { safeSocialURL($0) != nil }
                    if !socials.isEmpty { SocialLinks(socials: socials) }
                    Text("Liens et image déclarés par le créateur : non vérifiés. Ces chiffres ne disent pas si le token est sûr.").font(.system(size: 9)).foregroundStyle(.white.opacity(0.35)).fixedSize(horizontal: false, vertical: true)
                }
            } else if hit != nil {
                Text("Fiche non disponible (serveur à mettre à jour, ou lecture impossible).").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
            } else {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Lecture de la fiche…").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5)) }
            }
        }
    }

    func authority(_ s: String?) -> String? {
        switch s { case "renounced": return "renoncée"; case "active": return "active"; case nil: return nil; default: return s }
    }

    func row(_ k: String, _ v: String?, warn: Bool) -> some View {
        HStack {
            Text(k).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5)).help(Glossary.hint(for: k) ?? "")
            Spacer()
            if warn { Circle().fill(.orange).frame(width: 6, height: 6) }
            Text(v ?? "non lu").font(.system(size: 11, weight: .medium, design: .rounded)).monospacedDigit().foregroundStyle(v == nil ? .white.opacity(0.35) : .white.opacity(0.9))
        }
    }
}

// MARK: liens sociaux avec aperçu au survol

@MainActor
final class PreviewCache {
    static let shared = PreviewCache()
    private var hits: [URL: (at: Date, value: SocialPreview?)] = [:]
    private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.httpCookieAcceptPolicy = .never; c.httpShouldSetCookies = false
        c.timeoutIntervalForRequest = 8
        return URLSession(configuration: c)
    }()

    func cached(_ u: URL) -> SocialPreview?? { hits[u].flatMap { Date().timeIntervalSince($0.at) < 600 ? .some($0.value) : nil } }

    /// Lecture de la page publique (≤ 300 Ko, sans cookies, rien d'exécuté).
    func load(_ u: URL, kind: String) async -> SocialPreview? {
        if let c = cached(u) { return c }
        var value: SocialPreview?
        if let (data, resp) = try? await session.data(from: u), (resp as? HTTPURLResponse)?.statusCode == 200, data.count <= 300_000 {
            value = kind == "twitter" ? parseTweetOEmbed(json: data) : String(data: data, encoding: .utf8).map(parsePreview)
        }
        hits[u] = (Date(), value)
        if hits.count > 200 { hits.removeAll() }
        return value
    }
}

struct SocialLinks: View {
    var socials: [Social]
    @State private var hovered: String?
    @State private var preview: SocialPreview?
    @State private var loading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(socials) { s in
                    if let url = safeSocialURL(s) {
                        let kind = s.kind ?? ""
                        Button { NSWorkspace.shared.open(url) } label: {
                            Label(kind == "twitter" ? "X" : kind == "telegram" ? "Telegram" : "Site", systemImage: kind == "twitter" ? "at" : kind == "telegram" ? "paperplane" : "globe")
                                .font(.system(size: 10, weight: .semibold, design: .rounded)).labelStyle(.titleAndIcon)
                                .padding(.horizontal, 9).padding(.vertical, 5)
                                .background(Capsule().fill(.white.opacity(hovered == url.absoluteString ? 0.16 : 0.08))).foregroundStyle(.white.opacity(0.85))
                        }
                        .buttonStyle(PressStyle()).help(url.absoluteString)
                        .onHover { on in
                            if on { hovered = url.absoluteString; Task { await show(s) } } else if hovered == url.absoluteString { hovered = nil }
                        }
                    }
                }
            }
            if let h = hovered, let s = socials.first(where: { safeSocialURL($0)?.absoluteString == h }) {
                VStack(alignment: .leading, spacing: 4) {
                    if loading { HStack(spacing: 6) { ProgressView().controlSize(.mini); Text("Lecture de l'aperçu…").font(.system(size: 10)).foregroundStyle(.white.opacity(0.5)) } }
                    else if let p = preview {
                        if let t = p.title { Text(t).font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(.white).lineLimit(1) }
                        if let m = p.members { Text(m).font(.system(size: 10, weight: .medium)).foregroundStyle(gain) }
                        if let x = p.text { Text(x).font(.system(size: 10)).foregroundStyle(.white.opacity(0.7)).lineLimit(5).fixedSize(horizontal: false, vertical: true) }
                    } else {
                        Text(s.kind == "twitter" ? "Profil X : aperçu indisponible sans compte (seuls les tweets ont un aperçu). Clique pour ouvrir." : s.kind == "website" ? "Site : clique pour l'ouvrir dans ton navigateur." : "Aperçu indisponible.")
                            .font(.system(size: 10)).foregroundStyle(.white.opacity(0.5)).fixedSize(horizontal: false, vertical: true)
                    }
                    Text("Contenu public de la page, non vérifié.").font(.system(size: 8)).foregroundStyle(.white.opacity(0.3))
                }
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.06)))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeOut(duration: 0.15), value: hovered)
    }

    func show(_ s: Social) async {
        guard let u = previewURL(for: s) else { preview = nil; loading = false; return }
        if let c = PreviewCache.shared.cached(u) { preview = c; loading = false; return }
        loading = true
        let p = await PreviewCache.shared.load(u, kind: s.kind ?? "")
        if hovered == safeSocialURL(s)?.absoluteString { preview = p; loading = false }
    }
}


/// Tokens que le serveur a regardés puis écartés : la raison, et ce qu'ils sont devenus. Information seulement (pas un conseil d'achat).
struct DroppedList: View {
    var items: [DroppedToken]
    var selected: String?
    var pick: (DroppedToken) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ÉCARTÉS RÉCEMMENT · \(items.count)").font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1).foregroundStyle(.white.opacity(0.4)).padding(.top, 8)
            Text("Le serveur les a vus et refusés. Clique pour voir le graphique et la fiche. Ce n'est pas un conseil : l'évolution est mesurée après coup.").font(.system(size: 9)).foregroundStyle(.white.opacity(0.35)).fixedSize(horizontal: false, vertical: true)
            ForEach(items.prefix(25)) { it in
                Button { pick(it) } label: {
                    HStack(spacing: 8) {
                        TokenAvatar(item: Feed.Item(dropped: it), size: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(safeLabel(it.symbol)).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
                            HStack(spacing: 4) {
                                Circle().fill(.orange).frame(width: 5, height: 5)
                                Text(it.reason ?? "raison non lue").font(.system(size: 9)).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
                            }
                        }
                        Spacer(minLength: 4)
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(it.marketCap.map(formatUSD) ?? "non lu").font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(.white.opacity(0.7))
                            if let c = it.lastCheck { Text("\(pct(c.pct)) à \(c.label)").font(.system(size: 9, design: .rounded)).foregroundStyle(c.pct >= 0 ? Color.green.opacity(0.8) : Color.red.opacity(0.8)) }
                            else { Text("pas encore mesuré").font(.system(size: 9)).foregroundStyle(.white.opacity(0.35)) }
                        }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(it.mint == selected ? 0.12 : 0.02)))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(it.mint == selected ? 0.2 : 0), lineWidth: 1))
                    .contentShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("\(safeLabel(it.symbol)), écarté : \(it.reason ?? "raison non lue")")
                .accessibilityAddTraits(it.mint == selected ? .isSelected : [])
            }
        }
    }
}
