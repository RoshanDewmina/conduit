import SwiftUI

// MARK: - DSOfflineState
// App-level offline banner: bolt-slash glyph + "you're offline" + tmux note.

public struct DSOfflineState: View {
    let onDismiss: (() -> Void)?

    @Environment(\.lancerTokens) private var t
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dotScale: CGFloat = 1

    public init(onDismiss: (() -> Void)? = nil) {
        self.onDismiss = onDismiss
    }

    public var body: some View {
        HStack(spacing: 14) {
            // Pulsing offline dot
            ZStack {
                Circle()
                    .fill(t.warn.opacity(0.15))
                    .frame(width: 32, height: 32)
                    .scaleEffect(dotScale)
                Image(systemName: "bolt.slash")
                    .font(.dsSansPt(14, weight: .semibold))
                    .foregroundStyle(t.warn)
            }
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                    dotScale = 1.18
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("you're offline")
                    .font(.dsMonoPt(13, weight: .semibold))
                    .foregroundStyle(t.text)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility3)
                Text("tmux preserved · reconnecting…")
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text3)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility3)
            }

            Spacer()

            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.dsSansPt(12, weight: .medium))
                        .foregroundStyle(t.text4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(t.warnSoft)
        .overlay(
            Rectangle()
                .strokeBorder(t.warn.opacity(0.3), lineWidth: 0.5)
        )
    }
}
