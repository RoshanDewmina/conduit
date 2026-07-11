#if os(iOS)
import SwiftUI

/// Deferred stub for `prDetail` deep-link route.
public struct CursorPRDetailView: View {
    private let onBack: () -> Void

    public init(onBack: @escaping () -> Void = {}) {
        self.onBack = onBack
    }

    public var body: some View {
        ContentUnavailableView(
            "Ship history not built yet",
            systemImage: "arrow.triangle.pull",
            description: Text("Waiting on a real PR / diff data source.")
        )
        .navigationTitle("PR")
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Back", systemImage: "chevron.left", action: onBack)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pr-detail-screen")
    }
}
#endif
