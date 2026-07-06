#if os(iOS)
import SwiftUI
import DesignSystem
import SessionFeature
import FilesFeature
import LancerCore

/// Read-only host directory browser over the E2E relay, styled in the Cursor
/// visual language (light list chrome, circular header controls).
struct RelayFileBrowserView: View {
    let bridge: E2ERelayBridge
    let initialPath: String

    @Environment(\.cursorScheme) private var cursorScheme
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

    private var colors: CursorColors { CursorColors.resolve(cursorScheme) }

    var body: some View {
        VStack(spacing: 0) {
            CursorHeaderBar(
                leading: AnyView(
                    CursorIconButton(systemImageName: "chevron.left", action: { dismiss() })
                ),
                trailing: []
            )
            .overlay(alignment: .center) {
                VStack(spacing: 2) {
                    Text("Files")
                        .font(CursorType.sheetTitle)
                        .foregroundColor(colors.primaryText)
                    Text(path)
                        .font(CursorType.rowSecondary)
                        .foregroundColor(colors.secondaryText)
                        .lineLimit(1)
                }
                .padding(.top, CursorMetrics.headerTopPadding)
            }

            pathBar
            content
        }
        .background(colors.background.ignoresSafeArea())
        .environment(\.cursorScheme, .light)
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
            CursorPillButton(title: "Up", style: .secondary) { goUp() }
                .disabled(parent == nil || loading)
            Text(path)
                .font(CursorType.inlineCode)
                .foregroundColor(colors.secondaryText)
                .lineLimit(1)
                .truncationMode(.head)
                .frame(maxWidth: .infinity, alignment: .leading)
            if loading {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, CursorMetrics.rowHorizontalPadding)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        if let errorText {
            VStack(spacing: 12) {
                Text("Couldn’t list this folder")
                    .font(CursorType.cardTitle)
                    .foregroundColor(colors.primaryText)
                Text(errorText)
                    .font(CursorType.bodyText)
                    .foregroundColor(colors.secondaryText)
                    .multilineTextAlignment(.center)
                CursorPillButton(title: "Retry", style: .primary) {
                    Task { await load() }
                }
            }
            .frame(maxHeight: .infinity)
            .padding(.horizontal, 24)
        } else if entries.isEmpty && !loading {
            Text("Empty folder")
                .font(CursorType.bodyText)
                .foregroundColor(colors.secondaryText)
                .frame(maxHeight: .infinity)
        } else {
            listView
        }
    }

    private var listView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(entries) { entry in
                    Button { handleTap(entry) } label: {
                        CursorListRow(
                            iconSystemName: entry.isDir ? "folder.fill" : "doc",
                            title: entry.name,
                            showChevron: entry.isDir
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(loading)
                }
            }
        }
    }

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
