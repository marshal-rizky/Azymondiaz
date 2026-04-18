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
            case .cornell:
                // Proportions for 1024×1366 page; scale for any size.
                let titleH: CGFloat   = 64 * (size.height / 1366)
                let summaryH: CGFloat = 120 * (size.height / 1366)
                let cueW: CGFloat     = 220 * (size.width / 1024)

                // Gold-tinted dividers at 15% opacity (light) / 25% (dark).
                let alpha: CGFloat = isDark ? 0.25 : 0.15
                let divColor = UIColor(red: 0.788, green: 0.659, blue: 0.298, alpha: alpha)
                cg.setStrokeColor(divColor.cgColor)
                cg.setLineWidth(1.5)

                // Title bottom border
                cg.move(to: CGPoint(x: 0, y: titleH))
                cg.addLine(to: CGPoint(x: size.width, y: titleH))

                // Summary top border
                let summaryY = size.height - summaryH
                cg.move(to: CGPoint(x: 0, y: summaryY))
                cg.addLine(to: CGPoint(x: size.width, y: summaryY))

                // Cue column right border (from title to summary)
                cg.move(to: CGPoint(x: cueW, y: titleH))
                cg.addLine(to: CGPoint(x: cueW, y: summaryY))

                cg.strokePath()

                // Ruled lines in notes area (right of cue column)
                cg.setStrokeColor(guide.cgColor)
                cg.setLineWidth(1.0)
                var ry = titleH + lineSpacing
                while ry < summaryY {
                    cg.move(to: CGPoint(x: cueW + 8, y: ry))
                    cg.addLine(to: CGPoint(x: size.width - 8, y: ry))
                    ry += lineSpacing
                }

                // Ruled lines in cue column
                var cy = titleH + lineSpacing
                while cy < summaryY {
                    cg.move(to: CGPoint(x: 8, y: cy))
                    cg.addLine(to: CGPoint(x: cueW - 8, y: cy))
                    cy += lineSpacing
                }
                cg.strokePath()
            }
        }
    }
}
