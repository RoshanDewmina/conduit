#if os(iOS)
import SwiftUI
import DesignSystem
import ConduitCore
import KeysFeature
import PersistenceKit
import SecurityKit
import SettingsFeature

// MARK: - Screen 6: KeysManagementView

public struct KeysManagementView: View {
    let keyStore: KeyStore

    @Environment(\.dismiss) private var dismiss
    @Environment(\.conduitTokens) private var t

    @State private var vm: KeysViewModel
    @State private var copiedTag: String? = nil

    // Mock host-count associations (TODO: wire real per-key host tracking)
    private let mockHostCounts: [Int] = [3, 1, 0]

    public init(keyStore: KeyStore) {
        self.keyStore = keyStore
        _vm = State(initialValue: KeysViewModel(store: keyStore))
    }

    public var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                DSDetailHeader("ssh keys", onBack: { dismiss() }) {
                    DSIconButton(.plus) {
                        Task { await vm.generate() }
                    }
                }

                ScrollView {
                    LazyVStack(spacing: 0) {
                        // Generate dashed row
                        Button {
                            Task { await vm.generate() }
                        } label: {
                            HStack(spacing: 10) {
                                DSIconView(.plus, size: 14, color: t.accent)
                                Text("generate ed25519 key")
                                    .font(.dsMonoPt(13))
                                    .foregroundStyle(t.accent)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .overlay(
                                Rectangle()
                                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                                    .foregroundStyle(t.accent.opacity(0.5))
                            )
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                        }
                        .buttonStyle(.plain)

                        if vm.keys.isEmpty {
                            DSEmptyState(
                                icon: .key,
                                title: "no keys yet",
                                subtitle: "Generate an Ed25519 key to authenticate without passwords."
                            )
                            .padding(.horizontal, 16)
                            .padding(.top, 24)
                        } else {
                            DSListSectionHead("STORED KEYS", count: vm.keys.count)
                                .padding(.top, 8)

                            ForEach(Array(vm.keys.enumerated()), id: \.element.id) { idx, key in
                                keyRow(key, hostCount: idx < mockHostCounts.count ? mockHostCounts[idx] : 0)
                                DSDivider()
                            }
                        }
                    }
                }
            }

