#if DEBUG && os(iOS)
import SwiftUI
import ConduitCore
import DesignSystem
import SessionFeature
import InboxFeature
import TerminalEngine
import OnboardingFeature
import DiffFeature
import DiffKit
import FilesFeature
import WorkspacesFeature
import PersistenceKit
import SecurityKit
import SettingsFeature

// UI-audit harness. Routed from AppRoot when SIMCTL_CHILD_CONDUIT_GALLERY is set.
struct DebugGalleryView: View {
    let route: String
    @Environment(\.conduitTokens) private var t
    @State private var showLiveTerminal = false
    @State private var showBlocks = false
    @State private var showLiveSession = false
    @State private var showAgentHUD = false
    @State private var showTypedInbox = false
    @State private var showFeatures = false

    var body: some View {
        switch route {
        case "orb-connecting": SSHConnectOverlay(phase: .connecting)
        case "orb-connected":  OrbConnectedDemo()
        case "orb-slow":       SSHConnectOverlay(phase: .slow(message: "Still connecting…"))
        case "orb-failed":     SSHConnectOverlay(phase: .failed(message: "Can't find host \"example.invalid\". Check the hostname."))
        case "orb-phases":     OrbPhasesDemo()
        case "onboarding":     OnboardingView(onContinue: {}, onSetupWorkspace: {})
        case "onboarding-b":   OnboardingView(onContinue: {}, onSetupWorkspace: {})
        case "diff":           DiffView(diff: UnifiedDiffParser.parse(Self.sampleDiff))
        case "filepreview":    FilePreviewView(filename: "Tokens.swift", content: Self.sampleFile)
        case "chat":           chatGallery
        case "components":     fullComponentCatalog
        case "pages":          PageReviewScreen()
        case "hosts":          HostsReviewScreen()
        case "inbox":          InboxReviewScreen()
        case "settings":       SettingsReviewScreen()
        case "settings-about": SettingsAboutGalleryScreen()
        case "blocks":         BlocksReviewScreen()
        case "session":        DebugSessionHarness()
        case "hud":            AgentHUDGalleryScreen()
        case "statusheader":   AgentStatusHeaderGalleryScreen()
        case "keyboard":       KeyboardGalleryScreen()
        case "inbox-typed":    TypedInboxGalleryScreen()
        case "features":       FeaturesGalleryScreen()
        case "library":        LibraryGalleryScreen()
        case "statusbar":      PersistentStatusBarGalleryScreen()
        case "addhost":        AddHostGalleryScreen()
        case "paywall":        PaywallSheet(featureName: "partial-hunk diff review")
        case "compare":        PremiumComparisonView()
        case "billing":        BillingView()
        // Phase 5 management screens
        case "mgmt-hostdetail":   MgmtGalleryHostDetail()
        case "mgmt-agentpolicy":  AgentPolicyView()
        case "mgmt-agents":       AgentListView()
        case "mgmt-vmlist":       VMListView()
        case "mgmt-vmdetail":     VMDetailView(vm: ManagementMocks.vms[0])
        case "mgmt-keys":         MgmtGalleryKeys()
        case "mgmt-snippets":     MgmtGallerySnippets()
        case "mgmt-workflow":     WorkflowBuilderView()
        case "mgmt-diagnostics":  DiagnosticsView()
        case "mgmt-commandbar":   CommandBarView(onConnect: { _ in }, onOpenInbox: {}, onRunSnippet: {}, onNewWorkspace: {}, onDismiss: {})
        // Phase 6 state atoms
        case "states":         StatesGalleryScreen()
        #if os(iOS)
        case "cc-policy":      CCPolicyGalleryScreen()
        case "cc-inbox":       CCInboxGalleryScreen()
        case "cc-usage":       CCUsageGalleryScreen()
        #endif
        case "review":         reviewScreen
        default:               reviewScreen
        }
    }

    // MARK: - Reskin review screen (before/after + populated mocks + full library)

    private var reviewScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                reviewHeader

                reviewBlock("Sessions — populated · live states") {
                    populatedSessions
                }

                reviewBlock("Inbox — activity card (proposed)") {
                    activityCardDemo
                }

                reviewBlock("Before  →  After") {
                    beforeAfterStrip
                }

                reviewBlock("Pro components") {
                    proComponentsPanel
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                }

