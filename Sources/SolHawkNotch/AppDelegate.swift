import AppKit
import SwiftUI
import SolHawkNotchCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    nonisolated static let defaultURL = "https://votre-serveur.example"
    let tokens = KeychainTokenStore()
    var store: FeedStore!
    var lab: PaperLab!
    private var hotKey: GlobalHotKey?
    var controller: NotchController?
    var settingsWindow: NSWindow?

    nonisolated static var baseURLString: String {
        ProcessInfo.processInfo.environment["SOLHAWK_NOTCH_URL"] ?? UserDefaults.standard.string(forKey: "baseURL") ?? defaultURL
    }

    /// Une app sans barre de menus (accessoire) ne reçoit pas Cmd+C / Cmd+V : on installe un menu Édition minimal pour que le collage marche dans les champs.
    private func installEditMenu() {
        let main = NSMenu()
        main.addItem(NSMenuItem())   // emplacement du menu de l'app (vide)
        let edit = NSMenuItem(); main.addItem(edit)
        let m = NSMenu(title: "Édition")
        m.addItem(withTitle: "Annuler", action: Selector(("undo:")), keyEquivalent: "z")
        m.addItem(withTitle: "Couper", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        m.addItem(withTitle: "Copier", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        m.addItem(withTitle: "Coller", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        m.addItem(withTitle: "Tout sélectionner", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.submenu = m
        NSApp.mainMenu = main
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        installEditMenu()
        _ = AlertRulesStore.shared   // règles d'alertes chargées avant le premier sondage
        let tokens = self.tokens
        store = FeedStore(makeClient: {
            guard let url = URL(string: AppDelegate.baseURLString) else { throw ConfigError.badURL }
            return try FeedClient(baseURL: url, transport: URLSessionTransport(), tokenProvider: { AppDelegate.token(tokens) })
        })
        let paperURL = ProcessInfo.processInfo.environment["SOLHAWK_NOTCH_PAPER_FILE"].map { URL(fileURLWithPath: $0) } ?? PaperLab.defaultURL()
        let lab = PaperLab(fileURL: paperURL)
        self.lab = lab
        // Essai de l'interface sur le serveur FACTICE seulement : achète (en fictif) les 2 premiers tokens reçus.
        let autoBuy = ProcessInfo.processInfo.environment["SOLHAWK_NOTCH_PAPER_AUTOBUY"] != nil && AppDelegate.isLoopback
        var bought = 0
        store.onFeed = { feed, now in
            lab.ingest(feed, now: now)
            AlertRulesStore.shared.checkPositions(lab: lab, now: now)   // alertes de positions fictives (seuil réglable)
            if autoBuy, bought < 2 { for it in feed.items.prefix(2) where !lab.manual.traded(it.mint) { lab.buy(it, now: now); bought += 1 } }
        }
        let market = MarketStore(client: { [weak store] in store?.client() })
        market.onPrices = { px, now in lab.updatePrices(px, now: now) }
        guard let geo = NotchGeometry.detect() else { NSApp.terminate(nil); return }
        controller = NotchController(store: store, lab: lab, wallets: WalletStore(client: { [weak store] in store?.client() }), market: market, geo: geo, openSettings: { [weak self] in self?.openSettings() })
        controller?.show(expanded: CommandLine.arguments.contains("--expanded"))
        let ui = controller?.ui
        if ProcessInfo.processInfo.environment["SOLHAWK_NOTCH_SNAPSHOT"] == nil { hotKey = GlobalHotKey { [weak self] in self?.controller?.ui.toggle() } }
        store.onAlert = { [weak self] alerts in
            if ProcessInfo.processInfo.environment["SOLHAWK_NOTCH_SNAPSHOT"] == nil { for a in alerts { AlertDelivery.notify(a) } }   // pas de son ni de notification pendant les essais
            guard AlertPrefs.autoOpen, let first = alerts.first else { return }
            ui?.focusMint = first.mint; ui?.tab = first.mint == nil ? .alerts : .live
            self?.controller?.setExpanded(true)   // ouverture automatique : sans prendre le clavier
        }
        if let t = ProcessInfo.processInfo.environment["SOLHAWK_NOTCH_TAB"], let tab = Tab(rawValue: t) { controller?.ui.tab = tab }
        if ProcessInfo.processInfo.environment["SOLHAWK_NOTCH_OPEN_SETTINGS"] != nil { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.openSettings() } }
        if let t = ProcessInfo.processInfo.environment["SOLHAWK_NOTCH_TOUR"], let n = Int(t), n >= 0, n < tourSteps.count { controller?.ui.tourStep = n }
        if ProcessInfo.processInfo.environment["SOLHAWK_NOTCH_GUIDED"] != nil { controller?.ui.guided = true }
        if ProcessInfo.processInfo.environment["SOLHAWK_NOTCH_FULL"] != nil { controller?.setFullScreen(true) }
        store.start()
        if let path = ProcessInfo.processInfo.environment["SOLHAWK_NOTCH_SNAPSHOT"] {
            let delay = Double(ProcessInfo.processInfo.environment["SOLHAWK_NOTCH_SNAPSHOT_DELAY"] ?? "") ?? 3.0
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                // une alerte a pu rouvrir le tiroir sur « Direct » : on remet l'onglet demandé avant la capture
                if let t = ProcessInfo.processInfo.environment["SOLHAWK_NOTCH_TAB"], let tab = Tab(rawValue: t) { self?.controller?.ui.tab = tab }
                if ProcessInfo.processInfo.environment["SOLHAWK_NOTCH_DETAIL"] != nil { self?.controller?.ui.tradeDetail = self?.lab.manual.trades.first?.id }
                if ProcessInfo.processInfo.environment["SOLHAWK_NOTCH_PALETTE"] != nil { self?.controller?.ui.palette = true }
                // essais visuels : SOLHAWK_NOTCH_FIRE=soldLoss (soldWin, soldLoss, signalGreen, signalRed, bought) déclenche la réaction juste avant la capture
                if let f = ProcessInfo.processInfo.environment["SOLHAWK_NOTCH_FIRE"], let r = MascotReaction.allCases.first(where: { "\($0)" == f }) {
                    self?.controller?.ui.reactions.fire(r, at: Date().addingTimeInterval(-0.4))
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    let ok = self?.controller?.snapshot(to: path) ?? false
                    print(ok ? "snapshot ok" : "snapshot echec"); NSApp.terminate(nil)
                }
            }
            return
        }
        // première ouverture : on demande (une fois) si SolHawk doit se lancer au démarrage du Mac, après l'animation d'accueil
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) { [weak self] in LoginItem.askOnce { self?.controller?.ui.flash($0) } }
        if AppDelegate.token(tokens) == nil { DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.openSettings() } }
    }

    /// Jeton : Trousseau. Exception de développement : variable d'environnement, acceptée SEULEMENT si l'adresse est la boucle locale (serveur factice).
    nonisolated static var isLoopback: Bool { URL(string: baseURLString)?.host.map { ["127.0.0.1", "localhost", "::1"].contains($0) } ?? false }

    nonisolated static func token(_ store: TokenStore) -> String? {
        // Serveur factice en local : le jeton de développement passe devant, pour ne jamais envoyer le vrai jeton du Trousseau à un faux serveur.
        if isLoopback, let t = ProcessInfo.processInfo.environment["SOLHAWK_NOTCH_DEV_TOKEN"], !t.isEmpty { return t }
        if let t = store.load(), !t.isEmpty { return t }
        return nil
    }

    func openSettings() {
        if settingsWindow == nil {
            let view = SettingsView(store: store, initialURL: AppDelegate.baseURLString) { [weak self] url, token in self?.saveSettings(url: url, token: token) }
            let w = NSWindow(contentViewController: NSHostingController(rootView: view))
            w.title = "SolHawk Notch · Réglages"; w.styleMask = [.titled, .closable]; w.isReleasedWhenClosed = false
            w.setContentSize(NSSize(width: 520, height: 620))   // sans taille, la fenêtre pouvait s'ouvrir réduite à sa barre de titre
            settingsWindow = w
        }
        NSApp.activate()
        settingsWindow?.center(); settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func saveSettings(url: String, token: String?) -> String? {
        let u = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = URL(string: u), (try? FeedClient(baseURL: parsed, transport: URLSessionTransport(), tokenProvider: { nil })) != nil else {
            return "Adresse refusée : HTTPS obligatoire (http seulement pour 127.0.0.1)."
        }
        UserDefaults.standard.set(u, forKey: "baseURL")
        if let token, !tokens.save(token) { return "Le Trousseau a refusé l'enregistrement du jeton." }
        store.configurationChanged()
        controller?.ui.flash(token == nil ? "Adresse enregistrée" : "Adresse et jeton enregistrés · lecture en cours…")
        settingsWindow?.close()
        return nil
    }
}
