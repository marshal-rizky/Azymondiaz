import XCTest
import GRDB
@testable import NotesApp

final class NotebookRepositoryTests: XCTestCase {
    private var db: AppDatabase!
    private var repo: NotebookRepository!

    override func setUpWithError() throws {
        db = try AppDatabase.makeInMemory()
        repo = NotebookRepository(writer: db.writer)
    }

    func test_create_then_fetchAll_returns_one_notebook() throws {
        let created = try repo.create(title: "Physics", coverColor: "#FF8800")
        let all = try repo.fetchAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.id, created.id)
        XCTAssertEqual(all.first?.title, "Physics")
    }

    func test_rename_persists() throws {
        var nb = try repo.create(title: "Old", coverColor: "#000000")
        nb.title = "New"
        try repo.update(nb)
        let reloaded = try XCTUnwrap(repo.fetch(id: nb.id))
        XCTAssertEqual(reloaded.title, "New")
    }

    func test_delete_removes_notebook() throws {
        let nb = try repo.create(title: "Temp", coverColor: "#111111")
        try repo.delete(id: nb.id)
        XCTAssertNil(try repo.fetch(id: nb.id))
        XCTAssertTrue(try repo.fetchAll().isEmpty)
    }

    func test_fetchAll_sorts_by_updated_at_desc() throws {
        let a = try repo.create(title: "A", coverColor: "#111111")
        Thread.sleep(forTimeInterval: 0.01)
        let b = try repo.create(title: "B", coverColor: "#222222")
        let all = try repo.fetchAll()
        XCTAssertEqual(all.map(\.id), [b.id, a.id])
    }
}