                Text("Full component library → relaunch with CONDUIT_GALLERY=components")
                    .font(.dsMonoPt(10))
                    .foregroundStyle(t.text4)
                    .padding(16)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(t.bg)
        .fullScreenCover(isPresented: $showLiveTerminal) {
            liveTerminalCover
        }
        .fullScreenCover(isPresented: $showBlocks) {
            ZStack(alignment: .topTrailing) {
                BlocksReviewScreen()
                Button { showBlocks = false } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(12)
                }
            }
        }
        .fullScreenCover(isPresented: $showLiveSession) {
            ZStack(alignment: .topTrailing) {
                DebugSessionHarness()
                Button { showLiveSession = false } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(12)
                }
            }
        }
        .fullScreenCover(isPresented: $showAgentHUD) {
            ZStack(alignment: .topTrailing) {
                AgentHUDGalleryScreen()
                Button { showAgentHUD = false } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(12)
                }
            }
        }
        .fullScreenCover(isPresented: $showTypedInbox) {
            ZStack(alignment: .topTrailing) {
                TypedInboxGalleryScreen()
                Button { showTypedInbox = false } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(.white.opacity(0.4))
                        .padding(12)
                }
            }
        }
        .fullScreenCover(isPresented: $showFeatures) {
            ZStack(alignment: .topTrailing) {
                FeaturesGalleryScreen()
                Button { showFeatures = false } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(.white.opacity(0.4))
                        .padding(12)
                }
            }
        }
    }

    private var reviewHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Reskin Review")
                .font(.dsDisplayPt(28, weight: .bold))
                .foregroundStyle(t.text)
            Text("Refined-clean direction · crisp borders + pro craft")
                .font(.dsMonoPt(11))
                .foregroundStyle(t.text3)

            ScrollView(.horizontal, showsIndicators: false) {
              HStack(spacing: 8) {
                DSButton(
                    "Live SSH Terminal",
                    systemImage: "terminal",
                    variant: .accent,
                    size: .sm,
                    mono: true
                ) { showLiveTerminal = true }

                DSButton(
                    "Block Transcript",
                    systemImage: "rectangle.stack",
                    variant: .secondary,
                    size: .sm,
                    mono: true
                ) { showBlocks = true }

                DSButton(
                    "Live Session",
                    systemImage: "bolt.horizontal",
                    variant: .secondary,
                    size: .sm,
                    mono: true
                ) { showLiveSession = true }

                DSButton(
                    "Agent HUD",
                    systemImage: "square.grid.3x3",
                    variant: .secondary,
                    size: .sm,
                    mono: true
                ) { showAgentHUD = true }

                DSButton(
                    "Typed Inbox",
                    systemImage: "tray.2",
                    variant: .secondary,
                    size: .sm,
                    mono: true
                ) { showTypedInbox = true }

                DSButton(
                    "Features",
                    systemImage: "sparkles",
                    variant: .accent,
                    size: .sm,
                    mono: true
                ) { showFeatures = true }
              }
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    /// Full-screen live terminal launched from the review screen. Reuses the
    /// env-driven `DebugTerminalHarness` (auto-trusts the first host key) and
    /// adds a close affordance, since `fullScreenCover` has no built-in chrome.
    private var liveTerminalCover: some View {
        ZStack(alignment: .topTrailing) {
            DebugTerminalHarness()
            Button { showLiveTerminal = false } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(12)
            }
        }
    }

    // Single-tone titled block on the page bg
    private func reviewBlock<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
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

    // MARK: Populated sessions (mirrors the v2 Sessions mock; every live state shown)

    private var populatedSessions: some View {
        VStack(spacing: 0) {
            DSListSectionHead("ACTIVE", count: 3)
            ReviewSessionRow(name: "Prod EU", agent: .claudeCode, subtitle: "I'll check the deployment status now…",
                             time: "2m", state: .thinking, unread: 3, live: true)
            reviewDivider
            ReviewSessionRow(name: "Dev Box", agent: .codex, subtitle: "Writing the patch for SessionViewModel…",
                             time: "14m", state: .streaming, unread: 0, live: true)
            reviewDivider
            ReviewSessionRow(name: "GPU Box", agent: .claudeCode, subtitle: "Needs approval · delete training/chec…",
                             time: "32m", state: .approval, unread: 1, live: true)
            Rectangle().fill(t.border).frame(height: 1)
            DSListSectionHead("RECENT")
            ReviewSessionRow(name: "Staging", agent: .unknown, subtitle: "All tests passed · exit 0",
                             time: "1h", state: .done, unread: 0, live: false)
            reviewDivider
            ReviewSessionRow(name: "AWS Tokyo", agent: .unknown, subtitle: "Session ended · reconnect to continue",
                             time: "3h", state: .offline, unread: 0, live: false)
            reviewDivider
            ReviewSessionRow(name: "Local Dev", agent: .claudeCode, subtitle: "Build failed · 2 errors",
                             time: "5h", state: .error, unread: 7, live: false)
        }
    }

    private var reviewDivider: some View {
        Rectangle().fill(t.divider).frame(height: 1).padding(.leading, 74)
    }

    // MARK: Inbox activity card (the 4th/5th-shot item, refined-clean)

    private var activityCardDemo: some View {
        VStack(spacing: 14) {
            ReviewActivityItem(
                host: "Prod EU", agent: .claudeCode, agentName: "Claude Code",
                action: "wants to run on", time: "2m",
                kind: .approval(command: "rm -rf ~/training/checkpoints/*")
            )
            ReviewActivityItem(
                host: "Dev Box", agent: .codex, agentName: "Codex",
                action: "finished on", time: "14m",
                kind: .done(result: "All 163 tests passed.", exit: 0)
            )
            ReviewActivityItem(
                host: "GPU Box", agent: .claudeCode, agentName: "Claude Code",
                action: "hit an error on", time: "32m",
                kind: .error(message: "make: *** [test] Error 1 — 2 tests failed")
            )
        }
        .padding(.horizontal, 16)
    }

    // MARK: Before → After craft strip

    private var beforeAfterStrip: some View {
        VStack(spacing: 0) {
            beforeAfterRow("Inline link",
                before: AnyView(Text("Gulf Oil Ltd.").font(.dsSansPt(14)).foregroundStyle(t.text)),
                after:  AnyView(DSLink("Gulf Oil Ltd.")))
            beforeAfterRow("Status transition",
                before: AnyView(Text("primary → secondary").font(.dsSansPt(13)).foregroundStyle(t.text2)),
                after:  AnyView(DSDiffChips(from: "PRIMARY", to: "SECONDARY")))
            beforeAfterRow("Button microcopy",
                before: AnyView(DSButton("Reply", variant: .secondary, size: .sm, action: {})),
                after:  AnyView(DSButton("REPLY", variant: .secondary, size: .sm, mono: true, action: {})))
            beforeAfterRow("Quoted context",
                before: AnyView(Text("Gulf EV Products — table entry / relevance")
                    .font(.dsSansPt(13)).foregroundStyle(t.text3)),
                after:  AnyView(DSQuoteBlock(title: "Gulf EV Products", tags: ["TABLE ENTRY", "RELEVANCE"])))
        }
        .padding(.horizontal, 16)
    }

    private func beforeAfterRow(_ label: String, before: AnyView, after: AnyView) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.dsSansPt(12, weight: .medium))
                .foregroundStyle(t.text2)
            HStack(alignment: .center, spacing: 0) {
                VStack { before }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(t.surface2)
                    .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))
                DSIconView(.arrowRight, size: 16, color: t.text4)
                    .padding(.horizontal, 8)
                VStack { after }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(t.surface)
                    .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: t.r3, style: .continuous).strokeBorder(t.border, lineWidth: 1))
            }
        }
        .padding(.vertical, 8)
    }

    private var proComponentsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            DSDiffChips(from: "PRIMARY", to: "SECONDARY")
            DSQuoteBlock(title: "Gulf EV Products", tags: ["TABLE ENTRY", "RELEVANCE"],
                         message: "This brand is secondary, not primary.")
            DSLink("Gulf Oil Ltd.")
        }
    }

    // MARK: - Full component catalog (both light + dark)

    private var fullComponentCatalog: some View {
        ScrollView {
            VStack(spacing: 0) {
                catalogSection("Buttons") { buttonsPanel }
                catalogSection("Chips & Badges") { chipsPanel }
                catalogSection("Status & Progress") { statusPanel }
                catalogSection("Avatars & Pixel") { avatarsPanel }
                catalogSection("Block Cards") { blockCardsPanel }
                catalogSection("Chat Bubbles") { chatBubblesPanel }
                catalogSection("List Components") { listComponentsPanel }
                catalogSection("Inputs") { inputsPanel }
            }
        }
        .background(t.bg)
        .navigationTitle("Component Gallery")
    }

    // Each section renders light + dark side by side
    private func catalogSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(.dsMonoPt(11))
                .tracking(1)
                .foregroundStyle(t.text3)
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 8)
            HStack(alignment: .top, spacing: 0) {
                // Light half
                content()
                    .environment(\.conduitTokens, .light)
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .background(ConduitTokens.light.bg)
                // Dark half
                content()
                    .environment(\.conduitTokens, .dark)
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .background(ConduitTokens.dark.bg)
            }
            Rectangle().fill(t.border).frame(height: 1)
        }
    }

    // MARK: - Buttons

    private var buttonsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                DSButton("Primary", variant: .primary, size: .sm, action: {})
                DSButton("Accent", variant: .accent, size: .sm, action: {})
            }
            HStack(spacing: 6) {
                DSButton("Secondary", variant: .secondary, action: {})
                DSButton("Ghost", variant: .ghost, action: {})
            }
            HStack(spacing: 6) {
                DSButton("Delete", variant: .destructive, action: {})
                DSButton("Loading", variant: .primary, isLoading: true, action: {})
            }
            HStack(spacing: 6) {
                DSButton("Large", variant: .primary, size: .lg, action: {})
            }
            HStack(spacing: 6) {
                DSButton("Add", icon: .plus, variant: .primary, size: .sm, action: {})
                DSButton("", icon: .settings, variant: .ghost, iconOnly: true, action: {})
                DSButton("Disabled", variant: .secondary, action: {}).disabled(true)
            }
        }
    }

    // MARK: - Chips & Badges

    private var chipsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                DSChip("accent", tone: .accent, style: .solid)
                DSChip("ok", tone: .ok, style: .solid)
                DSChip("warn", tone: .warn, style: .solid)
            }
            HStack(spacing: 6) {
                DSChip("danger", tone: .danger, style: .solid)
                DSChip("info", tone: .info, style: .solid)
                DSChip("neutral", tone: .neutral, style: .solid)
            }
            HStack(spacing: 6) {
                DSChip("soft", tone: .accent, style: .soft)
                DSChip("outlined", tone: .ok, style: .outlined)
                DSChip("mono", tone: .neutral, style: .mono)
            }
            HStack(spacing: 6) {
                RiskBadge(risk: 0)
                RiskBadge(risk: 1)
                RiskBadge(risk: 2)
                RiskBadge(risk: 3)
            }
            HStack(spacing: 6) {
                AgentIdentityBadge(agent: .claudeCode, label: "Claude")
                AgentIdentityBadge(agent: .codex, label: nil)
                AgentIdentityBadge(agent: .cursor, label: nil)
            }
            HStack(spacing: 6) {
                ForEach(AgentState.allCases, id: \.self) { AgentBadge($0) }
            }
        }
    }

    // MARK: - Status & Progress

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ForEach([DSStatusDotTone.ok, .warn, .danger, .accent, .info, .off], id: \.self) { tone in
                    VStack(spacing: 4) {
                        DSStatusDot(tone: tone, size: 10)
                        DSStatusDot(tone: tone, pulse: true, size: 10)
                    }
                }
            }
            HStack(spacing: 8) {
                DSExitChip(code: 0)
                DSExitChip(code: 1)
                DSExitChip(code: 130)
            }
            DSProgressBar(value: 0.65)
            DSProgressSegmented(total: 8, done: 5)
            HStack(spacing: 8) {
                PixelBox(state: .streaming, size: 5, gap: 1)
                PixelBox(state: .thinking, size: 5, gap: 1)
                PixelBox(state: .done, size: 5, gap: 1)
                PixelBox(state: .error, size: 5, gap: 1)
                PixelBox(state: .offline, size: 5, gap: 1)
            }
        }
    }

    // MARK: - Avatars & Pixel

    private var avatarsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                PixelAvatar(seed: "ubuntu@dev", size: 36)
                PixelAvatar(seed: "staging", size: 36)
                PixelAvatar(seed: "raspberry", size: 36)
                PixelAvatar(seed: "prod-db", size: 36)
            }
            HStack(spacing: 8) {
                PixelAvatar(seed: "conduit-lock", size: 24)
                PixelAvatar(seed: "conduit-lock", size: 36)
                PixelAvatar(seed: "conduit-lock", size: 48)
                PixelAvatar(seed: "conduit-lock", size: 60)
            }
        }
    }

    // MARK: - Block Cards

    private var blockCardsPanel: some View {
        VStack(spacing: 8) {
            DSBlockCard(state: .executing, command: "swift build") {
                Text("Compiling…").font(.dsMonoPt(12)).foregroundColor(.green)
            }
            DSBlockCard(state: .doneOk, command: "git status", exitCode: 0, duration: "0.4s") {
                Text("nothing to commit").font(.dsMonoPt(12)).foregroundColor(.green)
            }
            DSBlockCard(state: .doneErr, command: "make test", exitCode: 1, duration: "1.2s") {
                Text("2 tests failed").font(.dsMonoPt(12)).foregroundColor(.red)
            }
        }
    }

    // MARK: - Chat Bubbles

    private var chatBubblesPanel: some View {
        VStack(spacing: 8) {
            DSMessageBubble("Run the test suite.", sender: .user)
            DSMessageBubble("Running `swift test`…", sender: .agent)
            DSSystemEvent("Session resumed")
        }
    }

    // MARK: - List Components

    private var listComponentsPanel: some View {
        VStack(spacing: 0) {
            DSListSectionHead("SECTION", count: 3)
            DSEmptyState(
                icon: .inbox,
                title: "Nothing here",
                subtitle: "Add something to get started.",
                action: nil
            )
        }
    }

    // MARK: - Inputs

    @State private var searchDemo = ""

    private var inputsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            DSSearchField(text: $searchDemo, placeholder: "Search…")
            DSKey("⌘K")
        }
    }

    // MARK: - Chat hero (legacy route)

    private var chatGallery: some View {
        VStack(spacing: 0) {
            AgentStatusBar(
                state: .streaming,
                message: "running build",
                pendingApprovals: 1,
                tickValues: [0.2, 0.6, 0.9, 0.4, 0.7, 1.0, 0.3, 0.5]
            )
            ChatHeaderView(hostName: "ubuntu@dev", cwd: "~/repo/conduit", state: .streaming, onBack: {})
            ScrollView {
                VStack(spacing: 12) {
                    card(.success)
                    card(.running)
                    card(.error)
                    card(.idle)
                }
                .padding(14)
            }
            .background(t.surf0)
        }
        .background(t.surf0)
        .ignoresSafeArea(edges: .bottom)
    }

    private enum Demo { case success, running, error, idle }

    @ViewBuilder
    private func card(_ d: Demo) -> some View {
        let block = mockBlock(d)
        ToolCardView(
            block: block,
            render: AttributedString(block.joinedOutput),
            onExplain: {}, onRerun: {}, onCollapse: {}, onStar: {}
        ) { EmptyView() }
    }

    private func mockBlock(_ d: Demo) -> Block {
        let prompt = Block.PromptInfo(cwd: "~/repo/conduit", hostName: "ubuntu@dev")
        switch d {
        case .success:
            return Block(sessionID: SessionID(), prompt: prompt, command: "git status",
                         chunks: [BlockChunk(text: "On branch master\nnothing to commit\n", stream: .stdout)],
                         exitStatus: ExitStatus(code: 0), startedAt: Date().addingTimeInterval(-1.4),
                         finishedAt: Date(), state: .done(exitCode: 0))
        case .running:
            return Block(sessionID: SessionID(), prompt: prompt, command: "swift build",
                         chunks: [BlockChunk(text: "[3/42] Compiling DesignSystem\n", stream: .stdout)],
                         startedAt: Date().addingTimeInterval(-3), state: .executing)
        case .error:
            return Block(sessionID: SessionID(), prompt: prompt, command: "make test",
                         chunks: [BlockChunk(text: "error: 2 tests failed\n", stream: .stderr)],
                         exitStatus: ExitStatus(code: 1), startedAt: Date().addingTimeInterval(-0.8),
                         finishedAt: Date(), state: .done(exitCode: 1))
        case .idle:
            return Block(sessionID: SessionID(), prompt: prompt, command: "npm run dev",
                         isStarred: true, state: .promptEditing)
        }
    }
}

