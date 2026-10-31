import Foundation
import Security

public protocol TokenStore: Sendable {
    func load() -> String?
    func save(_ token: String) -> Bool
    func delete()
}

/// Le jeton vit dans le Trousseau macOS : jamais dans un fichier, une variable d'environnement, un argument ou un journal.
public struct KeychainTokenStore: TokenStore {
    private let service: String
    private let account = "api-token"
    public init(service: String = "fr.solhawk.notch") { self.service = service }

    private var base: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    public func load() -> String? {
        var q = base; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    public func save(_ token: String) -> Bool {
        delete()
        var q = base
        q[kSecValueData as String] = Data(token.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }

    public func delete() { SecItemDelete(base as CFDictionary) }
}
