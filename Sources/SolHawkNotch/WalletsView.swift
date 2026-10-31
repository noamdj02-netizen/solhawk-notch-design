import AppKit
import SwiftUI
import SolHawkNotchCore

// Wallets SUIVIS : adresses publiques et étiquettes données par l'utilisateur (non vérifiées).
// Lecture seule. Un wallet suivi qui achète n'est ni une recommandation ni une preuve de qualité.

@MainActor @Observable
final class WalletStore {
    private(set) var list: [TrackedWalletRow] = []
    private(set) var registry: WalletRegistry?
    private(set) var lastError: FetchFailure?
    private(set) var loadedAt: Date?
    private(set) var activity: [String: (at: Date, value: WalletActivity)] = [:]
    private(set) var checking: Set<String> = []
    private(set) var recent: [String: (at: Date, value: WalletRecent?)] = [:]
    @ObservationIgnored private let client: () -> FeedClient?

    init(client: @escaping () -> FeedClient?) { self.client = client }

    /// Liste (sans lecture RPC côté serveur). Au plus une fois toutes les 30 s.
    func refresh(force: Bool = false) async {
        if !force, let t = loadedAt, Date().timeIntervalSince(t) < 30 { return }
        guard let c = client() else { lastError = .network("configuration"); return }
        switch await c.fetchWallets() {
        case .success(let r): list = r.wallets ?? []; registry = r.registry; lastError = nil; loadedAt = Date()
        case .failure(let e): lastError = e
        }
    }

    /// Activité récente d'UNE adresse de MA liste (lecture RPC côté serveur : seulement sur demande, au plus une fois par minute).
    func loadRecent(address: String) async {
        guard !checking.contains(address), let c = client() else { return }
        if let r = recent[address], Date().timeIntervalSince(r.at) < 60 { return }
        checking.insert(address); defer { checking.remove(address) }
        switch await c.fetchWalletRecent(address: address) {
        case .success(let r): recent[address] = (Date(), r.activity)
        case .failure: recent[address] = (Date(), nil)
        }
        if recent.count > 100 { recent = recent.filter { $0.key == address } }
    }

    /// Qui parmi les wallets suivis a touché ce token récemment (lecture RPC côté serveur : seulement sur demande).
    func check(mint: String) async {
        guard !checking.contains(mint), let c = client() else { return }
        checking.insert(mint); defer { checking.remove(mint) }
        if case .success(let r) = await c.fetchWalletActivity(mint: mint), let a = r.activity {
            activity[mint] = (Date(), a)
            if activity.count > 100 { activity.removeAll() }
            await refresh(force: true)   // la liste montre aussi ce qui vient d'être lu
        }
    }
}

/// Avatar d'un wallet : son emoji s'il en a un, sinon un motif généré depuis l'adresse (un wallet n'a pas de photo).
struct WalletAvatar: View {
    var address: String
    var emoji: String?
    var size: CGFloat = 32
    var body: some View {
        let e = safeEmoji(emoji)
        let (cells, hue) = identicon(address)
        let color = Color(hue: hue, saturation: 0.55, brightness: 0.85)
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).fill(color.opacity(0.14))
            if e.isEmpty {
                Canvas { ctx, s in
                    let pad = s.width * 0.18, cell = (s.width - 2 * pad) / 5
                    for i in 0..<25 where cells[i] {
                        let r = CGRect(x: pad + CGFloat(i % 5) * cell, y: pad + CGFloat(i / 5) * cell, width: cell, height: cell)
                        ctx.fill(Path(roundedRect: r.insetBy(dx: 0.4, dy: 0.4), cornerRadius: cell * 0.25), with: .color(color))
                    }
                }
            } else {
                Text(e).font(.system(size: size * 0.55))
            }
        }
        .frame(width: size, height: size)
        .overlay(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).strokeBorder(color.opacity(0.35), lineWidth: 0.5))
        .accessibilityHidden(true)
    }
}

struct WalletsView: View {
    var wallets: WalletStore
    var store: FeedStore
    var ui: UIState
    var now: Date
    @State private var filter = "tous"

