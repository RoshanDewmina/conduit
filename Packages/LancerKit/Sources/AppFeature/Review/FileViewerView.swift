#if os(iOS)
import SwiftUI

/// Read-only file viewer: Done / share, monospaced + line numbers, binary/truncated states.
struct FileViewerView: View {
    let conversationID: String
    let path: String
    let dataSource: any ReviewDataSource

    @Environment(\.dismiss) private var dismiss
    @State private var content: RepoFileContent?
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var sharePayload: SharePayload?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let loadError {
                    Text(loadError)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .padding()
                } else if let content {
                    fileBody(content)
                }
            }
            .background(Color(.systemBackground))
            .navigationTitle(ChatFileNameDisplay.displayName(for: path))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        if let content, !content.binary {
                            sharePayload = SharePayload(text: content.content)
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(content == nil || content?.binary == true)
                    .accessibilityLabel(Text("Share"))
                }
            }
        }
        .task { await load() }
        .sheet(item: $sharePayload) { payload in
            ActivityView(activityItems: [payload.text])
        }
    }

    @ViewBuilder
    private func fileBody(_ content: RepoFileContent) -> some View {
        if content.binary {
            VStack(spacing: 12) {
                Image(systemName: "doc.zipper")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
                Text("Binary file")
                    .font(.system(size: 16, weight: .semibold))
                Text("\(content.size) bytes")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 0) {
                    if content.truncated {
                        Text("Truncated preview")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    }
                    let lines = content.content.split(separator: "\n", omittingEmptySubsequences: false)
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        HStack(alignment: .top, spacing: 0) {
                            Text("\(index + 1)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .frame(width: 40, alignment: .trailing)
                                .padding(.trailing, 10)
                            Text(String(line))
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 1)
                        .padding(.horizontal, 8)
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }

    private func load() async {
        isLoading = true
        do {
            content = try await dataSource.file(
                conversationID: conversationID,
                path: path,
                maxBytes: 256_000
            )
        } catch {
            loadError = error.localizedDescription
        }
        isLoading = false
    }
}

private struct SharePayload: Identifiable {
    let id = UUID()
    let text: String
}

private struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
