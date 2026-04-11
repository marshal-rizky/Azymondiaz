import UIKit
import PencilKit

enum LassoRasterizer {
    /// Renders the given drawing clipped to `bounds` on a transparent background
    /// and returns base64-encoded PNG. Caller passes the lasso selection bounds.
    static func rasterize(selection: PKDrawing, bounds: CGRect) -> String {
        guard !selection.bounds.isEmpty, bounds.width > 0, bounds.height > 0 else {
            return ""
        }
        // Use 2x scale so the vision model gets enough pixels for messy handwriting.
        let scale: CGFloat = 2.0
        let image = selection.image(from: bounds, scale: scale)
        // Compose on transparent canvas — selection.image already has transparent bg,
        // but rerender so the output PNG has exact `bounds` dimensions.
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: bounds.size, format: format)
        let out = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: bounds.size))
        }
        return out.pngData()?.base64EncodedString() ?? ""
    }
}
