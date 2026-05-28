#if DEBUG && os(iOS)
import SwiftUI
import ConduitCore
import DesignSystem
import SessionFeature
import OnboardingFeature
import DiffFeature
import DiffKit
import FilesFeature

// UI-audit harness. Routed from AppRoot when SIMCTL_CHILD_CONDUIT_GALLERY is set.
// Renders hero components with mock data so screens needing a live session can be
// screenshotted deterministically. Not compiled into release builds.
struct DebugGalleryView: View {
    let route: String
    @Environment(\.conduitTokens) private var t

    var body: some View {
        switch route {
        case "orb-connecting": SSHConnectOverlay(phase: .connecting)
        case "orb-connected":  OrbConnectedDemo()
        case "components":     componentsGallery
        case "onboarding":     OnboardingView(onContinue: {}, onSetupWorkspace: {})
        case "diff":           DiffView(diff: UnifiedDiffParser.parse(Self.sampleDiff))
        case "filepreview":    FilePreviewView(filename: "Tokens.swift", content: Self.sampleFile)
        default:               chatGallery
        }
    }

    // MARK: - Chat hero

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
                         chunks: [BlockChunk(text: "On branch master\nnothing to commit, working tree clean\n", stream: .stdout)],
                         exitStatus: ExitStatus(code: 0), startedAt: Date().addingTimeInterval(-1.4),
                         finishedAt: Date(), state: .done(exitCode: 0))
        case .running:
            return Block(sessionID: SessionID(), prompt: prompt, command: "swift build",
                         chunks: [BlockChunk(text: "[3/42] Compiling DesignSystem Tokens.swift\n", stream: .stdout)],
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

    // MARK: - Components

    private var componentsGallery: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    DSButton("Primary", variant: .primary, action: {})
                    DSButton("Secondary", variant: .secondary, action: {})
                    DSButton("Ghost", variant: .ghost, action: {})
                }
                HStack(spacing: 8) {
                    DSChip("accent", tone: .accent, style: .solid)
                    DSChip("ok", tone: .ok)
                    DSChip("warn", tone: .warn)
                    DSChip("danger", tone: .danger)
                }
                HStack(spacing: 8) {
                    RiskBadge(risk: 0); RiskBadge(risk: 1); RiskBadge(risk: 2); RiskBadge(risk: 3)
                }
                HStack(spacing: 8) {
                    ForEach(AgentState.allCases, id: \.self) { AgentBadge($0) }
                }
                HStack(spacing: 12) {
                    PixelAvatar(seed: "ubuntu@dev", size: 40)
                    PixelAvatar(seed: "staging", size: 40)
                    PixelAvatar(seed: "raspberry", size: 40)
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(t.surf0)
    }
}

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

// Plays connecting → connected so the burst/checkmark can be captured.
private struct OrbConnectedDemo: View {
    @State private var phase: SSHConnectPhase = .connecting
    var body: some View {
        SSHConnectOverlay(phase: phase)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { phase = .connected }
            }
    }
}
#endif
