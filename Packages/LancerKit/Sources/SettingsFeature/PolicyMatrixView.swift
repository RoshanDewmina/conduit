#if os(iOS)
import SwiftUI
import LancerCore
import DesignSystem

/// Read-only matrix that shows how one normalized policy is realized across each
/// agent provider, plus an "apply to all" action. Rows are rules, columns are
/// providers, and each cell shows whether the rule lands as a hook / approval
/// (✓) or is unsupported (⚠).
public struct PolicyMatrixView: View {
    let policy: NormalizedPolicy
    let onApply: (NormalizedPolicy) -> Void

    @Environment(\.lancerTokens) private var t
    @Environment(\.dismiss) private var dismiss

    private let providers = AgentProvider.allCases

    public init(
        policy: NormalizedPolicy = .defaultPolicy,
        onApply: @escaping (NormalizedPolicy) -> Void
    ) {
        self.policy = policy
        self.onApply = onApply
    }

    public var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    DSDetailHeader("policy matrix", onBack: { dismiss() })
                        .padding(.horizontal, 18)
                    headerSection
                    matrix
                    legend
                    applyButton
                }
            }
        }
        .navigationBarHidden(true)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CROSS-PROVIDER NORMALIZATION")
                .font(.dsMonoPt(10, weight: .semibold))
                .tracking(10 * 0.12)
                .foregroundStyle(t.text3)

            Text("One rule set, mapped onto every agent. Claude Code and OpenCode enforce inline via a PreToolUse hook; Codex gates through its exec approval prompt. Scope rules OpenCode can't yet see are flagged.")
                .font(.dsSansPt(13))
                .foregroundStyle(t.text2)
                .lineSpacing(2)
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 16)
    }

    // MARK: - Matrix

    private var matrix: some View {
        VStack(spacing: 0) {
            columnHeader
            Rectangle().fill(t.divider).frame(height: 1)
            ForEach(Array(policy.rules.enumerated()), id: \.element.id) { idx, rule in
                if idx > 0 {
                    Rectangle().fill(t.divider).frame(height: 1).padding(.leading, 12)
                }
                ruleRow(rule)
            }
        }
        .background(t.surface)
        .clipShape(RoundedRectangle(cornerRadius: t.r1, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: t.r1, style: .continuous)
                .strokeBorder(t.border, lineWidth: 1)
        )
        .padding(.horizontal, 18)
    }

    private var columnHeader: some View {
        HStack(spacing: 0) {
            Text("RULE")
                .font(.dsMonoPt(10, weight: .semibold))
                .tracking(10 * 0.12)
                .foregroundStyle(t.text3)
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(providers) { provider in
                Text(provider.shortName.uppercased())
                    .font(.dsMonoPt(9, weight: .semibold))
                    .tracking(9 * 0.08)
                    .foregroundStyle(t.text3)
                    .frame(width: cellWidth)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func ruleRow(_ rule: NormalizedRule) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text(rule.description)
                    .font(.dsSansPt(13))
                    .foregroundStyle(t.text)
                    .lineLimit(2)
                Text(rule.id)
                    .font(.dsMonoPt(10))
                    .foregroundStyle(t.text4)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(providers) { provider in
                cell(policy.mapping(for: rule, provider: provider))
                    .frame(width: cellWidth)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func cell(_ mapping: RuleMapping) -> some View {
        VStack(spacing: 4) {
            DSStatusDot(tone: tone(mapping))
            Text(label(mapping))
                .font(.dsMonoPt(9))
                .foregroundStyle(t.text3)
        }
    }

    // MARK: - Legend

    private var legend: some View {
        HStack(spacing: 14) {
            legendItem(.hook)
            legendItem(.approval)
            legendItem(.unsupported)
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
    }

    private func legendItem(_ mapping: RuleMapping) -> some View {
        HStack(spacing: 6) {
            DSStatusDot(tone: tone(mapping))
            Text(label(mapping))
                .font(.dsMonoPt(11))
                .foregroundStyle(t.text2)
        }
    }

    // MARK: - Apply

    private var applyButton: some View {
        DSButton(
            "Apply normalized policy to all \(providers.count) providers",
            variant: .accent,
            size: .md,
            mono: true,
            fullWidth: true
        ) {
            onApply(policy)
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 32)
    }

    // MARK: - Helpers

    private let cellWidth: CGFloat = 64

    private func tone(_ mapping: RuleMapping) -> DSStatusDotTone {
        switch mapping {
        case .hook:        return .ok
        case .approval:    return .warn
        case .unsupported: return .danger
        }
    }

    private func label(_ mapping: RuleMapping) -> String {
        switch mapping {
        case .hook:        return "✓ hook"
        case .approval:    return "✓ ask"
        case .unsupported: return "⚠ gap"
        }
    }
}

#Preview {
    NavigationStack {
        PolicyMatrixView(policy: .defaultPolicy) { _ in }
            .lancerTokens()
    }
}

#endif
