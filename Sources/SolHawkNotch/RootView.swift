import SwiftUI
import SolHawkNotchCore

enum TradeEvent { case bought, soldWin, soldLoss }

enum Tab: String, CaseIterable {
    case live = "Direct", trades = "Trades", robots = "Robots", wallets = "Wallets", funnel = "Entonnoir", alerts = "Alertes", settings = "Réglages"
    var symbol: String {
        switch self {
        case .live: return "waveform"; case .trades: return "chart.line.uptrend.xyaxis"; case .robots: return "cpu"; case .wallets: return "person.2"; case .settings: return "gearshape"
        case .funnel: return "line.3.horizontal.decrease"; case .alerts: return "bell"
        }
    }
}

/// Appui : le bouton se rétracte un peu (retour tactile discret, comme les boutons Apple).
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.94 : 1).opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

@MainActor @Observable
final class UIState {
    var expanded = false
    var tab: Tab = .live
    var toast: String?
    var notchWidth: Double = 0
    var barHeight: Double = 32
    var targetSize: CGSize = .zero   // taille finale de la forme (la mise en page se fait à cette taille, sans reflux pendant l'animation)
    var visibleSize: CGSize = .zero  // taille visible, animée par ressort : seul le masque grandit, la fenêtre ne bouge pas
    var openSettings: () -> Void = {}
    var quit: () -> Void = { NSApp.terminate(nil) }
    var toggle: () -> Void = {}
    var focusMint: String?          // token mis en premier à l'ouverture (celui qui faisait briller la barre)
    var fullScreen = false
    var guided = false                     // simulation guidée en cours (bandeau d'étapes dans le Terminal)
    var demo = false
    var settled = true                     // contenu posé (faux pendant le passage en plein écran : il sort de l'encoche)                       // serveur factice : bandeau « DÉMO » visible partout où il y a des chiffres
    var toggleFullScreen: () -> Void = {}
    let reactions = MascotReactions()      // réactions de la mascotte (saut, chapeau réajusté…)
    var onTrade: ((TradeEvent) -> Void)?   // achat / vente fictive : la mascotte réagit
    var tradeDetail: UUID?                 // trade ouvert dans le détail (page Trades)
    var palette = false                    // recherche universelle ouverte (⌘K ou « / »)
    var alertsSeen = 0              // alertes déjà vues (pour la pastille « non lues »)
    var tourStep: Int? = nil        // visite guidée en cours (nil = fermée)
    var appearedAt = Date()         // entrée Hawky (une fois par session)
    static let tourKey = "tourDone"

    /// Première ouverture : lance la visite guidée une seule fois.
    func startTourIfFirstTime() {
        if tourStep == nil, !UserDefaults.standard.bool(forKey: UIState.tourKey) { tourStep = 0 }
    }
    func nextTour() {
        guard let i = tourStep else { return }
        if i + 1 < tourSteps.count { withAnimation(.snappy(duration: 0.25)) { tourStep = i + 1 } } else { endTour() }
    }
    func endTour() {
        UserDefaults.standard.set(true, forKey: UIState.tourKey)
        withAnimation(.snappy(duration: 0.25)) { tourStep = nil }
    }

    func flash(_ text: String) {
        toast = text
        Task { try? await Task.sleep(for: .seconds(1.6)); if toast == text { toast = nil } }
    }
}

struct RootView: View {
    var store: FeedStore
    var gaze: Gaze
    var ui: UIState
    var lab: PaperLab
    var wallets: WalletStore
    var market: MarketStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var reduceMotionIntro: Bool { reduceMotion }

