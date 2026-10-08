import SwiftUI

struct CardEditor: View {
    @Bindable var card: Card
    @Environment(\.dismiss) private var dismiss
    @State private var showingFront = true
    @State private var angle = 0.0

    var body: some View {
        VStack(spacing: 28) {
            HStack {
                Button("Done") { dismiss() }
                Spacer()
                Text(showingFront ? "Front" : "Back").font(.headline)
                Spacer()
                Color.clear.frame(width: 50, height: 1)
            }
            .padding(.horizontal)

            // The placeholder fixes the card's size; the canvas is overlaid so its
            // large intrinsic size can't stretch the layout.
            Color.clear
                .aspectRatio(5.0 / 3.0, contentMode: .fit)
                .overlay {
                    ZStack {
                        RoundedRectangle(cornerRadius: 18).fill(.white).shadow(radius: 10)
                        CardLines()
                        DrawingCanvas(data: showingFront ? $card.front : $card.back)
                            .id(showingFront)   // reload the canvas when the side changes
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                    }
                }
                .padding(.horizontal, 40)
                .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0))

            Button {
                flip()
            } label: {
                Label("Rotate", systemImage: "arrow.triangle.2.circlepath")
                    .font(.title3)
            }
            .buttonStyle(.borderedProminent)

            Spacer()
        }
        .padding(.top, 24)
    }

    private func flip() {
        withAnimation(.easeIn(duration: 0.18)) { angle = 90 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            showingFront.toggle()
            angle = -90
            withAnimation(.easeOut(duration: 0.18)) { angle = 0 }
        }
    }
}

struct CardLines: View {
    var body: some View {
        Canvas { ctx, size in
            var y: CGFloat = 40
            while y < size.height {
                var line = Path()
                line.move(to: CGPoint(x: 16, y: y))
                line.addLine(to: CGPoint(x: size.width - 16, y: y))
                ctx.stroke(line, with: .color(.blue.opacity(0.18)), lineWidth: 1)
                y += 32
            }
        }
        .allowsHitTesting(false)
    }
}
