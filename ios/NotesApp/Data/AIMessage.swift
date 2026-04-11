import Foundation
import GRDB

enum AIMessageRole: String, Codable { case user, assistant }

struct AIMessage: Identifiable, Hashable, Codable, FetchableRecord, PersistableRecord {
    var id: String
    var pageId: String
    var role: AIMessageRole
    var text: String
    var createdAt: Date

    static let databaseTableName = "ai_messages"

    enum CodingKeys: String, CodingKey {
        case id
        case pageId = "page_id"
        case role
        case text
        case createdAt = "created_at"
    }
}
