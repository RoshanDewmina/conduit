#if os(iOS)
import SwiftUI
import Observation
import ConduitCore
import SSHTransport

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
    public init(viewModel: FilesViewModel) { _vm = State(initialValue: viewModel) }

    public var body: some View {
        List {
            Section {
                HStack {
                    Image(systemName: "folder")
                    Text(vm.path).font(.system(.callout, design: .monospaced))
                }
            }
            Button("..") { Task { await vm.goUp() } }
            ForEach(vm.entries) { e in
                Button {
                    if e.isDirectory { Task { await vm.enter(e) } }
                } label: {
                    HStack {
                        Image(systemName: e.isDirectory ? "folder" : "doc.text")
                            .foregroundStyle(.tint)
                        Text(e.name).font(.system(.callout, design: .monospaced))
                        Spacer()
                        if let s = e.sizeBytes, !e.isDirectory {
                            Text("\(s)").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.plain)
        .navigationTitle("Files")
        .contentMargins(.bottom, 72, for: .scrollContent)
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 72)
        }
        .task { await vm.reload() }
        .refreshable { await vm.reload() }
    }
}

// MARK: - SFTPFilesView

public struct SFTPFilesView: View {
    @State private var vm: SFTPFilesViewModel

    public init(viewModel: SFTPFilesViewModel) {
        _vm = State(initialValue: viewModel)
    }

    public var body: some View {
        List {
            Section {
                HStack {
                    Image(systemName: "folder.fill")
                    Text(vm.currentPath)
                        .font(.system(.callout, design: .monospaced))
                }
            }
            if vm.currentPath != "/" && vm.currentPath != "~" && vm.currentPath != "." {
                Button("..") { Task { await vm.navigateUp() } }
            }
            ForEach(vm.entries) { entry in
                Button {
                    Task { await vm.navigate(to: entry) }
                } label: {
                    HStack {
                        Image(systemName: entry.isDirectory ? "folder" : "doc.text")
                            .foregroundStyle(.tint)
                        Text(entry.name)
                            .font(.system(.callout, design: .monospaced))
                        Spacer()
                        if let size = entry.sizeBytes, !entry.isDirectory {
                            Text(
                                ByteCountFormatter.string(
                                    fromByteCount: Int64(size),
                                    countStyle: .file
                                )
                            )
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.plain)
        .navigationTitle("Files")
        .contentMargins(.bottom, 72, for: .scrollContent)
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 72)
        }
        .overlay { if vm.isLoading { ProgressView() } }
        .task { await vm.reload() }
        .refreshable { await vm.reload() }
        .sheet(isPresented: $vm.isShowingTextPreview) {
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
        .alert("Error", isPresented: .constant(vm.error != nil), actions: {
            Button("OK") { vm.error = nil }
        }, message: {
            Text(vm.error ?? "")
        })
    }
}

#endif