// MARK: - Sample data

extension DebugGalleryView {
    static let sampleDiff = """
    diff --git a/src/app.swift b/src/app.swift
    index 1a2b3c4..5d6e7f8 100644
    --- a/src/app.swift
    +++ b/src/app.swift
    @@ -1,5 +1,6 @@
     import SwiftUI
    -let title = "Old"
    +let title = "New"
    +let subtitle = "Added line"
     struct App {}
    """

    static let sampleFile = """
    import SwiftUI

    struct ConduitTokens {
        let accent: Color
        let surf0: Color
    }
    """
}

private struct OrbConnectedDemo: View {
    @State private var phase: SSHConnectPhase = .connecting
    var body: some View {
        SSHConnectOverlay(phase: phase)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { phase = .connected }
            }
    }
}

/// Gallery demo that cycles through all four connect phases:
/// connecting → slow → connected → failed.
/// Launch with CONDUIT_GALLERY=orb-phases.
private struct OrbPhasesDemo: View {
    @State private var phase: SSHConnectPhase = .connecting
    var body: some View {
        SSHConnectOverlay(phase: phase)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    phase = .slow(message: "Still connecting…")
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                    phase = .connected
                }
            }
    }
}

// MARK: - Review helpers

private struct ReviewSessionRow: View {
    let name: String
    let agent: AgentKey
    let subtitle: String
    let time: String
    let state: AgentState
    let unread: Int
    let live: Bool

