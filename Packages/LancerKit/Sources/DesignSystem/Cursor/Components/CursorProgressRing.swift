#if os(iOS)
import SwiftUI

public struct CursorProgressRing: View {
    @Environment(\.cursorScheme) private var cursorScheme

    let fraction: Double
    let color: Color
    let size: CGFloat
    let lineWidth: CGFloat

    public init(fraction: Double, color: Color, size: CGFloat = 64, lineWidth: CGFloat = 5) {
        self.fraction = fraction
        self.color = color
        self.size = size
        self.lineWidth = lineWidth
    }

    public var body: some View {
        let colors = CursorColors.resolve(cursorScheme)
        ZStack {
            Circle()
                .stroke(colors.hairline, lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: CGFloat(min(max(fraction, 0), 1)))
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.6), value: fraction)

            Text(String(format: "%.0f", fraction * 100))
                .font(CursorType.rowSecondary)
                .foregroundColor(color)
                .monospacedDigit()
        }
        .frame(width: size, height: size)
    }
}
#endif
