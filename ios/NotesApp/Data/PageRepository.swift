import Foundation
import GRDB

final class PageRepository {
    private let writer: any DatabaseWriter

    init(writer: any DatabaseWriter) {
        self.writer = writer
    }

    func fetchAll(notebookId: String) throws -> [Page] {
        try writer.read { db in
            try Page
                .filter(Column("notebook_id") == notebookId)
                .order(Column("page_index").asc)
                .fetchAll(db)
        }
    }

    func fetch(id: String) throws -> Page? {
        try writer.read { db in
            try Page.fetchOne(db, key: id)
        }
    }

    func append(notebookId: String, template: PageTemplateKind) throws -> Page {
        try writer.write { db in
            let nextIndex = try Int.fetchOne(db, sql:
                "SELECT COALESCE(MAX(page_index) + 1, 0) FROM pages WHERE notebook_id = ?",
                arguments: [notebookId]
            ) ?? 0
            let now = Date()
            let page = Page(
                id: UUID().uuidString,
                notebookId: notebookId,
                pageIndex: nextIndex,
                template: template,
                drawingBlob: nil,
                thumbnailBlob: nil,
                createdAt: now,
                updatedAt: now
            )
            try page.insert(db)
            return page
        }
    }

    func updateDrawing(pageId: String, drawing: Data, thumbnail: Data?) throws {
        try writer.write { db in
            try db.execute(sql: """
                UPDATE pages
                   SET drawing_blob = ?, thumbnail_blob = ?, updated_at = ?
                 WHERE id = ?
                """,
                arguments: [drawing, thumbnail, Date(), pageId]
            )
        }
    }

    func delete(id: String) throws {
        try writer.write { db in
            guard let page = try Page.fetchOne(db, key: id) else { return }
            try Page.deleteOne(db, key: id)
            // Re-number remaining pages so indexes stay contiguous.
            try db.execute(sql: """
                UPDATE pages
                   SET page_index = page_index - 1
                 WHERE notebook_id = ? AND page_index > ?
                """,
                arguments: [page.notebookId, page.pageIndex]
            )
        }
    }
}
