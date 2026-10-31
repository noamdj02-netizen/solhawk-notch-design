import Foundation

// Mes wallets à suivre : liste LOCALE (adresses publiques + étiquettes à moi), importable par collage comme dans Axiom/Padre.
// Aucune clé privée : une adresse publique ne sert qu'à regarder. Rien n'est envoyé au serveur.

public enum WatchGroup: String, Codable, CaseIterable, Sendable {
    case traders, devs
    public var label: String { self == .traders ? "Traders" : "Développeurs" }
    public var limit: Int { self == .traders ? 50 : 20 }
}

public struct WatchedWallet: Codable, Equatable, Sendable, Identifiable {
    public var address: String
    public var label: String
    public var group: WatchGroup
    public var id: String { address }
    public init(address: String, label: String, group: WatchGroup) { self.address = address; self.label = label; self.group = group }
}

public struct WatchImportResult: Equatable, Sendable {
    public var added = 0
    public var duplicates = 0
    public var invalid = 0
    public var overLimit = 0
    public var summary: String {
        var p = ["\(added) ajouté\(added > 1 ? "s" : "")"]
        if duplicates > 0 { p.append("\(duplicates) déjà présent\(duplicates > 1 ? "s" : "")") }
        if invalid > 0 { p.append("\(invalid) ligne\(invalid > 1 ? "s" : "") ignorée\(invalid > 1 ? "s" : "") (adresse invalide)") }
        if overLimit > 0 { p.append("\(overLimit) refusé\(overLimit > 1 ? "s" : "") (limite du groupe atteinte)") }
        return p.joined(separator: " · ")
    }
}

public struct WatchList: Codable, Equatable, Sendable {
    public private(set) var wallets: [WatchedWallet] = []
    public init(wallets: [WatchedWallet] = []) { self.wallets = wallets }

    public func wallets(in g: WatchGroup) -> [WatchedWallet] { wallets.filter { $0.group == g } }
    public func contains(_ address: String) -> Bool { wallets.contains { $0.address == address } }

    @discardableResult
    public mutating func add(address: String, label: String, group: WatchGroup) -> WatchImportResult {
        var r = WatchImportResult()
        guard isValidMint(address) else { r.invalid = 1; return r }
        guard !contains(address) else { r.duplicates = 1; return r }
        guard wallets(in: group).count < group.limit else { r.overLimit = 1; return r }
        wallets.append(WatchedWallet(address: address, label: cleanLabel(label), group: group))
        r.added = 1
        return r
    }

    public mutating func remove(_ address: String) { wallets.removeAll { $0.address == address } }
    public mutating func rename(_ address: String, to label: String) {
        if let i = wallets.firstIndex(where: { $0.address == address }) { wallets[i].label = cleanLabel(label) }
    }

    /// Colle un texte : une adresse par ligne, avec une étiquette facultative après (« adresse nom », « adresse,nom », « adresse;nom », « adresse<TAB>nom »),
    /// ou un tableau JSON (["adresse", …] / [{"address":…, "label":…}]). Tout ce qui n'a pas la forme d'une adresse Solana est ignoré.
    @discardableResult
    public mutating func importText(_ text: String, group: WatchGroup) -> WatchImportResult {
        var total = WatchImportResult()
        for (a, l) in WatchList.parse(text) {
            let r = add(address: a, label: l, group: group)
            total.added += r.added; total.duplicates += r.duplicates; total.invalid += r.invalid; total.overLimit += r.overLimit
        }
        total.invalid += WatchList.invalidLines(text)
        return total
    }

    static func parse(_ text: String) -> [(String, String)] {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("["), let d = t.data(using: .utf8), let any = try? JSONSerialization.jsonObject(with: d) as? [Any] {
            return any.compactMap { e in
                if let s = e as? String { return isValidMint(s) ? (s, "") : nil }
                if let o = e as? [String: Any], let a = (o["address"] ?? o["wallet"] ?? o["trackedWalletAddress"]) as? String, isValidMint(a) {
                    return (a, (o["label"] ?? o["name"]) as? String ?? "")
                }
                return nil
            }
        }
        return lines(text).compactMap { line in
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "," || $0 == ";" || $0 == "|" }).map(String.init)
            guard let i = parts.firstIndex(where: isValidMint) else { return nil }
            let label = (parts[..<i] + parts[(i + 1)...]).joined(separator: " ")
            return (parts[i], label)
        }
    }

    /// Nombre d'adresses valides détectées dans un texte collé (avant tout ajout).
    public static func countCandidates(_ text: String) -> Int { parse(text).count }

    static func lines(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    static func invalidLines(_ text: String) -> Int {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("[") { return 0 }
        return lines(text).filter { line in
            !line.split(whereSeparator: { " \t,;|".contains($0) }).contains { isValidMint(String($0)) }
        }.count
    }

    /// Texte à copier pour réimporter ailleurs : « adresse étiquette », une ligne par wallet.
    public func exportText(group: WatchGroup? = nil) -> String {
        wallets.filter { group == nil || $0.group == group }.map { $0.label.isEmpty ? $0.address : "\($0.address) \($0.label)" }.joined(separator: "\n")
    }
}

/// Étiquette : bornée, une ligne, sans caractère de contrôle (le texte collé n'est pas fiable).
func cleanLabel(_ s: String) -> String {
    let t = String(s.unicodeScalars.filter { !$0.properties.isDefaultIgnorableCodePoint && $0.value >= 32 && $0.value != 127 }.map(Character.init))
    return String(t.trimmingCharacters(in: .whitespaces).prefix(24))
}

/// Lecture / écriture du fichier local (JSON dans Application Support, droits 600).
public struct WatchListFile: Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }
    public static var standard: WatchListFile {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("SolHawk Notch", isDirectory: true)
        return WatchListFile(url: base.appendingPathComponent("watched-wallets.json"))
    }
    public func load() -> WatchList {
        guard let d = try? Data(contentsOf: url), let l = try? JSONDecoder().decode(WatchList.self, from: d) else { return WatchList() }
        return l
    }
    public func save(_ l: WatchList) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let d = try? JSONEncoder().encode(l) else { return }
        try? d.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
