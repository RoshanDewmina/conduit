#if os(iOS)
import SwiftUI
import UIKit
import WebKit
import LancerCore
import DesignSystem
import DiffFeature
import DiffKit
import FilesFeature
import PreviewKit
import SessionFeature
import SSHTransport

/// The single app-level presentation owner for workspace tools. Terminal remains
/// in SessionFeature; files, review, and host previews are composed here so no
/// feature needs to depend on another feature's implementation.
public struct SessionWorkspaceContainer: View {
    private let viewModel: SessionViewModel
    private let onSwitchHost: () -> Void

    @State private var showDrawer = false
    @State private var tab: WorkspaceTab = .workspace

    @Environment(\.lancerTokens) private var t

    public init(viewModel: SessionViewModel, onSwitchHost: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onSwitchHost = onSwitchHost
    }

    public var body: some View {
        SessionView(viewModel: viewModel, onOpenWorkspace: {
            Haptics.selection()
            showDrawer = true
        })
        .sheet(isPresented: $showDrawer) {
            CursorDrawer(detents: [.medium, .large]) {
                WorkspaceDrawer(
                    tab: $tab,
                    viewModel: viewModel,
                    onSwitchHost: { showDrawer = false; onSwitchHost() }
                )
            }
        }
        #if DEBUG
        // Visual-verification hook: auto-open the workspace drawer a moment after the
        // session screen appears so the live-SSH harness can screenshot it without a
        // tap (HID taps don't fire SwiftUI actions on the headless iOS 27 sim).
        .task {
            guard ProcessInfo.processInfo.environment["LANCER_TEST_OPEN_WORKSPACE"] == "1" else { return }
            try? await Task.sleep(for: .seconds(2))
            if let raw = ProcessInfo.processInfo.environment["LANCER_TEST_WORKSPACE_TAB"],
               let preset = WorkspaceTab(rawValue: raw) {
                tab = preset
            }
            showDrawer = true
        }
        #endif
    }
}

/// The Warp-style workspace drawer: one dark slide-up sheet with a segmented
/// Workspace · Files · Diff · Preview tab bar that swaps the full tool view.
/// Replaces the old launcher + per-tool sheet stack (the board's "C" drawer).
/// The session screen itself is the live terminal, so the drawer's first tab is
/// the git/environment Workspace rather than a duplicate terminal.
public enum WorkspaceTab: String, CaseIterable, Identifiable {
    case workspace, files, diff, preview
    public var id: String { rawValue }

    var title: String {
        switch self {
        case .workspace: "Workspace"
        case .files:     "Files"
        case .diff:      "Diff"
        case .preview:   "Preview"
        }
    }

    var icon: String {
        switch self {
        case .workspace: "arrow.triangle.branch"
        case .files:     "folder"
        case .diff:      "plusminus"
        case .preview:   "globe"
        }
    }
}

private struct WorkspaceDrawer: View {
    @Binding var tab: WorkspaceTab
    let viewModel: SessionViewModel
    let onSwitchHost: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Always-dark terminal palette so the drawer reads as the board's midnight surface.
    private let term = LancerTokens.dark
    private var tabActive: Color { term.accent }
    private var tabActiveInk: Color { term.accentFg }

