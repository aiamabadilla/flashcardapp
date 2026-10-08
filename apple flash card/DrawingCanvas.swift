import SwiftUI
import PencilKit

struct DrawingCanvas: UIViewRepresentable {
    @Binding var data: Data
    var viewport: Viewport? = nil
    /// Called with a finger tap's position in card coordinates (zoom already removed).
    var onTap: ((CGPoint) -> Void)? = nil
    /// False while typing, so the keyboard and the tool picker don't fight.
    var isActive = true
    @Environment(\.colorScheme) private var scheme

    func makeCoordinator() -> Coordinator { Coordinator(data: $data, viewport: viewport) }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        #if targetEnvironment(simulator)
        canvas.drawingPolicy = .anyInput      // the Simulator has no Pencil
        #else
        canvas.drawingPolicy = .pencilOnly    // Pencil draws, fingers pan and zoom
        #endif
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.contentInsetAdjustmentBehavior = .never
        canvas.minimumZoomScale = 1
        canvas.maximumZoomScale = 5
        canvas.delegate = context.coordinator
        // Finger taps select photos and text; the Pencil keeps drawing, even over them.
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        tap.delegate = context.coordinator
        canvas.addGestureRecognizer(tap)
        canvas.drawing = (try? PKDrawing(data: data)) ?? PKDrawing()
        context.coordinator.canvas = canvas
        viewport?.scrollView = canvas
        DispatchQueue.main.async { viewport?.reset() }

        DispatchQueue.main.async {
            let picker = context.coordinator.picker
            picker.addObserver(canvas)
            picker.setVisible(true, forFirstResponder: canvas)
            if isActive { canvas.becomeFirstResponder() }
        }
        return canvas
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        context.coordinator.onTap = onTap
        // PencilKit flips black ink to white (and adapts other colors) in dark mode.
        uiView.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
        if isActive {
            if !uiView.isFirstResponder { DispatchQueue.main.async { uiView.becomeFirstResponder() } }
        } else if uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
    }

    static func dismantleUIView(_ uiView: PKCanvasView, coordinator: Coordinator) {
        coordinator.flush()
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate, UIGestureRecognizerDelegate {
        var onTap: ((CGPoint) -> Void)?
        var data: Binding<Data>
        let picker = PKToolPicker()
        weak var canvas: PKCanvasView?
        let viewport: Viewport?
        private var pending: DispatchWorkItem?
        private var observer: NSObjectProtocol?

        init(data: Binding<Data>, viewport: Viewport?) {
            self.data = data
            self.viewport = viewport
            super.init()
            observer = NotificationCenter.default.addObserver(
                forName: UIApplication.willResignActiveNotification, object: nil, queue: .main
            ) { [weak self] _ in MainActor.assumeIsolated { self?.flush() } }
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let canvas, let onTap else { return }
            // Location in a scroll view is in content coordinates, i.e. already includes the
            // pan offset and is scaled by the zoom.
            let point = gesture.location(in: canvas)
            let zoom = max(canvas.zoomScale, 0.01)
            onTap(CGPoint(x: point.x / zoom, y: point.y / zoom))
        }

        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

        func scrollViewDidScroll(_ scrollView: UIScrollView) { report(scrollView) }
        func scrollViewDidZoom(_ scrollView: UIScrollView) { report(scrollView) }

        private func report(_ scrollView: UIScrollView) {
            guard let viewport else { return }
            viewport.zoom = scrollView.zoomScale
            viewport.offset = scrollView.contentOffset
        }

        deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

        /// Serializing the whole drawing on every stroke update made the app lag, so
        /// saves are debounced; the last change is always flushed on exit.
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            pending?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.flush() }
            pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
        }

        func flush() {
            pending?.cancel()
            pending = nil
            guard let canvas else { return }
            let bytes = canvas.drawing.dataRepresentation()
            if bytes != data.wrappedValue { data.wrappedValue = bytes }
        }
    }
}
