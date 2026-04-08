import XCTest
import PencilKit
@testable import NotesApp

final class ThumbnailRendererTests: XCTestCase {
    func test_renders_empty_drawing_to_target_size() {
        let drawing = PKDrawing()
        let png = ThumbnailRenderer.render(
            drawing: drawing,
            template: .line,
            pageSize: CGSize(width: 1024, height: 1366),
            thumbnailWidth: 160,
            isDark: false
        )
        let image = UIImage(data: png)!
        // aspect-preserved height: 1366 * (160/1024) ≈ 213
        XCTAssertEqual(image.size.width, 160, accuracy: 1)
        XCTAssertEqual(image.size.height, 213, accuracy: 2)
    }

    func test_output_is_nonempty_png() {
        let png = ThumbnailRenderer.render(
            drawing: PKDrawing(),
            template: .blank,
            pageSize: CGSize(width: 500, height: 700),
            thumbnailWidth: 100,
            isDark: false
        )
        XCTAssertGreaterThan(png.count, 0)
        // PNG magic: 0x89 'P' 'N' 'G'
        XCTAssertEqual(png.prefix(4), Data([0x89, 0x50, 0x4E, 0x47]))
    }
}
