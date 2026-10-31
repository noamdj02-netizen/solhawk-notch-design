import SwiftUI
import SolHawkNotchCore

// Dashboard de SIMULATION : tout est fictif. Aucun bouton ne passe d'ordre réel ; aucune clé n'existe dans l'app.

private let tile = RoundedRectangle(cornerRadius: 16, style: .continuous)
let gain = Color(red: 0.20, green: 0.83, blue: 0.60)
let loss = Color(red: 1.0, green: 0.36, blue: 0.36)
func tone(_ v: Double) -> Color { v > 0.0001 ? gain : v < -0.0001 ? loss : .white.opacity(0.7) }

struct Eyebrow: View {
    var text: String
    var body: some View {
        Text(text.uppercased()).font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1.1).foregroundStyle(.white.opacity(0.42))
            .help(Glossary.hint(for: text) ?? "")   // mot du métier : définition au survol
    }
}

/// Pastille « SIMULATION » : visible partout où un montant apparaît.
struct SimBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(Color.yellow).frame(width: 5, height: 5)
            Text("SIMULATION").font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(0.6)
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Capsule().fill(Color.yellow.opacity(0.12)))
        .foregroundStyle(Color.yellow.opacity(0.95))
        .accessibilityLabel("Simulation, argent fictif")
    }
}

struct Panel<Content: View>: View {
    var title: String
    var trailing: String? = nil
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Eyebrow(text: title); Spacer(); if let trailing { Text(trailing).font(.system(size: 10)).foregroundStyle(.white.opacity(0.4)) } }
            content
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .topLeading)
        .background(tile.fill(.white.opacity(0.05)))
        .overlay(tile.strokeBorder(.white.opacity(0.07), lineWidth: 0.5))
    }
}

struct KPI: View {
    var label: String
    var value: String
    var sub: String? = nil
    var color: Color = .white
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Eyebrow(text: label)
            Text(value).font(.system(size: 22, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            if let sub { Text(sub).font(.system(size: 10)).foregroundStyle(.white.opacity(0.45)).lineLimit(1) }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(tile.fill(.white.opacity(0.05)))
        .overlay(tile.strokeBorder(.white.opacity(0.07), lineWidth: 0.5))
        .accessibilityElement(children: .combine)
    }
}

/// Courbe de capital : ligne de départ en pointillés, aire teintée selon gain/perte.
struct EquityChart: View {
    var points: [EquityPoint]
    var start: Double
    var compact = false
    @State private var hover: CGFloat?

