import Foundation
import GRDB

/// Thin wrapper around a GRDB `DatabasePool`. Owns the app's single SQLite file.
final class Database {
    let pool: DatabasePool

    private init(pool: DatabasePool) {
        self.pool = pool
    }

    /// Production: opens/creates `~/Documents/notes.sqlite`.
    static func makeDefault() throws -> Database {
        let url = try FileManager.default
            .url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("notes.sqlite")
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        let pool = try DatabasePool(path: url.path, configuration: config)
        try Migrations.register(on: pool)
        return Database(pool: pool)
    }

    /// Tests: in-memory pool, no filesystem.
    static func makeInMemory() throws -> Database {
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        let pool = try DatabasePool(path: ":memory:", configuration: config)
        try Migrations.register(on: pool)
        return Database(pool: pool)
    }
}