            // Copy confirmation toast
            if let tag = copiedTag {
                VStack {
                    Spacer()
                    Text("public key copied for \(tag)")
                        .font(.dsMonoPt(12))
                        .foregroundStyle(t.textOnDark)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.8))
                        .clipShape(Capsule())
                        .padding(.bottom, 40)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .onAppear {
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        withAnimation { copiedTag = nil }
                    }
                }
            }
        }
        .navigationBarHidden(true)
        .animation(.easeInOut(duration: 0.2), value: copiedTag)
        .task { await vm.reload() }
    }

    private func keyRow(_ key: KeysViewModel.StoredKey, hostCount: Int) -> some View {
        HStack(spacing: 12) {
            DSIconView(.key, size: 16, color: t.accent)
                .frame(width: 36, height: 36)
                .background(t.accentSoft)
                .clipShape(Rectangle())

            VStack(alignment: .leading, spacing: 4) {
                Text(key.tag)
                    .font(.dsMonoPt(13, weight: .medium))
                    .foregroundStyle(t.text)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    DSChip("ed25519", tone: .neutral, variant: .soft, size: .sm)
                    if hostCount > 0 {
                        DSChip("\(hostCount) host\(hostCount == 1 ? "" : "s")", tone: .ok, variant: .soft, size: .sm)
                    } else {
                        DSChip("unused", tone: .neutral, variant: .soft, size: .sm)
                    }
                }
            }

            Spacer()

            Button {
                UIPasteboard.general.string = key.openSSH
                withAnimation { copiedTag = key.tag }
            } label: {
                DSIconView(.copy, size: 16, color: t.text3)
                    .frame(width: 36, height: 36)
                    .background(t.surface)
                    .clipShape(Rectangle())
                    .overlay(Rectangle().strokeBorder(t.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

// MARK: - Screen 7: SnippetsLibraryView (M5a)

public struct SnippetsLibraryView: View {
    let repository: SnippetRepository

    @Environment(\.dismiss) private var dismiss
    @Environment(\.conduitTokens) private var t

    @State private var snippets: [Snippet] = []
    @State private var selectedFilter: SnippetFilter = .all
    @State private var isLoading = false

    private enum SnippetFilter: String, CaseIterable, Hashable, Sendable {
        case all, ops, debug, data
    }

    public init(repository: SnippetRepository) {
        self.repository = repository
    }

    private var filtered: [Snippet] {
        guard selectedFilter != .all else { return snippets }
        return snippets.filter { $0.tags.contains(selectedFilter.rawValue) }
    }

    public var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                DSDetailHeader("snippets", onBack: { dismiss() })

                // Filter chips
                DSSegmentedPicker(
                    options: SnippetFilter.allCases.map { (label: $0.rawValue, value: $0) },
                    selection: $selectedFilter
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

                if isLoading {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else if filtered.isEmpty {
                    Spacer()
                    DSEmptyState(
                        icon: .list,
                        title: "no snippets",
                        subtitle: "Create reusable shell commands to run on your hosts."
                    )
                    .padding(.horizontal, 24)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(filtered) { snippet in
                                snippetRow(snippet)
                                DSDivider()
                            }
                        }
                    }
                }
            }
        }
        .navigationBarHidden(true)
        .task {
            isLoading = true
            snippets = (try? await repository.all()) ?? []
            isLoading = false
        }
    }

    private func snippetRow(_ snippet: Snippet) -> some View {
        HStack(spacing: 12) {
            DSIconView(.list, size: 14, color: t.accent)
                .frame(width: 32, height: 32)
                .background(t.accentSoft)
                .clipShape(Rectangle())

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(snippet.name)
                        .font(.dsMonoPt(13, weight: .semibold))
                        .foregroundStyle(t.text)
                        .lineLimit(1)
                    if let tag = snippet.tags.first {
                        DSChip(tag, tone: .neutral, variant: .soft, size: .sm)
                    }
                }
                Text("$ \(snippet.body)")
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text3)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                // TODO: run snippet
            } label: {
                DSIconView(.arrowRight, size: 14, color: t.accent)
                    .frame(width: 32, height: 32)
                    .background(t.accentSoft)
                    .clipShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

// MARK: - Screen 8: WorkflowBuilderView (M5b)

public struct WorkflowBuilderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.conduitTokens) private var t

    @State private var selectedWorkflow = LibraryMocks.workflows[0]

    public init() {}

    public var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                DSDetailHeader("workflows", onBack: { dismiss() })

                ScrollView {
                    VStack(spacing: 0) {
                        // Workflow picker
                        DSListSectionHead("WORKFLOW")

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(LibraryMocks.workflows) { wf in
                                    Button {
                                        selectedWorkflow = wf
                                    } label: {
                                        Text(wf.name)
                                            .font(.dsMonoPt(12, weight: .medium))
                                            .foregroundStyle(selectedWorkflow.id == wf.id ? t.accentFg : t.text2)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 7)
                                            .background(
                                                selectedWorkflow.id == wf.id
                                                    ? t.accent
                                                    : t.surface
                                            )
                                            .clipShape(Rectangle())
                                            .overlay(Rectangle().strokeBorder(t.border, lineWidth: 1))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                        }

                        // Info row
                        HStack {
                            DSChip("\(selectedWorkflow.stepCount) steps", tone: .neutral, variant: .soft, size: .sm)
                            DSChip("last run \(selectedWorkflow.lastRun)", tone: .neutral, variant: .soft, size: .sm)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)

                        DSDivider()

                        DSListSectionHead("STEPS")

                        // Step chain
                        VStack(spacing: 0) {
                            ForEach(Array(ManagementMocks.workflowSteps.enumerated()), id: \.element.id) { idx, step in
                                DSStepNode(
                                    number: idx + 1,
                                    title: step.title,
                                    subtitle: step.subtitle,
                                    isLast: idx == ManagementMocks.workflowSteps.count - 1
                                )
                                .padding(.horizontal, 16)
                            }
                        }
                        .padding(.vertical, 12)

                        // Add step dashed row
                        Button {
                            // TODO: add step
                        } label: {
                            HStack(spacing: 8) {
                                DSIconView(.plus, size: 14, color: t.text3)
                                Text("add step")
                                    .font(.dsMonoPt(13))
                                    .foregroundStyle(t.text3)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .overlay(
                                Rectangle()
                                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                                    .foregroundStyle(t.border)
                            )
                            .padding(.horizontal, 16)
                        }
                        .buttonStyle(.plain)

                        Spacer(minLength: 24)
                    }
                }
            }
        }
        .navigationBarHidden(true)
    }
}

// MARK: - Screen 9: DiagnosticsView (M6a)

public struct DiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.conduitTokens) private var t

    @State private var isRunning = false

    public init() {}

    private var allOk: Bool {
        ManagementMocks.diagnostics.allSatisfy { $0.tone == "ok" }
    }

    public var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                DSDetailHeader("diagnostics", onBack: { dismiss() })

                ScrollView {
                    VStack(spacing: 0) {
                        // Status hero
                        VStack(spacing: 12) {
                            DotMatrixView(state: allOk ? .done : .error,
                                          cols: 20, rows: 6, cell: 9, dot: 4)
                            Text(allOk ? "all systems ok" : "issues detected")
                                .font(.dsSansPt(16, weight: .semibold))
                                .foregroundStyle(allOk ? t.ok : t.danger)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)

                        DSDivider()
                        DSListSectionHead("CHECKS")

                        ForEach(ManagementMocks.diagnostics) { check in
                            DSHealthRow(
                                label: check.label,
                                status: check.status,
                                timing: check.timingMS.map { "\($0) ms" } ?? "",
                                tone: healthTone(check.tone)
                            )
                            DSDivider()
                        }

                        DSButton(
                            isRunning ? "running…" : "re-run diagnostics",
                            variant: .secondary,
                            mono: true,
                            isLoading: isRunning,
                            fullWidth: true
                        ) {
                            Task {
                                isRunning = true
                                try? await Task.sleep(for: .seconds(1.5))
                                isRunning = false
                            }
                        }
                        .padding(16)

                        Text("// TODO: wire to real SSHSession diagnostics")
                            .font(.dsMonoPt(10))
                            .foregroundStyle(t.text4)
                            .padding(.bottom, 8)
                    }
                }
            }
        }
        .navigationBarHidden(true)
    }

    private func healthTone(_ tone: String) -> DSStatusDotTone {
        switch tone {
        case "ok":     return .ok
        case "warn":   return .warn
        case "danger": return .danger
        default:       return .ok
        }
    }
}

