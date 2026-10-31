import SwiftUI
import SolHawkNotchCore

// « Flux de mes wallets » : les achats et ventes récents des wallets de MA liste locale, lus par le serveur toutes les 30 s.
// Lecture seule. Un wallet qui achète n'est ni une conseil ni une preuve de qualité : il peut revendre la seconde suivante.

struct WalletFlowSection: View {
    var ui: UIState
    var now: Date
    @Environment(MarketStore.self) private var market
    var store = WatchStore.shared

    var body: some View {
        let addresses = store.list.wallets.map(\.address)
        let labels = Dictionary(store.list.wallets.map { ($0.address, $0.label) }, uniquingKeysWith: { a, _ in a })
        let events = (market.flow?.events ?? []).filter { addresses.contains($0.address) }
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Flux de mes wallets").font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                if let at = market.flowAt { Text("lu il y a \(duration(now.timeIntervalSince(at)))").font(.system(size: 9)).foregroundStyle(.white.opacity(0.35)) }
                Spacer()
            }
            if addresses.isEmpty {
                Text("Ajoute des wallets dans « Mes wallets à suivre » : leurs achats et ventes apparaîtront ici tout seuls.")
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
            } else if events.isEmpty {
                Text(market.flowFailure.map(flowFailureText) ?? market.flow?.emptyText ?? "Lecture en cours…")
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.5)).fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView {
                    VStack(spacing: 3) {
                        ForEach(events.prefix(30)) { e in
                            FlowRow(e: e, who: labels[e.address].flatMap { $0.isEmpty ? nil : $0 } ?? shortAddress(e.address), now: now) {
                                ui.focusMint = e.mint; ui.tab = .live
                            }
                        }
                    }
                }.frame(maxHeight: 220).scrollIndicators(.hidden)
            }
            Text(market.flow?.note ?? "Achats et ventes vus dans un échantillon récent, pas l'historique. Un wallet qui achète n'est ni un conseil ni une preuve de qualité.")
                .font(.system(size: 9)).foregroundStyle(.white.opacity(0.35)).fixedSize(horizontal: false, vertical: true)
        }
        .padding(12).background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.04)))
        // sondé seulement quand cette page est à l'écran ; le serveur garde ces adresses 15 min après la dernière demande
        .task(id: addresses) {
            while !Task.isCancelled {
                await market.loadFlow(addresses: addresses)
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }
}

func flowFailureText(_ f: FetchFailure) -> String {
    switch f {
    case .unauthorized: return "Jeton refusé : vérifie Réglages."
    case .rateLimited(let s): return "Serveur occupé, nouvel essai dans \(s) s."
    case .server(let c): return "Le serveur répond avec une erreur (\(c)). Mets le serveur à jour si la route est absente."
    case .network: return "Serveur injoignable ou trop lent. Nouvel essai en cours."
    case .badResponse: return "Réponse illisible du serveur. Mets-le à jour si la route est absente."
    }
}

private struct FlowRow: View {
    var e: WalletFlowEvent
    var who: String
    var now: Date
    var open: () -> Void
    var body: some View {
        Button(action: open) {
            HStack(spacing: 8) {
                TokenAvatar(item: Feed.Item(flow: e), size: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(safeLabel(e.symbol ?? shortAddress(e.mint))).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.9)).lineLimit(1)
                    Text(safeLabel(who, max: 24)).font(.system(size: 9)).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(e.isBuy ? "achat" : "vente").font(.system(size: 10, weight: .semibold)).foregroundStyle(e.isBuy ? gain : Color.orange)
                        Text(e.sol.map { "\(fmt1($0)) SOL" } ?? "SOL non lu").font(.system(size: 10, design: .rounded)).monospacedDigit().foregroundStyle(.white.opacity(0.6))
                    }
                    Text(ago(e.blockTime.map { Int($0) }, now)).font(.system(size: 9)).foregroundStyle(.white.opacity(0.4))
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.03)))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(PressStyle())
        .help("Ouvrir ce token dans le Terminal")
        .accessibilityLabel("\(who), \(e.isBuy ? "achat" : "vente") de \(safeLabel(e.symbol ?? shortAddress(e.mint)))")
    }
}