    var body: some View {
        if points.count < 2 || points.allSatisfy({ abs($0.equity - start) < 0.005 }) {
            VStack(spacing: 6) {
                Image(systemName: compact ? "minus" : "chart.xyaxis.line").font(.system(size: compact ? 10 : 18)).foregroundStyle(.white.opacity(0.3))
                if !compact { Text(points.count < 2 ? "La courbe apparaît après les premiers trades fictifs." : "Aucun trade pour l'instant : en attente d'un signal.").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5)).multilineTextAlignment(.center) }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let last = points.last!.equity
            let c = tone(last - start)
            Canvas { ctx, size in
                let vals = points.map(\.equity) + [start]
                let lo = vals.min()!, hi = vals.max()!
                let span = max(hi - lo, max(start, 1) * 0.04)
                let t0 = points.first!.at, t1 = points.last!.at
                let tspan = max(t1.timeIntervalSince(t0), 1)
                func y(_ v: Double) -> CGFloat { size.height - 4 - (v - lo) / span * (size.height - 8) }
                func x(_ d: Date) -> CGFloat { 2 + d.timeIntervalSince(t0) / tspan * (size.width - 4) }
                var base = Path(); base.move(to: CGPoint(x: 0, y: y(start))); base.addLine(to: CGPoint(x: size.width, y: y(start)))
                ctx.stroke(base, with: .color(.white.opacity(0.18)), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                var line = Path()
                for (i, p) in points.enumerated() { let q = CGPoint(x: x(p.at), y: y(p.equity)); i == 0 ? line.move(to: q) : line.addLine(to: q) }
                var area = line
                area.addLine(to: CGPoint(x: x(t1), y: size.height)); area.addLine(to: CGPoint(x: x(t0), y: size.height)); area.closeSubpath()
                ctx.fill(area, with: .linearGradient(Gradient(colors: [c.opacity(0.25), c.opacity(0)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                ctx.stroke(line, with: .color(c), style: StrokeStyle(lineWidth: compact ? 1.4 : 2, lineCap: .round, lineJoin: .round))
                let end = CGPoint(x: x(t1), y: y(last))
                if !compact {
                    ctx.fill(Path(ellipseIn: CGRect(x: end.x - 7, y: end.y - 7, width: 14, height: 14)), with: .color(c.opacity(0.2)))
                }
                ctx.fill(Path(ellipseIn: CGRect(x: end.x - 3, y: end.y - 3, width: 6, height: 6)), with: .color(c))
                // viseur : le point de la courbe le plus proche de la souris, avec sa valeur et son heure
                if !compact, let hx = hover, let near = points.min(by: { abs(x($0.at) - hx) < abs(x($1.at) - hx) }) {
                    let q = CGPoint(x: x(near.at), y: y(near.equity))
                    var v = Path(); v.move(to: CGPoint(x: q.x, y: 0)); v.addLine(to: CGPoint(x: q.x, y: size.height))
                    ctx.stroke(v, with: .color(.white.opacity(0.25)), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    ctx.fill(Path(ellipseIn: CGRect(x: q.x - 4, y: q.y - 4, width: 8, height: 8)), with: .color(c))
                    let d = near.equity - start
                    let label = "\(money(near.equity)) · \(money(d, signed: true)) · \(near.at.formatted(date: .omitted, time: .standard))"
                    ctx.draw(Text(label).font(.system(size: 10, weight: .semibold, design: .rounded)).foregroundStyle(.white),
                             at: CGPoint(x: min(max(q.x, 110), size.width - 110), y: q.y < 24 ? q.y + 16 : q.y - 14), anchor: .center)
                }
            }
            .onContinuousHover { phase in if case .active(let p) = phase { hover = p.x } else { hover = nil } }
            .accessibilityLabel("Courbe de capital fictif, \(money(last)) pour un départ à \(money(start))")
        }
    }
}

// MARK: onglet Trades

struct TradesView: View {
    var lab: PaperLab
    var store: FeedStore
    var ui: UIState
    var now: Date
    @State private var confirmReset = false
    @State private var scope = "Moi"
    @Environment(MarketStore.self) private var market

    var body: some View {
        let b = lab.manual
        Group {
            if let id = ui.tradeDetail, let found = lab.trade(id) {
                TradeDetailView(t: found.trade, owner: found.owner, lab: lab, ui: ui, now: now).transition(.move(edge: .trailing).combined(with: .opacity))
            } else if ui.fullScreen && b.trades.isEmpty && b.pending.isEmpty && !(market.extTrades.map { !$0.isEmpty } ?? false) { FirstSimulation(lab: lab, ui: ui, now: now)
            } else if ui.fullScreen { full(b) } else { compact(b) }
        }
        // trades fictifs de l'extension (GET) : relus toutes les 20 s, seulement tant que l'onglet Trades est à l'écran
        .task {
            while !Task.isCancelled {
                await market.loadExtTrades()
                try? await Task.sleep(for: .seconds(20))
            }
        }
    }

    func header(_ b: PaperBook) -> some View {
        HStack(spacing: 10) {
            Text("Mes trades").font(.system(size: ui.fullScreen ? 22 : 15, weight: .semibold, design: .rounded)).tracking(-0.3).foregroundStyle(.white)
            SimBadge()
            Spacer()
            if ui.fullScreen {
                Text("Mise").font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
                StakePicker(lab: lab)
                Button(confirmReset ? "Confirmer (l'ancien est archivé)" : "Remettre à zéro") {
                    if confirmReset { lab.reset(now: now); confirmReset = false; ui.flash("Simulation remise à zéro · ancienne archivée") }
                    else { withAnimation(.snappy) { confirmReset = true }; Task { try? await Task.sleep(for: .seconds(3)); confirmReset = false } }
                }
                .buttonStyle(.plain).font(.system(size: 10, weight: .medium)).foregroundStyle(confirmReset ? loss : .white.opacity(0.55))
                .padding(.horizontal, 10).padding(.vertical, 5).background(Capsule().fill(.white.opacity(confirmReset ? 0.1 : 0.05)))
            }
        }
    }

    func kpis(_ b: PaperBook, full: Bool) -> some View {
        let n = b.closed.count
        return HStack(spacing: 10) {
            KPI(label: "Capital fictif", value: money(b.equity), sub: "départ \(money(b.startCash)) · libre \(money(b.cash))")
            KPI(label: "Résultat net estimé", value: money(b.pnlUSD, signed: true), sub: pct(b.pnlPct), color: tone(b.pnlUSD))
            if full {
                KPI(label: "Trades fermés", value: "\(n)", sub: "\(b.open.count) en cours · \(b.pending.count) en attente")
                KPI(label: "Réussite", value: b.winRate.map { String(format: "%.0f %%", $0) } ?? "—", sub: n < 30 ? "échantillon trop petit" : "\(n) trades")
                KPI(label: "Pire baisse", value: pct(b.maxDrawdownPct), sub: "depuis un sommet", color: b.maxDrawdownPct < -0.01 ? loss : .white)
                KPI(label: "Non exécutés", value: "\(b.canceled)", sub: "prix parti / plus de prix")
            } else {
                KPI(label: "En cours", value: "\(b.open.count)", sub: "\(n) fermés")
            }
        }
    }

    func full(_ b: PaperBook) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header(b)
                kpis(b, full: true)
                HStack(alignment: .top, spacing: 12) {
                    Panel(title: "Capital fictif", trailing: "pointillés = départ") { EquityChart(points: b.equityCurve, start: b.startCash).frame(height: 240) }
                        .frame(maxWidth: .infinity)
                    Panel(title: "Positions ouvertes", trailing: b.pending.isEmpty ? nil : "\(b.pending.count) ordre(s) en attente") { positions(b, limit: 8) }
                        .frame(width: 380)
                }
                ExtensionTradesSection(store: store, ui: ui, now: now)
                scopePicker
                diagnosisPanel
                HStack(alignment: .top, spacing: 12) {
                    Panel(title: "Historique · touche une ligne pour l'analyse", trailing: "\(scopedClosed.count) trade(s)") {
                        VStack(alignment: .trailing, spacing: 8) {
                            Button { exportTradesCSV(lab.allTrades().filter { scope == "Tout" || ($0.owner == "Moi") == (scope == "Moi") }, ui: ui) } label: {
                                Label("Exporter en CSV", systemImage: "square.and.arrow.up").font(.system(size: 10, weight: .semibold, design: .rounded))
                                    .padding(.horizontal, 10).padding(.vertical, 4).background(Capsule().fill(.white.opacity(0.1))).foregroundStyle(.white.opacity(0.75))
                            }.buttonStyle(PressStyle())
                            history(b)
                        }
                    }.frame(maxWidth: .infinity)
                    VStack(spacing: 12) {
                        Panel(title: "Statistiques", trailing: "trades fermés") { statsGrid(b) }
                        Panel(title: "Par stratégie", trailing: "trades fermés") { byStrategy(b) }
                        Panel(title: "Pas achetés", trailing: "depuis que l'app les a vus") { missed() }
                    }.frame(width: 380)
                }
                footnote(b)
            }
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
    }

    func compact(_ b: PaperBook) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header(b)
            kpis(b, full: false)
            Panel(title: "Positions ouvertes", trailing: "F : dashboard complet") { positions(b, limit: 3) }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder func positions(_ b: PaperBook, limit: Int) -> some View {
        if b.open.isEmpty && b.pending.isEmpty {
            EmptyHint(symbol: "hand.tap", text: "Aucune position. Touche « Acheter » sur une carte du Direct : l'ordre est fictif, rempli au prix lu ~\(Int(lab.costs.latencyS)) s plus tard.")
        } else {
            VStack(spacing: 6) {
                ForEach(b.pending.filter { $0.side == .buy }) { o in
                    HStack {
                        ProgressView().controlSize(.mini)
                        Text(o.symbol).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                        Text("achat \(money(o.stakeUSD)) en cours…").font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                        Spacer()
                    }
                }
                ForEach(b.open.prefix(limit)) { t in PositionRow(t: t, lab: lab, ui: ui, now: now, pendingSell: b.pending.contains { $0.mint == t.mint && $0.side == .sell }) }
            }
        }
    }

    @ViewBuilder func history(_ b: PaperBook) -> some View {
        let rows = Array(scopedClosed.prefix(40))
        if rows.isEmpty {
            EmptyHint(symbol: "clock.arrow.circlepath", text: "Tes trades fermés s'afficheront ici, avec le résultat net estimé et la raison de sortie.")
        } else {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    ForEach([("Token", 90.0), ("Ouvert", 70), ("Durée", 56), ("Mise", 60), ("Entrée", 70), ("Sortie", 70), ("Net", 74), ("%", 60)], id: \.0) { Eyebrow(text: $0.0).frame(width: $0.1, alignment: .leading) }
                    Eyebrow(text: "Raison"); Spacer()
                }.padding(.bottom, 6)
                ForEach(rows, id: \.trade.id) { r in
                    Divider().overlay(.white.opacity(0.06))
                    HistoryRow(t: r.trade, owner: scope == "Moi" ? nil : r.owner, lab: lab, ui: ui)
                }
            }
        }
    }

    /// Trades fermés du périmètre choisi (les tiens, ceux des robots, ou tout), les plus récents d'abord.
    var scopedClosed: [(owner: String, trade: PaperTrade)] {
        lab.allTrades().filter { !$0.trade.isOpen && (scope == "Tout" || (scope == "Moi") == ($0.owner == "Moi")) }
            .sorted { ($0.trade.closedAt ?? .distantPast) > ($1.trade.closedAt ?? .distantPast) }
    }

    var scopePicker: some View {
        HStack(spacing: 8) {
            Text("Voir").font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
            HStack(spacing: 2) {
                ForEach(["Moi", "Robots", "Tout"], id: \.self) { k in
                    Button(k) { withAnimation(.snappy(duration: 0.2)) { scope = k } }
                        .buttonStyle(.plain).font(.system(size: 11, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 12).padding(.vertical, 4)
                        .background(Capsule().fill(.white.opacity(scope == k ? 0.16 : 0)))
                        .foregroundStyle(.white.opacity(scope == k ? 1 : 0.5))
                }
            }.padding(2).background(Capsule().fill(.white.opacity(0.05)))
            Text(scope == "Moi" ? "tes ordres fictifs" : scope == "Robots" ? "les 5 robots (fictifs eux aussi)" : "toi + les robots").font(.system(size: 10)).foregroundStyle(.white.opacity(0.35))
            Spacer()
        }
    }

    /// Diagnostic : ce qui t'a le plus coûté, les motifs qui reviennent, comment tu sors et selon la durée.
    @ViewBuilder var diagnosisPanel: some View {
        let closed = scopedClosed.map(\.trade)
        let d = diagnoseHistory(closed, before: { lab.pointsBefore($0) })
        Panel(title: "Diagnostic de ton historique", trailing: d.enoughData ? "\(d.closedCount) trades" : "\(d.closedCount) trade(s) : échantillon trop petit") {
            if closed.isEmpty {
                EmptyHint(symbol: "stethoscope", text: "Dès ton premier trade fermé, ici : ce qui t'a le plus coûté, avec des flèches sur le graphique pour voir où ça a tourné.")
            } else if d.worst.isEmpty {
                EmptyHint(symbol: "checkmark.seal", text: "Aucune perte dans ce périmètre pour l'instant. Rien à diagnostiquer, mais \(closed.count) trade(s) ne prouvent pas grand-chose.")
            } else {
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Eyebrow(text: "Ce qui t'a le plus coûté")
                        ForEach(d.worst) { w in
                            let t = closed.first { $0.id == w.id }
                            Button { withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { ui.tradeDetail = w.id } } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    TokenAvatar(mint: w.mint, symbol: w.symbol, image: t?.image, size: 30)
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text(w.symbol).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                                            Text(w.cause.title).font(.system(size: 9, weight: .bold, design: .rounded)).padding(.horizontal, 6).padding(.vertical, 2).background(Capsule().fill(loss.opacity(0.18))).foregroundStyle(loss)
                                            Spacer()
                                            Text("\(money(w.pnlUSD, signed: true)) · \(pct(w.pnlPct))").font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(loss)
                                        }
                                        Text(w.headline).font(.system(size: 10)).foregroundStyle(.white.opacity(0.6)).fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
                                        Text("Voir sur le graphique →").font(.system(size: 9, weight: .semibold)).foregroundStyle(.white.opacity(0.4))
                                    }
                                }
                                .padding(8).background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.04))).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: 8) {
                        Eyebrow(text: "Ce qui revient")
                        ForEach(d.patterns, id: \.self) { p in
                            HStack(alignment: .top, spacing: 6) { Text("•").foregroundStyle(.white.opacity(0.4)); Text(p).fixedSize(horizontal: false, vertical: true) }
                                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.7))
                        }
                        Eyebrow(text: "Comment tu sors")
                        bucketRows(d.exits)
                        Eyebrow(text: "Selon la durée")
                        bucketRows(d.holds)
                        if !d.enoughData { Text("Moins de 30 trades : ces motifs peuvent être du hasard.").font(.system(size: 9)).foregroundStyle(.white.opacity(0.35)) }
                    }.frame(width: 340, alignment: .leading)
                }
            }
        }
    }

    func bucketRows(_ rows: [ExitBucket]) -> some View {
        VStack(spacing: 3) {
            ForEach(rows) { r in
                HStack {
                    Text(r.name).foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    Text("\(r.count)").foregroundStyle(.white.opacity(0.4))
                    Text(money(r.netUSD, signed: true)).monospacedDigit().foregroundStyle(tone(r.netUSD)).frame(width: 70, alignment: .trailing)
                }.font(.system(size: 10, design: .rounded))
            }
        }
    }

    /// Chiffres qui comptent pour juger un trader : gain moyen contre perte moyenne, facteur de profit, durée, extrêmes, coûts payés.
    @ViewBuilder func statsGrid(_ b: PaperBook) -> some View {
        let c = b.closed
        if c.isEmpty {
            EmptyHint(symbol: "chart.bar", text: "Les statistiques apparaissent après ton premier trade fermé.")
        } else {
            let wins = c.filter { $0.pnlUSD > 0 }, losses = c.filter { $0.pnlUSD < 0 }
            let gross = wins.reduce(0) { $0 + $1.pnlUSD }, lost = -losses.reduce(0) { $0 + $1.pnlUSD }
            let avgWin = wins.isEmpty ? nil : wins.reduce(0) { $0 + $1.pnlPct } / Double(wins.count)
            let avgLoss = losses.isEmpty ? nil : losses.reduce(0) { $0 + $1.pnlPct } / Double(losses.count)
            let best = c.max { $0.pnlUSD < $1.pnlUSD }, worst = c.min { $0.pnlUSD < $1.pnlUSD }
            let hold = c.reduce(0) { $0 + $1.holdS } / Double(c.count)
            let costs = b.trades.reduce(0) { $0 + $1.costsUSD }
            let cells: [(String, String, Color)] = [
                ("Gain moyen", avgWin.map { pct($0) } ?? "—", gain),
                ("Perte moyenne", avgLoss.map { pct($0) } ?? "—", loss),
                ("Facteur de profit", lost > 0 ? String(format: "%.2f", gross / lost) : (gross > 0 ? "∞" : "—"), .white),
                ("Durée moyenne", duration(hold), .white),
                ("Meilleur trade", best.map { "\(safeLabel($0.symbol)) \(pct($0.pnlPct))" } ?? "—", gain),
                ("Pire trade", worst.map { "\(safeLabel($0.symbol)) \(pct($0.pnlPct))" } ?? "—", loss),
                ("Gagnants / perdants", "\(wins.count) / \(losses.count)", .white),
                ("Frais + glissement", money(costs), .white.opacity(0.85)),
                ("Pire série de pertes", "\(longestLosingStreak(c)) d'affilée", loss),
                ("Net par trade", money(c.reduce(0) { $0 + $1.pnlUSD } / Double(c.count), signed: true), tone(c.reduce(0) { $0 + $1.pnlUSD })),
            ]
            VStack(spacing: 8) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], alignment: .leading, spacing: 10) {
                    ForEach(cells, id: \.0) { k, v, col in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(v).font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(col).lineLimit(1).minimumScaleFactor(0.7)
                            Text(k).font(.system(size: 9)).foregroundStyle(.white.opacity(0.4)).lineLimit(1)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if c.count < 30 { Text("Moins de 30 trades : ces moyennes peuvent être du hasard.").font(.system(size: 9)).foregroundStyle(.white.opacity(0.35)).frame(maxWidth: .infinity, alignment: .leading) }
            }
        }
    }

    @ViewBuilder func byStrategy(_ b: PaperBook) -> some View {
        let s = strategyStats(b.trades)
        if s.isEmpty {
            EmptyHint(symbol: "tag", text: "Choisis une stratégie dans le panneau d'ordre avant d'acheter : ici, tu verras laquelle marche le mieux pour toi (en fictif).")
        } else {
            VStack(spacing: 6) {
                ForEach(s) { x in
                    HStack {
                        Text(x.name).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                        Spacer()
                        Text("\(x.count) · \(Int(x.winRate.rounded())) % gagnants").font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                        Text(money(x.netUSD, signed: true)).font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(tone(x.netUSD)).frame(width: 70, alignment: .trailing)
                    }
                }
                Text("Petit échantillon : un écart entre stratégies peut être du hasard.").font(.system(size: 9)).foregroundStyle(.white.opacity(0.35))
            }
        }
    }

    @ViewBuilder func missed() -> some View {
        let m = lab.missed(limit: 8)
        if m.isEmpty {
            EmptyHint(symbol: "eye", text: "Les tokens vus mais pas achetés apparaîtront ici, avec ce qu'ils sont devenus. Utile pour voir ce que tu rates… et ce que tu évites.")
        } else {
            VStack(spacing: 6) {
                ForEach(m) { x in
                    let meta = lab.meta[x.mint]
                    HStack(spacing: 10) {
                        TokenAvatar(mint: x.mint, symbol: meta?.symbol, image: meta?.image, size: 28)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(safeLabel(meta?.symbol)).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                            Text("vu à \(formatUSD(x.firstMcap)) · plus haut \(pct(x.peakPct))").font(.system(size: 9)).foregroundStyle(.white.opacity(0.45))
                        }
                        Spacer()
                        Text(pct(x.changePct)).font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(tone(x.changePct))
                    }
                    .padding(.vertical, 3)
                }
                Text("Prix bruts, sans frais : un token « raté » à +100 % n'aurait pas forcément été un gain après coûts et délai.").font(.system(size: 9)).foregroundStyle(.white.opacity(0.35)).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    func footnote(_ b: PaperBook) -> some View {
        Text("Résultats NETS ESTIMÉS : frais \(fmt1(lab.costs.feePct)) % + \(money(lab.costs.priorityUSD)) par ordre, glissement selon la taille, délai \(Int(lab.costs.latencyS)) s. Le flux ne donne pas la vraie liquidité : le glissement est une hypothèse. \(b.closed.count < 30 ? "Moins de 30 trades : ne conclus rien." : "") Simulation seulement : aucun ordre réel n'est possible depuis cette app.")
            .font(.system(size: 10)).foregroundStyle(.white.opacity(0.4)).fixedSize(horizontal: false, vertical: true)
    }
}

/// Écran d'accueil de la page Trades tant qu'il n'y a aucun trade : 3 étapes, le capital de départ, et un bouton pour y aller.
struct FirstSimulation: View {
    var lab: PaperLab
    var ui: UIState
    var now: Date
    @Environment(MarketStore.self) private var market
    @State private var capital = 100.0

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 10) { Text("Ta première simulation").font(.system(size: 30, weight: .semibold, design: .rounded)).tracking(-0.6).foregroundStyle(.white); SimBadge() }
            Text("Tu trades avec de l'argent fictif, sur le vrai marché, avec de vrais délais et des frais estimés. Chaque trade est gardé, relu et comparé aux robots. Rien de réel, aucun risque.")
                .font(.system(size: 14)).foregroundStyle(.white.opacity(0.65)).frame(maxWidth: 640, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 14) {
                stepCard(1, "hand.point.up.left", "Choisis un token", "Dans le Terminal, colonne de gauche. Regarde sa fiche : dev, détenteurs, autorités.")
                stepCard(2, "plus.circle", "Achète en fictif", "Un clic sur 0,2 ou 0,5 SOL. L'ordre est rempli au prix lu ~2 s plus tard, comme en vrai.")
                stepCard(3, "chart.bar.doc.horizontal", "Relis ton trade", "Ici, l'analyse : entré trop tard ? sorti trop tôt ? frais trop lourds ? Et tu compares aux robots.")
            }
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow(text: "Capital fictif de départ")
                HStack(spacing: 8) {
                    ForEach([100.0, 500, 1000, 5000], id: \.self) { v in
                        Button(money(v) + (solText(v, solUSD: market.live?.new?.solUSD).map { " · ≈ \($0)" } ?? "")) { capital = v }
                            .buttonStyle(.plain).font(.system(size: 13, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(Capsule().fill(.white.opacity(capital == v ? 0.16 : 0.05)))
                            .foregroundStyle(.white.opacity(capital == v ? 1 : 0.6))
                    }
                    Text("actuel : \(money(lab.manual.startCash))").font(.system(size: 11)).foregroundStyle(.white.opacity(0.4)).padding(.leading, 6)
                }
            }
            HStack(spacing: 10) {
                Button {
                    if capital != lab.manual.startCash { lab.reset(now: now, startCash: capital) }
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { ui.tab = .live }
                } label: {
                    Label("Aller au Terminal", systemImage: "arrow.right").font(.system(size: 14, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 20).frame(height: 44).background(Capsule().fill(.white)).foregroundStyle(.black)
                }.buttonStyle(PressStyle())
                Button {
                    if capital != lab.manual.startCash { lab.reset(now: now, startCash: capital) }
                    ui.guided = true
                    ui.focusMint = market.allItems(feed: nil).first?.mint ?? ui.focusMint
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { ui.tab = .live }
                } label: {
                    Label("Lancer une simulation guidée", systemImage: "sparkles").font(.system(size: 14, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 20).frame(height: 44).background(Capsule().fill(.white.opacity(0.1))).foregroundStyle(.white)
                }.buttonStyle(PressStyle())
                Text("Astuce : B achète, S vend le token affiché (au clavier).").font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 30).padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    func stepCard(_ n: Int, _ icon: String, _ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon).font(.system(size: 18, weight: .semibold)).foregroundStyle(gain)
                Spacer()
                Text(String(format: "%02d", n)).font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(.white.opacity(0.3))
            }
            Text(title).font(.system(size: 16, weight: .semibold, design: .rounded)).foregroundStyle(.white)
            Text(text).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6)).fixedSize(horizontal: false, vertical: true)
        }
        .padding(18).frame(maxWidth: 300, minHeight: 170, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.07), lineWidth: 0.5))
    }
}

