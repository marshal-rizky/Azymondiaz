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

        // Topmost transparent proxy routes finger touches to images/handles while
        // letting pencil touches fall through to PencilKit's drawing recognizer.
        // Added here (before images are inserted) so images at index 1 stay below
        // PK's rendering layer while the proxy remains at the highest index.
        let proxy = ImageInteractionProxy()
        proxy.frame = CGRect(origin: .zero, size: pageSize)
        proxy.backgroundColor = .clear
        proxy.isUserInteractionEnabled = true
        proxy.coordinator = context.coordinator
        canvas.addSubview(proxy)
        context.coordinator.imageProxy = proxy

        // Tap on empty canvas area → deselect the currently selected image.
        let bgTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleCanvasBackgroundTap(_:))
        )
        bgTap.cancelsTouchesInView = false
        canvas.addGestureRecognizer(bgTap)
        context.coordinator.canvasDeselectTap = bgTap

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

    // MARK: - MediaImageView

    /// UIImageView subclass for floating canvas images.
    /// Images are inserted at index 1 (below PencilKit's rendering layer) so ink
    /// strokes always appear on top. An ImageInteractionProxy at the top of the
    /// subview stack routes finger touches down to these views while letting
    /// pencil touches fall through to PencilKit's private drawing system.
    final class MediaImageView: UIImageView {}

    // MARK: - ImageInteractionProxy

    /// Transparent topmost subview of PKCanvasView. Routes finger touches to
    /// the MediaImageView or resize handle that lies at the touch point.
    /// Returns nil for pencil touches so PencilKit's drawing gesture recognizer
    /// (on the ancestor PKCanvasView) can claim them unobstructed.
    final class ImageInteractionProxy: UIView {
        weak var coordinator: Coordinator?

        // Must return true so hitTest is called even on a clear view.
        override func point(inside point: CGPoint, with event: UIEvent?) -> Bool { true }

        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            guard isUserInteractionEnabled, !isHidden else { return nil }
            guard let coord = coordinator else { return nil }
            // Pencil always falls through — PK's drawing recogniser on the ancestor
            // PKCanvasView handles it regardless of which subview is the hit target.
            if event?.allTouches?.contains(where: {
                $0.type == .pencil || $0.type == .stylus
            }) == true {
                return nil
            }
            // Handles have higher visual priority than images.
            for handle in coord.handleViews where handle.frame.contains(point) {
                return handle
            }
            // Route finger touch to the image view underneath.
            for (_, iv) in coord.mediaImageViews where iv.frame.contains(point) {
                return iv.hitTest(convert(point, to: iv), with: event)
            }
            return nil
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: CanvasView
        weak var bgView: UIImageView?
        weak var observedCanvas: PKCanvasView?
        weak var imageProxy: ImageInteractionProxy?
        var rerenderTimer: Timer?
        // Map from PageMediaItem.id → MediaImageView for gesture handling
        var mediaImageViews: [String: MediaImageView] = [:]
        // Track which media item each gesture is acting on
        var gestureMediaID: [UIGestureRecognizer: String] = [:]
        private var isScratchErasing = false
        private let scratchFeedback = UIImpactFeedbackGenerator(style: .light)

        // AI selection mode state
        var isInAISelectionMode = false
        private var aiPanGesture: UIPanGestureRecognizer?
        private var aiHighlightView: UIView?
        private var aiStartPoint: CGPoint?

        // Image selection + corner resize handles
        var selectedMediaID: String? = nil
        var handleViews: [UIView] = []
        var handleCorners: [UIView: String] = [:]   // handle → "tl" | "tr" | "bl" | "br"
        weak var canvasDeselectTap: UITapGestureRecognizer?
        /// Desired screen-space size for corner handles in points.
        private let handleScreenPts: CGFloat = 22

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
            if let tap = canvasDeselectTap {
                canvas.removeGestureRecognizer(tap)
            }
            removeHandles()
            imageProxy?.removeFromSuperview()
            imageProxy = nil
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

            bgView?.frame    = CGRect(origin: .zero, size: newSize)
            imageProxy?.frame = CGRect(origin: .zero, size: newSize)

            // Reposition media image views to stay at their fractional positions
            // within the scaled content area (newSize = pageSize × zoomScale).
            for (id, iv) in mediaImageViews {
                if let item = parent.mediaItems.first(where: { $0.id == id }) {
                    iv.frame = CGRect(
                        x: CGFloat(item.x) * newSize.width,
                        y: CGFloat(item.y) * newSize.height,
                        width: CGFloat(item.width) * newSize.width,
                        height: CGFloat(item.height) * newSize.height
                    )
                }
            }

            // Keep corner handles pinned to the selected image and the correct
            // screen size (handles live in content space so they'd grow with zoom
            // unless we compensate by shrinking their content-space size).
            if let selID = selectedMediaID, let selIV = mediaImageViews[selID] {
                let zoom = canvas.zoomScale > 0 ? canvas.zoomScale : 1
                selIV.layer.borderWidth = 2.0 / zoom
                updateHandlePositions(for: selIV, in: canvas)
            }

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

            // Remove views for deleted items, cleaning up gesture recognizer entries
            for id in existingIDs.subtracting(currentIDs) {
                // Clear selection state if this was the selected image
                if id == selectedMediaID {
                    removeHandles()
                    selectedMediaID = nil
                }
                if let iv = mediaImageViews[id] {
                    for gr in iv.gestureRecognizers ?? [] {
                        gestureMediaID.removeValue(forKey: gr)
                    }
                    iv.removeFromSuperview()
                }
                mediaImageViews.removeValue(forKey: id)
            }

            // Add views for new items; update frames for existing
            // Use current contentSize (pageSize × zoomScale) so frames stay
            // anchored to the correct fractional position at any zoom level.
            let contentSize = canvas.contentSize.width > 1 ? canvas.contentSize : pageSize
            for item in mediaItems {
                let frame = CGRect(
                    x: CGFloat(item.x) * contentSize.width,
                    y: CGFloat(item.y) * contentSize.height,
                    width: CGFloat(item.width) * contentSize.width,
                    height: CGFloat(item.height) * contentSize.height
                )
                if let existing = mediaImageViews[item.id] {
                    existing.frame = frame
                    // Keep handles in sync if this image is currently selected
                    if item.id == selectedMediaID {
                        updateHandlePositions(for: existing, in: canvas)
                    }
                } else {
                    guard let image = UIImage(data: item.imageBlob) else { continue }
                    let iv = MediaImageView(image: image)
                    iv.frame = frame
                    iv.contentMode = .scaleAspectFit
                    iv.isUserInteractionEnabled = true
                    // Required for UIPinchGestureRecognizer — default is false,
                    // which means the second finger never reaches this view and
                    // the pinch never accumulates 2 touches → never recognizes.
                    iv.isMultipleTouchEnabled = true
                    // No zPosition override — render order controlled by subview index.

                    // All image gestures are finger-only. The ImageInteractionProxy at
                    // the top of the stack routes finger touches here; pencil touches
                    // fall through the proxy to PencilKit's drawing recognizer.
                    let fingerOnly: [NSNumber] = [NSNumber(value: UITouch.TouchType.direct.rawValue)]

                    let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleMediaSingleTap(_:)))
                    singleTap.numberOfTapsRequired = 1
                    singleTap.allowedTouchTypes = fingerOnly
                    iv.addGestureRecognizer(singleTap)
                    gestureMediaID[singleTap] = item.id

                    // Pan to move (finger only)
                    let pan = UIPanGestureRecognizer(target: self, action: #selector(handleMediaPan(_:)))
                    pan.allowedTouchTypes = fingerOnly
                    iv.addGestureRecognizer(pan)
                    gestureMediaID[pan] = item.id

                    // Pinch to resize (finger only)
                    let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handleMediaPinch(_:)))
                    pinch.allowedTouchTypes = fingerOnly
                    iv.addGestureRecognizer(pinch)
                    gestureMediaID[pinch] = item.id

                    // Double-tap to delete (finger only)
                    let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleMediaDoubleTap(_:)))
                    doubleTap.numberOfTapsRequired = 2
                    doubleTap.allowedTouchTypes = fingerOnly
                    iv.addGestureRecognizer(doubleTap)
                    gestureMediaID[doubleTap] = item.id

                    // Insert at index 1 — above template (index 0) but below
                    // PencilKit's internal rendering layer, so ink strokes appear
                    // on top of images. The ImageInteractionProxy (at the highest
                    // subview index) routes finger touches down to this view.
                    canvas.insertSubview(iv, at: 1)
                    mediaImageViews[item.id] = iv
                }
            }
        }

        // MARK: - Image selection

        /// Select an image: shows a gold border and four corner resize handles.
        func selectMedia(id: String, in canvas: PKCanvasView) {
            // Deselect the previous selection if different
            if let prev = selectedMediaID, prev != id {
                if let prevIV = mediaImageViews[prev] {
                    prevIV.layer.borderWidth = 0
                }
                removeHandles()
            }
            guard let iv = mediaImageViews[id] else { return }
            selectedMediaID = id
            let zoom = canvas.zoomScale > 0 ? canvas.zoomScale : 1
            iv.layer.borderWidth = 2.0 / zoom
            iv.layer.borderColor = UIColor(AppColors.gold).cgColor
            addHandles(to: iv, mediaID: id, in: canvas)
        }

        /// Deselect the current image: hides border and removes handles.
        func deselectMedia() {
            if let id = selectedMediaID, let iv = mediaImageViews[id] {
                iv.layer.borderWidth = 0
            }
            removeHandles()
            selectedMediaID = nil
        }

        /// Remove all corner handle views and clear tracking dictionaries.
        func removeHandles() {
            for handle in handleViews {
                handleCorners.removeValue(forKey: handle)
                for gr in handle.gestureRecognizers ?? [] {
                    gestureMediaID.removeValue(forKey: gr)
                }
                handle.removeFromSuperview()
            }
            handleViews.removeAll()
        }

        /// Add four corner handles around `iv` as subviews of `canvas`.
        /// Handles live in canvas content space; their size is divided by zoom
        /// so they maintain a constant ~handleScreenPts screen-space size.
        private func addHandles(to iv: UIImageView, mediaID: String, in canvas: PKCanvasView) {
            removeHandles()  // clear any stale handles first
            let zoom = canvas.zoomScale > 0 ? canvas.zoomScale : 1
            let hs = handleScreenPts / zoom  // content-space handle size

            let corners: [(String, CGFloat, CGFloat)] = [
                ("tl", iv.frame.minX, iv.frame.minY),
                ("tr", iv.frame.maxX, iv.frame.minY),
                ("bl", iv.frame.minX, iv.frame.maxY),
                ("br", iv.frame.maxX, iv.frame.maxY),
            ]
            for (corner, cx, cy) in corners {
                let handle = UIView(frame: CGRect(x: cx - hs / 2, y: cy - hs / 2, width: hs, height: hs))
                handle.backgroundColor = .white
                handle.layer.borderWidth = 1.5 / zoom
                handle.layer.borderColor = UIColor(AppColors.gold).cgColor
                handle.layer.cornerRadius = hs * 0.25
                handle.isUserInteractionEnabled = true
                handle.layer.zPosition = 3  // above image views (z=1)

                let pan = UIPanGestureRecognizer(target: self, action: #selector(handleResizePan(_:)))
                pan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
                pan.minimumNumberOfTouches = 1
                pan.maximumNumberOfTouches = 1
                handle.addGestureRecognizer(pan)
                gestureMediaID[pan] = mediaID
                handleCorners[handle] = corner

                canvas.addSubview(handle)
                handleViews.append(handle)
            }
        }

        /// Reposition the corner handles to match `iv`'s current frame.
        /// Also rescales handles to keep screen size constant at the current zoom.
        func updateHandlePositions(for iv: UIImageView, in canvas: PKCanvasView) {
            let zoom = canvas.zoomScale > 0 ? canvas.zoomScale : 1
            let hs = handleScreenPts / zoom

            let positions: [String: (CGFloat, CGFloat)] = [
                "tl": (iv.frame.minX, iv.frame.minY),
                "tr": (iv.frame.maxX, iv.frame.minY),
                "bl": (iv.frame.minX, iv.frame.maxY),
                "br": (iv.frame.maxX, iv.frame.maxY),
            ]
            for handle in handleViews {
                guard let corner = handleCorners[handle],
                      let (cx, cy) = positions[corner] else { continue }
                handle.frame = CGRect(x: cx - hs / 2, y: cy - hs / 2, width: hs, height: hs)
                handle.layer.cornerRadius = hs * 0.25
                handle.layer.borderWidth = 1.5 / zoom
            }
        }

        // MARK: - Gesture handlers

        @objc func handleCanvasBackgroundTap(_ sender: UITapGestureRecognizer) {
            guard selectedMediaID != nil, let canvas = observedCanvas else { return }
            let pt = sender.location(in: canvas)
            // Only deselect when tap lands on empty canvas (not on an image or handle).
            let onMedia  = mediaImageViews.values.contains { $0.frame.contains(pt) }
            let onHandle = handleViews.contains { $0.frame.contains(pt) }
            if !onMedia && !onHandle { deselectMedia() }
        }

        @objc func handleMediaSingleTap(_ sender: UITapGestureRecognizer) {
            guard let id = gestureMediaID[sender],
                  let canvas = observedCanvas else { return }
            if selectedMediaID == id {
                deselectMedia()  // tap selected image again → deselect
            } else {
                selectMedia(id: id, in: canvas)
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

            // Keep handles pinned during drag
            if id == selectedMediaID {
                updateHandlePositions(for: iv, in: canvas)
            }

            if sender.state == .ended {
                if let newItem = updatedMediaItem(id: id, from: iv, pageSize: parent.pageSize) {
                    parent.onMediaUpdated?(newItem)
                }
            }
        }

        @objc func handleMediaPinch(_ sender: UIPinchGestureRecognizer) {
            guard let id = gestureMediaID[sender],
                  let iv = mediaImageViews[id],
                  let canvas = observedCanvas else { return }

            switch sender.state {
            case .began:
                // Prevent PKCanvasView from zooming while the user resizes an image.
                canvas.maximumZoomScale = canvas.zoomScale
            case .changed:
                iv.transform = iv.transform.scaledBy(x: sender.scale, y: sender.scale)
                sender.scale = 1.0
                if id == selectedMediaID { updateHandlePositions(for: iv, in: canvas) }
            case .ended:
                canvas.maximumZoomScale = 5.0
                // Flatten transform into frame then persist.
                let newFrame = iv.frame
                iv.transform = .identity
                iv.frame = newFrame
                if id == selectedMediaID { updateHandlePositions(for: iv, in: canvas) }
                if let newItem = updatedMediaItem(id: id, from: iv, pageSize: parent.pageSize) {
                    parent.onMediaUpdated?(newItem)
                }
            case .cancelled, .failed:
                canvas.maximumZoomScale = 5.0
                iv.transform = .identity
            default:
                break
            }
        }

        /// Drag a corner handle to resize the image from that corner.
        @objc func handleResizePan(_ sender: UIPanGestureRecognizer) {
            guard let mediaID = gestureMediaID[sender],
                  let iv = mediaImageViews[mediaID],
                  let handle = sender.view,
                  let corner = handleCorners[handle],
                  let canvas = observedCanvas else { return }

            let translation = sender.translation(in: canvas)
            sender.setTranslation(.zero, in: canvas)

            var f = iv.frame
            let minSize: CGFloat = 40

            switch corner {
            case "tl":
                // Right & bottom edges stay fixed; top-left moves.
                let newW = max(minSize, f.width  - translation.x)
                let newH = max(minSize, f.height - translation.y)
                f.origin.x = f.maxX - newW
                f.origin.y = f.maxY - newH
                f.size = CGSize(width: newW, height: newH)
            case "tr":
                // Left & bottom edges stay fixed; top-right moves.
                let newW = max(minSize, f.width  + translation.x)
                let newH = max(minSize, f.height - translation.y)
                f.origin.y = f.maxY - newH
                f.size = CGSize(width: newW, height: newH)
            case "bl":
                // Right & top edges stay fixed; bottom-left moves.
                let newW = max(minSize, f.width  - translation.x)
                let newH = max(minSize, f.height + translation.y)
                f.origin.x = f.maxX - newW
                f.size = CGSize(width: newW, height: newH)
            case "br":
                // Top-left corner stays fixed; bottom-right moves.
                f.size = CGSize(
                    width:  max(minSize, f.width  + translation.x),
                    height: max(minSize, f.height + translation.y)
                )
            default:
                break
            }

            iv.frame = f
            updateHandlePositions(for: iv, in: canvas)

            if sender.state == .ended {
                if let newItem = updatedMediaItem(id: mediaID, from: iv, pageSize: parent.pageSize) {
                    parent.onMediaUpdated?(newItem)
                }
            }
        }

        @objc func handleMediaDoubleTap(_ sender: UITapGestureRecognizer) {
            guard let id = gestureMediaID[sender] else { return }
            parent.onMediaDeleted?(id)
        }

        private func updatedMediaItem(id: String, from iv: UIImageView, pageSize: CGSize) -> PageMediaItem? {
            guard var item = parent.mediaItems.first(where: { $0.id == id }) else { return nil }
            // Normalize by contentSize (= pageSize × zoomScale) so the stored
            // fractional position remains zoom-invariant.
            let cs = observedCanvas?.contentSize ?? pageSize
            let w = cs.width  > 1 ? cs.width  : pageSize.width
            let h = cs.height > 1 ? cs.height : pageSize.height
            item.x = Double(iv.frame.minX / w)
            item.y = Double(iv.frame.minY / h)
            item.width = Double(iv.frame.width / w)
            item.height = Double(iv.frame.height / h)
            return item
        }
    }
}
