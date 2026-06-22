#if os(iOS)
import SwiftUI
import DesignSystem
import AgentKit
import SSHTransport
import SettingsFeature

/// Git workspace panel for an agent's ssh-host repo: branch state, changed
/// files with diff preview, branch/commit/push, and PR creation via `gh`.
/// Requires the agent to have a `workspacePath`. ssh-host runtime only.
struct AgentWorkspaceView: View {
    let store: AgentStore
    let agent: HostedAgent

    @Environment(\.lancerTokens) private var t
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    @State private var status: GitStatus?
    @State private var loading = false
    @State private var message: MessageBanner?
    @State private var busy = false
    @State private var diff: DiffPreview?

    @State private var newBranch = ""
    @State private var commitMessage = ""
    @State private var prTitle = ""
    @State private var prBody = ""

    private struct DiffPreview: Identifiable {
        let id = UUID()
        let path: String
        let text: String
    }

    private struct MessageBanner: Identifiable {
        let id = UUID()
        let text: String
        let isError: Bool
    }

    var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                DSDetailHeader("workspace — \(agent.name)", onBack: { dismiss() })
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let message { banner(message) }
                        branchSection
                        changesSection
                        commitSection
                        pullRequestSection
                    }
                    .padding(16)
                }
            }
        }
        .navigationBarHidden(true)
        .task { await reload() }
        .sheet(item: $diff) { d in diffSheet(d) }
    }

    // MARK: - Sections

    private func banner(_ m: MessageBanner) -> some View {
        Text(m.text)
            .font(.dsMonoPt(11))
            .foregroundStyle(m.isError ? t.danger : t.ok)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background((m.isError ? t.danger : t.ok).opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var branchSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                DSListSectionHead("BRANCH")
                Spacer()
                if loading { ProgressView().controlSize(.small) }
            }
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 12))
                    .foregroundStyle(t.accent)
                Text(status?.branch ?? "—")
                    .font(.dsMonoPt(13, weight: .semibold))
                    .foregroundStyle(t.text)
                if let s = status, s.ahead > 0 {
                    DSChip("↑\(s.ahead)", tone: .accent, variant: .soft, size: .sm)
                }
                if let s = status, s.behind > 0 {
                    DSChip("↓\(s.behind)", tone: .warn, variant: .soft, size: .sm)
                }
                Spacer()
            }
            HStack(spacing: 8) {
                TextField("new branch name", text: $newBranch)
                    .font(.dsMonoPt(12))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                DSButton("Create", variant: .secondary, size: .sm, mono: true) {
                    runAction("Created branch \(newBranch)") {
                        try await store.workspaceCreateBranch(agent: agent, name: newBranch.trimmingCharacters(in: .whitespaces))
                        newBranch = ""
                    }
                }
                .disabled(busy || newBranch.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private var changesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                DSListSectionHead("CHANGES")
                Spacer()
                DSButton("Refresh", variant: .ghost, size: .sm, mono: true) {
                    Task { await reload() }
                }
                .disabled(loading)
            }
            let changes = status?.changes ?? []
            if changes.isEmpty {
                Text(status == nil ? "Loading…" : "Working tree clean.")
                    .font(.dsMonoPt(12))
                    .foregroundStyle(t.text3)
            } else {
                ForEach(changes) { change in
                    Button { showDiff(change) } label: {
                        HStack(spacing: 8) {
                            Text(change.code)
                                .font(.dsMonoPt(11, weight: .bold))
                                .foregroundStyle(change.staged ? t.ok : t.accent)
                                .frame(width: 22, alignment: .leading)
                            Text(change.path)
                                .font(.dsMonoPt(12))
                                .foregroundStyle(t.text)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Text(change.label)
                                .font(.dsMonoPt(10))
                                .foregroundStyle(t.text4)
                        }
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    DSDivider()
                }
            }
        }
    }

    private var commitSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            DSListSectionHead("COMMIT")
            TextField("commit message", text: $commitMessage, axis: .vertical)
                .font(.dsMonoPt(12))
                .lineLimit(1...3)
            HStack(spacing: 8) {
                DSButton("Stage all & commit", variant: .accent, size: .sm, mono: true) {
                    runAction("Committed changes") {
                        try await store.workspaceCommitAll(agent: agent, message: commitMessage.trimmingCharacters(in: .whitespaces))
                        commitMessage = ""
                    }
                }
                .disabled(busy || commitMessage.trimmingCharacters(in: .whitespaces).isEmpty || (status?.isClean ?? true))
                DSButton("Push", variant: .secondary, size: .sm, mono: true) {
                    runAction("Pushed to origin") {
                        try await store.workspacePush(agent: agent)
                    }
                }
                .disabled(busy)
            }
        }
    }

    private var pullRequestSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            DSListSectionHead("PULL REQUEST")
            TextField("PR title", text: $prTitle)
                .font(.dsMonoPt(12))
            TextField("PR description", text: $prBody, axis: .vertical)
                .font(.dsMonoPt(12))
                .lineLimit(2...5)
            DSButton("Create PR", variant: .primary, size: .sm, mono: true) {
                runAction(nil) {
                    let url = try await store.workspaceCreatePR(
                        agent: agent,
                        title: prTitle.trimmingCharacters(in: .whitespaces),
                        body: prBody
                    )
                    prTitle = ""
                    prBody = ""
                    message = MessageBanner(text: "PR created: \(url)", isError: false)
                    if let u = URL(string: url) { openURL(u) }
                }
            }
            .disabled(busy || prTitle.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func diffSheet(_ d: DiffPreview) -> some View {
        ZStack(alignment: .top) {
            t.termBg.ignoresSafeArea()
            VStack(spacing: 0) {
                DSDetailHeader(d.path, onBack: { diff = nil })
                ScrollView {
                    Text(d.text.isEmpty ? "No diff." : d.text)
                        .font(.dsMonoPt(11))
                        .foregroundStyle(t.termText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(12)
                }
            }
        }
    }

    // MARK: - Actions

    private func reload() async {
        loading = true
        defer { loading = false }
        do {
            status = try await store.workspaceStatus(agent: agent)
        } catch {
            message = MessageBanner(text: error.localizedDescription, isError: true)
        }
    }

    private func showDiff(_ change: GitFileChange) {
        diff = DiffPreview(path: change.path, text: "Loading diff…")
        Task {
            do {
                let text = try await store.workspaceDiff(agent: agent, path: change.path)
                diff = DiffPreview(path: change.path, text: text)
            } catch {
                diff = DiffPreview(path: change.path, text: "[error] \(error.localizedDescription)")
            }
        }
    }

    /// Runs a mutating workspace action, surfaces success/error, and reloads status.
    private func runAction(_ successText: String?, _ work: @escaping () async throws -> Void) {
        guard !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                try await work()
                if let successText { message = MessageBanner(text: successText, isError: false) }
                await reload()
            } catch {
                message = MessageBanner(text: error.localizedDescription, isError: true)
            }
        }
    }
}
#endif
