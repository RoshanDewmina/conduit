#if os(iOS)
import SwiftUI
import ConduitCore

// MARK: - DSDecisionSheet — approval bottom-sheet content
// Full-detail view rendered inside a sheet with .presentationDetents([.medium,.large]).
// The presenter is responsible for BiometricGate and sheet presentation;
// this view is purely display + action routing.

public struct DSDecisionSheet: View {
    public let risk: Int
    public let agentName: String
    public let action: String
    public let command: String
    public let whyText: String
    public let requiresBiometric: Bool
    public let diff: AnyView?
    public let blastRadius: ApprovalBlastRadius
    public let onDeny: () -> Void
    public let onApprove: () -> Void
    public let onEditAndRun: () -> Void
    public let onAllowAlways: () -> Void

    @Environment(\.conduitTokens) private var t

    public init(
        risk: Int,
        agentName: String,
        action: String,
        command: String,
        whyText: String,
        requiresBiometric: Bool = false,
        diff: AnyView? = nil,
        blastRadius: ApprovalBlastRadius,
        onDeny: @escaping () -> Void,
        onApprove: @escaping () -> Void,
        onEditAndRun: @escaping () -> Void,
        onAllowAlways: @escaping () -> Void
    ) {
        self.risk = risk
        self.agentName = agentName
        self.action = action
        self.command = command
        self.whyText = whyText
        self.requiresBiometric = requiresBiometric
        self.diff = diff
        self.blastRadius = blastRadius
        self.onDeny = onDeny
        self.onApprove = onApprove
        self.onEditAndRun = onEditAndRun
        self.onAllowAlways = onAllowAlways
    }

    private var riskTone: DSChipTone {
        switch risk {
        case 0:  return .ok
        case 1:  return .warn
        case 2:  return .orange
        default: return .danger
        }
    }

    private var riskLabel: String {
        switch risk {
        case 0:  return "LOW"
        case 1:  return "MED"
        case 2:  return "HIGH"
        default: return "CRIT"
        }
    }

    public var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                headerSection
                commandSection
                if let diff {
                    diff
                }
                blastSection
                whySection
                if requiresBiometric {
                    biometricNote
                }
                actionButtons
            }
            .padding(.horizontal, 18)
            .padding(.top, 22)
            .padding(.bottom, 28)
        }
        .background(t.surface)
    }

    private var headerSection: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(agentName)
                    .font(.dsMonoPt(13, weight: .medium))
                    .foregroundStyle(t.text2)
                    .lineLimit(1)
                Text(action)
                    .font(.dsSansPt(17, weight: .semibold))
                    .foregroundStyle(t.text)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            RiskBadge(risk: risk)
        }
    }

    private var commandSection: some View {
        DSQuoteBlock(
            title: "COMMAND",
            tags: [],
            message: command,
            tone: riskTone
        )
    }

    private var blastSection: some View {
        DSBlastRadiusBanner(blastRadius: blastRadius)
    }

    private var whySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("WHY THIS ASKS YOU")
                .font(.dsMonoPt(10, weight: .medium))
                .tracking(10 * 0.12)
                .foregroundStyle(t.text3)

            Text(whyText)
                .font(.dsSansPt(14))
                .foregroundStyle(t.text2)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var biometricNote: some View {
        HStack(spacing: 8) {
            Image(systemName: "faceid")
                .font(.system(size: 13))
                .foregroundStyle(t.text3)
            Text("Face ID required to approve")
                .font(.dsSansPt(13))
                .foregroundStyle(t.text3)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(t.surfaceSunk)
        .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                DSButton("Deny", variant: .destructive, fullWidth: true, action: onDeny)
                DSButton("Approve", variant: .primary, fullWidth: true, action: onApprove)
            }
            HStack(spacing: 10) {
                DSButton("Edit & run", variant: .secondary, size: .sm, mono: true, fullWidth: true, action: onEditAndRun)
                DSButton("Allow always", variant: .secondary, size: .sm, mono: true, fullWidth: true, action: onAllowAlways)
            }
        }
    }
}

#Preview {
    Color.black.ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            DSDecisionSheet(
                risk: 2,
                agentName: "claude-opus",
                action: "Write files to production path",
                command: "rm -rf /var/log/app/*.log && echo 'cleaned'",
                whyText: "This command matches the policy rule \"file-delete on /var/log/**\" which requires human sign-off before destructive removals outside the project root.",
                requiresBiometric: true,
                diff: nil,
                blastRadius: ApprovalBlastRadius(
                    files: ["/var/log/app/error.log", "/var/log/app/access.log"],
                    touchesGit: false,
                    touchesNetwork: false,
                    matchedRule: "file-delete"
                ),
                onDeny: {},
                onApprove: {},
                onEditAndRun: {},
                onAllowAlways: {}
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .environment(\.conduitTokens, .dark)
        }
        .environment(\.conduitTokens, .dark)
}
#endif