struct StakePicker: View {
    var lab: PaperLab
    var values: [Double] = [5, 10, 25]
    var body: some View {
        HStack(spacing: 2) {
            ForEach(values, id: \.self) { v in
                Button(money(v)) { withAnimation(.snappy) { lab.stakeUSD = v } }
                    .buttonStyle(.plain).font(.system(size: 10, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Capsule().fill(.white.opacity(lab.stakeUSD == v ? 0.16 : 0)))
                    .foregroundStyle(.white.opacity(lab.stakeUSD == v ? 1 : 0.5))
                    .accessibilityAddTraits(lab.stakeUSD == v ? .isSelected : [])
            }
        }
        .padding(2).background(Capsule().fill(.white.opacity(0.05)))
    }
}

struct PositionRow: View {
    var t: PaperTrade
    var lab: PaperLab
    var ui: UIState
    var now: Date
    var pendingSell: Bool
    @State private var hover = false

    var body: some View {
        let stale = now.timeIntervalSince(t.lastSeen) > 30
        HStack(spacing: 10) {
            TokenAvatar(mint: t.mint, symbol: t.symbol, image: t.image, size: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(t.symbol).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                Text(stale ? "prix non lu depuis \(duration(now.timeIntervalSince(t.lastSeen)))" : "entrée \(formatUSD(t.entryMcap)) · \(duration(t.holdS))")
                    .font(.system(size: 9)).foregroundStyle(stale ? .orange : .white.opacity(0.45)).lineLimit(1)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 2) {
                Text(pct(t.pnlPct)).font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(tone(t.pnlUSD)).contentTransition(.numericText())
                Text(money(t.pnlUSD, signed: true)).font(.system(size: 9, design: .rounded)).monospacedDigit().foregroundStyle(.white.opacity(0.45))
            }
            if pendingSell {
                ProgressView().controlSize(.mini).frame(width: 64)
            } else {
                HStack(spacing: 4) {
                    smallButton("½") { ui.flash(lab.sell(mint: t.mint, fraction: 0.5, seenMcap: t.lastMcap, now: Date())) }
                    smallButton("Vendre", strong: true) { ui.flash(lab.sell(mint: t.mint, fraction: 1, seenMcap: t.lastMcap, now: Date())); ui.onTrade?(t.pnlUSD >= 0 ? .soldWin : .soldLoss) }
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(.white.opacity(hover ? 0.07 : 0.03)))
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { ui.tab = .trades; ui.tradeDetail = t.id } }
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.15), value: hover)
    }

