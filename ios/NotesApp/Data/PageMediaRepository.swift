import Foundation
import GRDB

final class PageMediaRepository {
    private let writer: any DatabaseWriter

    init(writer: any DatabaseWriter) {
        self.writer = writer
    }

    func fetchAll(pageId: String) throws -> [PageMediaItem] {
        try writer.read { db in
            try PageMediaItem
                .filter(Column("page_id") == pageId)
                .order(Column("sort_index").asc)
                .fetchAll(db)
        }
    }

    func insert(_ item: PageMediaItem) throws {
        try writer.write { db in
            try item.insert(db)
        }
    }

    func update(_ item: PageMediaItem) throws {
        try writer.write { db in
            try item.update(db)
        }
    }

    func delete(id: String) throws {
        try writer.write { db in
            try PageMediaItem.deleteOne(db, key: id)
        }
    }
}
