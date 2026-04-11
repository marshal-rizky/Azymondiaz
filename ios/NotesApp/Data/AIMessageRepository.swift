import Foundation
import GRDB

final class AIMessageRepository {
    private let writer: any DatabaseWriter

    init(writer: any DatabaseWriter) { self.writer = writer }

    @discardableResult
    func append(pageId: String, role: AIMessageRole, text: String) throws -> AIMessage {
        let m = AIMessage(
            id: UUID().uuidString,
            pageId: pageId,
            role: role,
            text: text,
            createdAt: Date()
        )
        try writer.write { db in try m.insert(db) }
        return m
    }

    func fetchAll(pageId: String) throws -> [AIMessage] {
        try writer.read { db in
            try AIMessage
                .filter(Column("page_id") == pageId)
                .order(Column("created_at").asc)
                .fetchAll(db)
        }
    }

    func deleteAll(pageId: String) throws {
        try writer.write { db in
            try AIMessage
                .filter(Column("page_id") == pageId)
                .deleteAll(db)
        }
    }
}
