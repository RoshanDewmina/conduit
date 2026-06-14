#if os(iOS)
import SwiftUI

/// App-shell status strip (BLOCKS "pinned" placement). Unlike `AgentStatusHeader`,
/// this ALWAYS renders — when idle it shows a calm summary so its vertical
/// position never shifts between tabs. Mount once in the app shell, above the
/// per-tab content. Reconnect/expand actions are surfaced via the closures.
public struct PersistentStatusBar: View {
    let agents: [AgentInfo]
    var relayState: E2ERelayStatusBadge.State?
    var onTap: () -> Void
    var onReconnect: (() -> Void)?

    public init(agents: [AgentInfo], relayState: E2ERelayStatusBadge.State? = nil, onTap: @escaping () -> Void = {}, onReconnect: (() -> Void)? = nil) {
        self.agents = agents
        self.relayState = relayState
        self.onTap = onTap
        self.onReconnect = onReconnect
    }

    private var approvals: [AgentInfo] { agents.filter { $0.state == .approval } }
    private var primary: AgentInfo? { approvals.first ?? agents.first { $0.state != .offline } ?? agents.first }
    private var hasApproval: Bool { !approvals.isEmpty }
    private var isFailed: Bool { primary?.state == .error }

    // DI namespace has no .danger token — use the same red as PixelBox.stateColor(.error)
    private static let dangerRed = Color(.sRGB, red: 0.765, green: 0.227, blue: 0.192, opacity: 1)
    // DI namespace has no .accent token — use DI.streaming (blue accent) for the idle tint
    private static let accentTint = DI.streaming

    public var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                if let primary {
                    PixelBox(state: primary.state, size: 9, gap: 1.6, subdivisions: 3)
                    Text(primary.host).font(.dsSansPt(13, weight: .semibold)).foregroundStyle(DI.ink).lineLimit(1)
                    Text("·").font(DI.mono(12)).foregroundStyle(DI.ink3)
                    Text(primary.state == .done ? "Connected" : primary.state.islandLabel)
                        .font(DI.mono(12))
                        .foregroundStyle(hasApproval ? DI.approval : PixelBox.stateColor(primary.state))
                        .lineLimit(1)
                } else {
                    // calm idle summary — keeps the strip's height/position stable
                    PixelBox(state: .offline, size: 9, gap: 1.6, subdivisions: 3).opacity(0.5)
                    Text("·").font(DI.mono(12)).foregroundStyle(DI.ink3)
                    Text("no active session").font(DI.mono(12)).foregroundStyle(DI.ink3).lineLimit(1)
                }
                Spacer(minLength: 8)
                if let relayState {
                    E2ERelayStatusBadge(state: relayState)
                }
                if isFailed, let onReconnect {
                    Button("reconnect", action: onReconnect)
                        .font(DI.mono(11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).frame(height: 22)
                        .background(Self.dangerRed, in: RoundedRectangle(cornerRadius: 2))
                        .buttonStyle(.plain)
                }
                if hasApproval {
                    Text("\(approvals.count)")
                        .font(DI.mono(11, weight: .bold))
                        .foregroundStyle(Color(.sRGB, red: 0.10, green: 0.07, blue: 0, opacity: 1))
                        .frame(minWidth: 18, minHeight: 18)
                        .background(DI.approval, in: Capsule())
                }
                Image(systemName: "chevron.right").font(.dsSansPt(11, weight: .semibold)).foregroundStyle(DI.ink3)
            }
            .padding(.horizontal, 16)
            .frame(height: 34)
            .frame(maxWidth: .infinity)
            .background(alignment: .bottom) {
                ZStack(alignment: .bottom) {
                    (hasApproval ? DI.approval.opacity(0.10) : Self.accentTint.opacity(0.06))
                    Rectangle().frame(height: 0.5)
                        .foregroundStyle(hasApproval ? DI.approval.opacity(0.45) : Color.white.opacity(0.10))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(primary.map { "\($0.host), \($0.state.hudLabel)" } ?? "No active session")
    }
}
#endif
