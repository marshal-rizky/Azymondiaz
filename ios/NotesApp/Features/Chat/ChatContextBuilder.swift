import UIKit
import PencilKit

enum ChatScope: String { case page, notebook }

enum ChatContextBuilder {
    static func makeContextImageBase64(
        scope: ChatScope,
        currentPage: Page,
        notebookPages: [Page],
        pageSize: CGSize
    ) -> String? {
        let pages: [Page] = scope == .page ? [currentPage] : notebookPages
        guard !pages.isEmpty else { return nil }

        // Stack pages vertically at half resolution to keep payload small.
        let scale: CGFloat = 0.5
        let singleSize = CGSize(width: pageSize.width * scale, height: pageSize.height * scale)
        let totalSize = CGSize(
            width: singleSize.width,
            height: singleSize.height * CGFloat(pages.count)
        )
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: totalSize, format: format)
        let image = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: totalSize))
            for (idx, page) in pages.enumerated() {
                let origin = CGPoint(x: 0, y: CGFloat(idx) * singleSize.height)
                let rect = CGRect(origin: origin, size: singleSize)
                // Background template
                let bg = PageTemplate.render(kind: page.template, size: singleSize, isDark: false)
                bg.draw(in: rect)
                // Ink
                if let blob = page.drawingBlob,
                   let drawing = try? PKDrawing(data: blob),
                   !drawing.bounds.isEmpty {
                    let inkImg = drawing.image(
                        from: CGRect(origin: .zero, size: pageSize),
                        scale: scale
                    )
                    inkImg.draw(in: rect)
                }
            }
        }
        return image.jpegData(compressionQuality: 0.7)?.base64EncodedString()
    }
}