    func smallButton(_ label: String, strong: Bool = false, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            Text(label).font(.system(size: 10, weight: .semibold, design: .rounded)).lineLimit(1).fixedSize()
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(Capsule().fill(strong ? loss.opacity(0.22) : .white.opacity(0.1)))
                .foregroundStyle(strong ? loss : .white.opacity(0.85))
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(label == "½" ? "Vendre la moitié, fictif" : "Tout vendre, fictif")
    }
}

struct EmptyHint: View {
    var symbol: String
    var text: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).font(.system(size: 14)).foregroundStyle(.white.opacity(0.35))
            Text(text).font(.system(size: 11)).foregroundStyle(.white.opacity(0.55)).fixedSize(horizontal: false, vertical: true)
        }.padding(.vertical, 6)
    }
}

struct HistoryRow: View {
    var t: PaperTrade
    var owner: String? = nil
    var lab: PaperLab
    var ui: UIState
    @State private var open = false
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { withAnimation(.snappy(duration: 0.22)) { open.toggle() } } label: {
                HStack(spacing: 8) {
                    Image(systemName: open ? "chevron.down" : "chevron.right").font(.system(size: 8, weight: .bold)).foregroundStyle(.white.opacity(0.35)).frame(width: 8)
                    HStack(spacing: 6) { TokenAvatar(mint: t.mint, symbol: t.symbol, image: t.image, size: 18); Text(t.symbol).font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(.white) }.frame(width: 90, alignment: .leading)
                    Text(t.openedAt, format: .dateTime.hour().minute()).frame(width: 62, alignment: .leading)
                    Text(duration(t.holdS)).frame(width: 56, alignment: .leading)
                    Text(money(t.stakeUSD)).frame(width: 56, alignment: .leading)
                    Text(formatUSD(t.entryMcap)).frame(width: 66, alignment: .leading)
                    Text(t.exitMcap.map(formatUSD) ?? "—").frame(width: 66, alignment: .leading)
                    Text(money(t.pnlUSD, signed: true)).foregroundStyle(tone(t.pnlUSD)).frame(width: 70, alignment: .leading)
                    Text(pct(t.pnlPct)).foregroundStyle(tone(t.pnlUSD)).frame(width: 60, alignment: .leading)
                    Text((owner.map { "\($0) · " } ?? "") + (t.exitReason ?? "")).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
                    Spacer(minLength: 0)
                    Button("Détail") { withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { ui.tradeDetail = t.id } }
                        .buttonStyle(.plain).font(.system(size: 10, weight: .semibold, design: .rounded)).padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(.white.opacity(0.08))).foregroundStyle(.white.opacity(0.8))
                }
                .font(.system(size: 11, design: .rounded)).monospacedDigit().foregroundStyle(.white.opacity(0.8))
                .frame(height: 30).contentShape(Rectangle())
            }.buttonStyle(.plain)
            if open { NotesList(notes: review(t, before: lab.pointsBefore(t))).padding(.leading, 16).padding(.bottom, 6) }
        }
    }
}

