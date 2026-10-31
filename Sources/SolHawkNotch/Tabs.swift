import SwiftUI
import SolHawkNotchCore

private let panel = RoundedRectangle(cornerRadius: 14, style: .continuous)

// MARK: Entonnoir : d'où viennent les tokens, et pourquoi ils tombent
struct FunnelView: View {
    var store: FeedStore
    @State private var open: Set<String> = []

    var body: some View {
        let s = store.feed?.stats
        let seen = s?.seen ?? 0
        let steps: [(String, Int?, Color)] = [("Vus", s?.seen, .white), ("En observation", s?.watching, .blue), ("Listés", s?.listed, .green),
                                               ("Passent les filtres", store.feed.map { f in f.items.filter { status(of: $0) == .passesFilters }.count }, .green)]
        let drops = (s?.drops ?? [:]).sorted { $0.value > $1.value }
        let totalDrops = max(1, s?.dropped ?? drops.reduce(0) { $0 + $1.value })
        let top = Double(drops.first?.value ?? 1)
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Le trajet d'un token").font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.55))
                    ForEach(Array(steps.enumerated()), id: \.offset) { _, st in
                        HStack(spacing: 8) {
                            Text(st.0).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.85)).frame(width: 118, alignment: .leading)
                            GeometryReader { g in
                                Capsule().fill(st.2.opacity(0.75)).frame(width: st.1 == nil ? 0 : max(4, g.size.width * Double(st.1 ?? 0) / Double(max(seen, 1))))
                            }.frame(height: 7)
                            Text(st.1.map(String.init) ?? "non lu").font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(.white).frame(width: 44, alignment: .trailing)
                        }
                    }
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading).background(panel.fill(.white.opacity(0.05)))

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Pourquoi ils sont écartés").font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.55))
                        Spacer()
                        Text("touche une ligne pour l'explication").font(.system(size: 9)).foregroundStyle(.white.opacity(0.35))
                    }
                    if drops.isEmpty { Text("Aucune raison reçue.").font(.system(size: 11)).foregroundStyle(.white.opacity(0.6)) }
                    ForEach(drops, id: \.key) { k, v in
                        VStack(alignment: .leading, spacing: 4) {
                            Button { withAnimation(.snappy(duration: 0.22)) { if open.contains(k) { open.remove(k) } else { open.insert(k) } } } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: open.contains(k) ? "chevron.down" : "chevron.right").font(.system(size: 8, weight: .bold)).foregroundStyle(.white.opacity(0.4)).frame(width: 8)
                                    Text(dropLabel(k)).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.85)).frame(width: 128, alignment: .leading)
                                    GeometryReader { g in Capsule().fill(Color.orange.opacity(0.75)).frame(width: max(4, g.size.width * Double(v) / top)) }.frame(height: 7)
                                    Text("\(v)").font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(.white).frame(width: 36, alignment: .trailing)
                                    Text(String(format: "%.0f %%", Double(v) / Double(totalDrops) * 100)).font(.system(size: 10)).monospacedDigit().foregroundStyle(.white.opacity(0.5)).frame(width: 34, alignment: .trailing)
                                }.contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            if open.contains(k) {
                                Text(dropExplain(k)).font(.system(size: 10)).foregroundStyle(.white.opacity(0.6)).padding(.leading, 16).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    Text("Ça montre où le filtre coupe, pas si c'était à tort ou à raison. Le serveur suit ce que deviennent les écartés (\(s?.ghost?.tracked.map(String.init) ?? "non lu") suivis) pour le mesurer.")
                        .font(.system(size: 9)).foregroundStyle(.white.opacity(0.4)).fixedSize(horizontal: false, vertical: true).padding(.top, 2)
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading).background(panel.fill(.white.opacity(0.05)))
            }
        }
        .scrollIndicators(.hidden)
    }
}

// MARK: Alertes : règles par type (plein écran) + historique de la session
// Une alerte dit ce qui s'est passé ; elle ne conseille jamais d'acheter ni de vendre.
struct AlertsView: View {
    var store: FeedStore
    var ui: UIState
    var now: Date
    var rules: AlertRulesStore = .shared

    /// Journal du flux + journal des positions fictives, du plus récent au plus ancien.
    private var log: [AlertLogRow] { (store.alertLog + rules.positionLog).sorted { $0.at > $1.at }.map { AlertLogRow(at: $0.at, alert: $0.alert) } }

    var body: some View {
        Group { if ui.fullScreen { full } else { drawer } }
            .onAppear { ui.alertsSeen = store.alertTotal }                    // on regarde l'onglet : tout est lu
            .onChange(of: store.alertTotal) { ui.alertsSeen = store.alertTotal }
    }