    var body: some View {
        TimelineView(.animation(minimumInterval: HawkyPace.interval(
            mood: store.mood(now: Date()), expanded: ui.expanded,
            reduceMotion: reduceMotion, sinceAppearS: Date().timeIntervalSince(ui.appearedAt)
        ))) { tl in
            let mood = store.mood(now: tl.date)
            let sig = barSignal(feed: store.feed, mood: mood)
            let shape = UnevenRoundedRectangle(bottomLeadingRadius: 26, bottomTrailingRadius: 26)
            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    bar(mood: mood, date: tl.date, signal: sig)
                    if ui.expanded {
                        if ui.fullScreen {
                            // vrai dashboard : barre latérale (personnage réduit + sections) et grand contenu
                            HStack(alignment: .top, spacing: 0) {
                                sidebar(mood: mood, date: tl.date).frame(width: 224)
                                Rectangle().fill(.white.opacity(0.07)).frame(width: 0.5)
                                content(now: tl.date).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                    .padding(.horizontal, 22).padding(.top, 10)
                            }
                        } else {
                            HStack(alignment: .top, spacing: 14) {
                                mascot(mood: mood, date: tl.date)
                                Divider().overlay(.white.opacity(0.12))
                                content(now: tl.date).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            }
                            .padding(.horizontal, 18).padding(.top, 6)
                        }
                        footer
                    }
                }
                .frame(width: ui.targetSize.width, height: ui.targetSize.height, alignment: .top)
                .scaleEffect(ui.settled ? 1 : 0.94, anchor: .top)
                .opacity(ui.settled ? 1 : 0)
                .background(Rectangle().fill(.black))
                .overlay { if !ui.expanded { SignalGlow(signal: sig.signal, date: tl.date) } }
                .frame(width: ui.visibleSize.width, height: ui.visibleSize.height, alignment: .top)
                .clipShape(shape)
                .contentShape(shape)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .overlay(alignment: .bottomTrailing) {
                // l'accompagnant du dashboard : il surgit en grand dans le coin quand il réagit (gain, perte, barre verte ou rouge)
                if ui.expanded, ui.fullScreen, ui.reactions.activeEmote(at: tl.date) != nil {
                    mascotView(mood: mood, date: tl.date).frame(width: 200, height: 150)
                        .padding(.trailing, 28).padding(.bottom, 46).allowsHitTesting(false)
                }
            }
            .overlay(alignment: .top) {
                if ui.expanded, ui.palette {
                    Color.black.opacity(0.35).ignoresSafeArea().onTapGesture { ui.palette = false }
                        .overlay(alignment: .top) { PaletteView(store: store, ui: ui).padding(.top, ui.fullScreen ? 120 : 70) }
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.15), value: ui.palette)
            .background(SignalWatcher(signal: sig.signal) { ui.reactions.fire($0 == .green ? .signalGreen : .signalRed) })
        }
        .environment(lab)
        .environment(wallets)
        .environment(market)
        .preferredColorScheme(.dark)
    }

    // MARK: barre (même position repliée ou dépliée : l'encoche est au milieu)
    @Namespace private var tabNS

    var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(Tab.allCases.filter { $0 != .settings }, id: \.self) { t in
                let unread = t == .alerts && ui.tab != .alerts ? max(0, store.alertTotal - ui.alertsSeen) : 0
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { ui.tab = t }
                    if t == .alerts { ui.alertsSeen = store.alertTotal }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: t.symbol).font(.system(size: 10, weight: .semibold))
                        if ui.tab == t || ui.fullScreen { Text(t.rawValue).font(.system(size: 11, weight: .semibold, design: .rounded)).lineLimit(1).fixedSize().transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .leading))) }
                        if unread > 0 { Text("\(unread)").font(.system(size: 9, weight: .bold, design: .rounded)).foregroundStyle(.white).padding(.horizontal, 5).padding(.vertical, 1).background(Capsule().fill(Color.red)) }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background { if ui.tab == t { Capsule().fill(.white.opacity(0.16)).matchedGeometryEffect(id: "tab", in: tabNS) } }
                    .foregroundStyle(ui.tab == t ? .white : .white.opacity(0.55))
                    .contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
                .help(t.rawValue)
                .accessibilityLabel(t.rawValue + (unread > 0 ? ", \(unread) non lue\(unread > 1 ? "s" : "")" : ""))
                .accessibilityAddTraits(ui.tab == t ? .isSelected : [])
            }
        }
    }

    func bar(mood: Mood, date: Date, signal: (signal: BarSignal, mint: String?)) -> some View {
        let h = ui.barHeight
        let tint = signalColor(signal.signal) ?? .white.opacity(0.85)
        return HStack(spacing: 0) {
            if ui.expanded {
                mascotView(mood: mood, date: date).frame(width: h * 0.8, height: h * 0.8).padding(.leading, 14)
                if ui.fullScreen {
                    Text("SolHawk").font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.8)).padding(.leading, 8)
                    if ui.demo {
                        Text("DÉMO · données inventées").font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(0.8)
                            .padding(.horizontal, 8).padding(.vertical, 3).background(Capsule().fill(Color.orange.opacity(0.2))).foregroundStyle(.orange).padding(.leading, 8)
                    }
                }
                else { tabBar.padding(.leading, 8) }
                Spacer(minLength: ui.notchWidth + 8)   // l'encoche physique occupe le milieu
                Button(action: ui.toggleFullScreen) { Image(systemName: ui.fullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right").font(.system(size: 11)).foregroundStyle(.white.opacity(0.7)) }
                    .buttonStyle(PressStyle()).help("Plein écran (F)").accessibilityLabel("Plein écran").padding(.trailing, 10)
                Button(action: ui.openSettings) { Image(systemName: "gearshape").font(.system(size: 12)).foregroundStyle(.white.opacity(0.7)) }.buttonStyle(PressStyle()).help("Réglages").accessibilityLabel("Réglages").padding(.trailing, 10)
                AvatarStack(items: barItems(signal.mint), size: 16).padding(.trailing, 6)
                Text(counter(mood)).font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(tint).padding(.trailing, 14)
            } else {
                // repliée : le personnage se colle contre l'encoche (à gauche), le compteur contre l'encoche (à droite)
                HStack { Spacer(minLength: 0); mascotView(mood: mood, date: date).frame(width: h - 2, height: h - 2).padding(.trailing, 58) }
                    .frame(maxWidth: .infinity)
                Spacer().frame(width: ui.notchWidth)
                ZStack {
                    HStack(spacing: 6) {
                        Text(counter(mood)).font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(tint).padding(.leading, 58).lineLimit(1).fixedSize()
                        AvatarStack(items: barItems(signal.mint), size: 15)   // logos des tokens en vue, celui qui brille en premier
                        Spacer(minLength: 0)
                    }
                    if !reduceMotionIntro, date.timeIntervalSince(ui.appearedAt) < LaunchIntro.duration {
                        LaunchIntro(age: max(0, date.timeIntervalSince(ui.appearedAt)))
                            .padding(.leading, 58).padding(.trailing, 8).padding(.vertical, 5)
                            .background(Color.black.opacity(date.timeIntervalSince(ui.appearedAt) < 2.4 ? 1 : 0))
                    }
                }
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: h)
        .contentShape(Rectangle())
        .onTapGesture {
            if !ui.expanded { ui.focusMint = signal.mint; ui.tab = .live; ui.startTourIfFirstTime() }
            ui.toggle()
        }
    }

    /// Tokens montrés en logos dans la barre : celui qui fait briller la barre d'abord.
    func barItems(_ mint: String?) -> [Feed.Item] {
        let all = store.feed?.items ?? []
        return all.filter { $0.mint == mint } + all.filter { $0.mint != mint }
    }

    // MARK: barre latérale du dashboard (plein écran)
    func sidebar(mood: Mood, date: Date) -> some View {
        let b = lab.manual
        let n = store.feed?.items.count ?? 0
        let unread = max(0, store.alertTotal - ui.alertsSeen)
        let best = lab.robots.compactMap { lab.books[$0.id]?.pnlUSD }.max()
        let age = store.receivedAt.map { max(0, Int(date.timeIntervalSince($0))) }
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                mascotView(mood: mood, date: date).frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text(quip(mood)).font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(.white).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    Text(status(mood: mood, date: date).text).font(.system(size: 9)).foregroundStyle(.white.opacity(0.55)).lineLimit(2)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Eyebrow(text: "Sections").padding(.leading, 12).padding(.bottom, 4)
                navItem(.live, label: "Terminal", badge: n > 0 ? "\(n)" : nil, key: "1")
                navItem(.trades, badge: b.open.isEmpty ? nil : "\(b.open.count)", key: "2")
                navItem(.robots, badge: best.map { money($0, signed: true) }, badgeColor: best.map(tone), key: "3")
                navItem(.wallets, label: "Wallets suivis", badge: wallets.list.isEmpty ? nil : "\(wallets.list.count)", key: "4")
                navItem(.alerts, badge: unread > 0 ? "\(unread)" : nil, badgeColor: unread > 0 ? .red : nil, key: "6")
                navItem(.settings, badge: nil, key: "7")
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 6) {
                HStack { Eyebrow(text: "Portefeuille fictif"); Spacer() }
                Text(money(b.equity)).font(.system(size: 20, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(.white).contentTransition(.numericText())
                Text("\(money(b.pnlUSD, signed: true)) · \(pct(b.pnlPct))").font(.system(size: 10, weight: .medium, design: .rounded)).monospacedDigit().foregroundStyle(tone(b.pnlUSD))
                EquityChart(points: b.equityCurve, start: b.startCash, compact: true).frame(height: 34)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.05)))
            HStack(spacing: 6) {
                Circle().fill(age == nil ? Color.gray : (age ?? 99) < 10 ? Color.green : Color.orange).frame(width: 6, height: 6)
                Text(age.map { $0 < 10 ? "flux à jour" : "flux de \($0) s" } ?? "aucune donnée").font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                Spacer()
                Text("lecture seule").font(.system(size: 9)).foregroundStyle(.white.opacity(0.3))
            }
        }
        .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 4)
    }

    func navItem(_ t: Tab, label: String? = nil, badge: String?, badgeColor: Color? = nil, key: String) -> some View {
        let on = ui.tab == t
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { ui.tab = t }
            if t == .alerts { ui.alertsSeen = store.alertTotal }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: t.symbol).font(.system(size: 12, weight: .semibold)).frame(width: 18)
                Text(label ?? t.rawValue).font(.system(size: 13, weight: on ? .semibold : .medium, design: .rounded))
                Spacer(minLength: 4)
                if let badge {
                    Text(badge).font(.system(size: 10, weight: .semibold, design: .rounded)).monospacedDigit()
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill((badgeColor ?? .white).opacity(badgeColor == .red ? 0.9 : 0.12)))
                        .foregroundStyle(badgeColor == .red ? .white : (badgeColor ?? .white.opacity(0.75)))
                } else {
                    Text(key).font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(.white.opacity(0.25))
                }
            }
            .foregroundStyle(on ? .white : .white.opacity(0.6))
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background { if on { RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.1)).matchedGeometryEffect(id: "side", in: tabNS) } }
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(t.rawValue + (badge.map { ", \($0)" } ?? ""))
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    func mascotView(mood: Mood, date: Date) -> MascotView {
        MascotView(
            mood: mood, look: gaze.look, date: date, hop: hop(date),
            sinceSpottedS: sinceSpotted(date),
            reaction: ui.reactions.activeEmote(at: date),
            sinceAppearS: date.timeIntervalSince(ui.appearedAt),
            dot: status(mood: mood, date: date).dot
        )
    }

    /// Ligne d'état de la mascotte (réaction en cours, panne, couleur de la barre ou humeur).
    func status(mood: Mood, date: Date) -> MascotStatus {
        mascotStatus(mood: mood, signal: barSignal(feed: store.feed, mood: mood).signal, reaction: ui.reactions.activeEmote(at: date)?.0)
    }

    /// 0...1 pendant ~0,6 s après l'apparition d'un nouveau token (sursaut du personnage).
    func hop(_ date: Date) -> Double {
        guard let until = store.tracker.spottedUntil else { return 0 }
        let since = date.timeIntervalSince(until.addingTimeInterval(-store.tracker.holdS))
        guard since >= 0, since < 0.6 else { return 0 }
        return abs(sin(since / 0.6 * .pi * 2)) * (1 - since / 0.6)
    }

    func sinceSpotted(_ date: Date) -> Double {
        guard let until = store.tracker.spottedUntil else { return 99 }
        return max(0, date.timeIntervalSince(until.addingTimeInterval(-store.tracker.holdS)))
    }

    func counter(_ m: Mood) -> String {
        switch m {
        case .calm(let n): return "\(n) listé\(n > 1 ? "s" : "")"
        case .spotted: return "nouveau"
        case .waiting: return "…"
        case .stale: return "périmé"
        case .offline: return "hors ligne"
        case .tokenRejected: return "jeton ?"
        case .badConfig: return "adresse ?"
        case .rateLimited: return "pause"
        }
    }

    // MARK: colonne personnage
    func mascot(mood: Mood, date: Date) -> some View {
        VStack(spacing: 8) {
            mascotView(mood: mood, date: date).frame(width: 80, height: 80)
            Text(quip(mood)).font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(.white)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.1)))
            Text(status(mood: mood, date: date).text).font(.system(size: 9)).foregroundStyle(.white.opacity(0.6)).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 6)
            miniPortfolio
        }
        .frame(width: 132).frame(maxHeight: .infinity, alignment: .top)
        .padding(.bottom, 4)
    }

    /// Sous la mascotte : le portefeuille fictif en un coup d'œil (capital, gain, courbe, positions, meilleur robot).
    var miniPortfolio: some View {
        let b = lab.manual
        let sol = store.feed?.solUSD ?? market.live?.new?.solUSD
        let best = lab.robots.compactMap { r in lab.books[r.id].map { (r, $0) } }.filter { $0.0.kind != .random }.max { $0.1.pnlUSD < $1.1.pnlUSD }
        func line(_ k: String, _ v: String, _ c: Color = .white.opacity(0.85)) -> some View {
            HStack(spacing: 4) {
                Text(k).font(.system(size: 9)).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
                Spacer(minLength: 2)
                Text(v).font(.system(size: 10, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(c).lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        return VStack(alignment: .leading, spacing: 6) {
            Eyebrow(text: "Mon portefeuille")
            Text(solText(b.equity, solUSD: sol) ?? money(b.equity)).font(.system(size: 17, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.7)
            Text("\(pct(b.pnlPct)) · \(money(b.pnlUSD, signed: true))").font(.system(size: 10, weight: .medium, design: .rounded)).monospacedDigit().foregroundStyle(tone(b.pnlUSD)).lineLimit(1).minimumScaleFactor(0.7)
            EquityChart(points: b.equityCurve, start: b.startCash, compact: true).frame(height: 28)
            Divider().overlay(.white.opacity(0.08))
            line("Positions", "\(b.open.count)")
            line("Libre", solText(b.cash, solUSD: sol) ?? money(b.cash))
            if let (r, bk) = best, !bk.trades.isEmpty { line("Meilleur robot", "\(r.name.split(separator: " ").first.map(String.init) ?? r.name) \(money(bk.pnlUSD, signed: true))", tone(bk.pnlUSD)) }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.07), lineWidth: 0.5))
    }

    // MARK: onglets
    /// Changement d'onglet : l'ancien contenu se floute et laisse place au nouveau (idée de fondu flou, écrite pour SolHawk). « Réduire les animations » = changement sans animation.
    @ViewBuilder func content(now: Date) -> some View {
        Group {
            if let step = ui.tourStep { TourCard(step: step, ui: ui) } else { tabContent(now: now) }
        }
        .id(ui.tourStep == nil ? ui.tab.rawValue : "visite")
        .transition(.blurReplace)
        .animation(reduceMotion ? nil : .smooth(duration: 0.28), value: ui.tab)
    }

    @ViewBuilder func tabContent(now: Date) -> some View {
        switch ui.tab {
        case .live: if ui.fullScreen { TerminalView(store: store, lab: lab, ui: ui, now: now) } else { liveTab(now: now) }
        case .trades: TradesView(lab: lab, store: store, ui: ui, now: now)
        case .robots: RobotsView(lab: lab, ui: ui)
        case .wallets: WalletsView(wallets: wallets, store: store, ui: ui, now: now)
        case .settings: DashSettings(lab: lab, ui: ui, now: now)
        case .funnel: FunnelView(store: store)
        case .alerts: AlertsView(store: store, ui: ui, now: now)
        }
    }

    func liveTab(now: Date) -> some View {
        let raw = store.feed?.items ?? []
        let all = raw.filter { $0.mint == ui.focusMint } + raw.filter { $0.mint != ui.focusMint }
        let solUSD = store.feed?.solUSD ?? market.live?.new?.solUSD
        return VStack(alignment: .leading, spacing: 8) {
            liveHeader(count: all.count, now: now)
            if all.isEmpty {
                Text(store.feed == nil ? "Aucune donnée reçue." : "Aucun token listé pour l'instant. C'est un état normal, pas un feu vert.")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.7))
                if let feed = store.feed, let line = Feed.drySummary(feed.stats) {
                    Text("Le serveur a regardé : \(line).").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5)).fixedSize(horizontal: false, vertical: true)
                }
                if store.feed == nil {
                    Button(action: ui.openSettings) {
                        Label("Régler l'adresse et le jeton du serveur", systemImage: "gearshape").font(.system(size: 12, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 14).padding(.vertical, 8).background(Capsule().fill(.white.opacity(0.14))).foregroundStyle(.white)
                    }.buttonStyle(PressStyle())
                }
            } else {
                if ui.fullScreen {
                    HStack(alignment: .top, spacing: 16) {
                        ScrollView { LazyVGrid(columns: [GridItem(.adaptive(minimum: 236, maximum: 236), spacing: 14)], alignment: .leading, spacing: 14) { ForEach(all) { TokenColumn(item: $0, ui: ui, solUSD: solUSD) } } }
                            .scrollIndicators(.hidden).frame(maxWidth: .infinity)
                        SidePortfolio(lab: lab, ui: ui, now: now).frame(width: 360)
                    }
                } else {
                    HStack(alignment: .top, spacing: 10) { ForEach(all.prefix(3)) { TokenColumn(item: $0, ui: ui, solUSD: solUSD) } }
                }
                if !ui.fullScreen, all.count > 3 { Text("+ \(all.count - 3) autre\(all.count - 3 > 1 ? "s" : "") listé\(all.count - 3 > 1 ? "s" : "")").font(.system(size: 10)).foregroundStyle(.white.opacity(0.5)) }
            }
        }
    }

    func liveHeader(count: Int, now: Date) -> some View {
        let age = store.receivedAt.map { max(0, Int(now.timeIntervalSince($0))) }
        let fresh = (age ?? 999) < 10
        return HStack(spacing: 6) {
            Text("En direct").font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.55))
            if count > 0 { Text("\(count) listé\(count > 1 ? "s" : "")").font(.system(size: 11, design: .rounded)).foregroundStyle(.white.opacity(0.35)) }
            Spacer()
            Circle().fill(age == nil ? Color.gray : fresh ? Color.green : Color.orange).frame(width: 6, height: 6)
            Text(age.map { fresh ? "à jour" : "données de \($0) s" } ?? "aucune donnée").font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
        }
    }

    var footer: some View {
        HStack {
            if let t = ui.toast { Text(t).font(.system(size: 10, weight: .semibold)).foregroundStyle(.green) }
            else {
                Text((ui.demo ? "DÉMO · données inventées · " : "") + (store.feed?.note ?? "Heuristiques non calibrées, pas des promesses. Lecture seule : aucun achat, aucune clé."))
                    .font(.system(size: 9)).foregroundStyle(.white.opacity(0.4)).lineLimit(1)
            }
            Spacer()
            Text("Ctrl+Option+Espace").font(.system(size: 9)).foregroundStyle(.white.opacity(0.3)).padding(.trailing, 10)
            Button("Revoir le tour") { ui.tourStep = 0 }.buttonStyle(.plain).font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.6)).padding(.trailing, 10)
            Button("Quitter", action: ui.quit).buttonStyle(.plain).font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.6))
        }
        .padding(.horizontal, 22).padding(.bottom, 10).padding(.top, 4)
    }
}

