#if os(iOS)
import SwiftUI
import DesignSystem

// TODO: back with real agent service

public struct AgentsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.conduitTokens) private var t

    public init() {}

    public var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                DSDetailHeader("agents", onBack: { dismiss() })
                if LibraryMocks.agents.isEmpty {
                    Spacer()
                    DSEmptyState(icon: .sparkles, title: "no agents",
                                 subtitle: "Connect an AI provider in Settings to manage agents here.")
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(LibraryMocks.agents) { agent in
                                agentRow(agent)
                                DSDivider()
                            }
                        }
                    }
                }
            }
        }
        .navigationBarHidden(true)
    }

    @ViewBuilder
    private func agentRow(_ agent: MockAgent) -> some View {
        HStack(spacing: 12) {
            PixelAvatar(seed: agent.name, size: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(agent.name)
                    .font(.dsMonoPt(14, weight: .semibold))
                    .foregroundStyle(t.text)
                    .lineLimit(1)
                Text(agent.model)
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text3)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                DSStatusDot(tone: agent.isActive ? .ok : .off, pulse: agent.isActive)
                Text(agent.monthlyCost)
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text4)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}
#endif