    var body: some View {
        VStack(spacing: 0) {
            tabBar.padding(.horizontal, 16)
                .padding(.top, 4)

            content
                .padding(.top, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(term.termBg.ignoresSafeArea())
    }

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(WorkspaceTab.allCases) { item in
                let active = tab == item
                Button {
                    Haptics.selection()
                    withAnimation(LancerMotion.resolved(.smooth(duration: 0.18, extraBounce: 0), reduceMotion: reduceMotion)) {
                        tab = item
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: item.icon).font(.system(size: 11, weight: .semibold))
                        Text(item.title).font(.dsSansPt(11.5, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .foregroundStyle(active ? tabActiveInk : term.termText3)
                    .background(active ? tabActive : .clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
                .accessibilityValue(active ? "selected" : "")
            }
        }
        .padding(3)
        .background(term.termSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(term.termBorder, lineWidth: 1))
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .workspace:
            WorkspaceEnvironmentView(
                session: viewModel.session,
                host: viewModel.host,
                workdir: viewModel.cwd,
                onOpenReview: { tab = .diff },
                onOpenFiles: { tab = .files },
                onOpenBrowser: { tab = .preview },
                onSwitchHost: onSwitchHost
            )
        case .files:
            HostFilesView(session: viewModel.session, initialPath: viewModel.cwd)
        case .diff:
            WorkspaceReviewView(session: viewModel.session, workdir: viewModel.cwd)
        case .preview:
            HostPreviewView(session: viewModel.session, host: viewModel.host)
        }
    }
}

public struct RelayWorkspaceUnavailableView: View {
    private let onConnectSSH: (() -> Void)?

    @Environment(\.cursorScheme) private var cursorScheme
    @Environment(\.dismiss) private var dismiss

    public init(onConnectSSH: (() -> Void)? = nil) {
        self.onConnectSSH = onConnectSSH
    }

    private struct SSHFeature {
        let systemImage: String
        let title: String
        let subtitle: String
    }

    private static let features: [SSHFeature] = [
        SSHFeature(systemImage: "terminal", title: "Terminal", subtitle: "Interactive shell with command blocks"),
        SSHFeature(systemImage: "folder", title: "File browser", subtitle: "Browse and open files on the machine"),
        SSHFeature(systemImage: "network", title: "Port forwarding", subtitle: "Reach a dev server running on the host"),
    ]

    private var colors: CursorColors { CursorColors.resolve(cursorScheme) }

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "lock.laptopcomputer")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(colors.statusDotActive)
                Text("Unlock the full workspace")
                    .font(CursorType.cardTitle)
                    .foregroundColor(colors.primaryText)
                Text("These features need a direct SSH connection to this machine — they aren't available over relay.")
                    .font(CursorType.bodyText)
                    .foregroundColor(colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            CursorArtifactCard {
                VStack(spacing: 0) {
                    ForEach(Array(Self.features.enumerated()), id: \.offset) { index, feature in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: feature.systemImage)
                                .font(.system(size: 17, weight: .medium))
                                .foregroundColor(colors.secondaryText)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(feature.title)
                                    .font(CursorType.bodyEmphasis)
                                    .foregroundColor(colors.primaryText)
                                Text(feature.subtitle)
                                    .font(CursorType.rowSecondary)
                                    .foregroundColor(colors.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        if index < Self.features.count - 1 {
                            Rectangle()
                                .fill(colors.hairline)
                                .frame(height: 1)
                        }
                    }
                }
            }

            Text("Relay still handles dispatch, output, and approvals for this machine.")
                .font(CursorType.rowSecondary)
                .foregroundColor(colors.mutedText)
                .fixedSize(horizontal: false, vertical: true)

            if let onConnectSSH {
                CursorPillButton(title: "Connect over SSH", style: .primary, action: onConnectSSH)
                    .frame(maxWidth: .infinity)
            }

            CursorPillButton(title: "Not now", style: .secondary) { dismiss() }
                .frame(maxWidth: .infinity)
        }
        .padding(20)
        .background(colors.background)
        .environment(\.cursorScheme, .light)
    }
}

private struct WorkspaceEnvironmentView: View {
    let session: SSHSession
    let host: Host
    let workdir: String
    let onOpenReview: () -> Void
    let onOpenFiles: () -> Void
    let onOpenBrowser: () -> Void
    let onSwitchHost: () -> Void

