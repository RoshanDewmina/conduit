#if DEBUG && os(iOS)
import SwiftUI
import ConduitCore
import DesignSystem

// MARK: - Combined pages review (launch with SIMCTL_CHILD_CONDUIT_GALLERY=pages)

struct PageReviewScreen: View {
    @Environment(\.conduitTokens) private var t

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                pageBlock("Hosts") { HostsReviewContent() }
                pageBlock("Inbox") { InboxReviewContent() }
                pageBlock("Settings") { SettingsReviewContent() }
            }
        }
        .background(t.bg)
    }

    private func pageBlock<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(.dsMonoPt(11, weight: .medium))
                .tracking(1.2)
                .foregroundStyle(t.text3)
                .padding(.horizontal, 16)
                .padding(.top, 24)
                .padding(.bottom, 10)
            content()
            Rectangle().fill(t.border).frame(height: 1).padding(.top, 20)
        }
    }
}

// MARK: - Individual screens (hosts / inbox / settings)

struct HostsReviewScreen: View {
    @Environment(\.conduitTokens) private var t

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageReviewHeader(title: "Hosts", subtitle: "Manage your SSH connections")
                HostsReviewContent()
            }
        }
        .background(t.bg)
    }
}

struct InboxReviewScreen: View {
    @Environment(\.conduitTokens) private var t

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageReviewHeader(title: "Inbox", subtitle: "Agent approvals & activity")
                InboxReviewContent()
            }
        }
        .background(t.bg)
    }
}

struct SettingsReviewScreen: View {
    @Environment(\.conduitTokens) private var t

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageReviewHeader(title: "Settings", subtitle: "Preferences & billing")
                SettingsReviewContent()
            }
        }
        .background(t.bg)
    }
}

// MARK: - Shared header

private struct PageReviewHeader: View {
    let title: String
    let subtitle: String
    @Environment(\.conduitTokens) private var t

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.dsDisplayPt(28, weight: .bold))
                .foregroundStyle(t.text)
            Text(subtitle)
                .font(.dsMonoPt(11))
                .foregroundStyle(t.text3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }
}

// MARK: - Hosts content

private struct HostsReviewContent: View {
    @Environment(\.conduitTokens) private var t
    @State private var search = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                DSSearchField(text: $search, placeholder: "Search hosts…")
                DSButton("ADD HOST", icon: .plus, variant: .primary, size: .sm, mono: true, action: {})
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            DSListSectionHead("PRODUCTION", count: 3)
            VStack(spacing: 8) {
                DSHostRow(name: "Prod EU", address: "ubuntu@prod-eu.example.com", initials: "PE",
                          status: .connected, agentCount: 1, lastConnected: "2m ago", onTap: {})
                DSHostRow(name: "Prod US", address: "ubuntu@prod-us.example.com", initials: "PU",
                          status: .agentRunning, pendingApprovals: 2, agentCount: 2,
                          lastConnected: "now", onTap: {})
                DSHostRow(name: "Prod APAC", address: "ubuntu@prod-apac.example.com", initials: "PA",
                          status: .reconnecting, lastConnected: "12m ago", onTap: {})
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            DSListSectionHead("STAGING", count: 2)
                .padding(.top, 16)
            VStack(spacing: 8) {
                DSHostRow(name: "Staging", address: "ubuntu@staging.example.com", initials: "ST",
                          status: .disconnected, lastConnected: "1h ago", onTap: {})
                DSHostRow(name: "Dev Box", address: "ubuntu@dev.example.com", initials: "DB",
                          status: .agentRunning, agentCount: 1, lastConnected: "5m ago", onTap: {})
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)

            Rectangle().fill(t.border).frame(height: 1)
            Text("EMPTY STATE")
                .font(.dsMonoPt(11, weight: .medium))
                .tracking(1.2)
                .foregroundStyle(t.text3)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 10)
            DSEmptyState(icon: .server, title: "No hosts yet",
                         subtitle: "Add your first SSH host to get started.",
                         action: ("ADD HOST", {}))
                .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Inbox content

private struct InboxReviewContent: View {
    @Environment(\.conduitTokens) private var t

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DSListSectionHead("PENDING", count: 3)
            VStack(spacing: 12) {
                DSApprovalCard(
                    agentKey: .claudeCode, risk: 3, timeLabel: "2m",
                    agentName: "Claude Code", action: "delete files",
                    hostLabel: "prod-eu · ~/training",
                    command: "rm -rf ~/training/checkpoints/*",
                    onDeny: {}, onAllowAlways: {}, onApprove: {}
                )
                DSApprovalCard(
                    agentKey: .codex, risk: 1, timeLabel: "14m",
                    agentName: "Codex", action: "run tests",
                    hostLabel: "dev-box · ~/repo",
                    command: "make test",
                    onViewDiff: {},
                    onDeny: {}, onAllowAlways: {}, onApprove: {}
                )
                DSApprovalCard(
                    agentKey: .claudeCode, risk: 0, timeLabel: "32m",
                    agentName: "Claude Code", action: "view diff",
                    hostLabel: "staging · ~/app",
                    onViewDiff: {},
                    onDeny: {}, onAllowAlways: {}, onApprove: {}
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Rectangle().fill(t.border).frame(height: 1)
            DSListSectionHead("DECIDED", count: 2)
            VStack(spacing: 8) {
                InboxDecidedRow(agentKey: .claudeCode, command: "git push origin main",
                                host: "Prod EU", time: "1h", approved: true)
                InboxDecidedRow(agentKey: .codex, command: "npm run build",
                                host: "Dev Box", time: "2h", approved: false)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Rectangle().fill(t.border).frame(height: 1)
            Text("EMPTY STATE")
                .font(.dsMonoPt(11, weight: .medium))
                .tracking(1.2)
                .foregroundStyle(t.text3)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 10)
            DSEmptyState(icon: .inbox, title: "All clear",
                         subtitle: "No pending approvals. Go ship something.")
                .frame(maxWidth: .infinity)
                .padding(.bottom, 8)
        }
    }
}

private struct InboxDecidedRow: View {
    let agentKey: AgentKey
    let command: String
    let host: String
    let time: String
    let approved: Bool

