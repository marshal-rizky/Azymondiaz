// ios/NotesApp/Data/Folder.swift
import Foundation
import GRDB

struct Folder: Identifiable, Hashable, Codable, FetchableRecord, PersistableRecord {
    var id: String
    var parentFolderID: String?
    var title: String
    var createdAt: Date
    var updatedAt: Date

    static let databaseTableName = "folders"

    enum CodingKeys: String, CodingKey {
        case id
        case parentFolderID = "parent_folder_id"
        case title
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
