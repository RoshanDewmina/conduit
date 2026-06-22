import SwiftUI

// MARK: - DSSkeletonRow
// Shimmer placeholder row for list loading states.
// Uses SwiftUI .redacted + a phase-based shimmer animation.

public struct DSSkeletonRow: View {
    let showAvatar: Bool
    let titleWidth: CGFloat
    let subtitleWidth: CGFloat

    @Environment(\.lancerTokens) private var t
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    public init(showAvatar: Bool = true, titleWidth: CGFloat = 0.55, subtitleWidth: CGFloat = 0.35) {
        self.showAvatar = showAvatar
        self.titleWidth = titleWidth
        self.subtitleWidth = subtitleWidth
    }

    public var body: some View {
        HStack(spacing: 14) {
            if showAvatar {
                Rectangle()
                    .fill(shimmerGradient)
                    .frame(width: 44, height: 44)
            }

            VStack(alignment: .leading, spacing: 7) {
                GeometryReader { geo in
                    Rectangle()
                        .fill(shimmerGradient)
                        .frame(width: geo.size.width * titleWidth, height: 12)
                }
                .frame(height: 12)

                GeometryReader { geo in
                    Rectangle()
                        .fill(shimmerGradient)
                        .frame(width: geo.size.width * subtitleWidth, height: 10)
                }
                .frame(height: 10)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .onAppear { startShimmer() }
    }

    private var shimmerGradient: LinearGradient {
        let base = t.border.opacity(0.6)
        let highlight = t.surface2
        return LinearGradient(
            stops: [
                .init(color: base,      location: max(0, phase - 0.3)),
                .init(color: highlight, location: phase),
                .init(color: base,      location: min(1, phase + 0.3)),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private func startShimmer() {
        guard !reduceMotion else { return }
        withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
            phase = 1.3
        }
    }
}

// MARK: - DSSkeletonList
// Convenience: renders N staggered skeleton rows.

public struct DSSkeletonList: View {
    let count: Int
    let showAvatar: Bool

    public init(count: Int = 4, showAvatar: Bool = true) {
        self.count = count
        self.showAvatar = showAvatar
    }

    private static let widthPairs: [(CGFloat, CGFloat)] = [
        (0.60, 0.40), (0.45, 0.30), (0.70, 0.50), (0.50, 0.35),
        (0.65, 0.45), (0.40, 0.25),
    ]

    public var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { i in
                let pair = Self.widthPairs[i % Self.widthPairs.count]
                DSSkeletonRow(showAvatar: showAvatar, titleWidth: pair.0, subtitleWidth: pair.1)
                    .opacity(1.0 - Double(i) * 0.15)
            }
        }
    }
}
