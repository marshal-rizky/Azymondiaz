import Foundation
import GRDB

/// Thin wrapper around a GRDB writer. Owns the app's single SQLite connection.
final class AppDatabase {
    let writer: any DatabaseWriter

    private init(writer: any DatabaseWriter) {
        self.writer = writer
    }

    /// Production: opens/creates `~/Documents/notes.sqlite` using a pool (WAL mode).
    static func makeDefault() throws -> AppDatabase {
        let url = try FileManager.default
            .url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("notes.sqlite")
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        let pool = try DatabasePool(path: url.path, configuration: config)
        try Migrations.register(on: pool)
        return AppDatabase(writer: pool)
    }

    /// Tests: in-memory queue (DatabasePool cannot use WAL on :memory:).
    static func makeInMemory() throws -> AppDatabase {
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        let queue = try DatabaseQueue(path: ":memory:", configuration: config)
        try Migrations.register(on: queue)
        return AppDatabase(writer: queue)
    }
}
