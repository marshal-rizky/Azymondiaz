import Foundation
import Security

/// Thin Keychain wrapper for the handful of secrets this app stores.
/// Never log values from here. Treat errors as non-fatal: a missing
/// item returns nil/empty rather than throwing, so first-launch flows
/// degrade gracefully.
final class KeychainStore {
    static let shared = KeychainStore()
    private init() {}

    private let service = "dev.user.NotesApp"
    private enum Key: String {
        case groqKeys   = "groq.keys.json"
        case pcURL      = "pc.server.url"
    }

    enum KeychainError: Error { case unexpectedStatus(OSStatus) }

    // MARK: - Public

    func setGroqKeys(_ keys: [String]) throws {
        let data = try JSONEncoder().encode(keys)
        try set(key: .groqKeys, data: data)
    }

    func getGroqKeys() throws -> [String] {
        guard let data = try get(key: .groqKeys) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    func setPCServerURL(_ url: String) throws {
        try set(key: .pcURL, data: Data(url.utf8))
    }

    func getPCServerURL() throws -> String? {
        guard let data = try get(key: .pcURL) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func deleteAll() {
        for key in [Key.groqKeys, .pcURL] {
            let q: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: key.rawValue
            ]
            SecItemDelete(q as CFDictionary)
        }
    }

    // MARK: - Private

    private func set(key: Key, data: Data) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }

    private func get(key: Key) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
        return result as? Data
    }
}
