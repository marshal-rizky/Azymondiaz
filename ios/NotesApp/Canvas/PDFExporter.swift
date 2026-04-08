import UIKit
import PencilKit

struct RenderablePage {
    let drawing: PKDrawing
    let template: PageTemplateKind
    let size: CGSize
}

enum PDFExporter {
    /// Renders pages into a single PDF. Always exports in LIGHT theme for print readability.
    static func export(pages: [RenderablePage], isDark: Bool) -> Data {
        guard let first = pages.first else { return Data() }
        let pageRect = CGRect(origin: .zero, size: first.size)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        return renderer.pdfData { ctx in
            for page in pages {
                ctx.beginPage(withBounds: CGRect(origin: .zero, size: page.size), pageInfo: [:])
                // Background: always light for export readability.
                let bg = PageTemplate.render(kind: page.template, size: page.size, isDark: false)
                bg.draw(in: CGRect(origin: .zero, size: page.size))
                // Ink.
                if !page.drawing.bounds.isEmpty {
                    let ink = page.drawing.image(
                        from: CGRect(origin: .zero, size: page.size),
                        scale: 2.0
                    )
                    ink.draw(in: CGRect(origin: .zero, size: page.size))
                }
            }
        }
    }
}
