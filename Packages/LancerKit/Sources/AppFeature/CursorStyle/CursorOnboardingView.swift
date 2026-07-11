#if os(iOS)
import SwiftUI

/// Two-step onboarding: product proof, then pair-or-skip.
public struct CursorOnboardingView: View {
    @Environment(\.cursorShellLiveBridge) private var liveBridge
    @State private var step: Int = 0
    private let onComplete: () -> Void

    public init(onComplete: @escaping () -> Void = {}) {
        self.onComplete = onComplete
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer(minLength: 0)
            if step == 0 {
                Text("Steer AI coding agents from your phone.")
                    .font(.title2.bold())
                Text("Lancer runs on machines you own. Approve, review, and dispatch from here.")
                    .foregroundStyle(.secondary)
                Button("Get started") { step = 1 }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("onboarding.get-started")
            } else {
                Text("Pair your machine")
                    .font(.title2.bold())
                Text("Run `lancerd pair` on your Mac, then enter the code. You can also do this later from Settings.")
                    .foregroundStyle(.secondary)
                Button("Pair now") {
                    liveBridge?.onRequestPairing?()
                    onComplete()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("onboarding.pair-now")
                Button("Skip for now") { onComplete() }
                    .accessibilityIdentifier("onboarding.skip")
            }
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
#endif
