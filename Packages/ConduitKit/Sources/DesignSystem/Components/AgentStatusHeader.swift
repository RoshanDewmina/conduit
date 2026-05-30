#if os(iOS)
import SwiftUI

// ============================================================
// AgentStatusHeader — a slim, in-layout status header for the live agent
// session. The calm replacement for the floating "island" banner on the app's
// tabs: it sits pinned at the top of a screen (via `.safeAreaInset(edge: .top)`),
// never floats over the camera cutout, and is only shown when there is a real
// live session (the store returns no agents when idle).
//
// Shows: state glyph · host · status label, with a pending-approval badge, and
// opens the live session on tap. The expressive expandable island lives only in
// the gallery now; this is what ships on the tabs.
// ============================================================

public struct AgentStatusHeader: View {
    let agents: [AgentInfo]
    var onTap: () -> Void

    public init(agents: [AgentInfo], onTap: @escaping () -> Void = {}) {
        self.agents = agents
        self.onTap = onTap
    }

    private var approvals: [AgentInfo] { agents.filter { $0.state == .approval } }
    private var primary: AgentInfo? {
        approvals.first ?? agents.first { $0.state != .offline } ?? agents.first
    }
    private var hasApproval: Bool { !approvals.isEmpty }

    public var body: some View {
        if let primary {
            Button(action: onTap) {
                HStack(spacing: 10) {
                    PixelBox(state: primary.state, size: 9, gap: 1.6, subdivisions: 3)

                    Text(primary.host)
                        .font(.dsSansPt(13, weight: .semibold))
                        .foregroundStyle(DI.ink)
                        .lineLimit(1)
                    Text("·")
                        .font(DI.mono(12))
                        .foregroundStyle(DI.ink3)
                    Text(primary.state == .done ? "Connected" : primary.state.islandLabel)
                        .font(DI.mono(12))
                        .foregroundStyle(hasApproval ? DI.approval : PixelBox.stateColor(primary.state))
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    if hasApproval {
                        // State label already reads "Needs you"; the trailing
                        // capsule just carries the count.
                        Text("\(approvals.count)")
                            .font(DI.mono(11, weight: .bold))
                            .foregroundStyle(Color(.sRGB, red: 0.10, green: 0.07, blue: 0, opacity: 1))
                            .frame(minWidth: 18, minHeight: 18)
                            .background(DI.approval, in: Capsule())
                    }

                    Image(systemName: "chevron.right")
                        .font(.dsSansPt(11, weight: .semibold))
                        .foregroundStyle(DI.ink3)
                }
                .padding(.horizontal, 16)
                .frame(height: 34)
                .frame(maxWidth: .infinity)
                .background(alignment: .bottom) {
                    ZStack(alignment: .bottom) {
                        (hasApproval ? DI.approval.opacity(0.10) : Color.white.opacity(0.05))
                        Rectangle()
                            .frame(height: 0.5)
                            .foregroundStyle(hasApproval ? DI.approval.opacity(0.45) : Color.white.opacity(0.10))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "\(primary.host), \(primary.state.hudLabel)"
                + (hasApproval ? ", \(approvals.count) needs approval" : "")
            )
        }
    }
}
#endif
