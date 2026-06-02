#if os(iOS)
import SwiftUI
import Observation
import ConduitCore
import SSHTransport
import DesignSystem
import UniformTypeIdentifiers

@MainActor @Observable
public final class FilesViewModel {
    public var path: String = "."
    public var entries: [Entry] = []
    public var error: String?

    public struct Entry: Identifiable, Hashable {
        public let id = UUID()
        public let name: String
        public let isDirectory: Bool
        public let sizeBytes: Int?
    }

    private let session: SSHSession
    public init(session: SSHSession) { self.session = session }

    public func reload() async {
        do {
            // Listing via `ls -la --time-style=long-iso` is universally available
            // and avoids depending on `find` or `stat` portability quirks.
            let out = try await session.executeCollected("ls -la --time-style=long-iso \(shellQuote(path))")
            entries = parse(out)
        } catch { self.error = error.localizedDescription }
    }

    public func enter(_ entry: Entry) async {
        path = (path == "." ? "" : path + "/") + entry.name
        await reload()
    }

    public func goUp() async {
        if path == "." { return }
        path = (path as NSString).deletingLastPathComponent
        if path.isEmpty { path = "." }
        await reload()
    }

    // MARK: - Helpers

    private func parse(_ output: String) -> [Entry] {
        output.split(separator: "\n").compactMap { line -> Entry? in
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 8 else { return nil }
            let perms = String(parts[0])
            let name  = String(parts[7..<parts.count].joined(separator: " "))
            if name == "." || name == ".." { return nil }
            let isDir = perms.hasPrefix("d")
            let size  = Int(parts[4])
            return Entry(name: name, isDirectory: isDir, sizeBytes: size)
        }
    }

    private func shellQuote(_ s: String) -> String {
        "'\(s.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

public struct FilesView: View {
    @State private var vm: FilesViewModel
    @Environment(\.conduitTokens) private var t

    public init(viewModel: FilesViewModel) { _vm = State(initialValue: viewModel) }

    public var body: some View {
        List {
            Section {
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill").foregroundStyle(t.accent)
                    Text(vm.path)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(t.text2)
                }
            }
            .listRowBackground(t.surf1)

            Button("..") { Task { await vm.goUp() } }
                .foregroundStyle(t.text2)
                .listRowBackground(t.surf1)

            ForEach(vm.entries) { e in
                Button {
                    if e.isDirectory { Task { await vm.enter(e) } }
                } label: {
                    HStack {
                        Image(systemName: e.isDirectory ? "folder" : "doc.text")
                            .foregroundStyle(e.isDirectory ? t.accent : t.text3)
                        Text(e.name)
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(t.text1)
                        Spacer()
                        if let s = e.sizeBytes, !e.isDirectory {
                            Text("\(s)")
                                .font(.caption2)
                                .foregroundStyle(t.text4)
                        }
                    }
                }
                .buttonStyle(.plain)
                .listRowBackground(t.surf1)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(t.surf0)
        .navigationTitle("Files")
        .contentMargins(.bottom, 72, for: .scrollContent)
        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 72) }
        .task { await vm.reload() }
        .refreshable { await vm.reload() }
    }
}

// MARK: - SFTPFilesView

public struct SFTPFilesView: View {
    @State private var vm: SFTPFilesViewModel
    @Environment(\.conduitTokens) private var t
    @State private var isShowingImporter = false
    @State private var pendingRenameEntry: SFTPEntry?
    @State private var renameInput = ""
    @State private var isShowingCreateFolder = false
    @State private var newFolderInput = ""
    @State private var pendingChmodEntry: SFTPEntry?
    @State private var chmodInput = "755"

    public init(viewModel: SFTPFilesViewModel) {
        _vm = State(initialValue: viewModel)
    }

    public var body: some View {
        let base = AnyView(
            sftpFileList
                .sftpListChrome(t: t)
                .navigationTitle("Files")
                .sftpToolbar(
                    isShowingImporter: $isShowingImporter,
                    isShowingCreateFolder: $isShowingCreateFolder,
                    newFolderInput: $newFolderInput
                )
                .sftpOverlays(vm: vm, t: t)
                .sftpDataTasks(vm: vm, isShowingImporter: $isShowingImporter)
                .sftpSheets(vm: vm)
        )

        return base.sftpAlerts(
            vm: vm,
            pendingRenameEntry: $pendingRenameEntry,
            renameInput: $renameInput,
            isShowingCreateFolder: $isShowingCreateFolder,
            newFolderInput: $newFolderInput,
            pendingChmodEntry: $pendingChmodEntry,
            chmodInput: $chmodInput
        )
    }

