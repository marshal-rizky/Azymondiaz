import CoreGraphics
import PencilKit

enum ScratchOutDetector {
    /// Criteria (all must pass):
    ///   - ≥ 2 X-axis direction reversals
    ///   - Vertical extent of all points < 80pt
    ///   - Total horizontal travel ≥ 80pt
    ///   - Duration < 1.2 seconds
    static func isScribble(points: [CGPoint], duration: TimeInterval) -> Bool {
        guard points.count >= 4, duration < 1.2 else { return false }

        // Vertical extent check
        let minY = points.map(\.y).min()!
        let maxY = points.map(\.y).max()!
        guard (maxY - minY) < 80 else { return false }

        // Total horizontal travel
        var totalTravel: CGFloat = 0
        for i in 1..<points.count {
            totalTravel += abs(points[i].x - points[i - 1].x)
        }
        guard totalTravel >= 80 else { return false }

        // Direction reversals on X axis
        var reversals = 0
        var lastDx: CGFloat = 0
        for i in 1..<points.count {
            let dx = points[i].x - points[i - 1].x
            guard abs(dx) > 2 else { continue }  // ignore micro-jitter
            if lastDx != 0 && (dx > 0) != (lastDx > 0) {
                reversals += 1
            }
            lastDx = dx
        }
        return reversals >= 2
    }

    /// Convenience wrapper for a real PKStroke.
    static func isScribble(stroke: PKStroke) -> Bool {
        guard stroke.path.count >= 4 else { return false }
        let points = (0..<stroke.path.count).map { stroke.path[$0].location }
        let duration = stroke.path[stroke.path.count - 1].timeOffset
                     - stroke.path[0].timeOffset
        return isScribble(points: points, duration: duration)
    }
}
