import SwiftUI

// Dense vertical bar chart used in the HUD variant C (tick bars).
// `values` is normalized 0–1; renders ~24 recent samples by default.
public struct TickBars: View {
    let values: [Double]
    let barColor: Color
    let barWidth: CGFloat
    let spacing: CGFloat
    let maxHeight: CGFloat

    public init(
        values: [Double],
        barColor: Color = .white.opacity(0.7),
        barWidth: CGFloat = 2,
        spacing: CGFloat = 1,
        maxHeight: CGFloat = 20
    ) {
        self.values = values
        self.barColor = barColor
        self.barWidth = barWidth
        self.spacing = spacing
        self.maxHeight = maxHeight
    }

    public var body: some View {
        HStack(alignment: .bottom, spacing: spacing) {
            ForEach(values.indices, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(barColor)
                    .frame(width: barWidth, height: max(2, values[i] * maxHeight))
            }
        }
        .frame(height: maxHeight, alignment: .bottom)
    }
}
