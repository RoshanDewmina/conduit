#if os(iOS)
import SwiftUI

/// Add Repo sheet — enter a real cwd path; no fake GitHub / sample list.
/// Re-adding a path that already exists (after normalization) is a no-op that
/// selects the existing repo via `onAdd`.
public struct AddRepoView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var pathText = ""
    @State private var nameText = ""

    private let onAdd: (_ name: String, _ cwd: String) -> Void

    public init(onAdd: @escaping (_ name: String, _ cwd: String) -> Void) {
        self.onAdd = onAdd
    }

    private var normalizedPath: String {
        WorkspaceRepoCatalog.normalizeCwd(pathText)
    }

    private var canAdd: Bool { !normalizedPath.isEmpty }

    private var previewName: String {
        let trimmed = nameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        guard canAdd else { return "" }
        return WorkspaceRepoCatalog.displayName(forCwd: normalizedPath)
    }

    public var body: some View {
        VStack(spacing: 0) {
            RepoSheetHeader(title: "Add Repo") { dismiss() }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Repos also appear automatically when you run an agent in them from a paired machine. Add one manually if you want to send there before the first thread exists.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Path on the machine")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        TextField("~/Documents/my-repo", text: $pathText)
                            .font(.system(size: 16))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color(.secondarySystemBackground))
                            )
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Display name (optional)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        TextField(previewName.isEmpty ? "my-repo" : previewName, text: $nameText)
                            .font(.system(size: 16))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color(.secondarySystemBackground))
                            )
                    }

                    Button {
                        guard canAdd else { return }
                        // Always hand the normalized cwd to the store; duplicate
                        // normalized paths are a no-op that re-selects the existing repo.
                        onAdd(previewName, normalizedPath)
                        dismiss()
                    } label: {
                        Text("Add Repo")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .foregroundStyle(canAdd ? Color(.systemBackground) : .secondary)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(canAdd ? Color.primary : Color(.tertiarySystemFill))
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(!canAdd)
                    .padding(.top, 8)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 24)
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

#Preview {
    AddRepoView { _, _ in }
}
#endif