/// Détail d'un trade : bougies avec entrée et sortie, chronologie, coûts, fiche au clic, analyse.
struct TradeDetailView: View {
    var t: PaperTrade
    var owner: String = "Moi"
    var lab: PaperLab
    var ui: UIState
    var now: Date
    @Environment(MarketStore.self) private var market
    @State private var visible = 120

    var body: some View {
        let scr = market.screen(t.mint)
        let candles = scr?.chart?.candles ?? []
        let notes = chartNotes(for: t, candles: candles, now: now)
        let dx = diagnose(t, before: lab.pointsBefore(t))
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Button { withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { ui.tradeDetail = nil } } label: {
                        Label("Mes trades", systemImage: "chevron.left").font(.system(size: 12, weight: .semibold, design: .rounded))
                    }.buttonStyle(.plain).foregroundStyle(.white.opacity(0.7))
                    Spacer()
                    SimBadge()
                }
                HStack(spacing: 14) {
                    TokenAvatar(mint: t.mint, symbol: t.symbol, image: t.image, size: 56)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(t.symbol).font(.system(size: 22, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                            Text(t.entryReason).font(.system(size: 10, weight: .semibold, design: .rounded)).padding(.horizontal, 8).padding(.vertical, 3).background(Capsule().fill(.white.opacity(0.1))).foregroundStyle(.white.opacity(0.75))
                            if owner != "Moi" { Label(owner, systemImage: "cpu").font(.system(size: 10, weight: .semibold, design: .rounded)).padding(.horizontal, 8).padding(.vertical, 3).background(Capsule().fill(Color.blue.opacity(0.18))).foregroundStyle(.blue.opacity(0.9)) }
                            Text(t.isOpen ? "en cours" : "fermé").font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
                        }
                        Text(t.openedAt.formatted(date: .abbreviated, time: .standard)).font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(pct(t.pnlPct)).font(.system(size: 28, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(tone(t.pnlUSD))
                        Text("\(money(t.pnlUSD, signed: true)) net estimé").font(.system(size: 11, design: .rounded)).foregroundStyle(.white.opacity(0.55))
                    }
                }
                Panel(title: "Graphique", trailing: candles.isEmpty ? nil : "flèches = lecture de ce trade · A = achat · V = vente") {
                    if candles.count >= 2 {
                        CandleChart(candles: candles, ema9: scr?.chart?.ema9 ?? [], ema21: scr?.chart?.ema21 ?? [], trades: [t], entry: t.entryMcap, notes: notes, visible: $visible).frame(height: 360)
                    } else {
                        BigSeriesChart(item: .minimal(mint: t.mint, symbol: t.symbol, image: t.image), lab: lab).frame(height: 260)
                    }
                }
                if !t.isOpen {
                    Panel(title: "Ce qui s'est passé", trailing: dx.cause == .none ? nil : dx.cause.title) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(dx.headline).font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
                            ForEach(notes) { n in
                                HStack(alignment: .top, spacing: 8) {
                                    Circle().fill(n.tone == .good ? gain : n.tone == .bad ? loss : Color.yellow).frame(width: 7, height: 7).padding(.top, 4)
                                    Text(n.detail).font(.system(size: 11)).foregroundStyle(.white.opacity(0.7)).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            if candles.count < 2 { Text("Pas de bougies lues pour ce token : les flèches se limitent à l'entrée et à la sortie.").font(.system(size: 10)).foregroundStyle(.white.opacity(0.4)) }
                            Text("Pistes tirées des prix lus, pas des règles : un trade isolé ne prouve rien.").font(.system(size: 9)).foregroundStyle(.white.opacity(0.35))
                        }
                    }
                }
                HStack(alignment: .top, spacing: 12) {
                    Panel(title: "Chronologie") {
                        VStack(alignment: .leading, spacing: 10) {
                            step("cart.badge.plus", "Ordre rempli", "\(t.openedAt.formatted(date: .omitted, time: .standard)) · payé \(formatUSD(t.entryMcap))\(t.seenMcap.map { " (vu à \(formatUSD($0)) au clic)" } ?? "")")
                            if t.tookPartial { step("circle.lefthalf.filled", "Vente partielle", "une partie encaissée en route") }
                            if let c = t.closedAt { step("flag.checkered", "Sortie", "\(c.formatted(date: .omitted, time: .standard)) · \(t.exitMcap.map(formatUSD) ?? "non lu") · \(t.exitReason ?? "")") }
                            else { step("clock", "Toujours ouvert", "depuis \(duration(now.timeIntervalSince(t.openedAt)))") }
                        }
                    }.frame(maxWidth: .infinity)
                    Panel(title: "Argent (fictif)") {
                        VStack(spacing: 6) {
                            kv("Mise", money(t.stakeUSD)); kv("Encaissé", money(t.realizedUSD)); kv("Valeur restante", money(t.markUSD))
                            kv("Frais + glissement estimés", money(t.costsUSD)); Divider().overlay(.white.opacity(0.06))
                            kv("Résultat net estimé", money(t.pnlUSD, signed: true), color: tone(t.pnlUSD))
                        }
                    }.frame(width: 320)
                }
                JournalPanel(t: t, lab: lab)
                HStack(alignment: .top, spacing: 12) {
                    Panel(title: "Ce que tu savais au clic") {
                        Text(t.entryNote ?? "Fiche non lue au moment de l'achat.").font(.system(size: 11)).foregroundStyle(.white.opacity(t.entryNote == nil ? 0.4 : 0.8)).fixedSize(horizontal: false, vertical: true)
                    }.frame(maxWidth: .infinity)
                    Panel(title: "Analyse (pistes, pas des règles)") { NotesList(notes: review(t, before: lab.pointsBefore(t))) }.frame(maxWidth: .infinity)
                }
            }.padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
        .task(id: t.mint) { await market.loadScreen(t.mint) }
    }

