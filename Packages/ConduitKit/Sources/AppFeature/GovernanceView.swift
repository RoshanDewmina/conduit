#if os(iOS)
import SwiftUI
import ConduitCore
import DesignSystem

/// Proof-first governance overview. Policy editing remains in Settings and
/// approval decisions remain in Inbox; this screen answers whether the control
/// plane is present, connected, and enforcing rules right now.
public struct GovernanceView: View {
    private let actions: BridgeSessionActions
    private let onOpenSettings: () -> Void
    private let onOpenInbox: () -> Void
    private let onOpenFleet: () -> Void

    @Environment(\.conduitTokens) private var t
    @State private var policySummary = "Loading policy"
    @State private var latestEvent: AuditLogEntry?
    @State private var loadError: String?

    public init(
        actions: BridgeSessionActions,
        onOpenSettings: @escaping () -> Void,
        onOpenInbox: @escaping () -> Void,
        onOpenFleet: @escaping () -> Void
    ) {
        self.actions = actions
        self.onOpenSettings = onOpenSettings
        self.onOpenInbox = onOpenInbox
        self.onOpenFleet = onOpenFleet
    }

    public var body: some View {
        DSScreen("Governance", subtitle: "Policy, bridge and enforcement", trailing: {
            Button { Task { await loadProof() } } label: {
                Image(systemName: "arrow.clockwise")
                    .accessibilityLabel("Refresh governance proof")
            }
        }) {
            connectionCard

            DSSectionGroup("Provider coverage") {
                providerRow(.claudeCode, name: "Claude Code")
                DSDivider().padding(.leading, 48)
                providerRow(.codex, name: "Codex")
                DSDivider().padding(.leading, 48)
                providerRow(.opencode, name: "OpenCode")
                DSDivider().padding(.leading, 48)
                providerRow(.kimi, name: "Kimi")
            }

            DSSectionGroup("Policy") {
                DSNavigationRow(
                    "Active policy",
                    subtitle: policySummary,
                    value: actions.isConnected ? "Live" : "Offline",
                    systemImage: "checkmark.shield",
                    action: onOpenSettings
                )
                DSDivider().padding(.leading, 50)
                DSNavigationRow(
                    "Approval inbox",
                    subtitle: "Review governed requests and evidence",
                    systemImage: "tray.full",
                    action: onOpenInbox
                )
            }

            DSSectionGroup("Latest enforcement") {
                if let latestEvent {
                    latestEventRow(latestEvent)
                } else if let loadError {
                    Label(loadError, systemImage: "exclamationmark.triangle")
                        .font(.dsSansPt(14))
                        .foregroundStyle(t.danger)
                        .padding(14)
                } else {
                    Text(actions.isConnected ? "No enforcement event recorded yet." : "Connect a host to inspect enforcement history.")
                        .font(.dsSansPt(14))
                        .foregroundStyle(t.text3)
                        .padding(14)
                }
            }
        }
        .task { await loadProof() }
    }

    private var connectionCard: some View {
        HStack(spacing: 12) {
            Image(systemName: actions.isConnected ? "checkmark.shield.fill" : "shield.slash")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(actions.isConnected ? t.ok : t.text3)
                .frame(width: 38, height: 38)
                .background((actions.isConnected ? t.okSoft : t.surface2), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(actions.isConnected ? "Governance bridge connected" : "No governance bridge connected")
                    .font(.dsSansPt(16, weight: .semibold))
                    .foregroundStyle(t.text)
                Text(actions.isConnected ? "Live policy and audit evidence from the selected SSH host." : "Connect an SSH host to inspect policy and enforcement evidence.")
                    .font(.dsSansPt(13))
                    .foregroundStyle(t.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .conduitGlassChrome(cornerRadius: 14)
        .onTapGesture { if !actions.isConnected { onOpenFleet() } }
        .accessibilityAddTraits(actions.isConnected ? [] : .isButton)
    }

    private func providerRow(_ key: AgentKey, name: String) -> some View {
        HStack(spacing: 12) {
            AgentIdentityBadge(agent: key, dark: false)
            Text(name)
                .font(.dsSansPt(16, weight: .medium))
                .foregroundStyle(t.text)
            Spacer()
            Text(actions.isConnected ? "Policy capable" : "Connect to verify")
                .font(.dsSansPt(12))
                .foregroundStyle(actions.isConnected ? t.ok : t.text3)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 56)
    }

    private func latestEventRow(_ event: AuditLogEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(event.action.replacingOccurrences(of: "_", with: " "), systemImage: "shield.lefthalf.filled")
                    .font(.dsSansPt(15, weight: .semibold))
                    .foregroundStyle(t.text)
                Spacer()
                Text(event.timestamp)
                    .font(.dsMonoPt(10))
                    .foregroundStyle(t.text4)
                    .lineLimit(1)
            }
            if let command = event.command, !command.isEmpty {
                Text(command)
                    .font(.dsMonoPt(12))
                    .foregroundStyle(t.text2)
                    .lineLimit(2)
            }
            if let rule = event.rule, !rule.isEmpty {
                Text("Rule: \(rule)")
                    .font(.dsSansPt(12))
                    .foregroundStyle(t.text3)
            }
        }
        .padding(14)
    }

    private func loadProof() async {
        guard actions.isConnected else {
            policySummary = "Connect an SSH host to inspect policy"
            latestEvent = nil
            loadError = nil
            return
        }
        do {
            async let yaml = actions.loadPolicyYAML()
            async let events = actions.tailAudit(1)
            let policy = try await yaml
            let auditEvents = try await events
            latestEvent = auditEvents.first
            policySummary = Self.summary(for: policy)
            loadError = nil
        } catch {
            loadError = "Couldn’t load current enforcement proof."
        }
    }

    private static func summary(for yaml: String) -> String {
        let rules = yaml.components(separatedBy: .newlines).filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("- ") }.count
        return rules == 0 ? "Policy is loaded" : "\(rules) rule\(rules == 1 ? "" : "s") active"
    }
}
#endif
