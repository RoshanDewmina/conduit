import SwiftUI
import LancerCore

// MARK: - DSStatusHeader — per-tab status strip
// Calm root-level header bar: connection dot · policy · today spend.
// Sits at the top of each tab screen. Distinct from AgentStatusHeader
// (which is session-scoped, always-dark, and shows live agent state).

public struct DSStatusHeader: View {
    /// The one honest connection state (Finding #9). Drives the dot, the label,
    /// and the colour so this header can never claim "bridge connected" while
    /// the session is merely attempting or has failed.
    public let state: Session.ConnectionState
    public let policy: String
    public let todaySpend: String

    @Environment(\.lancerTokens) private var t

    public init(state: Session.ConnectionState, policy: String, todaySpend: String) {
        self.state = state
        self.policy = policy
        self.todaySpend = todaySpend
    }

    /// Back-compat shim for call sites that only have a Bool. A `true` means a
    /// fully-established bridge; `false` means offline. Prefer the
    /// `state:`-based initializer so "connecting" / "failed" stay distinct.
    public init(connected: Bool, policy: String, todaySpend: String) {
        self.init(state: connected ? .connected : .offline, policy: policy, todaySpend: todaySpend)
    }

    private var dotColor: Color {
        switch state {
        case .connected, .relayPaired: return t.ok
        case .connecting:              return t.warn
        case .failed:                  return t.danger
        case .offline:                 return t.text3
        }
    }

    private var label: String {
        switch state {
        case .connected:   return "bridge connected"
        case .relayPaired: return "relay paired"
        case .connecting:  return "connecting…"
        case .failed:      return "bridge unreachable"
        case .offline:     return "bridge offline"
        }
    }

    private var labelColor: Color {
        switch state {
        case .connected, .relayPaired: return t.text2
        case .connecting:              return t.warn
        case .failed, .offline:        return t.danger
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 6, height: 6)

                Text(label)
                    .font(.dsMonoPt(11))
                    .foregroundStyle(labelColor)

                Text("·")
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text3)

                Text("policy: \(policy)")
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text3)

                Text("·")
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text3)

                Text("today \(todaySpend)")
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text3)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 6)

            Rectangle()
                .fill(t.border)
                .frame(height: 0.5)
        }
        .background(t.bg)
    }
}

#Preview {
    VStack(spacing: 0) {
        DSStatusHeader(state: .connected, policy: "balanced", todaySpend: "$4.94")
        DSStatusHeader(state: .connecting, policy: "balanced", todaySpend: "$0.00")
        DSStatusHeader(state: .failed, policy: "strict", todaySpend: "$0.00")
        DSStatusHeader(state: .offline, policy: "strict", todaySpend: "$0.00")
    }
    .environment(\.lancerTokens, .dark)
    .background(Color(.sRGB, red: 0.039, green: 0.043, blue: 0.051, opacity: 1))
}
