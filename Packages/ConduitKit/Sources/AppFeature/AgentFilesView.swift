#if os(iOS)
import SwiftUI
import DesignSystem
import AgentKit
import SSHTransport
import SettingsFeature
import FilesFeature

/// SFTP file browser for an agent's ssh-host. Browse/preview-only when opened
/// from the agent detail; when `attachToRunID` is set (opened from a run), a
/// file can be registered as that run's artifact. ssh-host runtime only.
struct AgentFilesView: View {
    let store: AgentStore
    let agent: HostedAgent
    /// When non-nil, tapping a file registers it as an artifact of this run.
    var attachToRunID: String?

    @Environment(\.conduitTokens) private var t
    @Environment(\.dismiss) private var dismiss

    @State private var path = "."
    @State private var entries: [SFTPEntry] = []
    @State private var loading = false
    @State private var status: String?
    @State private var preview: FilePreview?
    @State private var busyPath: String?

    private struct FilePreview: Identifiable {
        let id = UUID()
        let name: String
        let text: String
        let path: String
    }

    var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                DSDetailHeader(headerTitle, onBack: { dismiss() })
                pathBar
                if let status {
                    Text(status)
                        .font(.dsMonoPt(11))
                        .foregroundStyle(t.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.top, 4)
                }
                listView
            }
        }
        .navigationBarHidden(true)
        .task(id: path) { await load() }
        .sheet(item: $preview) { p in
            FilePreviewView(filename: p.name, content: p.text, path: p.path)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var headerTitle: String {
        attachToRunID == nil ? "files — \(agent.name)" : "attach artifact"
    }

    private var pathBar: some View {
        HStack(spacing: 8) {
            DSButton("Up", variant: .ghost, size: .sm, mono: true) { goUp() }
                .disabled(path == "." || path == "/")
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

    private var listView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if entries.isEmpty && !loading {
                    Text("Empty directory.")
                        .font(.dsMonoPt(12))
                        .foregroundStyle(t.text3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                ForEach(entries) { entry in
                    entryRow(entry)
                    DSDivider()
                }
            }
        }
    }

    private func entryRow(_ entry: SFTPEntry) -> some View {
        Button {
            handleTap(entry)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: entry.isDirectory ? "folder.fill" : "doc")
                    .font(.system(size: 13))
                    .foregroundStyle(entry.isDirectory ? t.accent : t.text3)
                    .frame(width: 18)
                Text(entry.name)
                    .font(.dsMonoPt(13, weight: entry.isDirectory ? .semibold : .regular))
                    .foregroundStyle(t.text)
                    .lineLimit(1)
                Spacer()
                if busyPath == entry.path {
                    ProgressView().controlSize(.small)
                } else if !entry.isDirectory, let bytes = entry.sizeBytes {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))
                        .font(.dsMonoPt(10))
                        .foregroundStyle(t.text4)
                }
                if entry.isDirectory {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(t.text4)
                } else if attachToRunID != nil {
                    Image(systemName: "paperclip")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(t.accent)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(busyPath != nil)
    }

    // MARK: - Actions

    private func handleTap(_ entry: SFTPEntry) {
        guard busyPath == nil else { return }
        if entry.isDirectory {
            status = nil
            path = entry.path
        } else if attachToRunID != nil {
            registerArtifact(entry)
        } else {
            previewFile(entry)
        }
    }

    private func goUp() {
        status = nil
        let parent = (path as NSString).deletingLastPathComponent
        path = parent.isEmpty ? "." : parent
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            entries = try await store.listHostFiles(agent: agent, path: path)
            status = nil
        } catch {
            entries = []
            status = error.localizedDescription
        }
    }

    private func previewFile(_ entry: SFTPEntry) {
        busyPath = entry.path
        Task {
            defer { busyPath = nil }
            do {
                let data = try await store.readHostFile(agent: agent, path: entry.path, limitBytes: 256 * 1024)
                let text = String(data: data, encoding: .utf8) ?? "[binary — \(data.count) bytes, not shown]"
                preview = FilePreview(name: entry.name, text: text, path: entry.path)
            } catch {
                status = error.localizedDescription
            }
        }
    }

    private func registerArtifact(_ entry: SFTPEntry) {
        guard let runID = attachToRunID else { return }
        busyPath = entry.path
        Task {
            defer { busyPath = nil }
            do {
                _ = try await store.uploadHostArtifact(runID: runID, agent: agent, remotePath: entry.path)
                status = "Registered “\(entry.name)” as an artifact."
            } catch {
                status = error.localizedDescription
            }
        }
    }
}
#endif
