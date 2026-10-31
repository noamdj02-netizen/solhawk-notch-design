import SwiftUI
import SolHawkNotchCore

// Réglages du grand dashboard : simulation, montants, coûts supposés, personnage, raccourcis, et le « mode réel » (information seulement).

struct DashSettings: View {
    var lab: PaperLab
    var ui: UIState
    var now: Date
    @Environment(MarketStore.self) private var market
    @AppStorage("buyPresetsSOL") private var presetsSOL = "0.1,0.2,0.5,1,3,5,10,20"
    @AppStorage("buyPresetsUSD") private var presetsUSD = "5,10,25,50,100,250,500,1000"
    @AppStorage("quickPresetsSOL") private var quickSOL = "0.05,0.1,0.5,1"
    @State private var capital = 100.0
    @State private var confirmReset = false
    @State private var loginOn = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Réglages").font(.system(size: 22, weight: .semibold, design: .rounded)).tracking(-0.3).foregroundStyle(.white)
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 12) { simulation; amounts; costs }.frame(maxWidth: .infinity)
                    VStack(spacing: 12) { sounds; startup; shortcuts; realMode }.frame(maxWidth: .infinity)
                }
            }.padding(.bottom, 14)
        }
        .scrollIndicators(.hidden)
        .onAppear { capital = lab.manual.startCash }
    }

    var simulation: some View {
        Panel(title: "Simulation", trailing: "argent fictif") {
            VStack(alignment: .leading, spacing: 10) {
                row("Capital de départ actuel", money(lab.manual.startCash))
                HStack(spacing: 6) {
                    ForEach([100.0, 500, 1000, 5000, 10000], id: \.self) { v in
                        Button(money(v) + (solText(v, solUSD: market.live?.new?.solUSD).map { " · ≈ \($0)" } ?? "")) { capital = v }.buttonStyle(.plain).font(.system(size: 11, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 10).padding(.vertical, 5).background(Capsule().fill(.white.opacity(capital == v ? 0.16 : 0.05)))
                            .foregroundStyle(.white.opacity(capital == v ? 1 : 0.6))
                    }
                }
                Button(confirmReset ? "Confirmer : nouvelle simulation à \(money(capital)) (l'ancienne est archivée)" : "Nouvelle simulation") {
                    if confirmReset { lab.reset(now: now, startCash: capital); confirmReset = false; ui.flash("Nouvelle simulation · l'ancienne est archivée") }
                    else { withAnimation(.snappy) { confirmReset = true }; Task { try? await Task.sleep(for: .seconds(4)); confirmReset = false } }
                }
                .buttonStyle(.plain).font(.system(size: 12, weight: .semibold, design: .rounded))
                .padding(.horizontal, 12).padding(.vertical, 7).background(Capsule().fill((confirmReset ? loss : Color.white).opacity(0.1)))
                .foregroundStyle(confirmReset ? loss : .white.opacity(0.85))
                stepper("Limite de perte du jour (achats bloqués)", lab.lossLimitPct > 0 ? "−\(Int(lab.lossLimitPct)) %" : "aucune",
                        { lab.lossLimitPct = min(50, lab.lossLimitPct + 5) }, { lab.lossLimitPct = max(0, lab.lossLimitPct - 5) })
                Text("Si ta perte fictive du jour atteint ce seuil (en % du capital de départ), les achats fictifs sont bloqués jusqu'à demain. Les ventes restent possibles.")
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.4)).fixedSize(horizontal: false, vertical: true)
                stepper("Stop loss automatique (tes positions)", lab.stopLossPct > 0 ? "−\(Int(lab.stopLossPct)) %" : "aucun",
                        { lab.stopLossPct = min(95, lab.stopLossPct + 5) }, { lab.stopLossPct = max(0, lab.stopLossPct - 5) })
                stepper("Prise de gain automatique (tes positions)", lab.takeProfitPct > 0 ? "+\(Int(lab.takeProfitPct)) %" : "aucune",
                        { lab.takeProfitPct = min(1000, lab.takeProfitPct + (lab.takeProfitPct >= 100 ? 50 : 10)) }, { lab.takeProfitPct = max(0, lab.takeProfitPct - (lab.takeProfitPct > 100 ? 50 : 10)) })
                Text("Quand le prix passe ce seuil, l'app vend TOUTE la position fictive (rempli avec le délai et les frais supposés). Désactivé par défaut.")
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.4)).fixedSize(horizontal: false, vertical: true)
                Toggle("Robots en marche", isOn: Binding(get: { lab.robotsOn }, set: { lab.robotsOn = $0 })).toggleStyle(.switch).controlSize(.small)
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.8))
            }
        }
    }

    var amounts: some View {
        Panel(title: "Boutons d'achat", trailing: "séparés par des virgules") {
            VStack(alignment: .leading, spacing: 8) {
                field("Boutons des cartes du Direct (4, en SOL)", $quickSOL)
                field("Panneau d'ordre du Terminal (8, en SOL)", $presetsSOL)
                field("En $ (si le prix du SOL n'est pas lu)", $presetsUSD)
                Text("Exemples : 0.01, 0.05, 0.2, 0.5 pour les cartes · 0.1, 0.2, 0.5, 1, 3, 5, 10, 20 pour le panneau").font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
            }
        }
    }

    var costs: some View {
        Panel(title: "Coûts supposés de la simulation", trailing: "estimations, pas des mesures") {
            VStack(alignment: .leading, spacing: 8) {
                stepper("Frais de plateforme", "\(fmt1(lab.costs.feePct)) %", { lab.costs.feePct = min(5, lab.costs.feePct + 0.25) }, { lab.costs.feePct = max(0, lab.costs.feePct - 0.25) })
                stepper("Priorité + pourboire par ordre", money(lab.costs.priorityUSD), { lab.costs.priorityUSD = min(5, lab.costs.priorityUSD + 0.05) }, { lab.costs.priorityUSD = max(0, lab.costs.priorityUSD - 0.05) })
                stepper("Délai d'exécution", "\(Int(lab.costs.latencyS)) s", { lab.costs.latencyS = min(15, lab.costs.latencyS + 1) }, { lab.costs.latencyS = max(0, lab.costs.latencyS - 1) })
                stepper("Liquidité supposée (part du market cap)", "\(Int(lab.costs.depthRatio * 100)) %", { lab.costs.depthRatio = min(0.5, lab.costs.depthRatio + 0.05) }, { lab.costs.depthRatio = max(0.05, lab.costs.depthRatio - 0.05) })
                stepper("Achat annulé si le prix part de plus de", "\(Int(lab.costs.maxBuyDriftPct)) %", { lab.costs.maxBuyDriftPct = min(50, lab.costs.maxBuyDriftPct + 5) }, { lab.costs.maxBuyDriftPct = max(5, lab.costs.maxBuyDriftPct - 5) })
                Text("Plus ces coûts sont réalistes, plus la simulation te dit la vérité. Le flux ne donne pas la vraie liquidité : le glissement reste une hypothèse.").font(.system(size: 10)).foregroundStyle(.white.opacity(0.4)).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    var sounds: some View {
        Panel(title: "Sons", trailing: "alertes") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    AlertMuteToggle(rules: AlertRulesStore.shared, large: true)
                    Button { ui.tab = .alerts } label: { Text("Choisir le son de chaque alerte →").font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.75)) }.buttonStyle(.plain)
                }
                Text("Un son différent par type d'alerte, un bouton pour l'écouter, et des heures calmes (sans son ni notification) : page Alertes.")
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.4)).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    var startup: some View {
        Panel(title: "Démarrage", trailing: nil) {
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Lancer SolHawk à l'ouverture de ma session", isOn: Binding(get: { loginOn }, set: { on in
                    if let err = LoginItem.set(on) { ui.flash(err) } else { ui.flash(on ? "Lancement au démarrage activé" : "Lancement au démarrage désactivé") }
                    loginOn = LoginItem.enabled
                }))
                .toggleStyle(.switch).controlSize(.small).font(.system(size: 11, weight: .medium, design: .rounded)).disabled(!LoginItem.available)
                if !LoginItem.available {
                    Text("Disponible une fois l'app installée (SolHawk Notch.app).").font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
                }
            }
        }
        .onAppear { loginOn = LoginItem.enabled }
    }

    var shortcuts: some View {
        Panel(title: "Raccourcis") {
            VStack(alignment: .leading, spacing: 5) {
                key("Ctrl + Option + Espace", "ouvrir / fermer le tiroir")
                key("F", "plein écran (dashboard)")
                key("1 à 7", "Terminal, Trades, Robots, Wallets, Entonnoir, Alertes, Réglages")
                key("B / S", "acheter / vendre le token affiché (fictif)")
                key("C / D", "copier l'adresse / ouvrir DexScreener")
                key("Échap", "fermer")
            }
        }
    }

    var realMode: some View {
        Panel(title: "Mode réel", trailing: "information") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Pas disponible dans cette app.").font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                Text("SolHawk reste un simulateur : aucune clé de portefeuille, aucune signature, aucun ordre réel. Pour trader en vrai, utilise « Ouvrir dans… » sur un token : tu passes sur un autre site, sous ta seule responsabilité.")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.65)).fixedSize(horizontal: false, vertical: true)
                Text("Un mode réel ne viendrait qu'après : avis juridique (MiCA / AMF), audit de sécurité, conditions d'utilisation, signature de chaque ordre dans TON wallet (jamais de clé chez nous), et limites de pertes.")
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.45)).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    func row(_ k: String, _ v: String) -> some View {
        HStack { Text(k).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6)); Spacer(); Text(v).font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(.white) }
    }
    func field(_ k: String, _ b: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(k).font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
            TextField("", text: b).textFieldStyle(.plain).font(.system(size: 12, design: .monospaced))
                .padding(.horizontal, 10).padding(.vertical, 6).background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.06)))
                .onChange(of: b.wrappedValue) { _, v in if v.count > 80 { b.wrappedValue = String(v.prefix(80)) } }
        }
    }
    func stepper(_ k: String, _ v: String, _ up: @escaping () -> Void, _ down: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Text(k).font(.system(size: 12)).foregroundStyle(.white.opacity(0.65))
            Spacer()
            Button(action: down) { Image(systemName: "minus").font(.system(size: 9, weight: .bold)).frame(width: 22, height: 22).background(Circle().fill(.white.opacity(0.08))) }.buttonStyle(PressStyle())
            Text(v).font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(.white).frame(minWidth: 52)
            Button(action: up) { Image(systemName: "plus").font(.system(size: 9, weight: .bold)).frame(width: 22, height: 22).background(Circle().fill(.white.opacity(0.08))) }.buttonStyle(PressStyle())
        }.foregroundStyle(.white.opacity(0.8))
    }
    func key(_ k: String, _ v: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(k).font(.system(size: 10, weight: .semibold, design: .monospaced)).padding(.horizontal, 6).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 5).fill(.white.opacity(0.08))).foregroundStyle(.white.opacity(0.85))
            Text(v).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
        }
    }
}