func signalColor(_ s: BarSignal) -> Color? {
    switch s { case .none: return nil; case .yellow: return Color(red: 1.0, green: 0.82, blue: 0.2); case .green: return .green; case .red: return Color(red: 1.0, green: 0.3, blue: 0.3) }
}

/// Liseré lumineux le long des côtés et du bas de la barre repliée (le haut reste ouvert : il touche le bord de l'écran).
/// Vert : clignote. Jaune : respire, bien visible. Rouge : pulse vite. « Réduire les animations » : lueur fixe.
struct SignalGlow: View {
    var signal: BarSignal
    var date: Date
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let c = signalColor(signal) {
            let t = date.timeIntervalSinceReferenceDate
            let a: Double = reduceMotion ? 0.9 : {
                switch signal {
                case .green: return 0.35 + 0.65 * (0.5 + 0.5 * sin(t * 2 * .pi / 1.1))
                case .red: return 0.3 + 0.7 * (0.5 + 0.5 * sin(t * 2 * .pi / 0.55))
                default: return 0.75 + 0.25 * sin(t * 2 * .pi / 3)
                }
            }()
            Canvas { ctx, size in
                let r: CGFloat = 26, i: CGFloat = 1.5
                var p = Path()
                p.move(to: CGPoint(x: i, y: 0)); p.addLine(to: CGPoint(x: i, y: size.height - r))
                p.addArc(center: CGPoint(x: i + r, y: size.height - r - i), radius: r, startAngle: .degrees(180), endAngle: .degrees(90), clockwise: true)
                p.addLine(to: CGPoint(x: size.width - i - r, y: size.height - i))
                p.addArc(center: CGPoint(x: size.width - i - r, y: size.height - r - i), radius: r, startAngle: .degrees(90), endAngle: .degrees(0), clockwise: true)
                p.addLine(to: CGPoint(x: size.width - i, y: 0))
                var g = ctx
                g.addFilter(.blur(radius: 5)); g.stroke(p, with: .color(c.opacity(a * 0.9)), lineWidth: 5)
                ctx.stroke(p, with: .color(c.opacity(a)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }.allowsHitTesting(false)
        }
    }
}

/// Visite guidée : une étape à la fois, avec une petite démo des couleurs à l'étape 2.
struct TourCard: View {
    var step: Int
    var ui: UIState