    // Tiroir : historique compact seulement (les règles sont en plein écran).
    private var drawer: some View {
        let log = self.log
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Eyebrow(text: "Alertes de cette session · \(log.count)")
                if rules.quietNow { AlertQuietBadge() }
                Spacer()
                Text("F pour les règles").font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.35))
                AlertMuteToggle(rules: rules)
            }
            if log.isEmpty { alertsEmptyHint } else {
                ScrollView {
                    LazyVStack(spacing: 4) { ForEach(log) { e in historyRow(e, compact: true) } }
                }.scrollIndicators(.hidden)
            }
        }
    }

    // Plein écran : « Règles » à gauche, « Historique » à droite.
    private var full: some View {
        let log = self.log
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Alertes").font(.system(size: 22, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                    Text("Quand ça sonne, et ce qui a sonné. Une alerte décrit un fait, jamais un conseil.").font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
                }
                Spacer()
                if rules.quietNow { AlertQuietBadge() }
                AlertMuteToggle(rules: rules, large: true)
            }
            HStack(alignment: .top, spacing: 16) {
                ScrollView {
                    VStack(spacing: 14) {
                        Panel(title: "Règles", trailing: "un réglage par type") {
                            VStack(spacing: 0) {
                                ForEach(Array(AlertKind.allCases.enumerated()), id: \.element) { i, k in
                                    if i > 0 { Divider().overlay(.white.opacity(0.06)).padding(.vertical, 8) }
                                    AlertRuleRow(kind: k, rules: rules)
                                }
                            }
                        }
                        AlertQuietPanel(rules: rules)
                    }
                }
                .scrollIndicators(.hidden).frame(width: 380)

                Panel(title: "Historique", trailing: log.isEmpty ? nil : "\(log.count) · clique une ligne pour ouvrir le Terminal") {
                    if log.isEmpty { alertsEmptyHint } else {
                        ScrollView {
                            LazyVStack(spacing: 6) { ForEach(log) { e in historyRow(e, compact: false) } }
                        }.scrollIndicators(.hidden)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
    }

    private var alertsEmptyHint: some View {
        EmptyHint(symbol: "bell.slash", text: "Rien pour l'instant. Quand un token passe les filtres ou chute fort, qu'une position fictive franchit son seuil, ou si le serveur ne répond plus, ça s'écrit ici.")
    }

    private func historyRow(_ e: AlertLogRow, compact: Bool) -> some View {
        AlertHistoryRow(at: e.at, alert: e.alert, item: e.alert.mint.flatMap { m in store.feed?.items.first { $0.mint == m } }, ui: ui, now: now, compact: compact)
    }
}

/// Identité stable d'une ligne : plusieurs alertes d'un même sondage partagent la même heure.
struct AlertLogRow: Identifiable {
    var at: Date
    var alert: NotchAlert
    var id: String { "\(at.timeIntervalSince1970)-\(alert.id)" }
}

/// Couleur d'un type d'alerte (même code partout : pastille, puce, liseré).
func alertTypeColor(_ k: AlertKind) -> Color {
    switch k {
    case .newPassesFilters: return gain
    case .bigDrop: return loss
    case .positionThreshold: return Color(red: 1.0, green: 0.82, blue: 0.2)
    case .outage: return .orange
    }
}

/// « il y a » court : 12 s, 4 min, 2 h.
func alertAgo(_ d: Date, now: Date) -> String {
    let s = max(0, Int(now.timeIntervalSince(d)))
    return s < 5 ? "à l'instant" : s < 90 ? "\(s) s" : s < 5400 ? "\(s / 60) min" : "\(s / 3600) h"
}

/// Puce colorée du type (« Chute forte », « Passe les filtres »…).
struct AlertTypeChip: View {
    var kind: AlertKind
    var small = false
    var body: some View {
        let c = alertTypeColor(kind)
        HStack(spacing: 4) {
            Circle().fill(c).frame(width: small ? 5 : 6, height: small ? 5 : 6)
            Text(kind.label).font(.system(size: small ? 9 : 11, weight: .semibold, design: .rounded)).lineLimit(1)
        }
        .padding(.horizontal, small ? 6 : 8).padding(.vertical, small ? 2 : 3)
        .background(Capsule().fill(c.opacity(0.14)))
        .foregroundStyle(c)
    }
}

/// Coupure globale du son (les notifications et le journal continuent).
struct AlertMuteToggle: View {
    var rules: AlertRulesStore
    var large = false
    var body: some View {
        let m = rules.config.muted
        Button { withAnimation(.snappy(duration: 0.2)) { rules.update { $0.muted.toggle() } } } label: {
            HStack(spacing: 5) {
                Image(systemName: m ? "speaker.slash.fill" : "speaker.wave.2.fill").font(.system(size: large ? 11 : 9, weight: .semibold))
                Text(m ? "Son coupé" : "Son actif").font(.system(size: large ? 11 : 9, weight: .semibold, design: .rounded))
            }
            .padding(.horizontal, large ? 12 : 8).padding(.vertical, large ? 6 : 4)
            .background(Capsule().fill(m ? loss.opacity(0.18) : .white.opacity(0.08)))
            .foregroundStyle(m ? loss : .white.opacity(0.85))
            .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .help(m ? "Remettre le son des alertes" : "Couper le son de toutes les alertes")
        .accessibilityLabel(m ? "Remettre le son des alertes" : "Couper le son des alertes")
    }
}

struct AlertQuietBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "moon.fill").font(.system(size: 8, weight: .semibold))
            Text("Heures calmes").font(.system(size: 9, weight: .semibold, design: .rounded))
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Capsule().fill(Color.indigo.opacity(0.22))).foregroundStyle(Color(red: 0.7, green: 0.72, blue: 1.0))
        .help("Heures calmes : ni son, ni notification, ni ouverture du tiroir. Le journal note quand même.")
    }
}