    @Environment(\.conduitTokens) private var t

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                PixelAvatar(seed: name, size: 46)
                DSStatusDot(tone: dotTone, pulse: live && state != .done, size: 12)
                    .background(Circle().fill(t.bg).frame(width: 16, height: 16))
                    .offset(x: 2, y: 2)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(name)
                        .font(.dsSansPt(15, weight: .semibold))
                        .foregroundStyle(t.text)
                    if agent != .unknown {
                        AgentIdentityBadge(agent: agent, label: agentLabel)
                    }
                }
                Text(subtitle)
                    .font(.dsSansPt(13))
                    .foregroundStyle(t.text3)
                    .lineLimit(1)
            }
            Spacer()
            // Fixed-geometry right column: time on top, then [pixel grid][reserved
            // unread slot]. The unread slot is always allocated (even when empty) so
            // the pixel grid never shifts between rows.
            VStack(alignment: .trailing, spacing: 6) {
                Text(time)
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text3)
                HStack(spacing: 8) {
                    PixelBox(state: state, size: 5, gap: 1)
                    ZStack(alignment: .trailing) {
                        if unread > 0 {
                            Text("\(unread)")
                                .font(.dsMonoPt(11, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(t.accent)
                                .clipShape(Capsule())
                        }
                    }
                    .frame(width: 20, alignment: .trailing)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var agentLabel: String {
        switch agent {
        case .claudeCode: return "Claude Code"
        case .codex:      return "Codex"
        case .cursor:     return "Cursor"
        default:          return ""
        }
    }

    private var dotTone: DSStatusDotTone {
        switch state {
        case .thinking, .streaming: return .accent
        case .done:                 return .ok
        case .approval:             return .warn
        case .error:                return .danger
        case .offline:              return .off
        }
    }
}

private struct ReviewActivityItem: View {
    enum Kind {
        case approval(command: String)
        case done(result: String, exit: Int)
        case error(message: String)
    }

    let host: String
    let agent: AgentKey
    let agentName: String
    let action: String
    let time: String
    let kind: Kind

    @Environment(\.conduitTokens) private var t

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Host pixel avatar (kept — the look you preferred) + agent mark overlay.
            ZStack(alignment: .bottomTrailing) {
                PixelAvatar(seed: host, size: 38)
                ZStack {
                    RoundedRectangle(cornerRadius: 4).fill(agent.markColor).frame(width: 15, height: 15)
                    Text(agent.markLabel).font(.dsMonoPt(8, weight: .bold)).foregroundStyle(.white)
                }
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(t.surface, lineWidth: 1.5))
                .offset(x: 3, y: 3)
            }
            VStack(alignment: .leading, spacing: 10) {
                // Actor (agent) line + relative time
                HStack(alignment: .firstTextBaseline) {
                    Text("\(Text(agentName).font(.dsSansPt(14, weight: .semibold)).foregroundColor(t.text))\(Text(" \(action) ").font(.dsSansPt(14)).foregroundColor(t.text2))")
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Text(time)
                        .font(.dsMonoPt(11))
                        .foregroundStyle(t.text3)
                }
                DSLink(host)

                switch kind {
                case .approval(let command):
                    DSQuoteBlock(title: "bash", tags: ["DESTRUCTIVE"], message: command, tone: .accent)
                    HStack(spacing: 8) {
                        Spacer()
                        DSButton("DENY", variant: .destructive, size: .sm, mono: true, action: {})
                        DSButton("APPROVE", variant: .primary, size: .sm, mono: true, action: {})
                    }
                case .done(let result, let exit):
                    DSQuoteBlock(title: "result", message: result, tone: .ok)
                    HStack(spacing: 8) {
                        DSExitChip(code: exit)
                        Spacer()
                        DSButton("VIEW", variant: .secondary, size: .sm, mono: true, action: {})
                    }
                case .error(let message):
                    DSQuoteBlock(title: "error", tags: ["EXIT 1"], message: message, tone: .danger)
                    HStack(spacing: 8) {
                        Spacer()
                        DSButton("LOGS", variant: .ghost, size: .sm, mono: true, action: {})
                        DSButton("RETRY", variant: .secondary, size: .sm, mono: true, action: {})
                    }
                }
            }
        }
        .padding(14)
        .background(t.surface)
        .clipShape(RoundedRectangle(cornerRadius: t.r4, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: t.r4, style: .continuous).strokeBorder(t.border, lineWidth: 1))
    }
}