    var body: some View {
        let rows = wallets.list.filter { filter == "tous" || (filter == "élite" ? $0.elite == true : $0.category == filter) }
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("Wallets du serveur").font(.system(size: ui.fullScreen ? 22 : 15, weight: .semibold, design: .rounded)).tracking(-0.3).foregroundStyle(.white)
                Text("\(wallets.list.count)").font(.system(size: 11, weight: .semibold, design: .rounded)).padding(.horizontal, 7).padding(.vertical, 2).background(Capsule().fill(.white.opacity(0.1))).foregroundStyle(.white.opacity(0.7))
                Spacer()
                if ui.fullScreen {
                    Picker("", selection: $filter) {
                        Text("Tous").tag("tous"); Text("Élite").tag("élite"); Text("Traders").tag("trader"); Text("Devs").tag("dev")
                    }.pickerStyle(.segmented).labelsHidden().frame(width: 280).controlSize(.small)
                }
                Button { Task { await wallets.refresh(force: true) } } label: { Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .semibold)) }
                    .buttonStyle(PressStyle()).foregroundStyle(.white.opacity(0.6)).help("Actualiser").accessibilityLabel("Actualiser")
            }
            WalletFlowSection(ui: ui, now: now)
            if ui.fullScreen { WatchedSection(wallets: wallets, ui: ui, now: now) }
            Text("Étiquettes données par toi ou un export d'outil : non vérifiées. « Vu récemment » = échantillon des tokens déjà vérifiés, pas l'historique complet. Un wallet suivi qui achète n'est pas un conseil.")
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.45)).fixedSize(horizontal: false, vertical: true)
            if let e = wallets.lastError, wallets.list.isEmpty {
                EmptyHint(symbol: "exclamationmark.triangle", text: e == .unauthorized ? "Jeton refusé : vérifie Réglages." : "Liste non lue (serveur injoignable ou ancienne version du serveur).")
            } else if wallets.list.isEmpty {
                EmptyHint(symbol: "person.2", text: wallets.loadedAt == nil ? "Chargement…" : "Aucun wallet suivi. Ajoute-les depuis le plugin Chrome ou Telegram (/wallets) : l'app les affiche ici.")
            } else if ui.fullScreen {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 12)], alignment: .leading, spacing: 12) {
                        ForEach(rows) { WalletCard(w: $0, store: store, ui: ui, now: now) }
                    }.padding(.bottom, 12)
                }.scrollIndicators(.hidden)
            } else {
                ScrollView {
                    VStack(spacing: 4) { ForEach(rows) { WalletLine(w: $0, now: now) } }
                }.scrollIndicators(.hidden)
            }
        }
        .task { await wallets.refresh() }
    }
}

struct WalletLine: View {
    var w: TrackedWalletRow
    var now: Date
    var body: some View {
        HStack(spacing: 10) {
            WalletAvatar(address: w.address, emoji: w.emoji, size: 26)
            Text(w.label.map { safeLabel($0, max: 22) } ?? shortAddress(w.address)).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(.white)
            if w.elite == true { Image(systemName: "star.fill").font(.system(size: 8)).foregroundStyle(.yellow) }
            Spacer()
            if let r = w.recent?.first { Text("\(sideLabel(r.side)) · \(ago(r.blockTime, now))").font(.system(size: 10)).foregroundStyle(.white.opacity(0.5)) }
            else { Text(categoryLabel(w.category)).font(.system(size: 10)).foregroundStyle(.white.opacity(0.35)) }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.04)))
    }
}

struct WalletCard: View {
    var w: TrackedWalletRow
    var store: FeedStore
    var ui: UIState
    var now: Date
    @State private var hover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                WalletAvatar(address: w.address, emoji: w.emoji, size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(w.label.map { safeLabel($0, max: 24) } ?? "sans nom").font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(.white).lineLimit(1)
                        if w.elite == true { Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(.yellow).help("Élite (suivi de près)") }
                    }
                    HStack(spacing: 6) {
                        Text(shortAddress(w.address)).font(.system(size: 10, design: .monospaced)).foregroundStyle(.white.opacity(0.45))
                        Text(categoryLabel(w.category)).font(.system(size: 9, weight: .semibold, design: .rounded)).padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Capsule().fill(.white.opacity(0.08))).foregroundStyle(.white.opacity(0.6))
                    }
                }
                Spacer()
                HStack(spacing: 2) { ForEach(0..<3, id: \.self) { i in Circle().fill(.white.opacity(i < (w.influence ?? 0) ? 0.8 : 0.15)).frame(width: 5, height: 5) } }
                    .help("Influence \(w.influence ?? 0)/3 (réglage manuel)")
            }
            Divider().overlay(.white.opacity(0.06))
            Eyebrow(text: "Vu récemment")
            if let recent = w.recent, !recent.isEmpty {
                VStack(spacing: 5) {
                    ForEach(Array(recent.prefix(3).enumerated()), id: \.offset) { _, r in
                        let it = store.feed?.items.first { $0.mint == r.mint }
                        HStack(spacing: 8) {
                            if let it { TokenAvatar(item: it, size: 18) } else { Circle().fill(.white.opacity(0.1)).frame(width: 18, height: 18) }
                            Text(it.map { safeLabel($0.symbol) } ?? shortAddress(r.mint)).font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(.white.opacity(0.85))
                            Text(sideLabel(r.side)).font(.system(size: 10, weight: .semibold)).foregroundStyle(r.side == "BUY" ? gain : r.side == "SELL" ? loss : .white.opacity(0.5))
                            Spacer()
                            Text(ago(r.blockTime, now)).font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
                        }
                    }
                }
            } else {
                Text("Rien dans l'échantillon. Vérifie un token depuis le Terminal pour voir s'il y est.").font(.system(size: 10)).foregroundStyle(.white.opacity(0.4)).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                small("Copier l'adresse") {
                    guard isValidMint(w.address) else { ui.flash("Adresse invalide : non copiée"); return }
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(w.address, forType: .string); ui.flash("Adresse copiée")
                }
                small("Solscan ↗") {
                    guard isValidMint(w.address), let u = URL(string: "https://solscan.io/account/\(w.address)") else { ui.flash("Adresse invalide : lien refusé"); return }
                    NSWorkspace.shared.open(u)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(hover ? 0.07 : 0.05)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.07), lineWidth: 0.5))
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.15), value: hover)
    }

    func small(_ s: String, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            Text(s).font(.system(size: 11, weight: .medium, design: .rounded)).frame(maxWidth: .infinity).frame(height: 28)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.white.opacity(0.06))).foregroundStyle(.white.opacity(0.8))
        }.buttonStyle(PressStyle())
    }
}

