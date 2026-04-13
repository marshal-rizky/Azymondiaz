import Foundation
import GRDB

final class NotebookRepository {
    private let writer: any DatabaseWriter

    init(writer: any DatabaseWriter) {
        self.writer = writer
    }

    func create(title: String, coverColor: String, folderID: String? = nil) throws -> Notebook {
        let now = Date()
        let nb = Notebook(
            id: UUID().uuidString,
            folderID: folderID,
            title: title,
            coverColor: coverColor,
            createdAt: now,
            updatedAt: now
        )
        try writer.write { db in
            try nb.insert(db)
        }
        return nb
    }

    func fetchAll() throws -> [Notebook] {
        try writer.read { db in
            try Notebook
                .order(Column("updated_at").desc)
                .fetchAll(db)
        }
    }

    /// Fetches notebooks in a specific folder. Pass nil for root-level notebooks.
    func fetchAll(folderID: String?) throws -> [Notebook] {
        try writer.read { db in
            if let fid = folderID {
                return try Notebook
                    .filter(Column("folder_id") == fid)
                    .order(Column("updated_at").desc)
                    .fetchAll(db)
            } else {
                return try Notebook
                    .filter(Column("folder_id") == nil)
                    .order(Column("updated_at").desc)
                    .fetchAll(db)
            }
        }
    }

    func fetch(id: String) throws -> Notebook? {
        try writer.read { db in
            try Notebook.fetchOne(db, key: id)
        }
    }

    func update(_ notebook: Notebook) throws {
        var copy = notebook
        copy.updatedAt = Date()
        try writer.write { db in
            try copy.update(db)
        }
    }

    func delete(id: String) throws {
        _ = try writer.write { db in
            try Notebook.deleteOne(db, key: id)
        }
    }
}