    func step(_ icon: String, _ title: String, _ sub: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).font(.system(size: 11, weight: .semibold)).frame(width: 22, height: 22).background(Circle().fill(.white.opacity(0.08))).foregroundStyle(.white.opacity(0.8))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                Text(sub).font(.system(size: 10)).foregroundStyle(.white.opacity(0.55)).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    func kv(_ k: String, _ v: String, color: Color = .white) -> some View {
        HStack { Text(k).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5)); Spacer(); Text(v).font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(color) }
    }
}

// MARK: onglet Robots

struct RobotsView: View {
    var lab: PaperLab
    var ui: UIState

    var ranked: [(RobotSpec, PaperBook)] {
        lab.robots.compactMap { r in lab.books[r.id].map { (r, $0) } }.sorted { $0.1.pnlUSD > $1.1.pnlUSD }
    }

    var body: some View {
        let control = lab.books["random"]?.pnlUSD
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("Robots").font(.system(size: ui.fullScreen ? 22 : 15, weight: .semibold, design: .rounded)).tracking(-0.3).foregroundStyle(.white)
                SimBadge()
                Spacer()
                Toggle(isOn: Binding(get: { lab.robotsOn }, set: { lab.robotsOn = $0 })) {
                    Text(lab.robotsOn ? "en marche" : "en pause").font(.system(size: 10)).foregroundStyle(.white.opacity(0.55))
                }.toggleStyle(.switch).controlSize(.mini)
            }
            Text("Même flux, mêmes coûts, mêmes règles de sortie (stop −25 %, moitié à ×1,5, repli −30 % du plus haut, 30 min max). Un robot qui ne bat pas le témoin au hasard n'a rien démontré.")
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.45)).fixedSize(horizontal: false, vertical: true)
            if ui.fullScreen {
                ScrollView {
                    VStack(spacing: 12) {
                        if ranked.allSatisfy({ $0.1.trades.isEmpty && $0.1.pending.isEmpty }) {
                            HStack(spacing: 12) {
                                ProgressView().controlSize(.small)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Les robots observent le flux en direct.").font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                                    Text("Chacun attend que SA règle se déclenche (nouveau token qui passe les filtres, hausse rapide, repli, creux…). Le premier trade arrive tout seul ; rien n'est forcé pour faire joli.")
                                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.55)).fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer()
                                Button { ui.guided = true; withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { ui.tab = .live } } label: {
                                    Label("Essayer moi-même", systemImage: "sparkles").font(.system(size: 12, weight: .semibold, design: .rounded))
                                        .padding(.horizontal, 14).padding(.vertical, 8).background(Capsule().fill(.white.opacity(0.12))).foregroundStyle(.white)
                                }.buttonStyle(PressStyle())
                            }
                            .padding(14).background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(gain.opacity(0.07)))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(gain.opacity(0.2), lineWidth: 0.5))
                        }
                        Panel(title: "Tous les robots face au témoin", trailing: "capital fictif, départ $100 chacun") {
                            RaceChart(series: ranked.map { ($0.0, $0.1.equityCurve) }).frame(height: ranked.allSatisfy({ $0.1.trades.isEmpty }) ? 64 : 170)
                        }
                        Panel(title: "Classement", trailing: "net estimé après coûts") { RobotTable(ranked: ranked, control: control) }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 380), spacing: 12)], alignment: .leading, spacing: 12) {
                            ForEach(Array(ranked.enumerated()), id: \.element.0.id) { i, rb in
                                RobotCard(rank: i + 1, spec: rb.0, book: rb.1, beatsControl: control.map { rb.1.pnlUSD > $0 },
                                          on: !lab.paused.contains(rb.0.id), toggle: { if lab.paused.contains(rb.0.id) { lab.paused.remove(rb.0.id) } else { lab.paused.insert(rb.0.id) } })
                            }
                        }
                    }.padding(.bottom, 12)
                }.scrollIndicators(.hidden)
            } else {
                VStack(spacing: 4) {
                    ForEach(Array(ranked.enumerated()), id: \.element.0.id) { i, rb in RobotRow(rank: i + 1, spec: rb.0, book: rb.1) }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

/// Chiffres d'un portefeuille fermé : gain moyen, perte moyenne, facteur de profit, durée moyenne.
struct BookStats {
    var avgWin: Double?, avgLoss: Double?, profitFactor: Double?, avgHoldS: Double?
    init(_ b: PaperBook) {
        let c = b.closed
        let wins = c.filter { $0.pnlUSD > 0 }, losses = c.filter { $0.pnlUSD < 0 }
        avgWin = wins.isEmpty ? nil : wins.reduce(0) { $0 + $1.pnlPct } / Double(wins.count)
        avgLoss = losses.isEmpty ? nil : losses.reduce(0) { $0 + $1.pnlPct } / Double(losses.count)
        let gross = wins.reduce(0) { $0 + $1.pnlUSD }, lost = -losses.reduce(0) { $0 + $1.pnlUSD }
        profitFactor = lost > 0 ? gross / lost : nil
        avgHoldS = c.isEmpty ? nil : c.reduce(0) { $0 + $1.holdS } / Double(c.count)
    }
}

/// Tableau comparatif des robots : une ligne par robot, le témoin au hasard en repère.
struct RobotTable: View {
    var ranked: [(RobotSpec, PaperBook)]
    var control: Double?
    let cols: [(String, CGFloat)] = [("Trades", 56), ("Réussite", 64), ("Gain moy.", 72), ("Perte moy.", 72), ("Facteur", 60), ("Durée", 56), ("Pire baisse", 76), ("Net", 74)]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Eyebrow(text: "Robot").frame(maxWidth: .infinity, alignment: .leading)
                ForEach(cols, id: \.0) { Eyebrow(text: $0.0).frame(width: $0.1, alignment: .trailing) }
                Eyebrow(text: "vs témoin").frame(width: 70, alignment: .trailing)
            }.padding(.bottom, 6)
            ForEach(Array(ranked.enumerated()), id: \.element.0.id) { i, rb in
                let (r, b) = rb, st = BookStats(b)
                Divider().overlay(.white.opacity(0.06))
                HStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Text("\(i + 1)").font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(.white.opacity(0.35)).frame(width: 12)
                        RobotAvatar(kind: r.kind, size: 20)
                        Text(r.name).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(r.kind == .random ? .white.opacity(0.6) : .white).lineLimit(1)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    cell("\(b.closed.count)", cols[0].1)
                    cell(b.winRate.map { String(format: "%.0f %%", $0) } ?? "—", cols[1].1)
                    cell(st.avgWin.map { pct($0) } ?? "—", cols[2].1, gain)
                    cell(st.avgLoss.map { pct($0) } ?? "—", cols[3].1, loss)
                    cell(st.profitFactor.map { String(format: "%.2f", $0) } ?? "—", cols[4].1)
                    cell(st.avgHoldS.map { duration($0) } ?? "—", cols[5].1)
                    cell(pct(b.maxDrawdownPct), cols[6].1, b.maxDrawdownPct < -0.01 ? loss : .white.opacity(0.7))
                    cell(money(b.pnlUSD, signed: true), cols[7].1, tone(b.pnlUSD), bold: true)
                    Group {
                        if r.kind == .random { Text("témoin").foregroundStyle(.white.opacity(0.4)) }
                        else if let c = control, !b.closed.isEmpty { Text(b.pnlUSD > c ? "au-dessus" : "en dessous").foregroundStyle(b.pnlUSD > c ? gain : loss) }
                        else { Text("—").foregroundStyle(.white.opacity(0.4)) }
                    }.font(.system(size: 10, weight: .medium)).frame(width: 70, alignment: .trailing)
                }.padding(.vertical, 7)
            }
            Text("Facteur = gains ÷ pertes (au-dessus de 1 : les gains dépassent les pertes). Peu de trades : ne conclus rien.").font(.system(size: 9)).foregroundStyle(.white.opacity(0.35)).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
        }
    }

    func cell(_ s: String, _ w: CGFloat, _ c: Color = .white.opacity(0.85), bold: Bool = false) -> some View {
        Text(s).font(.system(size: 11, weight: bold ? .semibold : .medium, design: .rounded)).monospacedDigit().foregroundStyle(c).lineLimit(1).minimumScaleFactor(0.7).frame(width: w, alignment: .trailing)
    }
}

