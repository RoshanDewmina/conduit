#if DEBUG && os(iOS)
import SwiftUI
import ConduitCore
import DesignSystem
import WorkspacesFeature
import PersistenceKit
import SecurityKit

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

            settingsSection("ABOUT CONDUIT") {
                aboutSettingsRow(icon: "server.rack", title: "BYO host",
                    detail: "Connect to any SSH server you own or rent. Conduit does not provision or manage your infrastructure.")
                settingsDivider
                aboutSettingsRow(icon: "key", title: "BYO API key",
                    detail: "Your Anthropic or OpenAI key is stored in the device Keychain and sent directly to the provider.")
                settingsDivider
                aboutSettingsRow(icon: "person.badge.minus", title: "No account required",
                    detail: "No Conduit login. No subscription. All session data stays on-device.")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }

    private func aboutSettingsRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(t.accent)
                .frame(width: 20, alignment: .center)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.dsSansPt(14, weight: .semibold))
                    .foregroundStyle(t.text)
                Text(detail)
                    .font(.dsSansPt(13))
                    .foregroundStyle(t.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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

// MARK: - Isolated About section gallery (CONDUIT_GALLERY=settings-about)

struct SettingsAboutGalleryScreen: View {
    @Environment(\.conduitTokens) private var t

    var body: some View {
        ZStack {
            t.bg.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                Text("ABOUT CONDUIT")
                    .font(.dsMonoPt(11))
                    .tracking(0.8)
                    .foregroundStyle(t.text3)
                    .padding(.horizontal, 20)
                    .padding(.top, 60)
                    .padding(.bottom, 8)

                VStack(alignment: .leading, spacing: 0) {
                    aboutRow(icon: "server.rack", title: "BYO host",
                        detail: "Connect to any SSH server you own or rent. Conduit does not provision or manage your infrastructure.")
                    Rectangle().fill(t.divider).frame(height: 1).padding(.leading, 52)
                    aboutRow(icon: "key", title: "BYO API key",
                        detail: "Your Anthropic or OpenAI key is stored in the device Keychain and sent directly to the provider.")
                    Rectangle().fill(t.divider).frame(height: 1).padding(.leading, 52)
                    aboutRow(icon: "person.badge.minus", title: "No account required",
                        detail: "No Conduit login. No subscription. All session data stays on-device.")
                }
                .background(t.surface)
                .clipShape(RoundedRectangle(cornerRadius: t.r4, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: t.r4, style: .continuous).strokeBorder(t.border, lineWidth: 1))
                .padding(.horizontal, 16)

                Text("Keys are stored on-device (Keychain) and sent directly to the provider over TLS — never to Conduit servers.")
                    .font(.dsSansPt(12))
                    .foregroundStyle(t.text3)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                Spacer()
            }
        }
    }

    private func aboutRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(t.accent)
                .frame(width: 20, alignment: .center)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.dsSansPt(14, weight: .semibold))
                    .foregroundStyle(t.text)
                Text(detail)
                    .font(.dsSansPt(13))
                    .foregroundStyle(t.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Library gallery (CONDUIT_GALLERY=library)

struct LibraryGalleryScreen: View {
    @Environment(\.conduitTokens) private var t

    var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                DSScreenHeader("library", breadcrumb: "your toolkit", spectrumMode: .idle) {
                    DSIconButton(.plus) {}
                }
                ScrollView {
                    VStack(spacing: 16) {
                        LazyVGrid(
                            columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                            spacing: 12
                        ) {
                            DSCategoryCard(icon: .list,     count: "12", label: "Snippets",  subtitle: "reusable commands")
                            DSCategoryCard(icon: .key,      count: "3",  label: "SSH Keys",  subtitle: "enclave-backed")
                            DSCategoryCard(icon: .diff,     count: "4",  label: "Workflows", subtitle: "multi-step runs")
                            DSCategoryCard(icon: .sparkles, count: "2",  label: "Agents",    subtitle: "claude · codex")
                        }
                        VStack(spacing: 0) {
                            DSListSectionHead("RECENT")
                            DSSnippetRow(name: "deploy --prod", body: "git push && ssh prod ./deploy.sh", useCount: 14) {}
                            DSDivider()
                            DSSnippetRow(name: "tail logs", body: "tail -f /var/log/app.log", useCount: 8) {}
                            DSDivider()
                            DSSnippetRow(name: "db backup", body: "pg_dump $DB_URL > backup.sql", useCount: 3) {}
                            DSDivider()
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
            }
        }
    }
}

// MARK: - AddHost gallery (CONDUIT_GALLERY=addhost)
//
// Renders AddHostView with an in-memory HostRepository and KeyStore so the
// paste-to-parse, clipboard-sniff banner, and key-gen card are all inspectable
// without any real SSH host or Keychain access.

struct AddHostGalleryScreen: View {
    @Environment(\.conduitTokens) private var t

    // In-memory deps — no real DB or Keychain (try! is safe in DEBUG-only gallery)
    private let mockRepo = HostRepository(try! AppDatabase.inMemory())
    private let mockKeyStore = KeyStore(inMemory: true)

    @State private var connectLog: String? = nil

    var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()
            AddHostView(
                repository: mockRepo,
                keyStore: mockKeyStore,
                onCancel: { connectLog = "cancelled" },
                onConnectAndSave: { host in
                    connectLog = "connect & save → \(host.name)"
                }
            )

            // Toast overlay to confirm actions in the gallery
            if let log = connectLog {
                VStack {
                    Spacer()
                    Text(log)
                        .font(.dsMonoPt(12))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.75))
                        .clipShape(Capsule())
                        .padding(.bottom, 40)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                        withAnimation { connectLog = nil }
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: connectLog)
    }
}

// MARK: - PersistentStatusBar gallery (CONDUIT_GALLERY=statusbar)

struct PersistentStatusBarGalleryScreen: View {
    @Environment(\.conduitTokens) private var t

    private static let idle:     [AgentInfo] = []
    private static let working:  [AgentInfo] = [AgentInfo(name: "claude", agentKey: .claudeCode, host: "prod-api",   cwd: "~/web",   state: .streaming)]
    private static let approval: [AgentInfo] = [AgentInfo(name: "claude", agentKey: .claudeCode, host: "gpu-box",    cwd: "~/train", state: .approval)]
    private static let error:    [AgentInfo] = [AgentInfo(name: "claude", agentKey: .claudeCode, host: "mac-studio", cwd: "~/proj",  state: .error)]

    var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                DSScreenHeader("statusbar", breadcrumb: "all states")
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        stateBlock("idle (no session)", agents: Self.idle)
                        stateBlock("working · streaming", agents: Self.working)
                        stateBlock("needs approval", agents: Self.approval)
                        stateBlock("error · reconnect", agents: Self.error)
                    }
                    .padding(16)
                }
            }
        }
    }

    @ViewBuilder
    private func stateBlock(_ label: String, agents: [AgentInfo]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label.uppercased())
                .font(.dsMonoPt(11))
                .foregroundStyle(t.text3)
                .tracking(0.8)
            PersistentStatusBar(agents: agents, onTap: {}, onReconnect: agents.first?.state == .error ? {} : nil)
                .background(t.surface)
        }
    }
}
#endif