// MARK: - Block transcript review (CONDUIT_GALLERY=blocks)
//
// Renders the *real* ChatTranscriptView + ToolCardView against a mock
// BlockRenderer — no SSH. This is the canonical visual reference for the
// block experience, mirroring SessionView's HUD + header + transcript stack.

private struct BlocksReviewScreen: View {
    @Environment(\.conduitTokens) private var t
    @State private var renderer = BlockRenderer()
    @State private var built = false

    var body: some View {
        VStack(spacing: 0) {
            AgentStatusBar(
                state: .streaming,
                message: "tail -f /var/log/app.log",
                pendingApprovals: 1,
                tickValues: Self.mockTicks
            )
            ChatHeaderView(hostName: "Prod EU", cwd: "/srv/api", state: .streaming)
            ChatTranscriptView(
                blocks: renderer,
                onLiveBytes: { _ in },
                onLiveResize: { _, _ in },
                onExplain: { _ in },
                onRerun: { _ in },
                onCollapse: { renderer.toggleCollapsed(id: $0.id) },
                onStar: { renderer.toggleStarred(id: $0.id) }
            )
        }
        .background(t.surf0.ignoresSafeArea())
        .task {
            guard !built else { return }
            built = true
            Self.populate(renderer)
        }
    }

    private static let mockTicks: [Double] = [
        0.2, 0.5, 0.3, 0.8, 0.6, 0.4, 0.7, 0.9, 0.5, 0.3, 0.6, 0.8,
        0.4, 0.7, 0.5, 0.6, 0.3, 0.8, 0.5, 0.4, 0.7, 0.6, 0.5, 0.9,
    ]

