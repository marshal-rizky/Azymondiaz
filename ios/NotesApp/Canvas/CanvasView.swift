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
///   KVO on contentSize fires every zoom tick (user pinch + programmatic) — resizes bgView immediately.
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
    /// Called when the user completes a lasso gesture. Provides the bounds of selected strokes
    /// in drawing coordinates, or nil when the selection is cleared (e.g. new stroke drawn).
    var onSelectionBoundsChanged: ((CGRect?) -> Void)? = nil

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

        // Observe contentSize — PK updates this on every zoom tick (user pinch or
        // programmatic), whereas zoomScale KVO fires only for programmatic setZoomScale.
        canvas.addObserver(
            context.coordinator,
            forKeyPath: #keyPath(UIScrollView.contentSize),
            options: [.new],
            context: nil
        )
        context.coordinator.observedCanvas = canvas
        canvas.drawingGestureRecognizer.addTarget(
            context.coordinator,
            action: #selector(Coordinator.handleLassoGesture(_:))
        )

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

        let coord = context.coordinator
        // Re-render bgView if template kind or dark mode changed.
        if template != coord.parent.template || isDark != coord.parent.isDark {
            if let bgView = canvas.viewWithTag(Self.bgTag) as? UIImageView {
                bgView.image = PageTemplate.render(kind: template, size: pageSize, isDark: isDark)
            }
        }
        // Keep coordinator's parent current so KVO callbacks use latest values.
        coord.parent = self
    }

    static func dismantleUIView(_ uiView: PKCanvasView, coordinator: Coordinator) {
        coordinator.stopObserving()
        coordinator.rerenderTimer?.invalidate()
        uiView.drawingGestureRecognizer.removeTarget(coordinator, action: nil)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: CanvasView
        weak var bgView: UIImageView?
        weak var observedCanvas: PKCanvasView?
        var rerenderTimer: Timer?

        /// Accumulated view-space bounding rect while user draws a lasso gesture.
        private var lassoRawViewBounds: CGRect? = nil

        init(_ parent: CanvasView) { self.parent = parent }

        /// Tracks the lasso gesture and, on completion, fires onSelectionBoundsChanged with
        /// the bounding rect of the strokes enclosed by the lasso (drawing coordinates).
        @objc func handleLassoGesture(_ sender: UIGestureRecognizer) {
            guard let canvas = observedCanvas else { return }
            guard canvas.tool is PKLassoTool else {
                // Non-lasso tool gesture — ignore (selection already cleared in drawing-change callback)
                return
            }
            let pt = sender.location(in: canvas)
            switch sender.state {
            case .began:
                lassoRawViewBounds = CGRect(origin: pt, size: .zero)
            case .changed:
                if var b = lassoRawViewBounds {
                    b = b.union(CGRect(origin: pt, size: .zero))
                    lassoRawViewBounds = b
                }
            case .ended, .cancelled:
                defer { lassoRawViewBounds = nil }
                guard let viewBounds = lassoRawViewBounds,
                      viewBounds.width > 5 || viewBounds.height > 5 else { return }

                // Convert view-space bounds → drawing coordinate space
                let z = canvas.zoomScale > 0 ? canvas.zoomScale : 1
                let contentBounds = CGRect(
                    x: (viewBounds.minX + canvas.contentOffset.x) / z,
                    y: (viewBounds.minY + canvas.contentOffset.y) / z,
                    width: viewBounds.width / z,
                    height: viewBounds.height / z
                )

                // Refine: union the renderBounds of strokes that fall inside the lasso area
                let enclosed = canvas.drawing.strokes.filter { $0.renderBounds.intersects(contentBounds) }
                let selectionBounds: CGRect
                if !enclosed.isEmpty {
                    selectionBounds = enclosed
                        .reduce(CGRect.null) { $0.union($1.renderBounds) }
                        .insetBy(dx: -15, dy: -15)
                } else {
                    selectionBounds = contentBounds
                }
                parent.onSelectionBoundsChanged?(selectionBounds)
            default:
                break
            }
        }

        func stopObserving() {
            guard let canvas = observedCanvas else { return }
            canvas.removeObserver(self, forKeyPath: #keyPath(UIScrollView.contentSize))
            observedCanvas = nil
        }

        // MARK: PKCanvasViewDelegate

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            parent.drawing = canvasView.drawing
            // Clear stored lasso selection whenever the drawing changes: the selection
            // bounds are now stale (content moved or new ink was added).
            parent.onSelectionBoundsChanged?(nil)
        }

        // MARK: KVO — contentSize

        override func observeValue(
            forKeyPath keyPath: String?,
            of object: Any?,
            change: [NSKeyValueChangeKey: Any]?,
            context: UnsafeMutableRawPointer?
        ) {
            guard keyPath == #keyPath(UIScrollView.contentSize),
                  let newSize = change?[.newKey] as? CGSize,
                  newSize.width > 1, newSize.height > 1,
                  let canvas = object as? PKCanvasView else { return }

            // PK sets contentSize on every zoom tick (user pinch fires this each frame).
            // Resize bgView immediately so the template tracks the ink at all times.
            bgView?.frame = CGRect(origin: .zero, size: newSize)

            // After zoom settles: re-render template at true pixel size (crisp)
            // AND re-apply centering insets safely outside the active gesture.
            // contentInset is intentionally NOT set here — changing it mid-pinch
            // causes UIScrollView to re-clamp contentOffset, making the page slide.
            rerenderTimer?.invalidate()
            rerenderTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { [weak self, weak canvas] _ in
                guard let self, let canvas else { return }
                self.bgView?.image = PageTemplate.render(
                    kind: self.parent.template,
                    size: self.parent.pageSize,
                    isDark: self.parent.isDark
                )
                self.centerPage(in: canvas)
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
