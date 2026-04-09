import SwiftUI
import PencilKit

/// SwiftUI wrapper for the drawing canvas.
///
/// Architecture:
///   UIScrollView  (outer — owns ALL zoom and scroll)
///     └── containerView  (returned by viewForZooming — both layers scale together)
///           ├── UIImageView  (template background)
///           └── PKCanvasView (isScrollEnabled=false — drawing only, no competing scroll)
///
/// This ensures pinch-to-zoom scales both the template and the ink as a unit.
/// The area outside the page shows the scroll view's background (system grouped).
struct CanvasView: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    let allowsFingerDrawing: Bool
    let template: PageTemplateKind
    let pageSize: CGSize
    let isDark: Bool

    private enum Tag: Int {
        case container = 300, background = 100, canvas = 200
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.minimumZoomScale = 0.25
        scrollView.maximumZoomScale = 5.0
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.backgroundColor = UIColor.systemGroupedBackground
        scrollView.delegate = context.coordinator
        scrollView.contentSize = pageSize

        // Container — this is the single view that UIScrollView zooms.
        let container = UIView(frame: CGRect(origin: .zero, size: pageSize))
        container.tag = Tag.container.rawValue

        // Template background.
        let bgView = UIImageView(
            image: PageTemplate.render(kind: template, size: pageSize, isDark: isDark)
        )
        bgView.frame = CGRect(origin: .zero, size: pageSize)
        bgView.tag = Tag.background.rawValue
        container.addSubview(bgView)

        // PencilKit canvas — drawing only, scroll disabled so the outer
        // UIScrollView handles all pan/zoom without conflict.
        let canvas = PKCanvasView(frame: CGRect(origin: .zero, size: pageSize))
        canvas.drawing = drawing
        canvas.delegate = context.coordinator
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.isScrollEnabled = false
        canvas.alwaysBounceVertical = false
        canvas.drawingPolicy = allowsFingerDrawing ? .anyInput : .pencilOnly
        canvas.tag = Tag.canvas.rawValue
        container.addSubview(canvas)

        scrollView.addSubview(container)

        // Store refs in coordinator for updateUIView.
        context.coordinator.canvas = canvas
        context.coordinator.bgView = bgView

        DispatchQueue.main.async {
            // Zoom to fit page width on first appear.
            guard scrollView.bounds.width > 0 else { return }
            let fitZoom = scrollView.bounds.width / pageSize.width
            scrollView.setZoomScale(fitZoom, animated: false)
            context.coordinator.centerContent(in: scrollView)

            // Attach tool picker.
            if let window = canvas.window,
               let picker = PKToolPicker.shared(for: window) {
                picker.setVisible(true, forFirstResponder: canvas)
                picker.addObserver(canvas)
                canvas.becomeFirstResponder()
            }
        }
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        guard let canvas = context.coordinator.canvas,
              let bgView = context.coordinator.bgView else { return }

        if canvas.drawing != drawing {
            canvas.drawing = drawing
        }
        canvas.drawingPolicy = allowsFingerDrawing ? .anyInput : .pencilOnly
        bgView.image = PageTemplate.render(kind: template, size: pageSize, isDark: isDark)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, PKCanvasViewDelegate, UIScrollViewDelegate {
        var parent: CanvasView
        weak var canvas: PKCanvasView?
        weak var bgView: UIImageView?

        init(_ parent: CanvasView) { self.parent = parent }

        // MARK: PKCanvasViewDelegate

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            parent.drawing = canvasView.drawing
        }

        // MARK: UIScrollViewDelegate

        /// Tells UIScrollView which view to scale — the container holds both
        /// template and canvas, so they zoom as a unit.
        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            scrollView.viewWithTag(Tag.container.rawValue)
        }

        /// Keep the page centered when it is smaller than the scroll view.
        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerContent(in: scrollView)
        }

        func centerContent(in scrollView: UIScrollView) {
            let offsetX = max(0, (scrollView.bounds.width  - scrollView.contentSize.width)  / 2)
            let offsetY = max(0, (scrollView.bounds.height - scrollView.contentSize.height) / 2)
            scrollView.contentInset = UIEdgeInsets(
                top: offsetY, left: offsetX, bottom: offsetY, right: offsetX
            )
        }
    }
}
