import Foundation

/// Pure predicate for when a chat transcript should show a loading skeleton.
/// Show only while a load is in flight and there is nothing cached to paint —
/// never replace real turns with placeholders.
public enum ChatTranscriptSkeletonVisibility: Sendable {
    public static func shouldShow(hasCachedContent: Bool, isLoadInFlight: Bool) -> Bool {
        isLoadInFlight && !hasCachedContent
    }
}

#if os(iOS)
import SwiftUI

/// Placeholder transcript groups shown while turns hydrate (ThreadDetail /
/// LiveThread adopt). Appears immediately; callers cross-fade to real content.
struct ChatTranscriptSkeleton: View {
    @State private var isPulsing = false

    private static let groupCount = 4
    private static let pulseDuration: Double = 1.1

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            ForEach(0..<Self.groupCount, id: \.self) { index in
                skeletonGroup(index: index)
            }
        }
        .opacity(isPulsing ? 0.42 : 1.0)
        .animation(
            .easeInOut(duration: Self.pulseDuration).repeatForever(autoreverses: true),
            value: isPulsing
        )
        .onAppear { isPulsing = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Loading transcript"))
        .accessibilityIdentifier("chat-transcript-skeleton")
    }

    @ViewBuilder
    private func skeletonGroup(index: Int) -> some View {
        let userWidth: CGFloat = index % 2 == 0 ? 168 : 128
        let proseWide: CGFloat = index % 2 == 0 ? 0.92 : 0.78
        let proseNarrow: CGFloat = index % 2 == 0 ? 0.62 : 0.48
        let chipWidth: CGFloat = index % 2 == 0 ? 112 : 96

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Spacer(minLength: 48)
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemFill))
                    .frame(width: userWidth, height: 36)
            }

            GeometryReader { geo in
                VStack(alignment: .leading, spacing: 10) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color(.secondarySystemFill))
                        .frame(width: geo.size.width * proseWide, height: 13)
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color(.secondarySystemFill))
                        .frame(width: geo.size.width * proseNarrow, height: 13)
                }
            }
            .frame(height: 36)

            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemFill))
                .frame(width: chipWidth, height: 28)
        }
    }
}
#endif
