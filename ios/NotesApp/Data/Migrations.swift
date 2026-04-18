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

        migrator.registerMigration("v3_page_media_and_theme") { db in
            // Add per-page theme column (default 'light' for existing pages)
            try db.alter(table: "pages") { t in
                t.add(column: "theme", .text).notNull().defaults(to: "light")
            }

            // New table for floating image objects on canvas pages
            try db.create(table: "page_media") { t in
                t.column("id", .text).primaryKey()
                t.column("page_id", .text)
                    .notNull()
                    .references("pages", onDelete: .cascade)
                t.column("sort_index", .integer).notNull().defaults(to: 0)
                t.column("image_blob", .blob).notNull()
                t.column("x", .double).notNull().defaults(to: 0.3)
                t.column("y", .double).notNull().defaults(to: 0.3)
                t.column("width", .double).notNull().defaults(to: 0.4)
                t.column("height", .double).notNull().defaults(to: 0.4)
                t.column("created_at", .datetime).notNull()
            }
            try db.create(index: "idx_page_media_page", on: "page_media", columns: ["page_id"])
        }

        try migrator.migrate(writer)
    }
}