    var body: some View {
        let s = tourSteps[step]
        VStack(alignment: .leading, spacing: 10) {
            Text(s.title).font(.system(size: 20, weight: .semibold, design: .rounded)).foregroundStyle(.white)
            Text(s.text).font(.system(size: 13, design: .rounded)).foregroundStyle(.white.opacity(0.8)).fixedSize(horizontal: false, vertical: true)
            if step == 1 {
                HStack(spacing: 8) {
                    ForEach([(BarSignal.green, "vert"), (.yellow, "jaune"), (.red, "rouge")], id: \.1) { sig, name in
                        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { tl in
                            Text(name).font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .background(Capsule().fill(.black))
                                .overlay(SignalGlowCapsule(signal: sig, date: tl.date))
                                .padding(5)
                        }
                    }
                }.padding(.vertical, 4)
            }
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                HStack(spacing: 5) { ForEach(0..<tourSteps.count, id: \.self) { Circle().fill(.white.opacity($0 == step ? 0.9 : 0.25)).frame(width: 6, height: 6) } }
                Spacer()
                Button("Passer") { ui.endTour() }.buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.55))
                Button(step + 1 < tourSteps.count ? "Suivant" : "C'est parti") { ui.nextTour() }.buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(.black)
                    .padding(.horizontal, 16).padding(.vertical, 7).background(Capsule().fill(.white))
            }
        }
        .padding(20).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.08), lineWidth: 0.5))
        .padding(.bottom, 4)
    }
}

struct SignalGlowCapsule: View {
    var signal: BarSignal
    var date: Date
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        if let c = signalColor(signal) {
            let t = date.timeIntervalSinceReferenceDate
            let a: Double = reduceMotion ? 0.9 : (signal == .green ? 0.35 + 0.65 * (0.5 + 0.5 * sin(t * 2 * .pi / 1.1)) : signal == .red ? 0.3 + 0.7 * (0.5 + 0.5 * sin(t * 2 * .pi / 0.55)) : 0.75 + 0.25 * sin(t * 2 * .pi / 3))
            Capsule().strokeBorder(c.opacity(a), lineWidth: 2).shadow(color: c.opacity(a * 0.8), radius: 5)
        }
    }
}


/// Voit passer la barre au vert ou au rouge et déclenche la réaction du personnage (une fois par changement, pas plus d'une fois toutes les 8 s).
struct SignalWatcher: View {
    var signal: BarSignal
    var fire: (BarSignal) -> Void
    @State private var last = Date.distantPast

    var body: some View {
        Color.clear.onChange(of: signal) { _, new in
            guard new == .green || new == .red, Date().timeIntervalSince(last) > 8 else { return }
            last = Date()
            fire(new)
        }
    }
}
