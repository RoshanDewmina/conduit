#if os(iOS)
import SwiftUI
import LancerCore

// MARK: - DSAskQuestionCard
//
// Inbox card for Approval.Kind.askQuestion: renders the agent's question
// and a set of tappable answer buttons. The selected choice is highlighted
// and the user confirms with SUBMIT.

public struct DSAskQuestionCard: View {
    let agentKey: AgentKey
    let agentName: String
    let hostLabel: String
    let timeLabel: String
    let question: String
    let choices: [String]
    let onAnswer: (Int) -> Void          // called with the chosen index

    @State private var selected: Int? = nil
    @Environment(\.lancerTokens) private var t

    public init(
        agentKey: AgentKey,
        agentName: String,
        hostLabel: String = "",
        timeLabel: String,
        question: String,
        choices: [String],
        onAnswer: @escaping (Int) -> Void
    ) {
        self.agentKey = agentKey
        self.agentName = agentName
        self.hostLabel = hostLabel
        self.timeLabel = timeLabel
        self.question = question
        self.choices = choices
        self.onAnswer = onAnswer
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Head: AgentIdentityBadge + host name + spacer + time
            HStack(spacing: 6) {
                AgentIdentityBadge(agent: agentKey, label: agentName)
                Text(hostLabel)
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text3)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text(timeLabel)
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text3)
            }

            // Left-accent-bar question block
            HStack(spacing: 0) {
                Rectangle()
                    .fill(t.accent)
                    .frame(width: 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text("QUESTION")
                        .font(.dsDisplayPt(9, weight: .semibold))
                        .tracking(9 * 0.12)
                        .foregroundStyle(t.accent)
                    Text(question)
                        .font(.dsMonoPt(13))
                        .foregroundStyle(t.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.leading, 11)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

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
        .padding(13)
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
                // Letter chip: filled blue when selected, plain border otherwise
                ZStack {
                    RoundedRectangle(cornerRadius: t.r2, style: .continuous)
                        .fill(isSelected ? t.accent : t.bg)
                        .frame(width: 26, height: 26)
                        .overlay(
                            RoundedRectangle(cornerRadius: t.r2, style: .continuous)
                                .strokeBorder(isSelected ? t.accent : t.border, lineWidth: 1)
                        )
                    Text(letter)
                        .font(.dsMonoPt(12, weight: .semibold))
                        .foregroundStyle(isSelected ? t.accentFg : t.text2)
                }
                Text(label)
                    .font(.dsMonoPt(13))
                    .foregroundStyle(isSelected ? t.text : t.text2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isSelected {
                    DSIconView(.check, size: 14, color: t.accent)
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(isSelected ? t.accentSoft : t.bg)
            .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: t.r3, style: .continuous)
                    .strokeBorder(isSelected ? t.accent : t.border, lineWidth: 1)
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
    let hostLabel: String
    let timeLabel: String
    let toolName: String     // e.g. "read_file" or "bash"
    let toolUseID: String?
    let args: String?        // one-line summary of arguments
    let risk: Int
    let onDeny: () -> Void
    let onEditAndRun: () -> Void
    let onAllowAlways: () -> Void
    let onApprove: () -> Void

    @Environment(\.lancerTokens) private var t

    public init(
        agentKey: AgentKey,
        agentName: String,
        hostLabel: String = "",
        timeLabel: String,
        toolName: String,
        toolUseID: String? = nil,
        args: String? = nil,
        risk: Int,
        onDeny: @escaping () -> Void,
        onEditAndRun: @escaping () -> Void,
        onAllowAlways: @escaping () -> Void,
        onApprove: @escaping () -> Void
    ) {
        self.agentKey = agentKey
        self.agentName = agentName
        self.hostLabel = hostLabel
        self.timeLabel = timeLabel
        self.toolName = toolName
        self.toolUseID = toolUseID
        self.args = args
        self.risk = risk
        self.onDeny = onDeny
        self.onEditAndRun = onEditAndRun
        self.onAllowAlways = onAllowAlways
        self.onApprove = onApprove
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Head: AgentIdentityBadge + RiskBadge + spacer + time
            HStack(spacing: 6) {
                AgentIdentityBadge(agent: agentKey, label: agentName)
                RiskBadge(risk: risk)
                Spacer()
                Text(timeLabel)
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text3)
            }

            Text("\(Text(agentName).foregroundStyle(t.text))\(Text(" is asking permission to use \(toolName)").foregroundStyle(t.text2))")
                .font(.dsMonoPt(12))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if let toolUseID, !toolUseID.isEmpty {
                HStack(spacing: 6) {
                    DSChip("tool use", tone: .neutral, variant: .soft, size: .sm)
                    Text(toolUseID)
                        .font(.dsMonoPt(11))
                        .foregroundStyle(t.text3)
                        .lineLimit(1)
                }
            }

            // Inline blast-radius chips (risk ramp — never brand blue per R5.1/R5.2)
            blastRadiusChips

            // Command well: t.bg background, t.divider border, $ in danger + tool name mono
            HStack(alignment: .top, spacing: 8) {
                Text("$")
                    .font(.dsMonoPt(12, weight: .semibold))
                    .foregroundStyle(t.danger)
                VStack(alignment: .leading, spacing: 3) {
                    Text(toolName)
                        .font(.dsMonoPt(12))
                        .foregroundStyle(t.text)
                    if let a = args {
                        Text(a)
                            .font(.dsMonoPt(11))
                            .foregroundStyle(t.text3)
                            .lineLimit(6)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(t.bg)
            .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: t.r3, style: .continuous)
                    .strokeBorder(t.divider, lineWidth: 1)
            )

            // ONE-TAP ROW (R3.1–R3.3): Deny LEFT (destructive outline), Approve RIGHT (primary filled).
            HStack(spacing: 8) {
                DSButton("Deny", variant: .destructive, size: .md, mono: true, fullWidth: true, action: onDeny)
                DSButton("Approve", variant: .primary, size: .md, mono: true, fullWidth: true, action: onApprove)
            }

            // SECOND ROW: demoted secondary actions (quiet variant, R3.3)
            HStack(spacing: 8) {
                DSButton("Edit & run", variant: .quiet, size: .md, mono: true, fullWidth: true, action: onEditAndRun)
                DSButton("Allow always…", variant: .quiet, size: .md, mono: true, fullWidth: true, action: onAllowAlways)
            }

            Text("Allow always applies to this exact tool, input, and path. Revoke rules in Settings.")
                .font(.dsMonoPt(11))
                .foregroundStyle(t.text3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(13)
        .background(t.surface)
        .clipShape(RoundedRectangle(cornerRadius: t.r4, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: t.r4, style: .continuous)
                .strokeBorder(t.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
    }

    @ViewBuilder
    private var blastRadiusChips: some View {
        let riskTone: DSChipTone = risk >= 3 ? .danger : risk == 2 ? .orange : risk == 1 ? .warn : .ok
        let riskLabel: String = risk >= 3 ? "critical" : risk == 2 ? "high" : risk == 1 ? "medium" : "low"
        HStack(spacing: 6) {
            DSChip(riskLabel, systemImage: "exclamationmark.triangle", tone: riskTone, variant: .soft, size: .sm)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - DSAutonomyPresetBar
//
// Full-width BLOCKS segmented bar for the three autonomy presets.
// 1px t.border outer stroke, 1px dividers between segments, active = t.accent fill
// + white text; inactive = transparent + t.text2. Label: dsDisplayPt(10) semibold uppercase.

public struct DSAutonomyPresetBar: View {
    @Binding var preset: AutonomyPreset
    @Environment(\.lancerTokens) private var t

    private let presets: [AutonomyPreset] = AutonomyPreset.allCases

    public init(preset: Binding<AutonomyPreset>) {
        self._preset = preset
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Segmented bar
            HStack(spacing: 0) {
                ForEach(Array(presets.enumerated()), id: \.element) { idx, option in
                    let isActive = preset == option
                    Button {
                        withAnimation(.easeInOut(duration: 0.12)) { preset = option }
                        Haptics.selection()
                    } label: {
                        Text(option.shortLabel.uppercased())
                            .font(.dsDisplayPt(10, weight: .semibold))
                            .tracking(10 * 0.08)
                            .foregroundStyle(isActive ? t.accentFg : t.text2)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(isActive ? t.accent : Color.clear)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .animation(.easeInOut(duration: 0.12), value: preset)

                    // Divider between segments (not after last)
                    if idx < presets.count - 1 {
                        Rectangle()
                            .fill(t.border)
                            .frame(width: 1)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .background(Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: t.r3, style: .continuous)
                    .strokeBorder(t.border, lineWidth: 1)
            )
            .padding(.horizontal, 16)
            .padding(.top, 10)

            // Description hint
            Text(preset.description)
                .font(.dsMonoPt(11))
                .foregroundStyle(t.text3)
                .animation(.easeInOut(duration: 0.15), value: preset)
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 10)
        }
        .background(t.surface2)
        .overlay(alignment: .bottom) {
            Rectangle().fill(t.border).frame(height: 1)
        }
    }
}

// MARK: - DSCredentialRequestCard
//
// Inbox card for Approval.Kind.credential: shows which agent wants access
// to a credential, the requested scope, and offers scoped authorization.

public struct DSCredentialRequestCard: View {
    let agentKey: AgentKey
    let agentName: String
    let hostLabel: String
    let timeLabel: String
    let toolName: String
    let credentialHint: String
    let risk: Int
    let onDeny: () -> Void
    let onApprove: () -> Void
    let onAuthorizeScope: () -> Void

    @Environment(\.lancerTokens) private var t

    public init(
        agentKey: AgentKey,
        agentName: String,
        hostLabel: String = "",
        timeLabel: String,
        toolName: String,
        credentialHint: String,
        risk: Int,
        onDeny: @escaping () -> Void,
        onApprove: @escaping () -> Void,
        onAuthorizeScope: @escaping () -> Void
    ) {
        self.agentKey = agentKey
        self.agentName = agentName
        self.hostLabel = hostLabel
        self.timeLabel = timeLabel
        self.toolName = toolName
        self.credentialHint = credentialHint
        self.risk = risk
        self.onDeny = onDeny
        self.onApprove = onApprove
        self.onAuthorizeScope = onAuthorizeScope
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                AgentIdentityBadge(agent: agentKey, label: agentName)
                RiskBadge(risk: risk)
                Spacer()
                Text(timeLabel)
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text3)
            }

            HStack(spacing: 0) {
                Rectangle()
                    .fill(.orange)
                    .frame(width: 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text("CREDENTIAL REQUEST")
                        .font(.dsDisplayPt(9, weight: .semibold))
                        .tracking(9 * 0.12)
                        .foregroundStyle(.orange)
                    Text("\(Text(agentName).foregroundStyle(t.text))\(Text(" wants to access a credential via \(toolName)").foregroundStyle(t.text2))")
                        .font(.dsMonoPt(12))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.leading, 11)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 6) {
                DSIconView(.key, size: 12, color: .orange)
                Text(credentialHint)
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text2)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                Button { onDeny() } label: {
                    Label("Deny", systemImage: "xmark")
                        .font(.dsSansPt(13, weight: .medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)

                Button { onAuthorizeScope() } label: {
                    Label("Scope", systemImage: "scope")
                        .font(.dsSansPt(13, weight: .medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(t.accent)

                Button { onApprove() } label: {
                    Label("Approve", systemImage: "checkmark")
                        .font(.dsSansPt(13, weight: .medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(t.accent)
            }
        }
        .padding(16)
        .background(t.surface)
        .clipShape(RoundedRectangle(cornerRadius: t.r4, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: t.r4, style: .continuous)
                .strokeBorder(t.border, lineWidth: 1)
        )
    }
}

#endif