    @ViewBuilder
    private var sftpFileList: some View {
        List {
            Section {
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill").foregroundStyle(t.accent)
                    Text(vm.currentPath)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(t.text2)
                }
            }
            .listRowBackground(t.surf1)

            if vm.currentPath != "/" && vm.currentPath != "~" && vm.currentPath != "." {
                Button("..") { Task { await vm.navigateUp() } }
                    .foregroundStyle(t.text2)
                    .listRowBackground(t.surf1)
            }
            ForEach(vm.entries) { entry in
                SFTPEntryRow(
                    entry: entry,
                    onNavigate: { Task { await vm.navigate(to: entry) } },
                    onDownload: { Task { await vm.download(entry: entry) } },
                    onRename: {
                        pendingRenameEntry = entry
                        renameInput = entry.name
                    },
                    onChmod: {
                        pendingChmodEntry = entry
                        chmodInput = "755"
                    },
                    onDelete: { Task { await vm.delete(entry: entry) } }
                )
            }
        }
    }
}

// MARK: - SFTP row + view helpers

private struct SFTPEntryRow: View {
    let entry: SFTPEntry
    let onNavigate: () -> Void
    let onDownload: () -> Void
    let onRename: () -> Void
    let onChmod: () -> Void
    let onDelete: () -> Void
    @Environment(\.conduitTokens) private var t

    var body: some View {
        Button(action: onNavigate) {
            HStack {
                Image(systemName: entry.isDirectory ? "folder" : "doc.text")
                    .foregroundStyle(entry.isDirectory ? t.accent : t.text3)
                Text(entry.name)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(t.text1)
                Spacer()
                if let size = entry.sizeBytes, !entry.isDirectory {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                        .font(.caption2)
                        .foregroundStyle(t.text4)
                }
            }
        }
        .buttonStyle(.plain)
        .listRowBackground(t.surf1)
        .contextMenu { entryContextMenu }
        .swipeActions(edge: .trailing) { deleteSwipeButton }
        .swipeActions(edge: .leading, allowsFullSwipe: false) { renameSwipeButton }
    }

    @ViewBuilder
    private var entryContextMenu: some View {
        if !entry.isDirectory {
            Button(action: onDownload) {
                Label("Download", systemImage: "square.and.arrow.down")
            }
        }
        Button(action: onRename) {
            Label("Rename", systemImage: "pencil")
        }
        Button(action: onChmod) {
            Label("Change Mode", systemImage: "lock")
        }
        Button(role: .destructive, action: onDelete) {
            Label("Delete", systemImage: "trash")
        }
    }

    private var deleteSwipeButton: some View {
        Button(role: .destructive, action: onDelete) {
            Label("Delete", systemImage: "trash")
        }
    }

    private var renameSwipeButton: some View {
        Button(action: onRename) {
            Label("Rename", systemImage: "pencil")
        }
        .tint(.blue)
    }
}

