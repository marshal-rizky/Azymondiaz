import XCTest
import PencilKit
@testable import NotesApp

final class ChatContextBuilderTests: XCTestCase {
    func test_page_scope_uses_current_page_drawing() {
        let page = Page(id: "p1", notebookId: "nb", pageIndex: 0, template: .line,
                        drawingBlob: PKDrawing().dataRepresentation(),
                        thumbnailBlob: nil, createdAt: Date(), updatedAt: Date())
        let b64 = ChatContextBuilder.makeContextImageBase64(
            scope: .page,
            currentPage: page,
            notebookPages: [page],
            pageSize: CGSize(width: 400, height: 600)
        )
        XCTAssertNotNil(b64)
    }

    func test_notebook_scope_stacks_multiple_pages_vertically() {
        let blank = PKDrawing().dataRepresentation()
        let pages: [Page] = (0..<3).map { i in
            Page(id: "p\(i)", notebookId: "nb", pageIndex: i, template: .blank,
                 drawingBlob: blank, thumbnailBlob: nil,
                 createdAt: Date(), updatedAt: Date())
        }
        let single = ChatContextBuilder.makeContextImageBase64(
            scope: .page, currentPage: pages[0], notebookPages: pages,
            pageSize: CGSize(width: 200, height: 300)
        )!
        let many = ChatContextBuilder.makeContextImageBase64(
            scope: .notebook, currentPage: pages[0], notebookPages: pages,
            pageSize: CGSize(width: 200, height: 300)
        )!
        let singleBytes = Data(base64Encoded: single)!
        let manyBytes = Data(base64Encoded: many)!
        XCTAssertGreaterThan(manyBytes.count, singleBytes.count)
    }
}
