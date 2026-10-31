import AppKit
import SwiftUI
import SolHawkNotchCore

final class NotchPanel: NSPanel {
    /// Vrai seulement quand l'utilisateur a cliqué / utilisé le raccourci : ainsi une ouverture automatique ne vole jamais ta saisie.
    var allowKey = false
    override var canBecomeKey: Bool { allowKey }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }   // reste collée au bord haut, sur la barre de menus
}

struct NotchGeometry {
    var screen: NSScreen
    var notchWidth: Double
    var barHeight: Double
    var hasNotch: Bool { notchWidth > 0 }

    @MainActor static func detect() -> NotchGeometry? {
        let screens = NSScreen.screens
        guard let screen = screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main ?? screens.first else { return nil }
        let inset = screen.safeAreaInsets.top
        let simulateNoNotch = ProcessInfo.processInfo.environment["SOLHAWK_NOTCH_SIMULATE_NONOTCH"] != nil   // essai de la mise en page sans encoche
        if inset > 0, !simulateNoNotch, let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea {
            return NotchGeometry(screen: screen, notchWidth: Double(screen.frame.width - l.width - r.width), barHeight: Double(inset))
        }
        return NotchGeometry(screen: screen, notchWidth: 0, barHeight: 32)   // pas d'encoche : barre centrée en haut
    }

    var collapsedSize: NSSize { NSSize(width: hasNotch ? notchWidth + 2 * 152 : 210, height: barHeight) }
    /// Largeur du tiroir : 780 pt, mais jamais plus large que l'écran (petit écran, résolution réduite).
    /// La fenêtre couvre tout l'écran, transparente : seule la forme dessinée (masque animé) est visible et cliquable. Pas d'animation de fenêtre = pas de saccade.
    var windowFrame: NSRect { screen.frame }
    var expandedSize: NSSize { NSSize(width: min(max(collapsedSize.width, 780), max(collapsedSize.width, screen.frame.width - 24)), height: barHeight + 374) }
}

@MainActor
final class NotchController {
    let panel: NotchPanel
    let ui = UIState()
    let gaze = Gaze()
    private(set) var geo: NotchGeometry
    private var monitor: Any?
    private var keyMonitor: Any?
    private var moveMonitors: [Any] = []
    private var shown = CGSize.zero
    private var shrinkWork: DispatchWorkItem?
    /// Mode capture (essais) : fenêtre invisible et jamais cliquable, pour ne pas gêner l'écran de l'utilisateur.
    private let captureOnly = ProcessInfo.processInfo.environment["SOLHAWK_NOTCH_SNAPSHOT"] != nil
    private var collapsedFrame: NSRect { let f = geo.screen.frame, c = geo.collapsedSize; return NSRect(x: f.midX - c.width / 2, y: f.maxY - c.height, width: c.width, height: c.height) }
    private let store: FeedStore
    private let lab: PaperLab

