import XCTest
@testable import NotesApp

final class SyncDiffTests: XCTestCase {
    private var db: AppDatabase!
    private var notebooks: NotebookRepository!
    private var pages: PageRepository!

    override func setUpWithError() throws {
        db = try AppDatabase.makeInMemory()
        notebooks = NotebookRepository(writer: db.writer)
        pages = PageRepository(writer: db.writer)
    }

    func test_empty_database_produces_empty_diff() throws {
        let diff = try SyncDiff.compute(writer: db.writer, since: nil)
        XCTAssertTrue(diff.notebooks.isEmpty)
        XCTAssertTrue(diff.pages.isEmpty)
    }

    func test_nil_since_returns_everything() throws {
        let nb = try notebooks.create(title: "A", coverColor: "#123456")
        _ = try pages.append(notebookId: nb.id, template: .line)
        _ = try pages.append(notebookId: nb.id, template: .grid)
        let diff = try SyncDiff.compute(writer: db.writer, since: nil)
        XCTAssertEqual(diff.notebooks.count, 1)
        XCTAssertEqual(diff.pages.count, 2)
    }

    func test_since_filters_by_updated_at() throws {
        let nb = try notebooks.create(title: "A", coverColor: "#000000")
        let p1 = try pages.append(notebookId: nb.id, template: .line)
        Thread.sleep(forTimeInterval: 0.1)
        let cutoff = Date()
        Thread.sleep(forTimeInterval: 0.1)
        try pages.updateDrawing(pageId: p1.id, drawing: Data([0x01]), thumbnail: nil)
        let diff = try SyncDiff.compute(writer: db.writer, since: cutoff)
        XCTAssertEqual(diff.pages.map(\.id), [p1.id])
    }
}
