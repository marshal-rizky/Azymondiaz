import XCTest
import UIKit
@testable import NotesApp

final class PageTemplateTests: XCTestCase {
    func test_blank_returns_solid_background() {
        let image = PageTemplate.render(
            kind: .blank,
            size: CGSize(width: 100, height: 100),
            isDark: false
        )
        XCTAssertEqual(image.size, CGSize(width: 100, height: 100))
    }

    func test_line_and_grid_have_different_pixels_than_blank() {
        let size = CGSize(width: 200, height: 200)
        let blank = PageTemplate.render(kind: .blank, size: size, isDark: false).pngData()
        let line  = PageTemplate.render(kind: .line,  size: size, isDark: false).pngData()
        let grid  = PageTemplate.render(kind: .grid,  size: size, isDark: false).pngData()
        XCTAssertNotEqual(blank, line)
        XCTAssertNotEqual(blank, grid)
        XCTAssertNotEqual(line, grid)
    }

    func test_dark_blank_differs_from_light_blank() {
        let size = CGSize(width: 50, height: 50)
        let light = PageTemplate.render(kind: .blank, size: size, isDark: false).pngData()
        let dark  = PageTemplate.render(kind: .blank, size: size, isDark: true).pngData()
        XCTAssertNotEqual(light, dark)
    }
}