private extension View {
    func sftpListChrome(t: ConduitTokens) -> some View {
        listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(t.surf0)
            .contentMargins(.bottom, 72, for: .scrollContent)
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 72) }
    }

    func sftpToolbar(
        isShowingImporter: Binding<Bool>,
        isShowingCreateFolder: Binding<Bool>,
        newFolderInput: Binding<String>
    ) -> some View {
        toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { isShowingImporter.wrappedValue = true } label: {
                    Label("Upload", systemImage: "square.and.arrow.up")
                }
                Button {
                    isShowingCreateFolder.wrappedValue = true
                    newFolderInput.wrappedValue = ""
                } label: {
                    Label("New Folder", systemImage: "folder.badge.plus")
                }
            }
        }
    }

    @ViewBuilder
    func sftpOverlays(vm: SFTPFilesViewModel, t: ConduitTokens) -> some View {
        overlay(alignment: .center) {
            if vm.isLoading { ProgressView().tint(t.accent) }
        }
        .overlay(alignment: .bottom) {
            SFTPTransferProgressBanner(vm: vm, t: t)
        }
    }

    func sftpDataTasks(vm: SFTPFilesViewModel, isShowingImporter: Binding<Bool>) -> some View {
        task { await vm.reload() }
            .refreshable { await vm.reload() }
            .fileImporter(
                isPresented: isShowingImporter,
                allowedContentTypes: [.data, .item],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    let didStart = url.startAccessingSecurityScopedResource()
                    Task {
                        await vm.upload(localFileURL: url)
                        if didStart { url.stopAccessingSecurityScopedResource() }
                    }
                } else if case .failure(let error) = result {
                    vm.error = error.localizedDescription
                }
            }
            .fileExporter(
                isPresented: Binding(
                    get: { vm.isShowingExporter },
                    set: { vm.isShowingExporter = $0 }
                ),
                document: vm.exportDocument ?? ExportedFileDocument(filename: "download", data: Data()),
                contentType: .data,
                defaultFilename: vm.exportDocument?.filename ?? "download"
            ) { result in
                if case .failure(let error) = result {
                    vm.error = error.localizedDescription
                }
                vm.exportDocument = nil
            }
    }

    @ViewBuilder
    func sftpSheets(vm: SFTPFilesViewModel) -> some View {
        sheet(isPresented: Binding(
            get: { vm.isShowingTextPreview },
            set: { vm.isShowingTextPreview = $0 }
        )) {
            if let data = vm.selectedFileData, let name = vm.selectedFileName {
                NavigationStack {
                    TextPreview(filename: name, data: data)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { vm.isShowingTextPreview = false }
                            }
                        }
                }
                .presentationDetents([.large])
            }
        }
    }

    func sftpAlerts(
        vm: SFTPFilesViewModel,
        pendingRenameEntry: Binding<SFTPEntry?>,
        renameInput: Binding<String>,
        isShowingCreateFolder: Binding<Bool>,
        newFolderInput: Binding<String>,
        pendingChmodEntry: Binding<SFTPEntry?>,
        chmodInput: Binding<String>
    ) -> some View {
        alert(
            "Rename Item",
            isPresented: Binding(
                get: { pendingRenameEntry.wrappedValue != nil },
                set: { if !$0 { pendingRenameEntry.wrappedValue = nil } }
            ),
            actions: {
                TextField("New name", text: renameInput)
                Button("Cancel", role: .cancel) { pendingRenameEntry.wrappedValue = nil }
                Button("Rename") {
                    if let entry = pendingRenameEntry.wrappedValue {
                        Task { await vm.rename(entry: entry, to: renameInput.wrappedValue) }
                    }
                    pendingRenameEntry.wrappedValue = nil
                }
            }
        )
        .alert("New Folder", isPresented: isShowingCreateFolder) {
            TextField("Folder name", text: newFolderInput)
            Button("Cancel", role: .cancel) {}
            Button("Create") { Task { await vm.createDirectory(named: newFolderInput.wrappedValue) } }
        }
        .alert(
            "Change Mode",
            isPresented: Binding(
                get: { pendingChmodEntry.wrappedValue != nil },
                set: { if !$0 { pendingChmodEntry.wrappedValue = nil } }
            ),
            actions: {
                TextField("Octal mode (e.g. 755)", text: chmodInput)
                    .keyboardType(.numbersAndPunctuation)
                Button("Cancel", role: .cancel) { pendingChmodEntry.wrappedValue = nil }
                Button("Apply") {
                    if let entry = pendingChmodEntry.wrappedValue {
                        Task { await vm.chmod(entry: entry, modeOctal: chmodInput.wrappedValue) }
                    }
                    pendingChmodEntry.wrappedValue = nil
                }
            }
        )
        .alert("Error", isPresented: .constant(vm.error != nil)) {
            Button("OK") { vm.error = nil }
        } message: {
            Text(vm.error ?? "")
        }
    }
}

private struct SFTPTransferProgressBanner: View {
    let vm: SFTPFilesViewModel
    let t: ConduitTokens

    var body: some View {
        if let progress = vm.transferProgress {
            VStack(alignment: .leading, spacing: 6) {
                if let msg = vm.transferMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(t.text2)
                }
                ProgressView(value: progress.fractionCompleted ?? 0)
                    .tint(t.accent)
                HStack {
                    Text(ByteCountFormatter.string(fromByteCount: progress.bytesTransferred, countStyle: .file))
                    Spacer()
                    if let total = progress.totalBytes {
                        Text(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))
                    }
                }
                .font(.caption2)
                .foregroundStyle(t.text3)
            }
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 16)
            .padding(.bottom, 84)
        }
    }
}

#endif
