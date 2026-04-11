import XCTest
@testable import NotesApp

final class AIMessageRepositoryTests: XCTestCase {
    private var db: AppDatabase!
    private var notebooks: NotebookRepository!
    private var pages: PageRepository!
    private var messages: AIMessageRepository!
    private var pageId: String!

    override func setUpWithError() throws {
        db = try AppDatabase.makeInMemory()
        notebooks = NotebookRepository(writer: db.writer)
        pages = PageRepository(writer: db.writer)
        messages = AIMessageRepository(writer: db.writer)
        let nb = try notebooks.create(title: "NB", coverColor: "#111111")
        pageId = try pages.append(notebookId: nb.id, template: .line).id
    }

    func test_append_and_fetch_for_page_in_chronological_order() throws {
        _ = try messages.append(pageId: pageId, role: .user, text: "hi")
        _ = try messages.append(pageId: pageId, role: .assistant, text: "hello")
        _ = try messages.append(pageId: pageId, role: .user, text: "thanks")
        let all = try messages.fetchAll(pageId: pageId)
        XCTAssertEqual(all.map(\.text), ["hi", "hello", "thanks"])
    }

    func test_messages_are_cascade_deleted_with_page() throws {
        _ = try messages.append(pageId: pageId, role: .user, text: "hi")
        try pages.delete(id: pageId)
        XCTAssertTrue(try messages.fetchAll(pageId: pageId).isEmpty)
    }
}