    @MainActor
    private static func populate(_ r: BlockRenderer) {
        let sid = SessionID()

        func done(_ command: String, out: String, code: Int) {
            let id = r.begin(
                sessionID: sid,
                command: command,
                prompt: .init(cwd: "/srv/api", hostName: "Prod EU")
            )
            r.append(Data(out.utf8), stream: code == 0 ? .stdout : .stderr, to: id)
            r.finalize(id: id, exitCode: code)
        }

        // A currently-executing block (running/animated state) — at the top.
        let live = r.begin(
            sessionID: sid,
            command: "tail -f /var/log/app.log",
            prompt: .init(cwd: "/srv/api", hostName: "Prod EU")
        )
        r.append(
            Data("[12:01:04] GET /health 200 1ms\n[12:01:05] GET /v1/users 200 8ms".utf8),
            stream: .stdout, to: live
        )
        r.setState(.executing, for: live)

        // A starred success with short output.
        let gitID = r.begin(
            sessionID: sid,
            command: "git status",
            prompt: .init(cwd: "/srv/api", hostName: "Prod EU")
        )
        r.append(Data("On branch main\nnothing to commit, working tree clean".utf8), stream: .stdout, to: gitID)
        r.finalize(id: gitID, exitCode: 0)
        r.toggleStarred(id: gitID)

        // Success card (exit 0) — footer visible.
        done(
            "kubectl get pods -n api",
            out: "NAME             READY   STATUS    AGE\napi-7f8c-x42z    1/1     Running   5m",
            code: 0
        )

        // Error card (exit 1) — the key state, kept last so it's in view after
        // the transcript auto-scrolls to the bottom.
        done(
            "npm run build",
            out: "router.ts(42,7): error TS2322: Type 'string' not assignable to 'number'.\nBuild failed with 1 error.",
            code: 1
        )
    }
}

// MARK: - Agent Island gallery (CONDUIT_GALLERY=hud)
// Showcases the Agent Island: a live compact pill (tap/swipe to expand), a
// statically-expanded panel, an approval (amber) variant, and all six glyphs.

private struct AgentHUDGalleryScreen: View {
    @Environment(\.conduitTokens) private var t

    private var approvalFirst: [AgentInfo] {
        AgentInfo.demoSeed.filter { $0.state == .approval } + AgentInfo.demoSeed.filter { $0.state != .approval }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                section("LIVE — tap or swipe down to expand")
                islandStage { AgentIsland(agents: AgentInfo.demoSeed, screenWidth: 360) }
                    .frame(height: 70)

                section("EXPANDED PANEL")
                islandStage { AgentIsland(agents: AgentInfo.demoSeed, screenWidth: 360, defaultExpanded: true) }
                    .frame(height: 380)

                section("APPROVAL — amber tint + nudge")
                islandStage { AgentIsland(agents: approvalFirst, screenWidth: 360) }
                    .frame(height: 70)

                section("STATE GLYPHS")
                HStack(spacing: 14) {
                    ForEach(AgentState.allCases, id: \.self) { state in
                        VStack(spacing: 6) {
                            PixelBox(state: state, size: 16)
                            Text(state.islandLabel)
                                .font(.dsMonoPt(9))
                                .foregroundStyle(t.termText2)
                                .multilineTextAlignment(.center)
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
            }
            .padding(.vertical, 20)
        }
        .background(t.termBg.ignoresSafeArea())
    }

    private func section(_ title: String) -> some View {
        Text(title)
            .font(.dsMonoPt(10, weight: .medium)).tracking(1.2)
            .foregroundStyle(t.termText3)
            .padding(.horizontal, 16).padding(.top, 22).padding(.bottom, 6)
    }

    private func islandStage<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        ZStack(alignment: .top) { content() }
            .frame(maxWidth: .infinity, alignment: .top)
            .background(Color.black.opacity(0.001)) // hit area, keeps layout
    }
}

// MARK: - Agent status header gallery (CONDUIT_GALLERY=statusheader)
// Renders the slim AgentStatusHeader in the REAL placement it ships in on the
// Sessions tab: in-layout, BELOW a custom large title (as in SessionsHomeView),
// over the app's dark surface — the way to verify it reads cleanly and never
// overlaps the cutout or title.

private struct AgentStatusHeaderGalleryScreen: View {
    private let connected = AgentInfo(
        name: "Mac", agentKey: .claudeCode, host: "Mac",
        cwd: "~/code", state: .done
    )
    private let streaming = AgentInfo(
        name: "Mac", agentKey: .claudeCode, host: "Mac",
        cwd: "~/code", state: .streaming
    )
    private let approval = AgentInfo(
        name: "GPU Box", agentKey: .claudeCode, host: "GPU Box",
        cwd: "~/training", state: .approval, pendingApprovals: 1
    )

    private var t: ConduitTokens { .dark }

    var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Text("Sessions")
                        .font(.dsDisplayPt(30, weight: .bold))
                        .foregroundStyle(t.text)
                    Spacer()
                }
                .padding(.horizontal, 20).padding(.top, 8)

                // Connected/idle (green Done) — the common state, now with the
                // nested sub-pixels gently shimmering instead of sitting still.
                AgentStatusHeader(agents: [connected]) {}
                    .padding(.top, 10)

                DSSearchField(text: .constant(""), placeholder: "Search sessions")
                    .padding(.horizontal, 16).padding(.top, 12)

                galleryLabel("STREAMING STATE")
                AgentStatusHeader(agents: [streaming]) {}

                galleryLabel("APPROVAL STATE")
                AgentStatusHeader(agents: [approval]) {}

                // Big nested glyphs so the sub-pixel detail is easy to inspect.
                galleryLabel("NESTED GLYPH · 64pt")
                HStack(spacing: 22) {
                    PixelBox(state: .streaming, size: 18, gap: 3, subdivisions: 3)
                    PixelBox(state: .approval, size: 18, gap: 3, subdivisions: 3)
                    PixelBox(state: .done, size: 18, gap: 3, subdivisions: 3)
                }
                .padding(.top, 6)

                Spacer()
            }
        }
        .environment(\.conduitTokens, t)
    }

    private func galleryLabel(_ title: String) -> some View {
        Text(title)
            .font(.dsMonoPt(10, weight: .medium)).tracking(1.2)
            .foregroundStyle(t.termText3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20).padding(.top, 30).padding(.bottom, 6)
    }
}

