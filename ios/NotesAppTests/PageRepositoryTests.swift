import XCTest
import GRDB
@testable import NotesApp

final class PageRepositoryTests: XCTestCase {
    private var db: AppDatabase!
    private var notebooks: NotebookRepository!
    private var pages: PageRepository!
    private var notebookId: String!

    override func setUpWithError() throws {
        db = try AppDatabase.makeInMemory()
        notebooks = NotebookRepository(pool: db.pool)
        pages = PageRepository(pool: db.pool)
        notebookId = try notebooks.create(title: "NB", coverColor: "#123456").id
    }

    func test_append_creates_first_page_with_index_zero() throws {
        let page = try pages.append(notebookId: notebookId, template: .line)
        XCTAssertEqual(page.pageIndex, 0)
        XCTAssertEqual(page.template, .line)
        XCTAssertNil(page.drawingBlob)
    }

    func test_append_assigns_sequential_indexes() throws {
        _ = try pages.append(notebookId: notebookId, template: .blank)
        _ = try pages.append(notebookId: notebookId, template: .line)
        let p3 = try pages.append(notebookId: notebookId, template: .grid)
        XCTAssertEqual(p3.pageIndex, 2)
        let all = try pages.fetchAll(notebookId: notebookId)
        XCTAssertEqual(all.map(\.pageIndex), [0, 1, 2])
    }

    func test_updateDrawing_persists_blob() throws {
        let page = try pages.append(notebookId: notebookId, template: .grid)
        let bytes = Data([0xDE, 0xAD, 0xBE, 0xEF])
        try pages.updateDrawing(pageId: page.id, drawing: bytes, thumbnail: nil)
        let reloaded = try XCTUnwrap(pages.fetch(id: page.id))
        XCTAssertEqual(reloaded.drawingBlob, bytes)
    }

    func test_delete_cascades_from_notebook() throws {
        _ = try pages.append(notebookId: notebookId, template: .blank)
        _ = try pages.append(notebookId: notebookId, template: .blank)
        try notebooks.delete(id: notebookId)
        XCTAssertTrue(try pages.fetchAll(notebookId: notebookId).isEmpty)
    }

    func test_deletePage_reindexes_remaining() throws {
        let p0 = try pages.append(notebookId: notebookId, template: .line)
        let p1 = try pages.append(notebookId: notebookId, template: .line)
        let p2 = try pages.append(notebookId: notebookId, template: .line)
        try pages.delete(id: p1.id)
        let remaining = try pages.fetchAll(notebookId: notebookId)
        XCTAssertEqual(remaining.map(\.id), [p0.id, p2.id])
        XCTAssertEqual(remaining.map(\.pageIndex), [0, 1])
    }
}
