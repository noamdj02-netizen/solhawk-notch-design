import AppKit
import Carbon.HIToolbox
import Observation
import SolHawkNotchCore

/// Réglages des alertes (UserDefaults). Par défaut tout est activé : le but est d'être prévenu.
/// Le son se règle par type dans `AlertRulesStore` (avec une coupure globale), plus ici.
enum AlertPrefs {
    static var notify: Bool { get { flag("alertNotify") } set { UserDefaults.standard.set(newValue, forKey: "alertNotify") } }
    /// Ouverture automatique du tiroir. Jamais pendant les heures calmes (on ne dérange pas).
    static var autoOpen: Bool {
        get {
            let c = AlertConfigBox.shared.config
            return flag("alertAutoOpen") && !(c.quietHours && inQuietHours(Date(), start: c.quietStart, end: c.quietEnd))
        }
        set { UserDefaults.standard.set(newValue, forKey: "alertAutoOpen") }
    }
    fileprivate static func flag(_ k: String) -> Bool { UserDefaults.standard.object(forKey: k) == nil ? true : UserDefaults.standard.bool(forKey: k) }
}

/// Règles d'alerte (un type = activé, seuil, son) + coupure du son + heures calmes. JSON dans UserDefaults, rien d'autre.
/// Recopié dans `AlertConfigBox.shared` à chaque changement : c'est là que le moteur d'alerte (Core) le lit.
@MainActor @Observable
final class AlertRulesStore {
    static let shared = AlertRulesStore()
    static let key = "alertConfig.v1"

    private(set) var config: AlertConfig
    /// Alertes de positions fictives (le journal du flux est dans FeedStore ; celles-ci viennent du labo fictif).
    private(set) var positionLog: [(at: Date, alert: NotchAlert)] = []
    @ObservationIgnored private var positionFired: Set<String> = []

    private init() {
        let d = UserDefaults.standard
        if let data = d.data(forKey: AlertRulesStore.key) {
            config = AlertConfig.decode(data)
        } else {
            var c = AlertConfig.defaults
            if d.object(forKey: "alertSound") != nil, !d.bool(forKey: "alertSound") { c.muted = true }   // ancien réglage « Son : non »
            config = c
        }
        AlertConfigBox.shared.config = config
    }

    func update(_ edit: (inout AlertConfig) -> Void) {
        var c = config
        edit(&c)
        c = c.sanitized()
        guard c != config else { return }
        config = c
        AlertConfigBox.shared.config = c
        if let data = c.encoded() { UserDefaults.standard.set(data, forKey: AlertRulesStore.key) }
    }

    func setRule(_ kind: AlertKind, _ edit: (inout AlertRule) -> Void) { update { edit(&$0[kind]) } }

    var quietNow: Bool { config.quietHours && inQuietHours(Date(), start: config.quietStart, end: config.quietEnd) }

    /// Positions FICTIVES : à appeler à chaque flux reçu (après `lab.ingest`). Une alerte par franchissement du seuil.
    /// Un type désactivé reste suivi : le réactiver ne fait pas sonner un franchissement déjà ancien.
    func checkPositions(lab: PaperLab, now: Date) {
        let rule = config[.positionThreshold]
        let open = lab.manual.open
        let r = positionCrossings(open: open.map { (mint: $0.mint, symbol: $0.symbol, pnlPct: $0.pnlPct) }, threshold: rule.threshold ?? 50, alreadyFired: positionFired)
        positionFired = r.fired
        guard rule.enabled, !r.alerts.isEmpty else { return }
        let fresh = r.alerts.map { a in var a = a; a.image = open.first { $0.mint == a.mint }?.image; return a }
        positionLog = Array((fresh.map { (now, $0) } + positionLog).prefix(40))
        guard ProcessInfo.processInfo.environment["SOLHAWK_NOTCH_SNAPSHOT"] == nil else { return }   // pas de son pendant les essais
        for a in fresh { AlertDelivery.notify(a) }
    }
}

/// Notification macOS + son. Passe par osascript (l'app n'a pas de bundle signé) ; le texte est transmis en ARGUMENTS, jamais collé dans un script.
/// Le texte vient du serveur (donnée non fiable) : déjà nettoyé par `safeLabel` dans `AlertEngine`, et borné ici.
/// Le son est un nom de la liste autorisée (`alertSoundNames`), joué par `NSSound(named:)` : jamais un chemin ni un nom venu du serveur.
enum AlertDelivery {
    @MainActor static func notify(_ a: NotchAlert) {
        let d = decideDelivery(a.type, config: AlertRulesStore.shared.config, notifyPref: AlertPrefs.notify, now: Date())
        if d.notify {
            let title = String("SolHawk · \(a.title)".prefix(80)), body = String(a.body.prefix(160))
            DispatchQueue.global(qos: .utility).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                p.arguments = ["-e", "on run argv", "-e", "display notification (item 2 of argv) with title (item 1 of argv)", "-e", "end run", title, body]
                p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
                try? p.run()
            }
        }
        if let s = d.sound { play(s) }
    }

    /// Joue un son système autorisé. Retourne false si le nom est refusé ou introuvable.
    @MainActor @discardableResult static func play(_ name: String) -> Bool {
        guard let ok = validSoundName(name), let s = NSSound(named: NSSound.Name(ok)) else { return false }
        if s.isPlaying { s.stop() }
        return s.play()
    }
}

/// Raccourci clavier global (Contrôle + Option + Espace). Carbon : aucune permission demandée.
@MainActor
final class GlobalHotKey {
    private var ref: EventHotKeyRef?
    nonisolated(unsafe) static var action: (() -> Void)?

    init(action: @escaping () -> Void) {
        GlobalHotKey.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { GlobalHotKey.action?() }
            return noErr
        }, 1, &spec, nil, nil)
        RegisterEventHotKey(UInt32(kVK_Space), UInt32(controlKey | optionKey), EventHotKeyID(signature: OSType(0x53484B31), id: 1), GetApplicationEventTarget(), 0, &ref)
    }
}
