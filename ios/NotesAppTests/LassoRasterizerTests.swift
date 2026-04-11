import XCTest
import PencilKit
@testable import NotesApp

final class LassoRasterizerTests: XCTestCase {
    func test_rasterize_empty_drawing_returns_empty_base64() {
        let result = LassoRasterizer.rasterize(
            selection: PKDrawing(),
            bounds: .zero
        )
        XCTAssertTrue(result.isEmpty)
    }

    func test_rasterize_nonempty_drawing_returns_png_base64() {
        let stroke = PKStroke(
            ink: PKInk(.pen, color: .black),
            path: PKStrokePath(controlPoints: [
                PKStrokePoint(location: CGPoint(x: 10, y: 10), timeOffset: 0,
                              size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: 0),
                PKStrokePoint(location: CGPoint(x: 50, y: 50), timeOffset: 0.01,
                              size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: 0)
            ], creationDate: Date())
        )
        let drawing = PKDrawing(strokes: [stroke])
        let bounds = drawing.bounds.insetBy(dx: -10, dy: -10)
        let b64 = LassoRasterizer.rasterize(selection: drawing, bounds: bounds)
        XCTAssertFalse(b64.isEmpty)
        let data = Data(base64Encoded: b64)!
        XCTAssertEqual(data.prefix(4), Data([0x89, 0x50, 0x4E, 0x47]))
    }
}
