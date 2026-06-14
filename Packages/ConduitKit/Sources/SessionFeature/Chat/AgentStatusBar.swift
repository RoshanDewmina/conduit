#if os(iOS)
import SwiftUI
import ConduitCore
import DesignSystem

// Always-dark HUD strip at the top of Agent Chat.
// Variant B: "N running · message" or Variant C: tick bars (active output).
// Expandable into a full agent sheet.
public struct AgentStatusBar: View {
    let state: AgentState
    let message: String?
    let pendingApprovals: Int
    let tickValues: [Double]   // normalized 0–1 for TickBars
    let blockedReason: BlockedReason?

    @State private var isExpanded = false
    @Environment(\.conduitTokens) private var t

    /// Rich state bundling the lifecycle state with any active blocking context.
    private var context: AgentStateContext {
        AgentStateContext(state: state, blockedReason: blockedReason)
    }

    public init(
        state: AgentState,
        message: String? = nil,
        pendingApprovals: Int = 0,
        tickValues: [Double] = [],
        blockedReason: BlockedReason? = nil
    ) {
        self.state = state
        self.message = message
        self.pendingApprovals = pendingApprovals
        self.tickValues = tickValues
        self.blockedReason = blockedReason
    }

    public var body: some View {
        VStack(spacing: 0) {
            strip
            if !isExpanded, let row = DSBlockedReasonRow(context: context, onDark: true) {
                row
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
            }
            if isExpanded { expandedSheet }
        }
        .background(t.hudBg)
        .overlay(
            Rectangle().fill(t.hudBorder.opacity(0.8)).frame(height: 0.5),
            alignment: .bottom
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isExpanded)
    }

    // MARK: - Compact strip

    private var strip: some View {
        HStack(spacing: 10) {
            StatusIcon(state, size: 7)

            // Left side: state label
            HStack(spacing: 6) {
                Text(state.label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(t.hudText)

                if let msg = message {
                    Text("·").foregroundStyle(t.hudText.opacity(0.4)).font(.caption)
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(t.hudText.opacity(0.7))
                        .lineLimit(1)
                }
            }

            Spacer()

            // Right side: tick bars OR approval badge
            if state == .streaming, !tickValues.isEmpty {
                TickBars(values: tickValues, barColor: t.accent.opacity(0.8), maxHeight: 16)
            }

            if pendingApprovals > 0 {
                DSChip("\(pendingApprovals) pending", tone: .warn, style: .soft)
            }

            // Expand chevron
            Button { isExpanded.toggle() } label: {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(t.hudText.opacity(0.6))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Expanded agent sheet

    private var expandedSheet: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider().background(t.hudBorder)

            HStack(spacing: 12) {
                AgentBadge(state)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Agent status").font(.caption.weight(.semibold)).foregroundStyle(t.hudText)
                    if let msg = message {
                        Text(msg).font(.caption).foregroundStyle(t.hudText.opacity(0.7))
                    }
                }
                Spacer()
            }

            if pendingApprovals > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(t.warn)
                    Text("\(pendingApprovals) action\(pendingApprovals == 1 ? "" : "s") need\(pendingApprovals == 1 ? "s" : "") approval")
                        .font(.caption)
                        .foregroundStyle(t.hudText)
                }
            }

            if let row = DSBlockedReasonRow(context: context, onDark: true) {
                row
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

#endif
