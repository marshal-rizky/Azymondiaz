import SwiftUI
import PencilKit

/// SwiftUI host for a single `PKCanvasView`. Owns the ink, not the background.
/// Background is rendered separately (SwiftUI `Image` under the canvas) so the
/// canvas can stay transparent and the template can react to dark mode changes.
struct CanvasView: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    let allowsFingerDrawing: Bool

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
        canvas.alwaysBounceVertical = false

        // Tool picker is attached when canvas becomes first responder.
        DispatchQueue.main.async {
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
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: CanvasView
        init(_ parent: CanvasView) { self.parent = parent }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            parent.drawing = canvasView.drawing
        }
    }
}
