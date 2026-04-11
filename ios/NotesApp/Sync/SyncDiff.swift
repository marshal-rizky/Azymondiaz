import Foundation
import GRDB

struct SyncDiff: Codable {
    let notebooks: [Notebook]
    let pages: [Page]
    let messages: [AIMessage]
    let computedAt: Date

    static func compute(writer: any DatabaseWriter, since: Date?) throws -> SyncDiff {
        try writer.read { db in
            let cutoff = since ?? Date(timeIntervalSince1970: 0)
            let notebooks = try Notebook
                .filter(Column("updated_at") > cutoff)
                .fetchAll(db)
            let pages = try Page
                .filter(Column("updated_at") > cutoff)
                .fetchAll(db)
            let messages = try AIMessage
                .filter(Column("created_at") > cutoff)
                .fetchAll(db)
            return SyncDiff(
                notebooks: notebooks,
                pages: pages,
                messages: messages,
                computedAt: Date()
            )
        }
    }
}