    @Environment(\.lancerTokens) private var t
    @State private var status: GitStatus?
    @State private var summary: GitChangeSummary?
    @State private var branches: [String] = []
    @State private var pendingBranch: String?
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var isShowingCommit = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.dsSansPt(14))
                        .foregroundStyle(t.danger)
                }

                CursorSectionHeader("Workspace")
                CursorArtifactCard {
                    VStack(spacing: 0) {
                        Button(action: onOpenReview) {
                            CursorListRow(iconSystemName: "plusminus", title: "Changes", trailingText: changesValue, showChevron: true)
                        }.buttonStyle(.plain)
                        Button(action: onSwitchHost) {
                            CursorListRow(iconSystemName: "laptopcomputer", title: "Host", trailingText: host.name, showChevron: true)
                        }.buttonStyle(.plain)
                        branchRow
                        Button(action: { isShowingCommit = true }) {
                            CursorListRow(iconSystemName: "arrow.up.to.line.compact", title: "Commit or push", showChevron: true)
                        }.buttonStyle(.plain)
                    }
                }

                CursorSectionHeader("Sources")
                CursorArtifactCard {
                    VStack(spacing: 0) {
                        Button(action: onOpenFiles) {
                            CursorListRow(iconSystemName: "folder", title: "Files", showChevron: true)
                        }.buttonStyle(.plain)
                        Button(action: onOpenBrowser) {
                            CursorListRow(iconSystemName: "globe", title: "Browser", showChevron: true)
                        }.buttonStyle(.plain)
                    }
                }

                if isLoading {
                    ProgressView("Loading environment")
                        .font(.dsSansPt(14))
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .padding(16)
        }
        .task { await reload() }
        .refreshable { await reload() }
        .confirmationDialog(
            "Discard local changes?",
            isPresented: Binding(get: { pendingBranch != nil }, set: { if !$0 { pendingBranch = nil } }),
            titleVisibility: .visible
        ) {
            Button("Switch branch", role: .destructive) {
                if let pendingBranch { checkout(pendingBranch) }
            }
            Button("Cancel", role: .cancel) { pendingBranch = nil }
        } message: {
            Text("Your working tree has changes. Switching branches may overwrite or hide them.")
        }
        .sheet(isPresented: $isShowingCommit) {
            CommitAndPushSheet(session: session, workdir: workdir) { await reload() }
                .presentationDetents([.medium])
        }
    }

    private var branchRow: some View {
        Menu {
            ForEach(branches, id: \.self) { branch in
                Button(branch) { chooseBranch(branch) }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(t.text2)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Branch")
                        .font(.dsSansPt(16, weight: .medium))
                        .foregroundStyle(t.text)
                    Text(status?.branch ?? "Loading")
                        .font(.dsMonoPt(12))
                        .foregroundStyle(t.text3)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(t.text4)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Choose branch")
    }

    private var changesSubtitle: String {
        guard let status else { return "Loading Git status" }
        return status.isClean ? "Working tree is clean" : "\(status.changes.count) changed file\(status.changes.count == 1 ? "" : "s")"
    }

    private var changesValue: String? {
        guard let summary else { return nil }
        return "+\(summary.additions) -\(summary.deletions)"
    }

    private func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let client = GitClient(session: session)
            async let loadedStatus = client.status(workdir: workdir)
            async let loadedSummary = client.changeSummary(workdir: workdir)
            async let loadedBranches = client.listBranches(workdir: workdir)
            status = try await loadedStatus
            summary = try await loadedSummary
            branches = try await loadedBranches
            errorMessage = nil
        } catch {
            errorMessage = "Couldn’t load this Git workspace: \(error.localizedDescription)"
        }
    }

    private func chooseBranch(_ branch: String) {
        guard branch != status?.branch else { return }
        let isClean = status?.isClean ?? false
        if branch != (status?.branch ?? "") && !isClean {
            pendingBranch = branch
        } else {
            checkout(branch)
        }
    }

    private func checkout(_ branch: String) {
        pendingBranch = nil
        Task {
            do {
                try await GitClient(session: session).checkout(workdir: workdir, name: branch)
                await reload()
            } catch {
                errorMessage = "Couldn’t switch branches: \(error.localizedDescription)"
            }
        }
    }
}

