import SwiftUI
import SolHawkNotchCore

/// Adresse du serveur + jeton (Trousseau, jamais réaffiché), alertes, et l'état du serveur (ex-onglet Santé).
struct SettingsView: View {
    var store: FeedStore
    var save: (_ url: String, _ token: String?) -> String?
    @State private var url: String
    @State private var token = ""
    @State private var message: String?
    @AppStorage("alertNotify") private var notify = true
    @AppStorage("alertAutoOpen") private var autoOpen = true
    private var rules: AlertRulesStore { .shared }   // son (coupure globale) et heures calmes

    /// Un jeton SolHawk : 16 à 128 caractères parmi lettres, chiffres, « - » et « _ » (rien d'autre, pas d'espace ni de « @»).
    private var tokenLooksValid: Bool {
        (16...128).contains(token.count) && token.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }

    init(store: FeedStore, initialURL: String, save: @escaping (String, String?) -> String?) {
        self.store = store; self.save = save; _url = State(initialValue: initialURL)
    }

    var body: some View {
        Form {
            Section("Serveur") {
                TextField("Adresse", text: $url)
                HStack(spacing: 8) {
                    Button("Utiliser l'adresse SolHawk") { url = AppDelegate.defaultURL }.disabled(url == AppDelegate.defaultURL)
                    Text("L'adresse n'est pas un secret.").font(.footnote).foregroundStyle(.secondary)
                }
                SecureField("Jeton", text: $token, prompt: Text("Colle le jeton ici (vide = inchangé)"))
                HStack(spacing: 8) {
                    Button("Coller le jeton copié") {
                        if let c = NSPasteboard.general.string(forType: .string) { token = c.trimmingCharacters(in: .whitespacesAndNewlines) }
                    }
                    Text(token.isEmpty ? "rien saisi" : tokenLooksValid ? "\(token.count) caractères saisis" : "\(token.count) caractères : pas un jeton").font(.footnote)
                        .foregroundStyle(token.isEmpty ? Color.secondary : tokenLooksValid ? Color.green : Color.red)
                }
                if !token.isEmpty && !tokenLooksValid {
                    Text("Le texte collé contient autre chose que le jeton (par exemple le début de l'invite du Terminal, ou un espace). Un jeton ne contient que des lettres, des chiffres, « - » et « _ ». Recopie-le seul, sans le reste de la ligne.")
                        .font(.footnote).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                }
                Text("Le jeton est stocké dans le Trousseau du Mac. Il n'est jamais affiché ni écrit dans un fichier.").font(.footnote).foregroundStyle(.secondary)
                HStack {
                    Button("Enregistrer") { message = save(url, token.isEmpty ? nil : token); if message == nil { token = "" } }
                        .keyboardShortcut(.defaultAction).disabled(!token.isEmpty && !tokenLooksValid)
                    if let message { Text(message).font(.footnote).foregroundStyle(.red) }
                }
            }
            Section("Alertes") {
                Toggle("Notification macOS", isOn: $notify)
                Toggle("Son", isOn: Binding(get: { !rules.config.muted }, set: { v in rules.update { $0.muted = !v } }))
                Toggle("Ouvrir le tiroir tout seul (sans voler le clavier)", isOn: $autoOpen)
                Toggle("Heures calmes (ni son, ni notification, ni ouverture)", isOn: Binding(get: { rules.config.quietHours }, set: { v in rules.update { $0.quietHours = v } }))
                if rules.config.quietHours {
                    Stepper("De \(String(format: "%02d h", rules.config.quietStart))", onIncrement: { rules.update { $0.quietStart = ($0.quietStart + 1) % 24 } },
                            onDecrement: { rules.update { $0.quietStart = ($0.quietStart + 23) % 24 } })
                    Stepper("À \(String(format: "%02d h", rules.config.quietEnd))", onIncrement: { rules.update { $0.quietEnd = ($0.quietEnd + 1) % 24 } },
                            onDecrement: { rules.update { $0.quietEnd = ($0.quietEnd + 23) % 24 } })
                }
                Text("Règles par type (activée, son, seuil) : onglet Alertes en plein écran (touche F). Vert : un token passe les filtres (ça ne prouve pas qu'il est sûr). Rouge : chute forte depuis le pic, ou serveur injoignable. Jaune : une position fictive franchit son seuil. Raccourci : Ctrl+Option+Espace.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("État du serveur") { HealthView(store: store) }
        }
        .formStyle(.grouped)
        .frame(minWidth: 520, idealWidth: 520, minHeight: 560, idealHeight: 620)
    }
}