    @Environment(\.conduitTokens) private var t

    var body: some View {
        HStack(spacing: 12) {
            AgentIdentityBadge(agent: agentKey, label: nil)
            VStack(alignment: .leading, spacing: 3) {
                Text(command)
                    .font(.dsMonoPt(12, weight: .medium))
                    .foregroundStyle(t.text)
                    .lineLimit(1)
                Text(host)
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text3)
            }
            Spacer()
            HStack(spacing: 6) {
                Text(time)
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text4)
                DSChip(approved ? "APPROVED" : "DENIED",
                       tone: approved ? .ok : .danger,
                       style: approved ? .solid : .soft)
            }
        }
        .padding(12)
        .background(t.surface)
        .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: t.r3, style: .continuous)
            .strokeBorder(t.border, lineWidth: 1))
    }
}

// MARK: - Settings content

private struct SettingsReviewContent: View {
    @Environment(\.conduitTokens) private var t

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            settingsSection("AI PROVIDER") {
                settingsRow("Claude Code", badge: "ACTIVE", tone: .ok)
                settingsDivider
                settingsRow("Codex")
                settingsDivider
                settingsRow("Cursor")
            }

            settingsSection("API KEYS") {
                settingsRow("Anthropic", detail: "sk-ant-•••6f2a", badge: "SET", tone: .ok)
                settingsDivider
                settingsRow("OpenAI", detail: "sk-•••••••", badge: "SET", tone: .neutral)
            }

            settingsSection("APPEARANCE") {
                settingsRow("System", badge: "SELECTED", tone: .accent)
                settingsDivider
                settingsRow("Light")
                settingsDivider
                settingsRow("Dark")
            }

            settingsSection("SYNC") {
                HStack(spacing: 12) {
                    DSStatusDot(tone: .ok, size: 10)
                    Text("iCloud Sync")
                        .font(.dsSansPt(15))
                        .foregroundStyle(t.text)
                    Spacer()
                    Text("Just now")
                        .font(.dsMonoPt(11))
                        .foregroundStyle(t.text3)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }

            settingsSection("BILLING") {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Pro Plan")
                            .font(.dsSansPt(15, weight: .semibold))
                            .foregroundStyle(t.text)
                        Text("All features unlocked.")
                            .font(.dsMonoPt(11))
                            .foregroundStyle(t.text3)
                    }
                    Spacer()
                    DSChip("PRO", tone: .accent, style: .solid)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }

    private func settingsSection<C: View>(_ head: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(head)
                .font(.dsMonoPt(11))
                .tracking(0.8)
                .foregroundStyle(t.text3)
                .padding(.horizontal, 4)
            VStack(spacing: 0) { content() }
                .background(t.surface)
                .clipShape(RoundedRectangle(cornerRadius: t.r4, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: t.r4, style: .continuous)
                    .strokeBorder(t.border, lineWidth: 1))
        }
    }

    private func settingsRow(
        _ label: String,
        detail: String? = nil,
        badge: String? = nil,
        tone: DSChipTone = .neutral
    ) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.dsSansPt(15))
                .foregroundStyle(t.text)
            if let d = detail {
                Text(d)
                    .font(.dsMonoPt(12))
                    .foregroundStyle(t.text3)
            }
            Spacer()
            if let b = badge {
                DSChip(b, tone: tone, variant: .solid, size: .sm)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var settingsDivider: some View {
        Rectangle().fill(t.divider).frame(height: 1).padding(.leading, 16)
    }
}
#endif
