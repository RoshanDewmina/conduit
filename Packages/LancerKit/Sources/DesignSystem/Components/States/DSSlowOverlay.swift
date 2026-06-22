import SwiftUI

// MARK: - DSSlowOverlay
// Shown when a connection is taking unusually long.
// Dark overlay: DotMatrix(.connecting) + "still trying…" + cancel/retry.

public struct DSSlowOverlay: View {
    let message: String
    let onCancel: (() -> Void)?
    let onRetry: (() -> Void)?

    @Environment(\.lancerTokens) private var t

    public init(
        message: String = "still trying…",
        onCancel: (() -> Void)? = nil,
        onRetry: (() -> Void)? = nil
    ) {
        self.message = message
        self.onCancel = onCancel
        self.onRetry = onRetry
    }

    public var body: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                DotMatrixView(state: .working, cols: 18, rows: 6, cell: 9, dot: 4)
                    .frame(width: 180, height: 60)

                VStack(spacing: 6) {
                    Text(message)
                        .font(.dsMonoPt(15, weight: .semibold))
                        .foregroundStyle(.white)

                    Text("Check your network and host status.")
                        .font(.dsMonoPt(12))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .multilineTextAlignment(.center)

                HStack(spacing: 12) {
                    if let onCancel {
                        DSButton("cancel", variant: .ghost, size: .md, mono: true, action: onCancel)
                    }
                    if let onRetry {
                        DSButton("retry", variant: .primary, size: .md, mono: true, action: onRetry)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 32)
        }
    }
}
