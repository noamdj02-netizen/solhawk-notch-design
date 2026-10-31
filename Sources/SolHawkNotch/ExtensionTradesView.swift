import SwiftUI
import SolHawkNotchCore

// « Trades de l'extension » : les mises fictives faites dans le panneau flottant de Chrome (pump.fun, Axiom, Padre), relues en GET sur le serveur.
// SIMULATION, en SOL, portefeuille séparé de celui de l'app. Lecture seule. Pas d'analyse « entré tard » : l'app n'a pas l'historique de prix de ces trades.

struct ExtensionTradesSection: View {
    var store: FeedStore
    var ui: UIState
    var now: Date
    @Environment(MarketStore.self) private var market

    var body: some View {
        let reply = market.extTrades
        Panel(title: "Trades de l'extension", trailing: reply.map { "\($0.trades.count) ligne(s)" }) {
            VStack(alignment: .leading, spacing: 10) {
                if let reply, !reply.isEmpty {
                    kpis(reply)
                    positions(reply)
                    history(reply)
                } else {
                    EmptyHint(symbol: "puzzlepiece.extension", text: market.extTradesFailure.map(flowFailureText)
                              ?? "Aucun trade reçu de l'extension. Les mises du panneau flottant (pump.fun, Axiom, Padre) apparaissent ici quand l'extension et cette app utilisent le même serveur.")
                }
                Text(footnote).font(.system(size: 9)).foregroundStyle(.white.opacity(0.35)).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var footnote: String {
        var parts = ["Simulation en SOL, portefeuille fictif de l'extension (séparé du tien ici). Coûts estimés. Pas d'analyse d'entrée : l'app n'a pas l'historique de prix de ces trades."]
        if let at = market.extTradesAt { parts.append("Reçu il y a \(duration(now.timeIntervalSince(at))).") }
        if market.extTrades != nil, let f = market.extTradesFailure { parts.append("Dernière lecture ratée : \(flowFailureText(f))") }
        return parts.joined(separator: " ")
    }

    private func kpis(_ r: PaperSyncReply) -> some View {
        let s = r.summary
        return HStack(spacing: 10) {
            if let snap = r.snapshot {
                KPI(label: "SOL libres", value: "\(fmt2(snap.balance)) SOL", sub: "capital ajouté (départ + recharges) \(fmt2(snap.startSol)) SOL")
            }
            KPI(label: "Gain réalisé", value: "\(signedSol(s.realizedSol)) SOL", sub: "\(s.sells) vente(s)", color: tone(s.realizedSol))
            KPI(label: "Réussite", value: s.winRate.map { String(format: "%.0f %%", $0) } ?? "—", sub: s.sells < 30 ? "échantillon trop petit" : "\(s.sells) ventes")
            KPI(label: "Coûts estimés", value: "\(fmt2(s.costsSol)) SOL", sub: "\(s.buys) achat(s)")
        }
    }

    @ViewBuilder private func positions(_ r: PaperSyncReply) -> some View {
        let open = r.snapshot?.positions ?? []
        if !open.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Eyebrow(text: "Positions ouvertes")
                ForEach(open) { p in
                    let mc = store.feed?.items.first(where: { $0.mint == p.mint })?.marketCap
                    let value = p.grossValueSol(mc: mc)
                    Button { ui.focusMint = p.mint; ui.tab = .live } label: {
                        HStack(spacing: 8) {
                            Text(safeLabel(p.symbol ?? shortAddress(p.mint))).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.9)).lineLimit(1)
                            ExtensionTag()
                            Spacer(minLength: 4)
                            Text("mise \(fmt2(p.basisSol)) SOL").font(.system(size: 10)).monospacedDigit().foregroundStyle(.white.opacity(0.55))
                            if let value {
                                Text("≈ \(fmt2(value)) SOL brut").font(.system(size: 10, design: .rounded)).monospacedDigit().foregroundStyle(tone(value - p.basisSol))
                            } else {
                                Text("prix non lu").font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
                            }
                        }
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.03)))
                        .contentShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(PressStyle())
                    .help("Ouvrir ce token dans le Terminal. Valeur brute = unités × prix lu par l'app, avant coûts de sortie.")
                }
            }
        }
    }

    @ViewBuilder private func history(_ r: PaperSyncReply) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Eyebrow(text: "Historique")
            ForEach(r.trades.prefix(30)) { t in
                Button { ui.focusMint = t.mint; ui.tab = .live } label: {
                    HStack(spacing: 8) {
                        Text(safeLabel(t.symbol ?? shortAddress(t.mint))).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.9)).lineLimit(1)
                        ExtensionTag()
                        Text(t.isBuy ? "achat" : "vente").font(.system(size: 10, weight: .semibold)).foregroundStyle(t.isBuy ? gain : Color.orange)
                        Spacer(minLength: 4)
                        Text("\(fmt2(t.sol)) SOL").font(.system(size: 10, design: .rounded)).monospacedDigit().foregroundStyle(.white.opacity(0.6))
                        if let r = t.realizedSol, !t.isBuy {
                            Text("\(signedSol(r)) SOL").font(.system(size: 10, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(tone(r))
                        }
                        Text(ago(Int(t.t / 1000), now)).font(.system(size: 9)).foregroundStyle(.white.opacity(0.4))
                    }
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.03)))
                    .contentShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Extension, \(t.isBuy ? "achat" : "vente") fictif de \(safeLabel(t.symbol ?? shortAddress(t.mint)))")
            }
        }
    }
}

/// Étiquette « extension » : ces lignes ne viennent pas du laboratoire de l'app.
struct ExtensionTag: View {
    var body: some View {
        Text("extension").font(.system(size: 8, weight: .semibold, design: .monospaced)).padding(.horizontal, 5).padding(.vertical, 1.5)
            .background(Capsule().fill(.white.opacity(0.1))).foregroundStyle(.white.opacity(0.6))
    }
}

private func fmt2(_ v: Double) -> String { String(format: "%.2f", v).replacingOccurrences(of: ".", with: ",") }
private func signedSol(_ v: Double) -> String { (v > 0.0001 ? "+" : "") + fmt2(v) }
