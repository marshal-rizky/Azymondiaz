import Foundation
import GRDB

enum PageTemplateKind: String, Codable, CaseIterable {
    case line
    case grid
    case blank
}

struct Page: Identifiable, Hashable, Codable, FetchableRecord, PersistableRecord {
    var id: String
    var notebookId: String
    var pageIndex: Int
    var template: PageTemplateKind
    var theme: String       // "light" | "dark"
    var drawingBlob: Data?
    var thumbnailBlob: Data?
    var createdAt: Date
    var updatedAt: Date

    static let databaseTableName = "pages"

    enum CodingKeys: String, CodingKey {
        case id
        case notebookId = "notebook_id"
        case pageIndex = "page_index"
        case template
        case theme
        case drawingBlob = "drawing_blob"
        case thumbnailBlob = "thumbnail_blob"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
