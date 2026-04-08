import UIKit
import PencilKit

enum ThumbnailRenderer {
    /// Renders a page (template background + ink) scaled to `thumbnailWidth`, returns PNG data.
    static func render(
        drawing: PKDrawing,
        template: PageTemplateKind,
        pageSize: CGSize,
        thumbnailWidth: CGFloat,
        isDark: Bool
    ) -> Data {
        let scale = thumbnailWidth / pageSize.width
        let targetSize = CGSize(
            width: thumbnailWidth,
            height: (pageSize.height * scale).rounded()
        )

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let image = renderer.image { ctx in
            // 1. Background template scaled to thumb size.
            let bg = PageTemplate.render(kind: template, size: targetSize, isDark: isDark)
            bg.draw(in: CGRect(origin: .zero, size: targetSize))

            // 2. Ink rendered from drawing, scaled.
            if !drawing.bounds.isEmpty {
                let inkImage = drawing.image(
                    from: CGRect(origin: .zero, size: pageSize),
                    scale: scale
                )
                inkImage.draw(in: CGRect(origin: .zero, size: targetSize))
            }
        }
        return image.pngData() ?? Data()
    }
}
