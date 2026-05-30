#if os(iOS)
import SwiftUI
import ConduitCore

// MARK: - DSAskQuestionCard
//
// Inbox card for Approval.Kind.askQuestion: renders the agent's question
// and a set of tappable answer buttons. The selected choice is highlighted
// and the user confirms with SUBMIT.

public struct DSAskQuestionCard: View {
    let agentKey: AgentKey
    let agentName: String
    let timeLabel: String
    let question: String
    let choices: [String]
    let onAnswer: (Int) -> Void          // called with the chosen index

    @State private var selected: Int? = nil
    @Environment(\.conduitTokens) private var t

    public init(
        agentKey: AgentKey,
        agentName: String,
        timeLabel: String,
        question: String,
        choices: [String],
        onAnswer: @escaping (Int) -> Void
    ) {
        self.agentKey = agentKey
        self.agentName = agentName
        self.timeLabel = timeLabel
        self.question = question
        self.choices = choices
        self.onAnswer = onAnswer
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Head
            HStack {
                AgentIdentityBadge(agent: agentKey, label: agentName)
                DSChip("question", tone: .info, style: .soft)
                Spacer()
                Text(timeLabel)
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text3)
            }

            // Question
            DSQuoteBlock(title: "question", message: question, tone: .accent)

            // Choice grid
            VStack(spacing: 6) {
                ForEach(Array(choices.enumerated()), id: \.offset) { idx, choice in
                    choiceRow(idx: idx, label: choice)
                }
            }

            // Submit
            HStack {
                Spacer()
                DSButton(
                    "SUBMIT",
                    variant: selected != nil ? .primary : .secondary,
                    size: .sm,
                    mono: true
                ) {
                    if let s = selected { onAnswer(s) }
                }
                .disabled(selected == nil)
            }
        }
        .padding(16)
        .background(t.surface)
        .clipShape(RoundedRectangle(cornerRadius: t.r4, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: t.r4, style: .continuous)
                .strokeBorder(selected != nil ? t.accent.opacity(0.4) : t.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
    }

    private func choiceRow(idx: Int, label: String) -> some View {
        let isSelected = selected == idx
        let letter = ["A", "B", "C", "D", "E"][min(idx, 4)]

        return Button {
            withAnimation(.easeInOut(duration: 0.12)) { selected = idx }
            Haptics.selection()
        } label: {
            HStack(spacing: 10) {
                // Letter badge
                ZStack {
                    RoundedRectangle(cornerRadius: t.r2, style: .continuous)
                        .fill(isSelected ? t.accent : t.surfaceSunk)
                        .frame(width: 26, height: 26)
                    Text(letter)
                        .font(.dsMonoPt(12, weight: .semibold))
                        .foregroundStyle(isSelected ? t.accentFg : t.text3)
                }
                Text(label)
                    .font(.dsSansPt(14))
                    .foregroundStyle(isSelected ? t.text : t.text2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(t.accent)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(isSelected ? t.accentSoft : t.surface2)
            .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: t.r3, style: .continuous)
                    .strokeBorder(isSelected ? t.accent.opacity(0.5) : t.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.12), value: selected)
    }
}

// MARK: - DSMCPCallCard
//
// Compact card for Approval.Kind.callMCP: shows the tool name + args summary
// with a wire-frame "MCP" badge.

public struct DSMCPCallCard: View {
    let agentKey: AgentKey
    let agentName: String
    let timeLabel: String
    let toolName: String     // e.g. "read_file" or "bash"
    let args: String?        // one-line summary of arguments
    let risk: Int
    let onDeny: () -> Void
    let onApprove: () -> Void

    @Environment(\.conduitTokens) private var t

    public init(
        agentKey: AgentKey,
        agentName: String,
        timeLabel: String,
        toolName: String,
        args: String? = nil,
        risk: Int,
        onDeny: @escaping () -> Void,
        onApprove: @escaping () -> Void
    ) {
        self.agentKey = agentKey
        self.agentName = agentName
        self.timeLabel = timeLabel
        self.toolName = toolName
        self.args = args
        self.risk = risk
        self.onDeny = onDeny
        self.onApprove = onApprove
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                AgentIdentityBadge(agent: agentKey, label: agentName)
                RiskBadge(risk: risk)
                DSChip("MCP", tone: .info, style: .soft)
                Spacer()
                Text(timeLabel)
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text3)
            }

            HStack(spacing: 4) {
                Text(agentName).fontWeight(.semibold)
                Text("wants to call")
            }
            .font(.dsSansPt(14))
            .foregroundStyle(t.text)

            // Tool name row
            HStack(spacing: 8) {
                Image(systemName: "bolt.horizontal")
                    .font(.system(size: 12))
                    .foregroundStyle(t.info)
                Text(toolName)
                    .font(.dsMonoPt(13, weight: .semibold))
                    .foregroundStyle(t.termCwd)
                if let a = args {
                    Text(a)
                        .font(.dsMonoPt(12))
                        .foregroundStyle(t.text3)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(t.surfaceSunk)
            .clipShape(RoundedRectangle(cornerRadius: t.r2, style: .continuous))

            HStack(spacing: 8) {
                Spacer()
                DSButton("DENY", variant: .destructive, size: .sm, mono: true, action: onDeny)
                DSButton("APPROVE", variant: .primary, size: .sm, mono: true, action: onApprove)
            }
        }
        .padding(16)
        .background(t.surface)
        .clipShape(RoundedRectangle(cornerRadius: t.r4, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: t.r4, style: .continuous)
                .strokeBorder(t.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
    }
}

// MARK: - DSAutonomyPresetBar
//
// Horizontal segmented control for the three autonomy presets. Persists the
// selected preset to AppStorage under "inbox.autonomyPreset".

public struct DSAutonomyPresetBar: View {
    @Binding var preset: AutonomyPreset
    @Environment(\.conduitTokens) private var t

    public init(preset: Binding<AutonomyPreset>) {
        self._preset = preset
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            DSSegmentedPicker(
                options: AutonomyPreset.allCases.map { (.init($0.shortLabel), $0) },
                selection: $preset
            )
            Text(preset.description)
                .font(.dsMonoPt(11))
                .foregroundStyle(t.text3)
                .animation(.easeInOut(duration: 0.15), value: preset)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(t.surface2)
        .overlay(alignment: .bottom) {
            Rectangle().fill(t.border).frame(height: 1)
        }
    }
}

#endif
