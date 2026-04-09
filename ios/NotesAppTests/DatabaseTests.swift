import XCTest
import GRDB
@testable import NotesApp

final class DatabaseTests: XCTestCase {
    func test_migrator_creates_all_tables() throws {
        let db = try AppDatabase.makeInMemory()
        try db.writer.read { db in
            let tables = try String.fetchAll(db, sql:
                "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
            )
            XCTAssertTrue(tables.contains("notebooks"))
            XCTAssertTrue(tables.contains("pages"))
            XCTAssertTrue(tables.contains("ai_messages"))
            XCTAssertTrue(tables.contains("sync_state"))
        }
    }

    func test_migrator_is_idempotent() throws {
        let db = try AppDatabase.makeInMemory()
        // Running migrator twice should not throw.
        try Migrations.register(on: db.writer)
    }
}