// MARK: - Screen 10: CommandBarView (N6)

public struct CommandBarView: View {
    let onConnect: (String) -> Void
    let onOpenInbox: () -> Void
    let onRunSnippet: () -> Void
    let onNewWorkspace: () -> Void
    let onDismiss: () -> Void

    @Environment(\.conduitTokens) private var t
    @State private var searchText = ""
    @FocusState private var isTextFieldFocused: Bool

    private let savedHosts = ["prod-api", "dev-box", "staging"]

    public init(
        onConnect: @escaping (String) -> Void,
        onOpenInbox: @escaping () -> Void,
        onRunSnippet: @escaping () -> Void,
        onNewWorkspace: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.onConnect = onConnect
        self.onOpenInbox = onOpenInbox
        self.onRunSnippet = onRunSnippet
        self.onNewWorkspace = onNewWorkspace
        self.onDismiss = onDismiss
    }

    private var parsedHost: String? {
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        let pattern = #"^(?:ssh\s+)?([a-zA-Z0-9_.-]+@[\w.-]+)(?:\s+-p\s*\d+)?$"#
        guard let _ = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
            .firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) else { return nil }
        return trimmed.hasPrefix("ssh ") ? String(trimmed.dropFirst(4)) : trimmed
    }

    public var body: some View {
        ZStack {
            // Dark backdrop
            t.bg.opacity(0.95).ignoresSafeArea()
                .onTapGesture { onDismiss() }

            VStack(spacing: 0) {
                Spacer(minLength: 60)

                // Search field
                HStack(spacing: 10) {
                    DSIconView(.command, size: 16, color: t.accent)
                    TextField("search or user@host…", text: $searchText)
                        .font(.dsMonoPt(14))
                        .foregroundStyle(t.text)
                        .tint(t.accent)
                        .focused($isTextFieldFocused)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            DSIconView(.close, size: 14, color: t.text3)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .frame(height: 52)
                .background(t.surface)
                .overlay(Rectangle().strokeBorder(t.accent.opacity(0.6), lineWidth: 1))

                // Results container
                VStack(spacing: 0) {
                    // SSH connect if pattern matched
                    if let host = parsedHost {
                        commandSection("CONNECT") {
                            commandRow(icon: .server, label: "connect to \(host)", tint: t.accent) {
                                onConnect(host)
                                onDismiss()
                            }
                        }
                    }

                    // Saved hosts (CONNECT section if no parsed host)
                    if parsedHost == nil {
                        commandSection("CONNECT") {
                            ForEach(savedHosts.filter {
                                searchText.isEmpty || $0.contains(searchText.lowercased())
                            }, id: \.self) { host in
                                commandRow(icon: .server, label: host, tint: t.text2) {
                                    onConnect(host)
                                    onDismiss()
                                }
                                if host != savedHosts.last {
                                    DSDivider()
                                }
                            }
                        }
                    }

                    // Actions
                    commandSection("ACTIONS") {
                        commandRow(icon: .inbox, label: "open inbox", tint: t.text2) {
                            onOpenInbox()
                            onDismiss()
                        }
                        DSDivider()
                        commandRow(icon: .list, label: "run snippet", tint: t.text2) {
                            onRunSnippet()
                            onDismiss()
                        }
                        DSDivider()
                        commandRow(icon: .sparkles, label: "new cloud workspace", tint: t.text2) {
                            onNewWorkspace()
                            onDismiss()
                        }
                    }
                }
                .background(t.surface)
                .overlay(Rectangle().strokeBorder(t.border, lineWidth: 0.5))

                Spacer()
            }
            .padding(.horizontal, 16)
        }
        .onAppear { isTextFieldFocused = true }
    }

    private func commandSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.dsMonoPt(10, weight: .medium))
                    .tracking(10 * 0.10)
                    .textCase(.uppercase)
                    .foregroundStyle(t.text4)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(t.surfaceSunk)

            content()
        }
    }

    private func commandRow(icon: DSIcon, label: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                DSIconView(icon, size: 16, color: tint)
                Text(label)
                    .font(.dsMonoPt(13))
                    .foregroundStyle(t.text)
                Spacer()
                DSIconView(.arrowRight, size: 14, color: t.text4)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
#endif
