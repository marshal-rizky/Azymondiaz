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
/// AI selection mode:
///   PKCanvasView.drawingGestureRecognizer handles finger input only (not pencil). Since
///   drawingPolicy = .pencilOnly, pencil lasso is handled by PencilKit's private internal
///   recognizer — we cannot hook into it. Instead, when aiSelectionMode = true, scroll is
///   disabled and a finger pan gesture draws a selection rectangle. On lift, the rect in
///   drawing coordinates is reported via onAIRegionSelected and aiSelectionMode resets to false.
struct CanvasView: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    let allowsFingerDrawing: Bool
    let template: PageTemplateKind
    let pageSize: CGSize
    let isDark: Bool
    /// When true the canvas enters AI-region-selection mode: scroll is disabled, and a
    /// single-finger pan draws a selection rectangle. Resets to false after the gesture ends.
    @Binding var aiSelectionMode: Bool
    /// Called when the AI-region gesture completes. `nil` means no valid rectangle was drawn
    /// (caller should fall back to full-page context).
    var onAIRegionSelected: ((CGRect?) -> Void)? = nil
    /// The active drawing tool. Driven by the action bar. Setting this replaces PKToolPicker.
    var activeTool: PKTool = PKInkingTool(.pen, color: .black, width: 2)
    /// Bound to the PKCanvasView's undoManager so the parent can call undo/redo.
    @Binding var undoManager: UndoManager?
    /// Floating image objects to overlay on the canvas.
    var mediaItems: [PageMediaItem] = []
    /// Called when the user moves/resizes an image. Caller saves to DB.
    var onMediaUpdated: ((PageMediaItem) -> Void)? = nil
    /// Called when the user double-taps an image to delete it.
    var onMediaDeleted: ((String) -> Void)? = nil

    private static let bgTag = 100

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawing = drawing
        canvas.delegate = context.coordinator
        // Transparent canvas so the SwiftUI .background() shows through as the
        // gray "outside page" area.
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

        // Observe contentSize — PK updates this on every zoom tick.
        canvas.addObserver(
            context.coordinator,
            forKeyPath: #keyPath(UIScrollView.contentSize),
            options: [.new],
            context: nil
        )
        context.coordinator.observedCanvas = canvas

        DispatchQueue.main.async {
            guard canvas.bounds.width > 0 else { return }

            let fitZoom = min(
                canvas.bounds.width  / pageSize.width,
                canvas.bounds.height / pageSize.height
            )
            canvas.minimumZoomScale = fitZoom
            canvas.maximumZoomScale = 5.0
            canvas.setZoomScale(fitZoom, animated: false)

            context.coordinator.centerPage(in: canvas)
            canvas.contentOffset = CGPoint(
                x: -canvas.contentInset.left,
                y: -canvas.contentInset.top
            )

            canvas.tool = activeTool
            self.undoManager = canvas.undoManager
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

        // Handle AI selection mode transitions.
        if aiSelectionMode != coord.isInAISelectionMode {
            if aiSelectionMode {
                coord.enterAISelectionMode(in: canvas)
            } else {
                coord.exitAISelectionMode(in: canvas)
            }
        }

        // Sync active tool from action bar binding
        canvas.tool = activeTool

        // Keep coordinator's parent current so KVO callbacks use latest values.
        coord.parent = self

        context.coordinator.syncMediaImageViews(
            in: canvas,
            mediaItems: mediaItems,
            pageSize: pageSize,
            parent: self
        )
    }

    static func dismantleUIView(_ uiView: PKCanvasView, coordinator: Coordinator) {
        if coordinator.isInAISelectionMode {
            coordinator.exitAISelectionMode(in: uiView)
        }
        coordinator.stopObserving()
        coordinator.rerenderTimer?.invalidate()
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: CanvasView
        weak var bgView: UIImageView?
        weak var observedCanvas: PKCanvasView?
        var rerenderTimer: Timer?
        // Map from PageMediaItem.id → UIImageView for gesture handling
        var mediaImageViews: [String: UIImageView] = [:]
        // Track which media item each gesture is acting on
        var gestureMediaID: [UIGestureRecognizer: String] = [:]
        private var isScratchErasing = false
        private let scratchFeedback = UIImpactFeedbackGenerator(style: .light)

        // AI selection mode state
        var isInAISelectionMode = false
        private var aiPanGesture: UIPanGestureRecognizer?
        private var aiHighlightView: UIView?
        private var aiStartPoint: CGPoint?

        init(_ parent: CanvasView) { self.parent = parent }

        // MARK: - AI Selection Mode

        /// Enter selection mode: disables UIScrollView panning so finger drag draws a rectangle.
        func enterAISelectionMode(in canvas: PKCanvasView) {
            guard !isInAISelectionMode else { return }
            isInAISelectionMode = true
            // Disable built-in scroll so our single-finger pan doesn't conflict.
            canvas.panGestureRecognizer.isEnabled = false

            let pan = UIPanGestureRecognizer(target: self, action: #selector(handleAIRegionPan(_:)))
            // Finger (direct) touches only — pencil continues to draw normally.
            pan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
            pan.minimumNumberOfTouches = 1
            pan.maximumNumberOfTouches = 1
            canvas.addGestureRecognizer(pan)
            aiPanGesture = pan
        }

        /// Exit selection mode: re-enables scroll and removes the pan gesture.
        func exitAISelectionMode(in canvas: PKCanvasView) {
            guard isInAISelectionMode else { return }
            isInAISelectionMode = false
            canvas.panGestureRecognizer.isEnabled = true
            if let pan = aiPanGesture {
                canvas.removeGestureRecognizer(pan)
                aiPanGesture = nil
            }
            aiHighlightView?.removeFromSuperview()
            aiHighlightView = nil
            aiStartPoint = nil
        }

        @objc func handleAIRegionPan(_ sender: UIPanGestureRecognizer) {
            guard let canvas = observedCanvas else { return }
            let pt = sender.location(in: canvas)

            switch sender.state {
            case .began:
                aiStartPoint = pt
                let view = UIView()
                view.backgroundColor = UIColor(AppColors.gold).withAlphaComponent(0.08)
                view.layer.borderColor = UIColor(AppColors.gold).cgColor
                view.layer.borderWidth = 2
                view.layer.cornerRadius = 4
                view.frame = CGRect(origin: pt, size: .zero)
                view.isUserInteractionEnabled = false
                canvas.addSubview(view)
                aiHighlightView = view

            case .changed:
                guard let start = aiStartPoint else { return }
                aiHighlightView?.frame = CGRect(
                    x: min(start.x, pt.x),
                    y: min(start.y, pt.y),
                    width: abs(pt.x - start.x),
                    height: abs(pt.y - start.y)
                )

            case .ended:
                let region = finishAIRegion(at: pt, canvas: canvas)
                parent.onAIRegionSelected?(region)
                parent.aiSelectionMode = false

            case .cancelled:
                aiHighlightView?.removeFromSuperview()
                aiHighlightView = nil
                aiStartPoint = nil
                parent.onAIRegionSelected?(nil)
                parent.aiSelectionMode = false

            default:
                break
            }
        }

        private func finishAIRegion(at pt: CGPoint, canvas: PKCanvasView) -> CGRect? {
            defer {
                aiHighlightView?.removeFromSuperview()
                aiHighlightView = nil
                aiStartPoint = nil
            }
            guard let start = aiStartPoint else { return nil }
            let viewRect = CGRect(
                x: min(start.x, pt.x),
                y: min(start.y, pt.y),
                width: abs(pt.x - start.x),
                height: abs(pt.y - start.y)
            )
            guard viewRect.width > 5, viewRect.height > 5 else { return nil }

            // Convert to drawing coordinate space.
            // sender.location(in: canvas) returns bounds-coordinate values.
            // UIScrollView sets bounds.origin = contentOffset, so contentOffset is
            // already embedded in every point from location(in: canvas). Do NOT add
            // it again — that would double-count and shift the rect into empty space.
            // Dividing by zoomScale converts content coords → PKDrawing coords.
            let z = canvas.zoomScale > 0 ? canvas.zoomScale : 1
            return CGRect(
                x: viewRect.minX / z,
                y: viewRect.minY / z,
                width: viewRect.width / z,
                height: viewRect.height / z
            )
        }

        func stopObserving() {
            guard let canvas = observedCanvas else { return }
            canvas.removeObserver(self, forKeyPath: #keyPath(UIScrollView.contentSize))
            observedCanvas = nil
        }

        // MARK: PKCanvasViewDelegate

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !isScratchErasing else { return }
            let drawing = canvasView.drawing
            if let lastStroke = drawing.strokes.last,
               ScratchOutDetector.isScribble(stroke: lastStroke) {
                isScratchErasing = true
                defer { isScratchErasing = false }
                let eraseBounds = lastStroke.renderBounds.insetBy(dx: -8, dy: -8)
                // Explicitly drop the scratch stroke, then filter remaining by bounds.
                var newDrawing = drawing
                let remaining = drawing.strokes.dropLast()
                newDrawing.strokes = remaining.filter {
                    !$0.renderBounds.intersects(eraseBounds)
                }
                canvasView.drawing = newDrawing
                parent.drawing = newDrawing
                scratchFeedback.impactOccurred()
                return
            }
            parent.drawing = drawing
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

            bgView?.frame = CGRect(origin: .zero, size: newSize)

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

        // MARK: - Media image views

        func syncMediaImageViews(
            in canvas: PKCanvasView,
            mediaItems: [PageMediaItem],
            pageSize: CGSize,
            parent: CanvasView
        ) {
            let currentIDs = Set(mediaItems.map(\.id))
            let existingIDs = Set(mediaImageViews.keys)

            // Remove views for deleted items
            for id in existingIDs.subtracting(currentIDs) {
                mediaImageViews[id]?.removeFromSuperview()
                mediaImageViews.removeValue(forKey: id)
            }

            // Add views for new items; update frames for existing
            for item in mediaItems {
                let frame = CGRect(
                    x: CGFloat(item.x) * pageSize.width,
                    y: CGFloat(item.y) * pageSize.height,
                    width: CGFloat(item.width) * pageSize.width,
                    height: CGFloat(item.height) * pageSize.height
                )
                if let existing = mediaImageViews[item.id] {
                    existing.frame = frame
                } else {
                    guard let image = UIImage(data: item.imageBlob) else { continue }
                    let iv = UIImageView(image: image)
                    iv.frame = frame
                    iv.contentMode = .scaleAspectFit
                    iv.isUserInteractionEnabled = true
                    iv.layer.zPosition = 1  // above template (z=0), below PK strokes

                    // Pan to move
                    let pan = UIPanGestureRecognizer(target: self, action: #selector(handleMediaPan(_:)))
                    iv.addGestureRecognizer(pan)
                    gestureMediaID[pan] = item.id

                    // Pinch to resize
                    let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handleMediaPinch(_:)))
                    iv.addGestureRecognizer(pinch)
                    gestureMediaID[pinch] = item.id

                    // Double-tap to delete
                    let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleMediaDoubleTap(_:)))
                    doubleTap.numberOfTapsRequired = 2
                    iv.addGestureRecognizer(doubleTap)
                    gestureMediaID[doubleTap] = item.id

                    canvas.insertSubview(iv, at: 1)  // after bgView (index 0)
                    mediaImageViews[item.id] = iv
                }
            }
        }

        @objc func handleMediaPan(_ sender: UIPanGestureRecognizer) {
            guard let id = gestureMediaID[sender],
                  let iv = mediaImageViews[id],
                  let canvas = observedCanvas else { return }
            let translation = sender.translation(in: canvas)
            iv.center = CGPoint(x: iv.center.x + translation.x,
                                y: iv.center.y + translation.y)
            sender.setTranslation(.zero, in: canvas)

            if sender.state == .ended {
                let newItem = updatedMediaItem(id: id, from: iv, pageSize: parent.pageSize)
                parent.onMediaUpdated?(newItem)
            }
        }

        @objc func handleMediaPinch(_ sender: UIPinchGestureRecognizer) {
            guard let id = gestureMediaID[sender],
                  let iv = mediaImageViews[id] else { return }
            iv.transform = iv.transform.scaledBy(x: sender.scale, y: sender.scale)
            sender.scale = 1.0

            if sender.state == .ended {
                // Flatten transform into frame
                let newFrame = iv.frame
                iv.transform = .identity
                iv.frame = newFrame
                let newItem = updatedMediaItem(id: id, from: iv, pageSize: parent.pageSize)
                parent.onMediaUpdated?(newItem)
            }
        }

        @objc func handleMediaDoubleTap(_ sender: UITapGestureRecognizer) {
            guard let id = gestureMediaID[sender] else { return }
            parent.onMediaDeleted?(id)
        }

        private func updatedMediaItem(id: String, from iv: UIImageView, pageSize: CGSize) -> PageMediaItem {
            var item = parent.mediaItems.first { $0.id == id }!
            item.x = Double(iv.frame.minX / pageSize.width)
            item.y = Double(iv.frame.minY / pageSize.height)
            item.width = Double(iv.frame.width / pageSize.width)
            item.height = Double(iv.frame.height / pageSize.height)
            return item
        }
    }
}