// MARK: - Typed Inbox gallery (CONDUIT_GALLERY=inbox-typed)
//
// Renders all three new inbox card types (standard command, MCP call, AskQuestion)
// plus the DSAutonomyPresetBar in both light and dark, without any SSH connection.

private struct TypedInboxGalleryScreen: View {
    @Environment(\.conduitTokens) private var t
    @State private var preset: AutonomyPreset = .alwaysAsk
    @State private var vm = InboxViewModel(approvals: TypedInboxGalleryScreen.mockApprovals())

    var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Text("Typed Inbox")
                        .font(.dsDisplayPt(28, weight: .bold))
                        .foregroundStyle(t.text)
                    Spacer()
                }
                .padding(.horizontal, 20).padding(.top, 14)

                DSAutonomyPresetBar(preset: $preset)
                    .padding(.top, 8)

                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(vm.approvals.filter { $0.isPending }) { approval in
                            pendingCard(approval)
                                .padding(.horizontal, 16)
                        }
                    }
                    .padding(.top, 12).padding(.bottom, 24)
                }
            }
        }
    }

    @ViewBuilder
    private func pendingCard(_ approval: Approval) -> some View {
        switch approval.kind {
        case .askQuestion:
            DSAskQuestionCard(
                agentKey: .claudeCode,
                agentName: "Claude Code",
                timeLabel: "just now",
                question: approval.question ?? "",
                choices: approval.choices ?? [],
                onAnswer: { idx in vm.decide(approval.id, decision: .approved, choiceIndex: idx) }
            )
        case .callMCP:
            DSMCPCallCard(
                agentKey: .claudeCode,
                agentName: "Claude Code",
                timeLabel: "1m",
                toolName: approval.toolName ?? approval.command ?? "read_file",
                toolUseID: approval.toolUseID,
                args: approval.toolInput ?? approval.patch,
                risk: approval.risk.rawValue,
                onDeny: { vm.decide(approval.id, decision: .rejected) },
                onEditAndRun: {},
                onAllowAlways: { vm.decide(approval.id, decision: .approvedAlways) },
                onApprove: { vm.decide(approval.id, decision: .approved) }
            )
        default:
            DSApprovalCard(
                agentKey: .claudeCode,
                risk: approval.risk.rawValue,
                timeLabel: "2m",
                agentName: "Claude Code",
                action: actionLabel(approval.kind),
                hostLabel: approval.cwd,
                command: approval.command,
                onDeny: { vm.decide(approval.id, decision: .rejected) },
                onAllowAlways: { vm.decide(approval.id, decision: .approvedAlways) },
                onApprove: { vm.decide(approval.id, decision: .approved) }
            )
        }
    }

    private func actionLabel(_ kind: Approval.Kind) -> String {
        switch kind {
        case .command:   "run a command"
        case .fileWrite: "write a file"
        case .fileDelete:"delete a file"
        case .callMCP:   "call an MCP tool"
        default:         "perform an action"
        }
    }

    private static func mockApprovals() -> [Approval] {
        let sid = SessionID()
        return [
            Approval(
                sessionID: sid, agent: .claudeCode, kind: .askQuestion,
                cwd: "~/repo/api", risk: .low,
                question: "Which branch should I target for this PR?",
                choices: ["main", "develop", "staging", "hotfix/auth"]
            ),
            Approval(
                sessionID: sid, agent: .claudeCode, kind: .callMCP,
                command: "read_file",
                cwd: "~/infra", risk: .low,
                toolName: "read_file",
                toolUseID: "toolu_01GfGYYsQxJ",
                toolInput: "{\n  \"path\": \"/etc/nginx/nginx.conf\"\n}"
            ),
            Approval(
                sessionID: sid, agent: .claudeCode, kind: .command,
                command: "rm -rf ./dist && npm run build",
                cwd: "~/repo/web", risk: .medium
            ),
            Approval(
                sessionID: sid, agent: .codex, kind: .fileWrite,
                command: "src/auth/middleware.ts",
                cwd: "~/repo/api", risk: .high
            ),
        ]
    }
}

// MARK: - Features gallery (CONDUIT_GALLERY=features)
//
// Comprehensive overview of all four prototyped features: approval bar, media
// attachment, typed inbox, and APNs push notifications.

private struct FeaturesGalleryScreen: View {
    @Environment(\.conduitTokens) private var t

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header

                featureBlock("(a) SHORTCUT BAR — approve/reject banner") {
                    approvalBannerPreview
                }

                featureBlock("(b) MEDIA ATTACHMENT — composer paperclip") {
                    attachmentPreview
                }

                featureBlock("(c) TYPED APPROVALS — AskQuestion card") {
                    askQuestionPreview
                }

                featureBlock("(c) TYPED APPROVALS — MCP call card") {
                    mcpCardPreview
                }

                featureBlock("(c) AUTONOMY PRESETS") {
                    autonomyPresetPreview
                }

