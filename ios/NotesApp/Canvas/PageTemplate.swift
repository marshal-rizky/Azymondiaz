import UIKit

enum PageTemplate {
    /// Line spacing for ruled paper, in points.
    static let lineSpacing: CGFloat = 32
    /// Grid cell size for grid paper, in points.
    static let gridSize: CGFloat = 24

    static func render(kind: PageTemplateKind, size: CGSize, isDark: Bool) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let cg = ctx.cgContext

            // Page background.
            let bg: UIColor = isDark
                ? UIColor(white: 0.08, alpha: 1.0)
                : UIColor(white: 0.99, alpha: 1.0)
            cg.setFillColor(bg.cgColor)
            cg.fill(CGRect(origin: .zero, size: size))

            // Guide color: low-contrast so it never competes with ink.
            let guide: UIColor = isDark
                ? UIColor(white: 0.22, alpha: 1.0)
                : UIColor(white: 0.82, alpha: 1.0)
            cg.setStrokeColor(guide.cgColor)
            cg.setLineWidth(1.0)

            switch kind {
            case .blank:
                return
            case .line:
                var y: CGFloat = lineSpacing
                while y < size.height {
                    cg.move(to: CGPoint(x: 0, y: y))
                    cg.addLine(to: CGPoint(x: size.width, y: y))
                    y += lineSpacing
                }
                cg.strokePath()
            case .grid:
                var x: CGFloat = gridSize
                while x < size.width {
                    cg.move(to: CGPoint(x: x, y: 0))
                    cg.addLine(to: CGPoint(x: x, y: size.height))
                    x += gridSize
                }
                var y: CGFloat = gridSize
                while y < size.height {
                    cg.move(to: CGPoint(x: 0, y: y))
                    cg.addLine(to: CGPoint(x: size.width, y: y))
                    y += gridSize
                }
                cg.strokePath()
            }
        }
    }
}
