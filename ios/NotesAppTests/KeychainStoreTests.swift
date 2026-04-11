import XCTest
@testable import NotesApp

// MARK: - In-memory storage for tests (no Keychain entitlement required)

final class InMemoryStorage: SecretStorage {
    private var store: [String: Data] = [:]

    func set(key: String, data: Data) throws { store[key] = data }
    func get(key: String) throws -> Data? { store[key] }
    func delete(key: String) { store.removeValue(forKey: key) }
}

// MARK: - Tests

final class KeychainStoreTests: XCTestCase {
    var sut: KeychainStore!

    override func setUp() {
        super.setUp()
        sut = KeychainStore(storage: InMemoryStorage())
    }

    func test_write_then_read_groq_keys() throws {
        let keys = ["sk-1", "sk-2", "sk-3"]
        try sut.setGroqKeys(keys)
        XCTAssertEqual(try sut.getGroqKeys(), keys)
    }

    func test_read_missing_returns_empty() throws {
        XCTAssertEqual(try sut.getGroqKeys(), [])
    }

    func test_pc_server_url_round_trip() throws {
        try sut.setPCServerURL("http://192.168.1.10:8000")
        XCTAssertEqual(try sut.getPCServerURL(), "http://192.168.1.10:8000")
    }
}
