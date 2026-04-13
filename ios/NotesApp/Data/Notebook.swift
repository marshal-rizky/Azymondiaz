// ios/NotesApp/Data/Notebook.swift
import Foundation
import GRDB

struct Notebook: Identifiable, Hashable, Codable, FetchableRecord, PersistableRecord {
    var id: String
    var folderID: String?
    var title: String
    var coverColor: String
    var createdAt: Date
    var updatedAt: Date

    static let databaseTableName = "notebooks"

    enum CodingKeys: String, CodingKey {
        case id
        case folderID   = "folder_id"
        case title
        case coverColor = "cover_color"
        case createdAt  = "created_at"
        case updatedAt  = "updated_at"
    }
}
