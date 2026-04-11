import XCTest
@testable import NotesApp

final class KeychainStoreTests: XCTestCase {
    override func setUp() {
        super.setUp()
        KeychainStore.shared.deleteAll()
    }

    func test_write_then_read_groq_keys() throws {
        let keys = ["sk-1", "sk-2", "sk-3"]
        try KeychainStore.shared.setGroqKeys(keys)
        XCTAssertEqual(try KeychainStore.shared.getGroqKeys(), keys)
    }

    func test_read_missing_returns_empty() throws {
        XCTAssertEqual(try KeychainStore.shared.getGroqKeys(), [])
    }

    func test_pc_server_url_round_trip() throws {
        try KeychainStore.shared.setPCServerURL("http://192.168.1.10:8000")
        XCTAssertEqual(try KeychainStore.shared.getPCServerURL(), "http://192.168.1.10:8000")
    }
}
