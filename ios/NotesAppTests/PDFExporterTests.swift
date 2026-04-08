import XCTest
import PencilKit
@testable import NotesApp

final class PDFExporterTests: XCTestCase {
    func test_export_single_empty_page_produces_valid_pdf() {
        let page = RenderablePage(
            drawing: PKDrawing(),
            template: .line,
            size: CGSize(width: 612, height: 792)
        )
        let pdf = PDFExporter.export(pages: [page], isDark: false)
        XCTAssertFalse(pdf.isEmpty)
        // PDF magic: "%PDF-"
        XCTAssertEqual(pdf.prefix(5), Data("%PDF-".utf8))
    }

    func test_export_multiple_pages_is_larger_than_single() {
        let size = CGSize(width: 612, height: 792)
        let one = PDFExporter.export(
            pages: [RenderablePage(drawing: PKDrawing(), template: .blank, size: size)],
            isDark: false
        )
        let three = PDFExporter.export(
            pages: Array(repeating:
                RenderablePage(drawing: PKDrawing(), template: .blank, size: size),
                count: 3
            ),
            isDark: false
        )
        XCTAssertGreaterThan(three.count, one.count)
    }
}
