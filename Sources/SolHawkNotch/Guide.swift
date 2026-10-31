import SwiftUI
import SolHawkNotchCore

// Simulation guidée : un bandeau en haut du Terminal qui coche chaque étape quand tu la fais (achat fictif, vente fictive, analyse).
// Rien n'est forcé : c'est un guide, pas un robot. Tout reste fictif.

struct GuideBanner: View {
    var lab: PaperLab
    var ui: UIState

    var body: some View {
        let b = lab.manual
        let bought = !b.trades.isEmpty || !b.pending.isEmpty
        let sold = b.trades.contains { $0.realizedUSD != 0 || !$0.isOpen }
        let steps: [(String, String, Bool)] = [
            ("1", "Choisis un token à gauche et lis sa fiche (dev, détenteurs)", ui.focusMint != nil || bought),
            ("2", "Achète un petit montant fictif (0,1 SOL)", bought),
            ("3", "Vends une partie (25 ou 50 %) quand tu veux", sold),
            ("4", "Relis ton trade dans Trades", false),
        ]
        let current = steps.firstIndex { !$0.2 } ?? steps.count - 1
        HStack(spacing: 14) {
            Image(systemName: "sparkles").font(.system(size: 14, weight: .semibold)).foregroundStyle(.yellow)
            HStack(spacing: 10) {
                ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                    HStack(spacing: 6) {
                        ZStack {
                            Circle().fill(s.2 ? gain : .white.opacity(i == current ? 0.22 : 0.08)).frame(width: 18, height: 18)
                            if s.2 { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.black) }
                            else { Text(s.0).font(.system(size: 9, weight: .bold, design: .rounded)).foregroundStyle(.white.opacity(i == current ? 1 : 0.5)) }
                        }
                        if i == current { Text(s.1).font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(.white).lineLimit(1) }
                    }
                }
            }
            Spacer(minLength: 8)
            if bought {
                Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { ui.tab = .trades } } label: {
                    Text("Voir l'analyse").font(.system(size: 11, weight: .semibold, design: .rounded)).padding(.horizontal, 12).padding(.vertical, 5)
                        .background(Capsule().fill(.white)).foregroundStyle(.black)
                }.buttonStyle(PressStyle())
            }
            Button { withAnimation(.snappy) { ui.guided = false } } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.5)) }
                .buttonStyle(.plain).help("Fermer le guide")
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.yellow.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.yellow.opacity(0.25), lineWidth: 0.5))
    }
}
