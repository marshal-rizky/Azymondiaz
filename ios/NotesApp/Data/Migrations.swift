import Foundation
import GRDB

enum Migrations {
    static func register(on writer: any DatabaseWriter) throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_initial_schema") { db in
            try db.create(table: "notebooks") { t in
                t.column("id", .text).primaryKey()
                t.column("title", .text).notNull()
                t.column("cover_color", .text).notNull().defaults(to: "#4A90E2")
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
            }

            try db.create(table: "pages") { t in
                t.column("id", .text).primaryKey()
                t.column("notebook_id", .text)
                    .notNull()
                    .references("notebooks", onDelete: .cascade)
                t.column("page_index", .integer).notNull()
                t.column("template", .text).notNull()
                t.column("drawing_blob", .blob)
                t.column("thumbnail_blob", .blob)
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
                t.uniqueKey(["notebook_id", "page_index"])
            }

            try db.create(table: "ai_messages") { t in
                t.column("id", .text).primaryKey()
                t.column("page_id", .text)
                    .notNull()
                    .references("pages", onDelete: .cascade)
                t.column("role", .text).notNull()
                t.column("text", .text).notNull()
                t.column("created_at", .datetime).notNull()
            }

            try db.create(table: "sync_state") { t in
                t.column("id", .integer).primaryKey()
                t.column("last_sync_at", .datetime)
                t.column("pc_server_url", .text)
            }
            try db.execute(sql:
                "INSERT INTO sync_state (id, last_sync_at, pc_server_url) VALUES (1, NULL, NULL)"
            )
        }

        migrator.registerMigration("v2_folders") { db in
            try db.create(table: "folders") { t in
                t.column("id", .text).primaryKey()
                t.column("parent_folder_id", .text)
                    .references("folders", onDelete: .cascade)
                t.column("title", .text).notNull()
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
            }
            try db.alter(table: "notebooks") { t in
                t.add(column: "folder_id", .text)
                    .references("folders", onDelete: .setNull)
            }
        }

        try migrator.migrate(writer)
    }
}
