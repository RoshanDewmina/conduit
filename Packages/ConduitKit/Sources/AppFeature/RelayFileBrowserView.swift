#if os(iOS)
import SwiftUI
import DesignSystem
import SessionFeature

/// Read-only host directory browser over the E2E relay. Mirrors `AgentFilesView`
/// (the SSH file browser) visually, but lists through `E2ERelayBridge.relayListDir`
/// instead of SFTP. The daemon's `fsList` is home-confined and fails closed, so the
/// browser can never escape the user's home directory — an out-of-home path comes
/// back as an error state.
///
/// Browse-only: tapping a folder lists into it; files are inert (no open/preview —
/// pulling file bytes over the relay is out of scope, like the terminal/PTY tunnel).
struct RelayFileBrowserView: View {
    let bridge: E2ERelayBridge
    let initialPath: String

    @Environment(\.conduitTokens) private var t
    @Environment(\.dismiss) private var dismiss

    @State private var path: String
    @State private var parent: String?
    @State private var entries: [RelayDirEntry] = []
    @State private var loading = false
    @State private var errorText: String?

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
        .disabled(!entry.isDir || loading)
    }

    // MARK: - Actions

    private func handleTap(_ entry: RelayDirEntry) {
        guard entry.isDir, !loading else { return }
        errorText = nil
        path = childPath(of: path, name: entry.name)
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
