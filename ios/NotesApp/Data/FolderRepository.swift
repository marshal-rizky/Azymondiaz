// ios/NotesApp/Data/FolderRepository.swift
import Foundation
import GRDB

final class FolderRepository {
    private let writer: any DatabaseWriter

    init(writer: any DatabaseWriter) {
        self.writer = writer
    }

    func create(title: String, parentFolderID: String?) throws -> Folder {
        let now = Date()
        let folder = Folder(
            id: UUID().uuidString,
            parentFolderID: parentFolderID,
            title: title,
            createdAt: now,
            updatedAt: now
        )
        try writer.write { db in try folder.insert(db) }
        return folder
    }

    /// Fetches direct children of a folder. Pass nil for root-level folders.
    func fetchChildren(of parentID: String?) throws -> [Folder] {
        try writer.read { db in
            if let pid = parentID {
                return try Folder
                    .filter(Column("parent_folder_id") == pid)
                    .order(Column("title"))
                    .fetchAll(db)
            } else {
                return try Folder
                    .filter(Column("parent_folder_id") == nil)
                    .order(Column("title"))
                    .fetchAll(db)
            }
        }
    }

    func fetch(id: String) throws -> Folder? {
        try writer.read { db in try Folder.fetchOne(db, key: id) }
    }

    func update(_ folder: Folder) throws {
        var copy = folder
        copy.updatedAt = Date()
        try writer.write { db in try copy.update(db) }
    }

    func delete(id: String) throws {
        _ = try writer.write { db in try Folder.deleteOne(db, key: id) }
    }
}