                featureBlock("(d) APNs — notification categories") {
                    apnsPreview
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(t.bg.ignoresSafeArea())
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Agent Features").font(.dsDisplayPt(28, weight: .bold)).foregroundStyle(t.text)
            Text("Prototype — flagged · verified in gallery light+dark")
                .font(.dsMonoPt(11)).foregroundStyle(t.text3)
        }
        .padding(.horizontal, 16).padding(.vertical, 16)
    }

    private func featureBlock<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.dsMonoPt(10, weight: .medium)).tracking(1.2)
                .foregroundStyle(t.text3)
                .padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 10)
            content()
            Rectangle().fill(t.border).frame(height: 1).padding(.top, 16)
        }
    }

    // (a) Approval banner mockup
    private var approvalBannerPreview: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "bell.badge")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(t.warn)
                Text("1 pending approval")
                    .font(.dsMonoPt(12, weight: .semibold))
                    .foregroundStyle(t.text2)
                Spacer()
                DSButton("DENY",    variant: .destructive, size: .sm, mono: true, action: {})
                DSButton("APPROVE", variant: .primary,     size: .sm, mono: true, action: {})
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(t.warnSoft)
            .overlay(Rectangle().fill(t.warn.opacity(0.25)).frame(height: 1), alignment: .bottom)

            HStack(spacing: 6) {
                Image(systemName: "terminal")
                    .font(.system(size: 11))
                    .foregroundStyle(t.text3)
                Text("$ git push origin main")
                    .font(.dsMonoPt(13))
                    .foregroundStyle(t.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(t.accent)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(t.surface)
        }
        .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: t.r3, style: .continuous).strokeBorder(t.border, lineWidth: 1))
        .padding(.horizontal, 16)
    }

    // (b) Attachment button mockup
    private var attachmentPreview: some View {
        HStack(spacing: 4) {
            Image(systemName: "paperclip")
                .font(.title3).foregroundStyle(t.accent)
                .padding(8)
                .background(t.accentSoft)
                .clipShape(RoundedRectangle(cornerRadius: t.r2, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("Photo Library / Files / Camera")
                    .font(.dsSansPt(13, weight: .medium)).foregroundStyle(t.text)
                Text("Tap paperclip → menu → selected media attached inline")
                    .font(.dsMonoPt(11)).foregroundStyle(t.text3)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
    }

    // (c) AskQuestion preview
    private var askQuestionPreview: some View {
        DSAskQuestionCard(
            agentKey: .claudeCode,
            agentName: "Claude Code",
            timeLabel: "just now",
            question: "Which branch should I open the pull request against?",
            choices: ["main", "develop", "staging"],
            onAnswer: { _ in }
        )
        .padding(.horizontal, 16)
    }

    // (c) MCP call preview
    private var mcpCardPreview: some View {
        DSMCPCallCard(
            agentKey: .claudeCode,
            agentName: "Claude Code",
            timeLabel: "30s",
            toolName: "execute_command",
            toolUseID: "toolu_01DmQxFA8L9",
            args: "cmd: \"docker ps -a\"",
            risk: 1,
            onDeny: {},
            onEditAndRun: {},
            onAllowAlways: {},
            onApprove: {}
        )
        .padding(.horizontal, 16)
    }

    // (c) Autonomy preset
    @State private var preset: AutonomyPreset = .autoReads
    private var autonomyPresetPreview: some View {
        DSAutonomyPresetBar(preset: $preset)
    }

    // (d) APNs status
    private var apnsPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            apnsRow("registerForRemoteNotifications()", done: true)
            apnsRow("registerCategories() — approval + run-complete", done: true)
            apnsRow("UNUserNotificationCenterDelegate — foreground banners", done: true)
            apnsRow("Push backend POST /run-complete endpoint", done: true)
            apnsRow("Notification action routing via NotificationCenter", done: true)
        }
        .padding(.horizontal, 16)
    }

    private func apnsRow(_ title: String, done: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(done ? t.ok : t.text4)
                .font(.system(size: 15))
            Text(title)
                .font(.dsMonoPt(12))
                .foregroundStyle(done ? t.text : t.text4)
            Spacer()
        }
    }
}

// MARK: - Keyboard gallery (CONDUIT_GALLERY=keyboard)

/// Renders the restyled accessory rail and the expanded `TerminalKeyboardPanel`
/// over a mock terminal backdrop so the keys can be inspected in light/dark
/// without an SSH connection.
private struct KeyboardGalleryScreen: View {
    @Environment(\.conduitTokens) private var t
    @State private var tab: TerminalKeyboardPanel.Tab = .keys
    @State private var ctrlLatched = false
    @State private var lastSent: String = "—"

    private let mockHistory = [
        "git status", "swift build", "cd Packages/ConduitKit",
        "ls -la", "vim Sources/SessionFeature/SessionView.swift",
    ]

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("KEYBOARD")
                    .font(.dsMonoPt(11, weight: .medium))
                    .tracking(2)
                    .foregroundStyle(t.termText.opacity(0.5))
                Text("last sent: \(lastSent)")
                    .font(.dsMonoPt(13))
                    .foregroundStyle(t.termAccent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)

            Spacer()

            // Collapsed rail (restyled UIKit accessory)
            KeyboardAccessoryRail(ctrlLatched: $ctrlLatched) { bytes in
                lastSent = describe(bytes)
            }
            .frame(height: 44)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(t.termSurface)

            // Expanded panel
            TerminalKeyboardPanel(
                selectedTab: $tab,
                ctrlLatched: $ctrlLatched,
                commandHistory: mockHistory,
                snippets: [],
                onBytes: { bytes in lastSent = describe(bytes) },
                onPaste: { lastSent = "paste" },
                onRunHistory: { cmd in lastSent = cmd },
                onInsertSnippet: { _ in },
                onDismiss: { lastSent = "ABC (collapse)" }
            )
            .frame(height: 320)
        }
        .background(t.termBg)
        .ignoresSafeArea(edges: .bottom)
    }

    private func describe(_ bytes: [UInt8]) -> String {
        bytes.map { b in
            switch b {
            case 0x1B: return "ESC"
            case 0x09: return "TAB"
            case 0x01...0x1A: return "^\(Character(UnicodeScalar(b + 0x40)))"
            case 0x20...0x7E: return String(UnicodeScalar(b))
            default: return String(format: "\\x%02x", b)
            }
        }.joined()
    }
}
#endif
