#if os(iOS)
import SwiftUI
import DesignSystem

// TODO: back with real workflow service

public struct WorkflowsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.conduitTokens) private var t

    public init() {}

    public var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                DSDetailHeader("workflows", onBack: { dismiss() })
                if LibraryMocks.workflows.isEmpty {
                    Spacer()
                    DSEmptyState(icon: .diff, title: "no workflows",
                                 subtitle: "Chain commands into a reusable multi-step run.")
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(LibraryMocks.workflows) { wf in
                                workflowRow(wf)
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
    private func workflowRow(_ wf: MockWorkflow) -> some View {
        HStack(spacing: 12) {
            DSIconView(.diff, size: 16, color: t.accent)
                .frame(width: 32, height: 32)
                .background(t.accentSoft)
            VStack(alignment: .leading, spacing: 3) {
                Text(wf.name)
                    .font(.dsMonoPt(14, weight: .semibold))
                    .foregroundStyle(t.text)
                    .lineLimit(1)
                Text("\(wf.stepCount) step\(wf.stepCount == 1 ? "" : "s") · last run \(wf.lastRun)")
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text3)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(t.text4)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}
#endif
