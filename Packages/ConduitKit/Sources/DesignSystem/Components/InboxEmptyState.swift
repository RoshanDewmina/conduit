#if os(iOS)
import SwiftUI

// MARK: - InboxEmptyState
//
// Empty state for inbox when no approvals are pending.
// Shows envelope icon, "No pending approvals" title, and subtitle.

public struct InboxEmptyState: View {
    @Environment(\.conduitTokens) private var t

    public init() {}

    public var body: some View {
        VStack(spacing: 12) {
            Spacer()

            // Envelope icon
            Image(systemName: "envelope")
                .font(.system(size: 48))
                .foregroundStyle(t.text3)

            // Title
            Text("No pending approvals")
                .font(.dsDisplayPt(18, weight: .semibold))
                .foregroundStyle(t.text)

            // Subtitle
            Text("When a coding agent needs permission, its request will appear here.")
                .font(.dsMonoPt(13))
                .foregroundStyle(t.text3)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

#endif