struct RobotRow: View {
    var rank: Int
    var spec: RobotSpec
    var book: PaperBook
    var body: some View {
        HStack(spacing: 10) {
            Text("\(rank)").font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(.white.opacity(0.35)).frame(width: 14)
            RobotAvatar(kind: spec.kind, size: 22)
            Text(spec.name).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(spec.kind == .random ? .white.opacity(0.6) : .white).frame(width: 150, alignment: .leading)
            EquityChart(points: book.equityCurve, start: book.startCash, compact: true).frame(width: 90, height: 22)
            Spacer()
            Text("\(plural(book.closed.count, "fermé")) · \(plural(book.open.count, "ouvert"))").font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
            Text(money(book.pnlUSD, signed: true)).font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(tone(book.pnlUSD)).frame(width: 70, alignment: .trailing)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(.white.opacity(0.04)))
    }
}

struct RobotCard: View {
    var rank: Int
    var spec: RobotSpec
    var book: PaperBook
    var beatsControl: Bool?
    var on: Bool = true
    var toggle: () -> Void = {}
    @State private var hover = false

    var body: some View {
        let isControl = spec.kind == .random
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                RobotAvatar(kind: spec.kind, size: 34).alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
                VStack(alignment: .leading, spacing: 0) {
                    Text(String(format: "N° %d", rank)).font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundStyle(.white.opacity(0.35))
                    Text(spec.name).font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                }
                Spacer()
                if isControl { tag("étalon", .white.opacity(0.6)) }
                else if let b = beatsControl, book.closed.count > 0 { tag(b ? "bat le témoin" : "sous le témoin", b ? gain : .orange) }
                Toggle("", isOn: Binding(get: { on }, set: { _ in toggle() })).toggleStyle(.switch).controlSize(.mini).labelsHidden()
                    .help(on ? "En marche : peut entrer" : "En pause : n'entre plus, gère ses sorties")
            }
            Text(spec.blurb).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5)).fixedSize(horizontal: false, vertical: true).frame(height: 28, alignment: .topLeading)
            EquityChart(points: book.equityCurve, start: book.startCash).frame(height: 70)
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(money(book.pnlUSD, signed: true)).font(.system(size: 22, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(tone(book.pnlUSD)).lineLimit(1).fixedSize()
                Text("\(pct(book.pnlPct)) net estimé").font(.system(size: 10)).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
                Spacer(minLength: 0)
            }
            Divider().overlay(.white.opacity(0.06))
            HStack(spacing: 0) {
                stat("Trades", "\(book.closed.count)")
                stat("Réussite", book.winRate.map { String(format: "%.0f %%", $0) } ?? "—")
                stat("Pire baisse", pct(book.maxDrawdownPct))
                stat("Ouverts", "\(book.open.count)")
            }
            let st = BookStats(book)
            HStack(spacing: 0) {
                stat("Gain moy.", st.avgWin.map { pct($0) } ?? "—")
                stat("Perte moy.", st.avgLoss.map { pct($0) } ?? "—")
                stat("Facteur", st.profitFactor.map { String(format: "%.2f", $0) } ?? "—")
                stat("Durée moy.", st.avgHoldS.map { duration($0) } ?? "—")
            }
            if !book.open.isEmpty {
                HStack(spacing: 6) {
                    Eyebrow(text: "Tient")
                    HStack(spacing: -6) { ForEach(book.open.prefix(6)) { t in TokenAvatar(mint: t.mint, symbol: t.symbol, image: t.image, size: 20).overlay(Circle().strokeBorder(.black, lineWidth: 1.5)) } }
                    Text(book.open.map(\.symbol).prefix(3).joined(separator: ", ")).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                }
            }
            Divider().overlay(.white.opacity(0.06))
            Eyebrow(text: "Journal : pourquoi il a fait ça")
            let recent = book.trades.suffix(4).reversed()
            if recent.isEmpty {
                Text("Pas encore de trade : sa règle ne s'est pas déclenchée.").font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
            } else {
                VStack(spacing: 6) {
                    ForEach(Array(recent)) { t in
                        HStack(alignment: .top, spacing: 8) {
                            TokenAvatar(mint: t.mint, symbol: t.symbol, image: t.image, size: 20)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(t.symbol) · \(t.entryReason)").font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.8)).lineLimit(2)
                                Text(t.exitReason.map { "sorti : \($0)" } ?? "en cours").font(.system(size: 9)).foregroundStyle(.white.opacity(0.4)).lineLimit(1)
                            }
                            Spacer(minLength: 4)
                            Text(pct(t.pnlPct)).font(.system(size: 10, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(tone(t.pnlUSD))
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(tile.fill(.white.opacity(hover ? 0.07 : 0.05)))
        .overlay(tile.strokeBorder(.white.opacity(isControl ? 0.18 : 0.07), style: StrokeStyle(lineWidth: isControl ? 1 : 0.5, dash: isControl ? [4, 4] : [])))
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.15), value: hover)
    }

    func tag(_ s: String, _ c: Color) -> some View {
        Text(s).font(.system(size: 9, weight: .semibold, design: .rounded)).padding(.horizontal, 7).padding(.vertical, 3).background(Capsule().fill(c.opacity(0.15))).foregroundStyle(c)
    }

    func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(.white).lineLimit(1)
            Text(label).font(.system(size: 9)).foregroundStyle(.white.opacity(0.4)).lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: colonne de droite du Direct en plein écran

struct SidePortfolio: View {
    var lab: PaperLab
    var ui: UIState
    var now: Date

    var body: some View {
        let b = lab.manual
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack { Text("Mes positions").font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(.white); Spacer(); SimBadge() }
                Panel(title: "Positions", trailing: b.open.isEmpty ? nil : "\(b.open.count) ouverte(s)") {
                    if b.open.isEmpty && b.pending.isEmpty {
                        EmptyHint(symbol: "hand.tap", text: "« Acheter » sous une carte : ordre fictif, rempli ~\(Int(lab.costs.latencyS)) s plus tard.")
                    } else {
                        VStack(spacing: 6) { ForEach(b.open.prefix(6)) { t in PositionRow(t: t, lab: lab, ui: ui, now: now, pendingSell: b.pending.contains { $0.mint == t.mint && $0.side == .sell }) } }
                    }
                }
                Panel(title: "Robots", trailing: "onglet 3 pour le détail") {
                    VStack(spacing: 4) {
                        ForEach(lab.robots.compactMap { r in lab.books[r.id].map { (r, $0) } }.sorted { $0.1.pnlUSD > $1.1.pnlUSD }, id: \.0.id) { r, bk in
                            HStack {
                                Text(r.name).font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(r.kind == .random ? .white.opacity(0.55) : .white)
                                Spacer()
                                Text(money(bk.pnlUSD, signed: true)).font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(tone(bk.pnlUSD))
                            }.frame(height: 20)
                        }
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
    }
}

/// Toutes les courbes de capital sur un graphique ; le témoin en pointillés.
struct RaceChart: View {
    var series: [(RobotSpec, [EquityPoint])]
    @State private var hover: CGFloat?
    func color(_ k: RobotKind) -> Color {
        switch k { case .onListing: return Color(red: 0.35, green: 0.6, blue: 1); case .momentum: return Color(red: 1, green: 0.72, blue: 0.2)
        case .fibRetrace: return Color(red: 0.72, green: 0.5, blue: 1); case .dipBuy: return Color(red: 0.25, green: 0.85, blue: 0.75); case .random: return .white.opacity(0.6) }
    }
    var body: some View {
        let pts = series.flatMap(\.1)
        if pts.count < 2 || pts.allSatisfy({ abs($0.equity - 100) < 0.005 }) {
            EmptyHint(symbol: "chart.xyaxis.line", text: "Les courbes apparaissent dès que les robots ont tradé.").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Canvas { ctx, size in
                    let vals = pts.map(\.equity) + [100]
                    let lo = vals.min()!, hi = vals.max()!, span = max(hi - lo, 4)
                    let t0 = pts.map(\.at).min()!, t1 = pts.map(\.at).max()!, ts = max(t1.timeIntervalSince(t0), 1)
                    func p(_ e: EquityPoint) -> CGPoint { CGPoint(x: e.at.timeIntervalSince(t0) / ts * size.width, y: size.height - (e.equity - lo) / span * size.height) }
                    var base = Path(); let yb = size.height - (100 - lo) / span * size.height
                    base.move(to: CGPoint(x: 0, y: yb)); base.addLine(to: CGPoint(x: size.width, y: yb))
                    ctx.stroke(base, with: .color(.white.opacity(0.12)), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    for (r, curve) in series where curve.count >= 2 {
                        var path = Path()
                        for (i, e) in curve.enumerated() { i == 0 ? path.move(to: p(e)) : path.addLine(to: p(e)) }
                        ctx.stroke(path, with: .color(color(r.kind)), style: StrokeStyle(lineWidth: r.kind == .random ? 1.2 : 1.8, lineCap: .round, dash: r.kind == .random ? [4, 3] : []))
                    }
                    // viseur : la valeur de chaque robot à l'instant survolé
                    if let hx = hover, size.width > 0 {
                        let tt = t0.addingTimeInterval(Double(hx / size.width) * ts)
                        var v = Path(); v.move(to: CGPoint(x: hx, y: 0)); v.addLine(to: CGPoint(x: hx, y: size.height))
                        ctx.stroke(v, with: .color(.white.opacity(0.25)), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                        var rows: [(String, Double, Color)] = []
                        for (r, curve) in series {
                            guard let e = curve.last(where: { $0.at <= tt }) ?? curve.first else { continue }
                            rows.append((r.name, e.equity, color(r.kind)))
                            ctx.fill(Path(ellipseIn: CGRect(x: hx - 3, y: p(e).y - 3, width: 6, height: 6)), with: .color(color(r.kind)))
                        }
                        let bx = hx > size.width / 2 ? hx - 168 : hx + 10
                        let boxH = 18 + CGFloat(rows.count) * 14
                        ctx.fill(Path(roundedRect: CGRect(x: bx, y: 4, width: 158, height: boxH), cornerRadius: 8), with: .color(Color(white: 0.1).opacity(0.95)))
                        ctx.draw(Text(tt.formatted(date: .omitted, time: .standard)).font(.system(size: 9, weight: .semibold)).foregroundStyle(.white.opacity(0.6)), at: CGPoint(x: bx + 8, y: 14), anchor: .leading)
                        for (i, row) in rows.sorted(by: { $0.1 > $1.1 }).enumerated() {
                            let yy = 28 + CGFloat(i) * 14
                            ctx.fill(Path(roundedRect: CGRect(x: bx + 8, y: yy - 1.5, width: 8, height: 3), cornerRadius: 1), with: .color(row.2))
                            ctx.draw(Text(row.0).font(.system(size: 9)).foregroundStyle(.white.opacity(0.75)), at: CGPoint(x: bx + 22, y: yy), anchor: .leading)
                            ctx.draw(Text(money(row.1 - 100, signed: true)).font(.system(size: 9, weight: .semibold, design: .rounded)).foregroundStyle(tone(row.1 - 100)), at: CGPoint(x: bx + 150, y: yy), anchor: .trailing)
                        }
                    }
                }
                .onContinuousHover { phase in if case .active(let p) = phase { hover = p.x } else { hover = nil } }
                HStack(spacing: 12) {
                    ForEach(series, id: \.0.id) { r, _ in
                        HStack(spacing: 4) { RoundedRectangle(cornerRadius: 1).fill(color(r.kind)).frame(width: 10, height: 3); Text(r.name).font(.system(size: 9)).foregroundStyle(.white.opacity(0.55)) }
                    }
                }
            }
        }
    }
}

// MARK: bandeau d'action sur une carte du Direct

struct TradeStrip: View {
    var item: Feed.Item
    var lab: PaperLab
    var ui: UIState
    var solUSD: Double? = nil

    var body: some View {
        let b = lab.manual
        Group {
            if b.pending.contains(where: { $0.mint == item.mint }) {
                HStack(spacing: 6) { ProgressView().controlSize(.mini); Text("ordre en cours…").font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.6)) }
                    .frame(maxWidth: .infinity).frame(height: 28)
            } else if let t = b.position(item.mint) {
                HStack(spacing: 6) {
                    Text(pct(t.pnlPct)).font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(tone(t.pnlUSD)).contentTransition(.numericText()).lineLimit(1).fixedSize()
                    Spacer(minLength: 0)
                    pill("½", fill: .white.opacity(0.1), fg: .white.opacity(0.85)) { ui.flash(lab.sell(mint: item.mint, fraction: 0.5, seenMcap: item.marketCap, now: Date())) }
                    pill("Vendre", fill: loss.opacity(0.22), fg: loss) { ui.flash(lab.sell(mint: item.mint, fraction: 1, seenMcap: item.marketCap, now: Date())); ui.onTrade?(t.pnlUSD >= 0 ? .soldWin : .soldLoss) }
                }
                .padding(.horizontal, 10).frame(height: 28)
                .background(Capsule().fill(.white.opacity(0.05)))
            } else {
                QuickBuyRow(item: item, lab: lab, ui: ui, solUSD: solUSD, count: ui.fullScreen ? 5 : 4)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: b.position(item.mint)?.id)
    }

    func pill(_ s: String, fill: Color, fg: Color, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            Text(s).font(.system(size: 10, weight: .semibold, design: .rounded)).padding(.horizontal, 9).padding(.vertical, 4)
                .background(Capsule().fill(fill)).foregroundStyle(fg)
        }.buttonStyle(PressStyle())
    }
}

func duration(_ s: Double) -> String {
    let s = max(0, Int(s))
    if s < 90 { return "\(s) s" }
    if s < 5400 { return "\(s / 60) min" }
    return "\(s / 3600) h \(s % 3600 / 60)"
}


func plural(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n > 1 ? "s" : "")" }
