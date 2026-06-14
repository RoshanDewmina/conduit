import SwiftUI

// MARK: - DSStatusHeader — per-tab status strip
// Calm root-level header bar: connection dot · policy · today spend.
// Sits at the top of each tab screen. Distinct from AgentStatusHeader
// (which is session-scoped, always-dark, and shows live agent state).

public struct DSStatusHeader: View {
    public let connected: Bool
    public let policy: String
    public let todaySpend: String

    @Environment(\.conduitTokens) private var t

    public init(connected: Bool, policy: String, todaySpend: String) {
        self.connected = connected
        self.policy = policy
        self.todaySpend = todaySpend
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Circle()
                    .fill(connected ? t.ok : t.danger)
                    .frame(width: 6, height: 6)

                Text(connected ? "bridge connected" : "bridge offline")
                    .font(.dsMonoPt(11))
                    .foregroundStyle(connected ? t.text2 : t.danger)

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
        DSStatusHeader(connected: true, policy: "balanced", todaySpend: "$4.94")
        DSStatusHeader(connected: false, policy: "strict", todaySpend: "$0.00")
    }
    .environment(\.conduitTokens, .dark)
    .background(Color(.sRGB, red: 0.039, green: 0.043, blue: 0.051, opacity: 1))
}
