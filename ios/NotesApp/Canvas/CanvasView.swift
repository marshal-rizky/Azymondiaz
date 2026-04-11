import SwiftUI
import PencilKit

/// SwiftUI wrapper for the PencilKit drawing canvas.
///
/// Architecture:
///   PKCanvasView  (root UIScrollView — owns zoom/scroll, PK re-renders strokes natively → sharp ink)
///     └── UIImageView (template, tag 100 — manually resized on zoom via KVO)
///
/// Why not an outer UIScrollView:
///   UIScrollView zoom applies a GPU transform to the container bitmap.
///   PencilKit only re-renders strokes when PKCanvasView.zoomScale changes directly.
///   Wrapping PKCanvasView in another scroll view → blurry ink at any zoom > 1x.
///
/// Template sharpness:
///   KVO on zoomScale resizes the UIImageView frame immediately (cheap).
///   A 0.15s debounced timer re-renders the template image at the new pixel size (sharp).
///
/// Initial positioning fix:
///   After setZoomScale + centerPage, contentOffset is explicitly set so the page
///   appears centered rather than off-screen.
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
        // Transparent canvas so the SwiftUI .background() shows through as the
        // gray "outside page" area. Setting opaque=true here blocks the bgView.
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawingPolicy = allowsFingerDrawing ? .anyInput : .pencilOnly
        canvas.alwaysBounceVertical = false
        canvas.contentSize = pageSize

        // Template background at z=0. Frame kept in sync with zoom via KVO.
        let bgView = UIImageView(
            image: PageTemplate.render(kind: template, size: pageSize, isDark: isDark)
        )
        bgView.frame = CGRect(origin: .zero, size: pageSize)
        bgView.tag = Self.bgTag
        canvas.insertSubview(bgView, at: 0)

        context.coordinator.bgView = bgView

        // Observe PKCanvasView's zoom to resize template and re-center.
        canvas.addObserver(
            context.coordinator,
            forKeyPath: #keyPath(UIScrollView.zoomScale),
            options: [.new],
            context: nil
        )
        context.coordinator.observedCanvas = canvas

        DispatchQueue.main.async {
            guard canvas.bounds.width > 0 else { return }

            // Fit the entire page on first appear; use as minimum so the user
            // cannot zoom out past the page boundary.
            let fitZoom = min(
                canvas.bounds.width  / pageSize.width,
                canvas.bounds.height / pageSize.height
            )
            canvas.minimumZoomScale = fitZoom
            canvas.maximumZoomScale = 5.0
            canvas.setZoomScale(fitZoom, animated: false)

            // Set contentInset for centering, then explicitly position the
            // viewport to show the page. Without the contentOffset reset,
            // setZoomScale leaves contentOffset in an undefined state and the
            // page appears off-screen.
            context.coordinator.centerPage(in: canvas)
            canvas.contentOffset = CGPoint(
                x: -canvas.contentInset.left,
                y: -canvas.contentInset.top
            )

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
        // Template re-render is handled by the KVO observer (debounced) and makeUIView.
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

            // Always keep contentSize equal to the current visual page size so
            // the scrollable extent matches what the user can actually see.
            // (The original conditional only grew contentSize, leaving empty
            // scroll space when zooming out and showing the background color.)
            if let canvas = object as? PKCanvasView {
                canvas.contentSize = newSize
                // Update centering insets in real time so the page stays
                // centered while the pinch gesture is still in progress.
                let insetX = max(0, (canvas.bounds.width  - newSize.width)  / 2)
                let insetY = max(0, (canvas.bounds.height - newSize.height) / 2)
                canvas.contentInset = UIEdgeInsets(
                    top: insetY, left: insetX, bottom: insetY, right: insetX
                )
            }

            // Debounce re-render: wait until zoom gesture settles, then redraw
            // at the actual pixel size so the template is always crisp.
            rerenderTimer?.invalidate()
            rerenderTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak self] _ in
                guard let self else { return }
                self.bgView?.image = PageTemplate.render(
                    kind: self.parent.template,
                    size: newSize,
                    isDark: self.parent.isDark
                )
            }
        }

        // MARK: Centering

        /// Sets contentInset so the page is centered when smaller than the viewport.
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
