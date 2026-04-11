import Foundation
import Security

// MARK: - Storage protocol (injectable for tests)

protocol SecretStorage {
    func set(key: String, data: Data) throws
    func get(key: String) throws -> Data?
    func delete(key: String)
}

// MARK: - Keychain backend (production)

final class KeychainStorage: SecretStorage {
    private let service: String
    enum Error: Swift.Error { case unexpectedStatus(OSStatus) }

    init(service: String) { self.service = service }

    func set(key: String, data: Data) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw Error.unexpectedStatus(status) }
    }

    func get(key: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw Error.unexpectedStatus(status) }
        return result as? Data
    }

    func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - KeychainStore

/// Thin wrapper that encodes/decodes app secrets and delegates raw storage.
/// Inject a different SecretStorage in tests to avoid Keychain entitlement requirements.
final class KeychainStore {
    static let shared = KeychainStore(storage: KeychainStorage(service: "dev.user.NotesApp"))

    private let storage: any SecretStorage
    private enum Key: String {
        case groqKeys = "groq.keys.json"
        case pcURL    = "pc.server.url"
    }

    init(storage: any SecretStorage) {
        self.storage = storage
    }

    // MARK: - Public

    func setGroqKeys(_ keys: [String]) throws {
        let data = try JSONEncoder().encode(keys)
        try storage.set(key: Key.groqKeys.rawValue, data: data)
    }

    func getGroqKeys() throws -> [String] {
        guard let data = try storage.get(key: Key.groqKeys.rawValue) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    func setPCServerURL(_ url: String) throws {
        try storage.set(key: Key.pcURL.rawValue, data: Data(url.utf8))
    }

    func getPCServerURL() throws -> String? {
        guard let data = try storage.get(key: Key.pcURL.rawValue) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func deleteAll() {
        storage.delete(key: Key.groqKeys.rawValue)
        storage.delete(key: Key.pcURL.rawValue)
    }
}