private struct CommitAndPushSheet: View {
    let session: SSHSession
    let workdir: String
    let onComplete: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.lancerTokens) private var t
    @State private var message = ""
    @State private var state: CommitState = .idle

    private enum CommitState: Equatable { case idle, working, complete(String), failed(String) }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Commit message")
                    .font(.dsSansPt(15, weight: .medium))
                TextField("Describe this change", text: $message, axis: .vertical)
                    .lineLimit(3...6)
                    .font(.dsSansPt(16))
                    .padding(12)
                    .background(t.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(t.border, lineWidth: 1))

                stateLabel
                Spacer()
                Button(action: commitAndPush) {
                    Group {
                        if state == .working { ProgressView().tint(t.accentInk) }
                        else { Label("Commit and push", systemImage: "arrow.up.to.line.compact") }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                }
                .buttonStyle(.borderedProminent)
                .tint(t.accent)
                .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || state == .working)
            }
            .padding(20)
            .navigationTitle("Commit or push")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    @ViewBuilder private var stateLabel: some View {
        switch state {
        case .idle: EmptyView()
        case .working: Text("Staging and pushing…").font(.dsSansPt(14)).foregroundStyle(t.text3)
        case .complete(let detail): Label(detail, systemImage: "checkmark.circle.fill").font(.dsSansPt(14)).foregroundStyle(t.ok)
        case .failed(let detail): Label(detail, systemImage: "exclamationmark.triangle.fill").font(.dsSansPt(14)).foregroundStyle(t.danger)
        }
    }

    private func commitAndPush() {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        state = .working
        Task {
            do {
                let client = GitClient(session: session)
                try await client.stage(workdir: workdir)
                try await client.commit(workdir: workdir, message: trimmed)
                try await client.push(workdir: workdir)
                state = .complete("Committed and pushed")
                await onComplete()
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }
}

private struct WorkspaceReviewView: View {
    let session: SSHSession
    let workdir: String

    @State private var diff: UnifiedDiff?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let diff, !diff.files.isEmpty {
                DiffView(diff: diff)
            } else if let errorMessage {
                ContentUnavailableView("Review unavailable", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
            } else {
                ContentUnavailableView("No changes", systemImage: "checkmark.circle", description: Text("This workspace has no changes relative to HEAD."))
            }
        }
        .task {
            do {
                let raw = try await GitClient(session: session).diff(workdir: workdir)
                diff = UnifiedDiffParser.parse(raw)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct HostFilesView: View {
    let session: SSHSession
    let initialPath: String

    @Environment(\.lancerTokens) private var t
    @State private var path = "~"
    @State private var entries: [SFTPEntry] = []
    @State private var preview: FilePreview?
    @State private var errorMessage: String?

    private struct FilePreview: Identifiable {
        let id = UUID()
        let entry: SFTPEntry
        let content: String
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(displayPath)
                    .font(.dsMonoPt(10))
                    .tracking(0.4)
                    .foregroundStyle(t.text3)
                    .lineLimit(1)
                    .truncationMode(.head)
                Spacer()
                Button { goUp() } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(t.termText2)
                        .frame(width: 30, height: 30)
                        .background(t.termSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(t.termBorder, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(path == "/" || path == "~")
                .accessibilityLabel("Parent folder")
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            if let errorMessage {
                Text(errorMessage).font(.dsSansPt(12)).foregroundStyle(t.termErr)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.bottom, 8)
            }

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(entries) { entry in
                        fileRow(entry)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 16)
            }
        }
        .task { path = initialPath; await load() }
        .task(id: path) { await load() }
        .sheet(item: $preview) { preview in
            CursorBottomSheetContainer(title: preview.entry.name) {
                FilePreviewView(filename: preview.entry.name, content: preview.content, path: preview.entry.path)
            }
            .presentationDetents([.medium, .large])
        }
    }

    private var displayPath: String { path }

    private func fileRow(_ entry: SFTPEntry) -> some View {
        Button { open(entry) } label: {
            HStack(spacing: 9) {
                if entry.isDirectory {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(t.termText3)
                        .frame(width: 10)
                    Image(systemName: "folder.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(t.termAccent)
                } else {
                    Text("›")
                        .font(.dsMonoPt(12))
                        .foregroundStyle(Color(.sRGB, red: 0.435, green: 0.608, blue: 0.820, opacity: 1)) // #6f9bd1
                        .frame(width: 10)
                }
                Text(entry.name)
                    .font(.dsMonoPt(12.5, weight: entry.isDirectory ? .medium : .regular))
                    .foregroundStyle(entry.isDirectory ? t.termText : t.termText2)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let bytes = entry.sizeBytes, !entry.isDirectory {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))
                        .font(.dsMonoPt(9.5))
                        .foregroundStyle(t.termText3)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func load() async {
        do {
            entries = try await SFTPClient(session: session).list(path: path)
            errorMessage = nil
        } catch {
            entries = []
            errorMessage = error.localizedDescription
        }
    }

    private func open(_ entry: SFTPEntry) {
        if entry.isDirectory {
            path = entry.path
            return
        }
        Task {
            do {
                let data = try await SFTPClient(session: session).read(path: entry.path, limitBytes: 256 * 1024)
                preview = FilePreview(entry: entry, content: String(data: data, encoding: .utf8) ?? "[Binary file — \(data.count) bytes]")
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func goUp() {
        let parent = (path as NSString).deletingLastPathComponent
        path = parent.isEmpty ? "/" : parent
    }
}

private struct HostPreviewView: View {
    let session: SSHSession
    let host: Host

    @Environment(\.lancerTokens) private var t
    @State private var ports: [Int] = []
    @State private var portText = ""
    @State private var displayedURL: URL?
    @State private var directTunnel: LocalPortForwardTunnel?
    @State private var fallbackPort: Int?
    @State private var errorMessage: String?
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {
            // Board browser chrome: nav glyphs + a mono URL pill + port menu/open.
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.left").font(.system(size: 12, weight: .semibold)).foregroundStyle(t.termText3)
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(t.termText3)
                    Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .semibold)).foregroundStyle(t.termText3)
                }
                HStack(spacing: 6) {
                    Text("localhost:")
                        .font(.dsMonoPt(11))
                        .foregroundStyle(t.termText3)
                    TextField("port", text: $portText)
                        .keyboardType(.numberPad)
                        .font(.dsMonoPt(11))
                        .foregroundStyle(t.termText2)
                        .frame(width: 54)
                    Spacer(minLength: 0)
                    if !ports.isEmpty {
                        Menu {
                            ForEach(ports, id: \.self) { port in
                                Button("localhost:\(port)") { portText = String(port); openPreview() }
                            }
                        } label: {
                            Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold)).foregroundStyle(t.termText3)
                        }
                    }
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(Color(.sRGB, red: 0.051, green: 0.043, blue: 0.035, opacity: 1), in: RoundedRectangle(cornerRadius: 6, style: .continuous)) // #0d0b09
                Button(action: openPreview) {
                    Text("Open")
                        .font(.dsSansPt(12, weight: .semibold))
                        .foregroundStyle(t.accentFg)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(t.termAccent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(HostPreviewPort.parse(portText) == nil)
                .opacity(HostPreviewPort.parse(portText) == nil ? 0.5 : 1)
            }
            .padding(12)
            .background(t.termSurface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(t.termBorder, lineWidth: 1))
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.dsSansPt(13))
                    .foregroundStyle(t.danger)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
            }

            if let displayedURL {
                HostPreviewWebView(url: displayedURL, fallbackSession: fallbackPort == nil ? nil : session, fallbackPort: fallbackPort)
            } else if isLoading {
                ProgressView("Detecting local development servers")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "No preview selected",
                    systemImage: "globe",
                    description: Text("Choose a detected loopback port or enter the port for a development server on \(host.name).")
                )
            }
        }
        .task { await detectPorts() }
        .onDisappear { Task { await directTunnel?.stop() } }
    }

    private func detectPorts() async {
        do {
            ports = try await PortDetector(session: session).detect()
            if let first = ports.first { portText = String(first) }
            errorMessage = nil
        } catch {
            errorMessage = "Couldn’t detect preview ports: \(error.localizedDescription)"
        }
        isLoading = false
    }

    private func openPreview() {
        guard let remotePort = HostPreviewPort.parse(portText) else {
            errorMessage = "Enter a port between 1 and 65535."
            return
        }
        Task {
            await directTunnel?.stop()
            let localPort = 49_152 + (remotePort % 10_000)
            let forward = PortForward(
                hostID: host.id,
                localPort: localPort,
                remoteHost: "127.0.0.1",
                remotePort: remotePort,
                label: "Host preview"
            )
            do {
                let tunnel = try await session.startLocalPortForward(forward)
                directTunnel = tunnel
                fallbackPort = nil
                displayedURL = URL(string: "http://127.0.0.1:\(localPort)/")
                errorMessage = nil
            } catch {
                // Narrow fallback only: the existing scheme handler can still
                // render basic HTTP when a direct local listener is unavailable.
                directTunnel = nil
                fallbackPort = remotePort
                displayedURL = URL(string: "lancer-preview://localhost/")
                errorMessage = "Direct preview forwarding failed. Using basic HTTP fallback; live reload may be unavailable."
            }
        }
    }
}

private struct HostPreviewWebView: UIViewRepresentable {
    let url: URL
    let fallbackSession: SSHSession?
    let fallbackPort: Int?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        if let fallbackSession, let fallbackPort {
            configuration.setURLSchemeHandler(SSHProxyURLSchemeHandler(session: fallbackSession, remotePort: fallbackPort), forURLScheme: "lancer-preview")
        }
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard webView.url != url else { return }
        webView.load(URLRequest(url: url))
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else { decisionHandler(.cancel); return }
            if HostPreviewNavigation.isEmbeddedPreviewURL(url) {
                decisionHandler(.allow)
            } else {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
            }
        }
    }
}
#endif
