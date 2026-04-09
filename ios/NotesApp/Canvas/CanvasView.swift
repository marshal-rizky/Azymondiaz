import SwiftUI
import PencilKit

/// SwiftUI host for a single `PKCanvasView`.
/// The template background is a UIImageView inserted at z=0 inside the
/// PKCanvasView (which is itself a UIScrollView), so both ink and background
/// zoom and scroll together as a unit.
struct CanvasView: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    let allowsFingerDrawing: Bool
    let template: PageTemplateKind
    let pageSize: CGSize
    let isDark: Bool

    private static let backgroundTag = 999

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawing = drawing
        canvas.delegate = context.coordinator
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawingPolicy = allowsFingerDrawing ? .anyInput : .pencilOnly
        canvas.minimumZoomScale = 0.25
        canvas.maximumZoomScale = 5.0
        canvas.alwaysBounceVertical = false
        canvas.contentSize = pageSize

        // Template background lives inside the scroll view so it zooms with ink.
        let bgView = UIImageView(
            image: PageTemplate.render(kind: template, size: pageSize, isDark: isDark)
        )
        bgView.frame = CGRect(origin: .zero, size: pageSize)
        bgView.tag = Self.backgroundTag
        canvas.insertSubview(bgView, at: 0)

        DispatchQueue.main.async {
            // Fit page width to the available screen width on first appear.
            if canvas.bounds.width > 0 {
                let fitZoom = canvas.bounds.width / pageSize.width
                canvas.setZoomScale(fitZoom, animated: false)
                canvas.contentOffset = .zero
            }

            if let window = canvas.window,
               let picker = PKToolPicker.shared(for: window) {
                picker.setVisible(true, forFirstResponder: canvas)
                picker.addObserver(canvas)
                canvas.becomeFirstResponder()
            }
        }
        return canvas
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        if uiView.drawing != drawing {
            uiView.drawing = drawing
        }
        uiView.drawingPolicy = allowsFingerDrawing ? .anyInput : .pencilOnly

        // Regenerate background when dark mode or template changes.
        if let bgView = uiView.viewWithTag(Self.backgroundTag) as? UIImageView {
            bgView.image = PageTemplate.render(kind: template, size: pageSize, isDark: isDark)
        }
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: CanvasView
        init(_ parent: CanvasView) { self.parent = parent }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            parent.drawing = canvasView.drawing
        }
    }
}