/// Une règle : interrupteur, son (menu + écoute), seuil quand le type en a un.
struct AlertRuleRow: View {
    var kind: AlertKind
    var rules: AlertRulesStore

    var body: some View {
        let r = rules.config[kind]
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                AlertTypeChip(kind: kind)
                Spacer()
                Toggle("", isOn: Binding(get: { rules.config[kind].enabled }, set: { v in rules.setRule(kind) { $0.enabled = v } }))
                    .toggleStyle(.switch).controlSize(.mini).labelsHidden().tint(gain)
                    .accessibilityLabel("Activer l'alerte \(kind.label)")
            }
            Text(kind.explain).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5)).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                soundMenu(r.sound)
                roundButton("play.fill", "Écouter le son \(r.sound)") { AlertDelivery.play(r.sound) }
                Spacer(minLength: 6)
                if kind.thresholdRange != nil, let t = r.threshold { threshold(t) }
            }
            .opacity(r.enabled ? 1 : 0.4).disabled(!r.enabled)
        }
        .animation(.snappy(duration: 0.2), value: r.enabled)
    }

    private func soundMenu(_ current: String) -> some View {
        Menu {
            ForEach(alertSoundNames, id: \.self) { n in
                Button { rules.setRule(kind) { $0.sound = n }; AlertDelivery.play(n) } label: {
                    if n == current { Label(n, systemImage: "checkmark") } else { Text(n) }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "speaker.wave.2.fill").font(.system(size: 9))
                Text(current).font(.system(size: 11, weight: .medium, design: .rounded))
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 7, weight: .bold)).opacity(0.5)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(.white.opacity(0.08))).foregroundStyle(.white.opacity(0.9))
            .contentShape(Capsule())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .accessibilityLabel("Son de l'alerte \(kind.label) : \(current)")
    }

    private func threshold(_ t: Double) -> some View {
        let step = kind.thresholdStep
        let text = kind == .bigDrop ? "−\(Int(t)) %" : "±\(Int(t)) %"
        return HStack(spacing: 6) {
            Text("seuil").font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.4))
            roundButton("minus", "Baisser le seuil") { rules.setRule(kind) { $0.threshold = t - step } }
            Text(text).font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(.white)
                .frame(minWidth: 46).contentTransition(.numericText())
            roundButton("plus", "Monter le seuil") { rules.setRule(kind) { $0.threshold = t + step } }
        }
        .accessibilityElement(children: .contain).accessibilityLabel("Seuil \(text)")
    }
}

/// Heures calmes : plage horaire (peut passer minuit) sans son ni notification.
struct AlertQuietPanel: View {
    var rules: AlertRulesStore
    var body: some View {
        let c = rules.config
        Panel(title: "Heures calmes", trailing: rules.quietNow ? "en cours" : nil) {
            HStack(alignment: .top, spacing: 10) {
                Text("Ni son, ni notification, ni ouverture du tiroir. Le journal note quand même.")
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.5)).fixedSize(horizontal: false, vertical: true)
                Spacer()
                Toggle("", isOn: Binding(get: { rules.config.quietHours }, set: { v in rules.update { $0.quietHours = v } }))
                    .toggleStyle(.switch).controlSize(.mini).labelsHidden().tint(Color.indigo)
                    .accessibilityLabel("Activer les heures calmes")
            }
            HStack(spacing: 14) {
                hour("de", c.quietStart) { h in rules.update { $0.quietStart = h } }
                hour("à", c.quietEnd) { h in rules.update { $0.quietEnd = h } }
                Spacer()
            }
            .opacity(c.quietHours ? 1 : 0.4).disabled(!c.quietHours)
            if c.quietStart == c.quietEnd { Text("Début = fin : la plage est vide.").font(.system(size: 9)).foregroundStyle(.white.opacity(0.4)) }
        }
    }

    private func hour(_ label: String, _ h: Int, _ set: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.45))
            roundButton("minus", "Une heure plus tôt (\(label))") { set((h + 23) % 24) }
            Text(String(format: "%02d h", h)).font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(.white).frame(minWidth: 40)
            roundButton("plus", "Une heure plus tard (\(label))") { set((h + 1) % 24) }
        }
    }
}