/// Panneau du Terminal : wallets suivis vus sur le token sélectionné (sur demande : une lecture RPC côté serveur).
struct WalletsOnToken: View {
    var item: Feed.Item
    var wallets: WalletStore
    var now: Date

    var body: some View {
        let res = wallets.activity[item.mint]
        let busy = wallets.checking.contains(item.mint)
        let ok = isValidMint(item.mint)
        Panel(title: "Wallets suivis sur ce token", trailing: res.map { "lu \(ago(Int($0.at.timeIntervalSince1970), now))" }) {
            VStack(alignment: .leading, spacing: 8) {
                if let a = res?.value {
                    if let rows = a.wallets, !rows.isEmpty {
                        ForEach(rows) { w in
                            HStack(spacing: 10) {
                                WalletAvatar(address: w.address, emoji: w.emoji, size: 26)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(w.label.map { safeLabel($0, max: 20) } ?? shortAddress(w.address)).font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                                    Text(activityText(w)).font(.system(size: 10)).foregroundStyle(.white.opacity(0.55))
                                }
                                Spacer()
                                Text(ago(w.lastBlockTime, now)).font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
                            }
                        }
                    } else {
                        Text(a.label ?? "Aucun wallet suivi dans l'échantillon.").font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                    }
                    Text("Échantillon des \(a.txRead ?? 0) dernières transactions réussies, pas l'historique complet.").font(.system(size: 9)).foregroundStyle(.white.opacity(0.35))
                } else {
                    Text("Regarde si un de tes wallets suivis a acheté, vendu ou reçu ce token récemment.").font(.system(size: 11)).foregroundStyle(.white.opacity(0.55)).fixedSize(horizontal: false, vertical: true)
                }
                Button { Task { await wallets.check(mint: item.mint) } } label: {
                    HStack(spacing: 6) {
                        if busy { ProgressView().controlSize(.mini) } else { Image(systemName: "magnifyingglass").font(.system(size: 10, weight: .semibold)) }
                        Text(res == nil ? "Vérifier" : "Revérifier").font(.system(size: 12, weight: .semibold, design: .rounded))
                    }
                    .frame(maxWidth: .infinity).frame(height: 30)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.white.opacity(0.08))).foregroundStyle(.white.opacity(0.85))
                }
                .buttonStyle(PressStyle()).disabled(busy || !ok)
                .help(ok ? "Lecture des transactions récentes par le serveur (en cache 60 s)" : "Adresse non reconnue")
            }
        }
    }

    func activityText(_ w: TrackedWalletRow) -> String {
        var parts: [String] = []
        if let b = w.buys, b > 0 { parts.append("\(b) achat\(b > 1 ? "s" : "")") }
        if let s = w.sells, s > 0 { parts.append("\(s) vente\(s > 1 ? "s" : "")") }
        if let r = w.received, r > 0 { parts.append("reçu \(r)× sans l'avoir demandé") }
        if let s = w.sent, s > 0 { parts.append("envoyé \(s)×") }
        return parts.isEmpty ? "mouvement indéterminé" : parts.joined(separator: " · ")
    }
}

/// « il y a 3 min » depuis un horodatage Unix (secondes). nil = « date non lue ».
func ago(_ unix: Int?, _ now: Date) -> String {
    guard let unix else { return "date non lue" }
    return "il y a \(duration(now.timeIntervalSince1970 - Double(unix)))"
}