    init(store: FeedStore, lab: PaperLab, wallets: WalletStore, market: MarketStore, geo: NotchGeometry, openSettings: @escaping () -> Void) {
        self.geo = geo
        self.store = store
        self.lab = lab
        panel = NotchPanel(contentRect: geo.windowFrame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isMovable = false; panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true   // transparente aux clics sauf sur la forme visible (voir updateMouse)
        ui.notchWidth = geo.notchWidth; ui.barHeight = geo.barHeight
        ui.demo = AppDelegate.isLoopback
        ui.openSettings = openSettings
        ui.toggle = { [weak self] in self?.setExpanded(!(self?.ui.expanded ?? false), takeKeys: true) }
        ui.onTrade = { [weak ui] e in
            switch e { case .bought: ui?.reactions.fire(.bought); case .soldWin: ui?.reactions.fire(.soldWin); case .soldLoss: ui?.reactions.fire(.soldLoss) }
        }
        ui.toggleFullScreen = { [weak self] in self?.setFullScreen(!(self?.ui.fullScreen ?? false)) }
        let host = NSHostingView(rootView: RootView(store: store, gaze: gaze, ui: ui, lab: lab, wallets: wallets, market: market))
        host.autoresizingMask = [.width, .height]
        host.sizingOptions = []   // la fenêtre garde SA taille (sinon SwiftUI l'agrandit selon son contenu)
        panel.contentView = host
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensChanged() }
        }
        gaze.center = { [weak self] in
            guard let self else { return .zero }
            let f = self.geo.screen.frame
            let h = self.geo.barHeight
            let y = f.maxY - h / 2
            if self.ui.expanded {
                let barLeft = f.midX - self.shown.width / 2
                return CGPoint(x: barLeft + 14 + h * 0.4, y: y)
            }
            if self.geo.hasNotch {
                return CGPoint(x: f.midX - self.geo.notchWidth / 2 - 58 - (h - 2) / 2, y: y)
            }
            return CGPoint(x: f.midX - 48, y: y)
        }
    }

    func show(expanded: Bool = false) {
        ui.expanded = expanded
        apply(expanded ? geo.expandedSize : geo.collapsedSize, animated: false)
        if captureOnly { panel.alphaValue = 0; panel.ignoresMouseEvents = true; gaze.enabled = false }
        panel.orderFrontRegardless()
        ui.appearedAt = Date()
        gaze.start()
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.captureOnly, self.ui.expanded, !self.ui.fullScreen, !self.visibleRect.contains(NSEvent.mouseLocation) else { return }
                self.setExpanded(false)
            }
        }
        // Clics : la fenêtre laisse passer la souris sauf au-dessus de la forme visible.
        moveMonitors = [NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in MainActor.assumeIsolated { self?.updateMouse() } } as Any,
                        NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] e in MainActor.assumeIsolated { self?.updateMouse() }; return e } as Any]
    }

    func setExpanded(_ on: Bool, takeKeys: Bool = false) {
        if !on { ui.fullScreen = false }
        // la fenêtre est d'abord posée (sans animation), PUIS la forme grandit depuis le centre de l'encoche
        apply(on ? (ui.fullScreen ? geo.screen.frame.size : geo.expandedSize) : geo.collapsedSize, animated: true)
        withAnimation(.spring(duration: 0.4, bounce: 0.18)) { ui.expanded = on }
        if !captureOnly { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }   // léger retour du trackpad (sans effet si le matériel n'en a pas)
        panel.allowKey = on && takeKeys
        if on && takeKeys { panel.makeKey(); installKeys() } else if !on { removeKeys() }
    }

    /// Écran branché / débranché / résolution changée : on retrouve l'encoche et on replace la barre (sinon elle resterait au mauvais endroit).
    private func screensChanged() {
        guard let g = NotchGeometry.detect() else { return }
        geo = g
        ui.notchWidth = g.notchWidth; ui.barHeight = g.barHeight
        apply(ui.fullScreen ? g.screen.frame.size : (ui.expanded ? g.expandedSize : g.collapsedSize), animated: false)
    }

    func setFullScreen(_ on: Bool) {
        guard ui.expanded else { return }
        // le contenu change de mise en page d'un coup : on le cache, puis il « sort de l'encoche » (zoom depuis le haut, au centre)
        ui.settled = false
        ui.fullScreen = on
        apply(on ? geo.screen.frame.size : geo.expandedSize, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
            withAnimation(.spring(duration: 0.45, bounce: 0.12)) { self?.ui.settled = true }
        }
    }

    /// Raccourcis dans le tiroir (actifs seulement si tu l'as ouvert toi-même) : 1–7 onglets · ⌘K ou / recherche · B acheter / S vendre (fictif) · C copier · D DexScreener · F plein écran · Échap fermer.
    private func installKeys() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, self.ui.expanded, e.window === self.panel else { return e }
            // ⌘K : recherche universelle
            if e.modifierFlags.contains(.command), e.charactersIgnoringModifiers?.lowercased() == "k" { self.ui.palette.toggle(); return nil }
            guard e.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return e }
            // Pendant la frappe (recherche, notes, filtres), les lettres vont au champ de texte : jamais d'achat fictif par accident.
            if self.ui.palette || e.window?.firstResponder is NSText { return e }
            let items = self.store.feed?.items ?? []
            let target = items.first(where: { $0.mint == self.ui.focusMint }) ?? items.first
            switch e.charactersIgnoringModifiers?.lowercased() {
            case "1": self.ui.tab = .live
            case "2": self.ui.tab = .trades
            case "3": self.ui.tab = .robots
            case "4": self.ui.tab = .wallets
            case "5": self.ui.tab = .funnel
            case "6": self.ui.tab = .alerts
            case "7": self.ui.tab = .settings
            case "/": self.ui.palette = true
            case "b": if let t = target { self.ui.flash(self.lab.buy(t, now: Date())) }
            case "s": if let t = target { self.ui.flash(self.lab.sell(mint: t.mint, fraction: 1, seenMcap: t.marketCap, now: Date())) }
            case "c": if let t = target { copyCA(t.mint, ui: self.ui) }
            case "d": if let t = target { openDexScreener(t.mint, ui: self.ui) }
            case "f": self.setFullScreen(!self.ui.fullScreen)
            case "\u{1b}": if self.ui.fullScreen { self.setFullScreen(false) } else { self.setExpanded(false) }
            default: return e
            }
            return nil
        }
    }

    private func removeKeys() { if let k = keyMonitor { NSEvent.removeMonitor(k); keyMonitor = nil } }

    /// Essai sans permission d'enregistrement d'écran : la vue se dessine elle-même dans un PNG (ne prouve PAS le placement sous l'encoche réelle).
    func snapshot(to path: String) -> Bool {
        guard let v = panel.contentView else { return false }
        let w = ui.visibleSize.width, h = ui.visibleSize.height
        let r = NSRect(x: (v.bounds.width - w) / 2, y: v.isFlipped ? 0 : v.bounds.height - h, width: w, height: h)
        guard let rep = v.bitmapImageRepForCachingDisplay(in: r) else { return false }
        v.cacheDisplay(in: r, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? png.write(to: URL(fileURLWithPath: path))) != nil
    }

    /// Forme visible (en coordonnées écran), avec une petite marge : au-delà, les clics traversent la fenêtre.
    var visibleRect: NSRect {
        let f = geo.screen.frame
        return NSRect(x: f.midX - shown.width / 2 - 6, y: f.maxY - shown.height - 6, width: shown.width + 12, height: shown.height + 6)
    }

    private func apply(_ size: NSSize, animated: Bool) {
        shrinkWork?.cancel()
        let isCollapsed = size == geo.collapsedSize
        // Fenêtre grande seulement pendant que le tiroir est ouvert (repliée : petite = 0 coût de composition d'un écran entier).
        if !isCollapsed {
            panel.setFrame(geo.windowFrame, display: true)
            // Sans ça, SwiftUI anime le passage « petite fenêtre » → « fenêtre plein écran » : la forme glisse depuis la gauche au lieu de sortir du centre.
            if animated { panel.contentView?.layoutSubtreeIfNeeded() }
        }
        else if animated {
            let w = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { guard let self else { return }; self.panel.setFrame(self.collapsedFrame, display: true) } }
            shrinkWork = w; DispatchQueue.main.asyncAfter(deadline: .now() + 0.55, execute: w)
        } else { panel.setFrame(collapsedFrame, display: true) }
        shown = size   // zone cliquable = taille finale (évite de perdre un clic pendant l'ouverture)
        ui.targetSize = size
        if animated { withAnimation(.spring(duration: 0.4, bounce: 0.18)) { ui.visibleSize = size } } else { ui.visibleSize = size }
        updateMouse()
    }

    private func updateMouse() {
        if captureOnly { return }
        let inside = visibleRect.contains(NSEvent.mouseLocation)
        if panel.ignoresMouseEvents == inside { panel.ignoresMouseEvents = !inside }
    }
}
