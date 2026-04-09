import SwiftUI
import PencilKit

/// SwiftUI wrapper for the PencilKit drawing canvas.
///
/// Architecture:
///   PKCanvasView  (root UIScrollView — owns zoom/scroll, PK re-renders strokes natively → sharp ink)
///     └── UIImageView (template, tag 100 — manually resized on zoom via KVO)
///
/// Why not an outer UIScrollView:
///   UIScrollView zoom applies a GPU transform to the zoomed view's rendered bitmap.
///   PencilKit only re-renders strokes when PKCanvasView.zoomScale changes.
///   Wrapping PKCanvasView in another scroll view bypasses PK's render pipeline → blurry ink.
///
/// Template sharpness:
///   KVO on zoomScale resizes the UIImageView frame immediately (cheap).
///   A 0.15s debounced timer re-renders the template image at the new pixel size (sharp).
struct CanvasView: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    let allowsFingerDrawing: Bool
    let template: PageTemplateKind
    let pageSize: CGSize
    let isDark: Bool

    private static let bgTag = 100

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawing = drawing
        canvas.delegate = context.coordinator
        // Gray outside the page area — visible when page is smaller than viewport.
        canvas.backgroundColor = UIColor.secondarySystemBackground
        canvas.isOpaque = true
        canvas.drawingPolicy = allowsFingerDrawing ? .anyInput : .pencilOnly
        canvas.alwaysBounceVertical = false
        canvas.contentSize = pageSize

        // Template background at z=0. Frame is kept in sync with zoom via KVO below.
        let bgView = UIImageView(
            image: PageTemplate.render(kind: template, size: pageSize, isDark: isDark)
        )
        bgView.frame = CGRect(origin: .zero, size: pageSize)
        bgView.tag = Self.bgTag
        canvas.insertSubview(bgView, at: 0)

        context.coordinator.bgView = bgView

        // Observe PKCanvasView's zoom so we can resize and re-render the template.
        canvas.addObserver(
            context.coordinator,
            forKeyPath: #keyPath(UIScrollView.zoomScale),
            options: [.new],
            context: nil
        )
        context.coordinator.observedCanvas = canvas

        DispatchQueue.main.async {
            guard canvas.bounds.width > 0 else { return }
            // Fit entire page on first appear; use as minimum to prevent black gaps.
            let fitZoom = min(
                canvas.bounds.width  / pageSize.width,
                canvas.bounds.height / pageSize.height
            )
            canvas.minimumZoomScale = fitZoom
            canvas.maximumZoomScale = 5.0
            canvas.setZoomScale(fitZoom, animated: false)
            context.coordinator.centerPage(in: canvas)

            if let window = canvas.window,
               let picker = PKToolPicker.shared(for: window) {
                picker.setVisible(true, forFirstResponder: canvas)
                picker.addObserver(canvas)
                canvas.becomeFirstResponder()
            }
        }
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        if canvas.drawing != drawing {
            canvas.drawing = drawing
        }
        canvas.drawingPolicy = allowsFingerDrawing ? .anyInput : .pencilOnly

        // Re-render template when dark mode or template type changes.
        let zoom = canvas.zoomScale > 0 ? canvas.zoomScale : 1
        let currentSize = CGSize(width: pageSize.width * zoom, height: pageSize.height * zoom)
        if let bgView = canvas.viewWithTag(Self.bgTag) as? UIImageView {
            bgView.image = PageTemplate.render(kind: template, size: currentSize, isDark: isDark)
            bgView.frame = CGRect(origin: .zero, size: currentSize)
        }
    }

    static func dismantleUIView(_ uiView: PKCanvasView, coordinator: Coordinator) {
        coordinator.stopObserving()
        coordinator.rerenderTimer?.invalidate()
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: CanvasView
        weak var bgView: UIImageView?
        weak var observedCanvas: PKCanvasView?
        var rerenderTimer: Timer?

        init(_ parent: CanvasView) { self.parent = parent }

        func stopObserving() {
            guard let canvas = observedCanvas else { return }
            canvas.removeObserver(self, forKeyPath: #keyPath(UIScrollView.zoomScale))
            observedCanvas = nil
        }

        // MARK: PKCanvasViewDelegate

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            parent.drawing = canvasView.drawing
        }

        // MARK: KVO — zoomScale

        override func observeValue(
            forKeyPath keyPath: String?,
            of object: Any?,
            change: [NSKeyValueChangeKey: Any]?,
            context: UnsafeMutableRawPointer?
        ) {
            guard keyPath == #keyPath(UIScrollView.zoomScale),
                  let zoom = change?[.newKey] as? CGFloat,
                  zoom > 0 else { return }

            let newSize = CGSize(
                width:  parent.pageSize.width  * zoom,
                height: parent.pageSize.height * zoom
            )

            // Resize frame immediately — cheap, keeps template visually in sync.
            bgView?.frame = CGRect(origin: .zero, size: newSize)

            // Ensure PKCanvasView can scroll to the full page at this zoom.
            if let canvas = object as? PKCanvasView,
               canvas.contentSize.width < newSize.width || canvas.contentSize.height < newSize.height {
                canvas.contentSize = newSize
            }

            // Debounce re-render: wait until zoom gesture settles, then redraw at
            // the actual pixel size so the template is always crisp after zooming.
            rerenderTimer?.invalidate()
            rerenderTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak self] _ in
                guard let self else { return }
                self.bgView?.image = PageTemplate.render(
                    kind: self.parent.template,
                    size: newSize,
                    isDark: self.parent.isDark
                )
                if let canvas = self.observedCanvas {
                    self.centerPage(in: canvas)
                }
            }
        }

        // MARK: Centering

        /// Pads contentInset so the page stays centered when smaller than the viewport.
        func centerPage(in canvas: PKCanvasView) {
            let zoom   = canvas.zoomScale > 0 ? canvas.zoomScale : 1
            let scaled = CGSize(
                width:  parent.pageSize.width  * zoom,
                height: parent.pageSize.height * zoom
            )
            let insetX = max(0, (canvas.bounds.width  - scaled.width)  / 2)
            let insetY = max(0, (canvas.bounds.height - scaled.height) / 2)
            canvas.contentInset = UIEdgeInsets(
                top: insetY, left: insetX, bottom: insetY, right: insetX
            )
        }
    }
}
