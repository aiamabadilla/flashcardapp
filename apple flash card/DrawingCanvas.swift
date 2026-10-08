import SwiftUI
import PencilKit

struct DrawingCanvas: UIViewRepresentable {
    @Binding var data: Data
    /// False while typing, so the keyboard and the tool picker don't fight.
    var isActive = true
    @Environment(\.colorScheme) private var scheme

    func makeCoordinator() -> Coordinator { Coordinator(data: $data) }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        #if targetEnvironment(simulator)
        canvas.drawingPolicy = .anyInput      // the Simulator has no Pencil
        #else
        canvas.drawingPolicy = .pencilOnly    // Pencil draws, fingers pan and zoom
        #endif
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.minimumZoomScale = 1
        canvas.maximumZoomScale = 5
        canvas.delegate = context.coordinator
        canvas.drawing = (try? PKDrawing(data: data)) ?? PKDrawing()
        context.coordinator.canvas = canvas

        DispatchQueue.main.async {
            let picker = context.coordinator.picker
            picker.addObserver(canvas)
            picker.setVisible(true, forFirstResponder: canvas)
            if isActive { canvas.becomeFirstResponder() }
        }
        return canvas
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
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

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var data: Binding<Data>
        let picker = PKToolPicker()
        weak var canvas: PKCanvasView?
        private var pending: DispatchWorkItem?
        private var observer: NSObjectProtocol?

        init(data: Binding<Data>) {
            self.data = data
            super.init()
            observer = NotificationCenter.default.addObserver(
                forName: UIApplication.willResignActiveNotification, object: nil, queue: .main
            ) { [weak self] _ in MainActor.assumeIsolated { self?.flush() } }
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
