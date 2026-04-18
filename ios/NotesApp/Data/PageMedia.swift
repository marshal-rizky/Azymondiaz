import Foundation
import GRDB

struct PageMediaItem: Identifiable, Codable, FetchableRecord, PersistableRecord {
    var id: String
    var pageId: String
    var sortIndex: Int
    var imageBlob: Data
    var x: Double        // fraction of page width (0–1)
    var y: Double        // fraction of page height (0–1)
    var width: Double    // fraction of page width (0–1)
    var height: Double   // computed to preserve aspect ratio
    var createdAt: Date

    static let databaseTableName = "page_media"

    enum CodingKeys: String, CodingKey {
        case id
        case pageId = "page_id"
        case sortIndex = "sort_index"
        case imageBlob = "image_blob"
        case x, y, width, height
        case createdAt = "created_at"
    }
}
