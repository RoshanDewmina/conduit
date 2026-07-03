#if os(iOS)
import SwiftUI
import DesignSystem
import SessionFeature
import FilesFeature
import LancerCore

/// Read-only host directory browser over the E2E relay. Mirrors `AgentFilesView`
/// (the SSH file browser) visually, but lists through `E2ERelayBridge.relayListDir`
/// instead of SFTP. The daemon's `fsList` is home-confined and fails closed, so the
/// browser can never escape the user's home directory — an out-of-home path comes
/// back as an error state.
///
/// Tapping a folder lists into it; tapping a file fetches its content through
/// `E2ERelayBridge.relayReadFile` (home-confined, size-capped, binary-rejecting,
/// same fail-closed posture as the directory listing) and shows it in
/// `FilePreviewView`.
struct RelayFileBrowserView: View {
    let bridge: E2ERelayBridge
    let initialPath: String

    @Environment(\.lancerTokens) private var t
    @Environment(\.dismiss) private var dismiss

    @State private var path: String
    @State private var parent: String?
    @State private var entries: [RelayDirEntry] = []
    @State private var loading = false
    @State private var errorText: String?
    @State private var previewFilename: String?
    @State private var previewContent: String?
    @State private var previewPath: String?
    @State private var isPreviewPresented = false
    @State private var fileLoadErrorText: String?

    init(bridge: E2ERelayBridge, initialPath: String = "~") {
        self.bridge = bridge
        self.initialPath = initialPath
        _path = State(initialValue: initialPath)
    }

    var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                DSDetailHeader("Files", breadcrumb: path, onBack: { dismiss() })
                pathBar
                content
            }
        }
        .navigationBarHidden(true)
        .task(id: path) { await load() }
        .filePreviewDrawer(
            filename: previewFilename,
            content: previewContent,
            path: previewPath,
            isPresented: $isPreviewPresented
        )
        .alert(
            "Couldn’t open file",
            isPresented: Binding(
                get: { fileLoadErrorText != nil },
                set: { if !$0 { fileLoadErrorText = nil } }
            ),
            presenting: fileLoadErrorText
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
    }

    private var pathBar: some View {
        HStack(spacing: 8) {
            DSButton("Up", variant: .ghost, size: .sm, mono: true) { goUp() }
                .disabled(parent == nil || loading)
            Text(path)
                .font(.dsMonoPt(12))
                .foregroundStyle(t.text2)
                .lineLimit(1)
                .truncationMode(.head)
                .frame(maxWidth: .infinity, alignment: .leading)
            if loading {
                ProgressView().controlSize(.small)
            }
        }
        .padding(12)
        .background(t.surface)
    }

    @ViewBuilder
    private var content: some View {
        if let errorText {
            DSEmptyState(
                icon: .folder,
                title: "Couldn’t list this folder",
                subtitle: errorText,
                action: ("Retry", { Task { await load() } })
            )
            .frame(maxHeight: .infinity)
            .padding(.horizontal, 24)
        } else if entries.isEmpty && !loading {
            DSEmptyState(
                icon: .folder,
                title: "Empty folder",
                subtitle: "Nothing to show in \(path)."
            )
            .frame(maxHeight: .infinity)
            .padding(.horizontal, 24)
        } else {
            listView
        }
    }

    private var listView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(entries) { entry in
                    entryRow(entry)
                    DSDivider()
                }
            }
        }
    }

    private func entryRow(_ entry: RelayDirEntry) -> some View {
        Button {
            handleTap(entry)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: entry.isDir ? "folder.fill" : "doc")
                    .font(.system(size: 13))
                    .foregroundStyle(entry.isDir ? t.accent : t.text3)
                    .frame(width: 18)
                Text(entry.name)
                    .font(.dsMonoPt(13, weight: entry.isDir ? .semibold : .regular))
                    .foregroundStyle(entry.isDir ? t.text : t.text2)
                    .lineLimit(1)
                Spacer()
                if entry.isDir {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(t.text4)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(loading)
    }

    // MARK: - Actions

    private func handleTap(_ entry: RelayDirEntry) {
        guard !loading else { return }
        if entry.isDir {
            errorText = nil
            path = childPath(of: path, name: entry.name)
        } else {
            Task { await loadFilePreview(entry) }
        }
    }

    private func loadFilePreview(_ entry: RelayDirEntry) async {
        loading = true
        defer { loading = false }
        let fullPath = childPath(of: path, name: entry.name)
        do {
            let file = try await bridge.relayReadFile(fullPath)
            previewFilename = entry.name
            previewContent = file.content
            previewPath = file.path
            isPreviewPresented = true
        } catch {
            fileLoadErrorText = error.localizedDescription
        }
    }

    private func goUp() {
        guard let parent else { return }
        errorText = nil
        path = parent
    }

    /// Joins a child name onto the displayed path. Paths are home-folded ("~",
    /// "~/projects"); the daemon re-resolves and re-confines, so a naive join is safe.
    private func childPath(of base: String, name: String) -> String {
        base.hasSuffix("/") ? base + name : base + "/" + name
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            let listing = try await bridge.relayListDir(path)
            entries = listing.entries
            parent = listing.parent
            errorText = nil
        } catch {
            entries = []
            parent = nil
            errorText = error.localizedDescription
        }
    }
}
#endif
