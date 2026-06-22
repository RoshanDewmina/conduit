#if os(iOS)
import SwiftUI
import LancerCore
import DesignSystem

// Compact navigation header: back button, BLOCKS server glyph, host name, AgentBadge,
// live cwd chip. Sits above the transcript.
public struct ChatHeaderView: View {
    let hostName: String
    let cwd: String
    let state: AgentState
    let blockedReason: BlockedReason?
    let onBack: (() -> Void)?
    let onDisconnect: (() -> Void)?
    let onPortForward: (() -> Void)?
    let onOpenWorkspace: (() -> Void)?
    let onReconnect: (() -> Void)?
    // P2.4: Budget burn display
    var budgetBurn: String?

    @Environment(\.lancerTokens) private var t

    public init(
        hostName: String,
        cwd: String,
        state: AgentState,
        blockedReason: BlockedReason? = nil,
        onBack: (() -> Void)? = nil,
        onDisconnect: (() -> Void)? = nil,
        onPortForward: (() -> Void)? = nil,
        onOpenWorkspace: (() -> Void)? = nil,
        onReconnect: (() -> Void)? = nil,
        budgetBurn: String? = nil
    ) {
        self.hostName = hostName
        self.cwd = cwd
        self.state = state
        self.blockedReason = blockedReason
        self.onBack = onBack
        self.onDisconnect = onDisconnect
        self.onPortForward = onPortForward
        self.onOpenWorkspace = onOpenWorkspace
        self.onReconnect = onReconnect
        self.budgetBurn = budgetBurn
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
                .accessibilityLabel("Leave session running")
            }

            // BLOCKS host glyph: square bordered server tile (matches session rows).
            DSIconView(.server, size: 16, color: t.text2)
                .frame(width: 34, height: 34)
                .background(t.surface)
                .clipShape(RoundedRectangle(cornerRadius: t.r2, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: t.r2, style: .continuous)
                        .strokeBorder(t.border, lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(hostName)
                    .font(.dsMonoPt(13, weight: .medium))
                    .foregroundStyle(t.text)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text("$").font(.dsMonoPt(10, weight: .medium)).foregroundStyle(t.accent)
                    Text(cwd)
                        .font(.dsMonoPt(10))
                        .foregroundStyle(t.text3)
                        .lineLimit(1).truncationMode(.head)
                }
            }

            Spacer()

            // P2.4: Budget burn display
            if let burn = budgetBurn {
                HStack(spacing: 3) {
                    Image(systemName: "flame")
                        .font(.dsMonoPt(9))
                    Text(burn)
                        .font(.dsMonoPt(11, weight: .medium))
                }
                .foregroundStyle(t.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(t.accent.opacity(0.12))
                .clipShape(Capsule())
            }

            AgentBadge(state)

            if let onOpenWorkspace {
                Button(action: onOpenWorkspace) {
                    Image(systemName: "rectangle.3.group")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(t.text2)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open workspace")
            }

            if onDisconnect != nil || onPortForward != nil || onReconnect != nil {
                Menu {
                    if let onReconnect {
                        Button {
                            onReconnect()
                        } label: {
                            Label("Reconnect", systemImage: "arrow.clockwise")
                        }
                    }
                    if let onPortForward {
                        Button {
                            onPortForward()
                        } label: {
                            Label("Port Forwarding", systemImage: "arrow.left.arrow.right")
                        }
                    }
                    if let onDisconnect {
                        Button(role: .destructive) {
                            onDisconnect()
                        } label: {
                            Label("Disconnect", systemImage: "bolt.slash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(t.text2)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Session options")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(t.surface2)
        .overlay(
            Rectangle()
                .fill(t.border)
                .frame(height: 1),
            alignment: .bottom
        )

        if let reason = blockedReason {
            DSBlockedReasonRow(reason)
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
        }
    }
}

#endif
