import XCTest
import PencilKit
@testable import NotesApp

final class ScratchOutDetectorTests: XCTestCase {

    func test_straight_line_not_scribble() {
        // A single left-to-right sweep — no reversals
        let points = stride(from: CGFloat(0), to: 200, by: 10).map {
            CGPoint(x: $0, y: 50)
        }
        XCTAssertFalse(ScratchOutDetector.isScribble(points: Array(points), duration: 0.5))
    }

    func test_back_and_forth_is_scribble() {
        // Four passes: right, left, right, left — 3 reversals ≥ threshold
        var points: [CGPoint] = []
        for x in stride(from: CGFloat(0), to: 120, by: 10) { points.append(CGPoint(x: x, y: 50)) }
        for x in stride(from: CGFloat(120), to: 0, by: -10) { points.append(CGPoint(x: x, y: 55)) }
        for x in stride(from: CGFloat(0), to: 120, by: 10) { points.append(CGPoint(x: x, y: 52)) }
        for x in stride(from: CGFloat(120), to: 0, by: -10) { points.append(CGPoint(x: x, y: 53)) }
        XCTAssertTrue(ScratchOutDetector.isScribble(points: points, duration: 0.8))
    }

    func test_too_short_horizontal_not_scribble() {
        // Only 40pt horizontal travel — below 80pt minimum
        var points: [CGPoint] = []
        for x in stride(from: CGFloat(0), to: 40, by: 5) { points.append(CGPoint(x: x, y: 50)) }
        for x in stride(from: CGFloat(40), to: 0, by: -5) { points.append(CGPoint(x: x, y: 52)) }
        for x in stride(from: CGFloat(0), to: 40, by: 5) { points.append(CGPoint(x: x, y: 51)) }
        XCTAssertFalse(ScratchOutDetector.isScribble(points: points, duration: 0.5))
    }

    func test_too_tall_vertical_not_scribble() {
        // 120pt vertical extent — above 80pt limit
        var points: [CGPoint] = []
        for i in 0..<20 {
            let x = CGFloat(i % 2 == 0 ? i * 6 : (20 - i) * 6)
            points.append(CGPoint(x: x, y: CGFloat(i * 7)))
        }
        XCTAssertFalse(ScratchOutDetector.isScribble(points: points, duration: 0.5))
    }

    func test_too_slow_not_scribble() {
        // Valid shape but duration > 1.2s
        var points: [CGPoint] = []
        for x in stride(from: CGFloat(0), to: 120, by: 10) { points.append(CGPoint(x: x, y: 50)) }
        for x in stride(from: CGFloat(120), to: 0, by: -10) { points.append(CGPoint(x: x, y: 52)) }
        for x in stride(from: CGFloat(0), to: 120, by: 10) { points.append(CGPoint(x: x, y: 51)) }
        XCTAssertFalse(ScratchOutDetector.isScribble(points: points, duration: 1.5))
    }
}
