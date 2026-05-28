import SwiftUI

// Animated 3×3 pixel-cell grid used in the HUD and agent states.
// Each cell pulses independently at a staggered rate.
public struct PixelBox: View {
    let color: Color
    let size: CGFloat
    let gap: CGFloat

    @State private var phase: Double = 0

    public init(color: Color, size: CGFloat = 5, gap: CGFloat = 1.5) {
        self.color = color
        self.size = size
        self.gap = gap
    }

    public var body: some View {
        let cols = 3
        let rows = 3
        Grid(horizontalSpacing: gap, verticalSpacing: gap) {
            ForEach(0..<rows, id: \.self) { row in
                GridRow {
                    ForEach(0..<cols, id: \.self) { col in
                        let index = row * cols + col
                        let delay = Double(index) * 0.07
                        RoundedRectangle(cornerRadius: 1, style: .continuous)
                            .fill(color)
                            .frame(width: size, height: size)
                            .opacity(cellOpacity(index: index, phase: phase))
                            .onAppear {
                                withAnimation(
                                    .easeInOut(duration: 0.9)
                                    .repeatForever(autoreverses: true)
                                    .delay(delay)
                                ) {
                                    phase = 1
                                }
                            }
                    }
                }
            }
        }
    }

    private func cellOpacity(index: Int, phase: Double) -> Double {
        // Each cell has a distinct duty cycle derived from its index.
        let base = 0.25 + Double(index % 3) * 0.15
        return base + (1.0 - base) * phase * (index % 2 == 0 ? 1.0 : 0.6)
    }
}