/// Une ligne d'historique. Avec un token : clic = Terminal ouvert dessus ; boutons copier / DexScreener.
struct AlertHistoryRow: View {
    var at: Date
    var alert: NotchAlert
    var item: Feed.Item?
    var ui: UIState
    var now: Date
    var compact: Bool
    @State private var hover = false

    var body: some View {
        let c = alertTypeColor(alert.type)
        HStack(spacing: compact ? 8 : 10) {
            avatar(c)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(alert.title).font(.system(size: compact ? 11 : 12, weight: .semibold, design: .rounded)).foregroundStyle(.white).lineLimit(1)
                    if !compact { AlertTypeChip(kind: alert.type, small: true) }
                }
                Text(alert.body).font(.system(size: 10)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
            }
            Spacer(minLength: 6)
            if compact { Circle().fill(c).frame(width: 6, height: 6).accessibilityLabel(alert.type.label) }
            Text(alertAgo(at, now: now)).font(.system(size: 10)).monospacedDigit().foregroundStyle(.white.opacity(0.4))
            if let m = alert.mint {
                roundButton("doc.on.doc", "Copier l'adresse") { copyCA(m, ui: ui) }
                roundButton("arrow.up.right", "Ouvrir sur DexScreener") { openDexScreener(m, ui: ui) }
            }
        }
        .padding(.horizontal, compact ? 10 : 12).padding(.vertical, compact ? 6 : 9)
        .background(panel.fill(.white.opacity(hover && alert.mint != nil ? 0.09 : 0.05)))
        .overlay(alignment: .leading) { Capsule().fill(c.opacity(0.9)).frame(width: 2.5).padding(.vertical, 8) }
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture { open() }
        .help(alert.mint == nil ? alert.type.explain : "Ouvrir le Terminal sur ce token")
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(alert.mint == nil ? [] : .isButton)
        .accessibilityAction(named: "Ouvrir le Terminal") { open() }
    }

    @ViewBuilder private func avatar(_ c: Color) -> some View {
        let size: CGFloat = compact ? 18 : 26
        if let item {
            TokenAvatar(item: item, size: size)
        } else if let m = alert.mint {
            TokenAvatar(mint: m, symbol: alert.symbol, image: alert.image, size: size)
        } else {
            Image(systemName: "wifi.slash").font(.system(size: size * 0.42, weight: .semibold)).foregroundStyle(c)
                .frame(width: size, height: size).background(Circle().fill(c.opacity(0.16)))
        }
    }

    private func open() {
        guard let m = alert.mint else { return }
        ui.focusMint = m
        ui.tab = .live
    }
}

func roundButton(_ symbol: String, _ label: String, _ a: @escaping () -> Void) -> some View {
    Button(action: a) {
        Image(systemName: symbol).font(.system(size: 10, weight: .semibold)).frame(width: 24, height: 24)
            .background(Circle().fill(.white.opacity(0.10))).foregroundStyle(.white.opacity(0.85))
    }.buttonStyle(PressStyle()).help(label).accessibilityLabel(label)
}

// MARK: Santé : déplacée dans les réglages (ça n'a pas sa place dans le tiroir)
struct HealthView: View {
    var store: FeedStore

    var body: some View {
        let s = store.feed?.stats, rpc = s?.rpc
        VStack(alignment: .leading, spacing: 4) {
            line("Source", store.receivedAt.map { "reçue il y a \(max(0, Int(Date().timeIntervalSince($0)))) s" } ?? "aucune donnée reçue")
            line("Lecture RPC du serveur", rpc.map { "ok \($0.ok ?? 0) · erreurs \($0.errors ?? 0)" + (($0.lastError).map { " · \(safeLabel($0, max: 40))" } ?? "") } ?? "non lu")
            line("Suivi des écartés", s?.ghost.map { "\($0.tracked ?? 0) suivis" } ?? "non lu")
            line("Profil du filtre", s?.profile.map { safeLabel($0, max: 16) } ?? "non lu")
            Text("« Non lu » veut dire pas de donnée, jamais « bon ».").font(.footnote).foregroundStyle(.secondary)
        }
    }

    func line(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top) { Text(k).fontWeight(.medium).frame(width: 170, alignment: .leading); Text(v).foregroundStyle(.secondary) }.font(.callout)
    }
}
