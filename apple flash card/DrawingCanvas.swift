import SwiftUI
import PencilKit

struct DrawingCanvas: UIViewRepresentable {
    @Binding var data: Data

    func makeCoordinator() -> Coordinator { Coordinator(data: $data) }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        #if targetEnvironment(simulator)
        canvas.drawingPolicy = .anyInput      // the Simulator has no Pencil
        #else
        canvas.drawingPolicy = .pencilOnly    // Pencil draws, fingers pan and zoom
        #endif
        canvas.overrideUserInterfaceStyle = .light  // cards are white; keep ink black
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.minimumZoomScale = 1
        canvas.maximumZoomScale = 5
        canvas.delegate = context.coordinator
        canvas.drawing = (try? PKDrawing(data: data)) ?? PKDrawing()

        DispatchQueue.main.async {
            let picker = context.coordinator.picker
            picker.addObserver(canvas)
            picker.setVisible(true, forFirstResponder: canvas)
            canvas.becomeFirstResponder()
        }
        return canvas
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {}

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var data: Binding<Data>
        let picker = PKToolPicker()
        init(data: Binding<Data>) { self.data = data }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            data.wrappedValue = canvasView.drawing.dataRepresentation()
        }
    }
}

/// Renders a saved PKDrawing as an image, always with light-mode ink.
struct DrawingImage: View {
    let data: Data
    var padding: CGFloat = 12

    var body: some View {
        if let image = Self.render(data) {
            Image(uiImage: image).resizable().scaledToFit().padding(padding)
        }
    }

    static func render(_ data: Data, scale: CGFloat = 2) -> UIImage? {
        guard !data.isEmpty,
              let drawing = try? PKDrawing(data: data),
              !drawing.bounds.isEmpty else { return nil }
        var image: UIImage?
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            image = drawing.image(from: drawing.bounds, scale: scale)
        }
        return image
    }
}
