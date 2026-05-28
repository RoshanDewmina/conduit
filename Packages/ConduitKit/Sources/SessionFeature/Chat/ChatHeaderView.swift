#if os(iOS)
import SwiftUI
import ConduitCore
import DesignSystem

// Compact navigation header: back button, PixelAvatar, host name, AgentBadge,
// live cwd chip. Sits above the transcript.
public struct ChatHeaderView: View {
    let hostName: String
    let cwd: String
    let state: AgentState
    let onBack: (() -> Void)?

    @Environment(\.conduitTokens) private var t

    public init(
        hostName: String,
        cwd: String,
        state: AgentState,
        onBack: (() -> Void)? = nil
    ) {
        self.hostName = hostName
        self.cwd = cwd
        self.state = state
        self.onBack = onBack
    }

    public var body: some View {
        HStack(spacing: 10) {
            if let back = onBack {
                Button(action: back) {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(t.text2)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            PixelAvatar(seed: hostName, size: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(hostName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(t.text1)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Image(systemName: "folder").font(.caption2).foregroundStyle(t.text4)
                    Text(cwd)
                        .font(.caption2.monospaced())
                        .foregroundStyle(t.text3)
                        .lineLimit(1).truncationMode(.head)
                }
            }

            Spacer()

            AgentBadge(state)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(t.surf1)
        .overlay(
            Rectangle()
                .fill(t.surf3.opacity(0.6))
                .frame(height: 0.5),
            alignment: .bottom
        )
    }
}

#endif
