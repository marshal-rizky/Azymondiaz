import XCTest
import GRDB
@testable import NotesApp

final class PageMediaRepositoryTests: XCTestCase {
    private var db: AppDatabase!
    private var notebooks: NotebookRepository!
    private var pages: PageRepository!
    private var media: PageMediaRepository!
    private var pageId: String!

    override func setUpWithError() throws {
        db = try AppDatabase.makeInMemory()
        notebooks = NotebookRepository(writer: db.writer)
        pages = PageRepository(writer: db.writer)
        media = PageMediaRepository(writer: db.writer)
        let nb = try notebooks.create(title: "NB", coverColor: "#000000")
        let p = try pages.append(notebookId: nb.id, template: .blank)
        pageId = p.id
    }

    func test_insert_and_fetchAll_returns_item() throws {
        let item = PageMediaItem(
            id: UUID().uuidString, pageId: pageId, sortIndex: 0,
            imageBlob: Data([0x89, 0x50]), x: 0.1, y: 0.2, width: 0.5, height: 0.5,
            createdAt: Date()
        )
        try media.insert(item)
        let fetched = try media.fetchAll(pageId: pageId)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].id, item.id)
    }

    func test_update_persists_new_position() throws {
        var item = PageMediaItem(
            id: UUID().uuidString, pageId: pageId, sortIndex: 0,
            imageBlob: Data([0x89, 0x50]), x: 0.1, y: 0.2, width: 0.5, height: 0.5,
            createdAt: Date()
        )
        try media.insert(item)
        item.x = 0.7
        item.y = 0.8
        try media.update(item)
        let fetched = try media.fetchAll(pageId: pageId)
        XCTAssertEqual(fetched[0].x, 0.7, accuracy: 0.001)
        XCTAssertEqual(fetched[0].y, 0.8, accuracy: 0.001)
    }

    func test_delete_removes_item() throws {
        let item = PageMediaItem(
            id: UUID().uuidString, pageId: pageId, sortIndex: 0,
            imageBlob: Data([0xFF]), x: 0.1, y: 0.1, width: 0.4, height: 0.4,
            createdAt: Date()
        )
        try media.insert(item)
        try media.delete(id: item.id)
        XCTAssertTrue(try media.fetchAll(pageId: pageId).isEmpty)
    }

    func test_cascade_delete_when_page_deleted() throws {
        let item = PageMediaItem(
            id: UUID().uuidString, pageId: pageId, sortIndex: 0,
            imageBlob: Data([0xFF]), x: 0.1, y: 0.1, width: 0.4, height: 0.4,
            createdAt: Date()
        )
        try media.insert(item)
        try pages.delete(id: pageId)
        // Foreign key cascade should remove the media item
        let fetched = try media.fetchAll(pageId: pageId)
        XCTAssertTrue(fetched.isEmpty)
    }
}
