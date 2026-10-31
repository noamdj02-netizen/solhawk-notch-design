import AppKit
import ServiceManagement

/// « Lancer SolHawk à l'ouverture de la session » : on le demande UNE fois, on ne l'active que sur un « Oui », et c'est réversible dans Réglages.
/// Ne touche à rien d'autre sur le Mac. Nécessite l'app installée (.app).
@MainActor
enum LoginItem {
    private static let askedKey = "loginItemAsked"

    static var available: Bool { Bundle.main.bundlePath.hasSuffix(".app") }
    static var enabled: Bool { SMAppService.mainApp.status == .enabled }

    /// Renvoie un message d'erreur lisible si ça échoue (app non signée, hors /Applications…), sinon nil.
    @discardableResult
    static func set(_ on: Bool) -> String? {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return nil
        } catch {
            return "Impossible de modifier le lancement au démarrage (\(error.localizedDescription))."
        }
    }

    /// Pose la question au premier lancement seulement. `flash` affiche le résultat dans l'app.
    static func askOnce(flash: (String) -> Void) {
        guard available, !UserDefaults.standard.bool(forKey: askedKey) else { return }
        UserDefaults.standard.set(true, forKey: askedKey)
        let a = NSAlert()
        a.messageText = "Lancer SolHawk au démarrage ?"
        a.informativeText = "Voulez-vous que SolHawk se lance tout seul quand vous ouvrez votre session ? Il reste en lecture seule et discret dans l'encoche. Vous pouvez le changer à tout moment dans Réglages."
        a.addButton(withTitle: "Oui, lancer au démarrage")
        a.addButton(withTitle: "Non")
        NSApp.activate(ignoringOtherApps: true)
        if a.runModal() == .alertFirstButtonReturn {
            flash(set(true) ?? "SolHawk se lancera au démarrage.")
        }
    }
}
