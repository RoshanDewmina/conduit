#if os(iOS)
import SwiftUI

/// Repo picker sheet over the real workspace list (derived + user-added).
public struct RepoPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    let repos: [WorkspaceRepo]
    let selectedCwd: String?
    let onSelect: (WorkspaceRepo) -> Void

    public init(
        repos: [WorkspaceRepo],
        selectedCwd: String?,
        onSelect: @escaping (WorkspaceRepo) -> Void
    ) {
        self.repos = repos
        self.selectedCwd = selectedCwd
        self.onSelect = onSelect
    }

    private var filtered: [WorkspaceRepo] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return repos }
        return repos.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed)
                || $0.cwd.localizedCaseInsensitiveContains(trimmed)
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            RepoSheetHeader(title: "Repo") { dismiss() }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 12)

            RepoSearchField(text: $searchText)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)

            Divider()

            if filtered.isEmpty {
                Text(repos.isEmpty ? "Add a repo to get started" : "No matching repos")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if let active = filtered.first(where: {
                            WorkspaceRepoCatalog.normalizeCwd($0.cwd)
                                == WorkspaceRepoCatalog.normalizeCwd(selectedCwd ?? "")
                        }) {
                            RepoSectionHeader(title: "Active")
                                .padding(.top, 20)
                            Button {
                                onSelect(active)
                                dismiss()
                            } label: {
                                RepoListRow(
                                    repo: RepoRow(
                                        name: active.name,
                                        branch: nil,
                                        showsSwitcher: true,
                                        subtitle: active.cwd
                                    )
                                )
                            }
                            .buttonStyle(.plain)
                            Divider()
                                .padding(.leading, 58)
                        }

                        RepoSectionHeader(title: "Workspaces")
                            .padding(.top, 20)

                        ForEach(filtered) { repo in
                            Button {
                                onSelect(repo)
                                dismiss()
                            } label: {
                                RepoListRow(
                                    repo: RepoRow(
                                        name: repo.name,
                                        branch: nil,
                                        showsSwitcher: false,
                                        subtitle: repo.cwd
                                    )
                                )
                            }
                            .buttonStyle(.plain)
                            Divider()
                                .padding(.leading, 58)
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Shared sheet chrome (used by RepoPickerView + AddRepoView)

struct RepoSheetHeader: View {
    let title: String
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Text(title)
                .font(.title3.bold())
                .frame(maxWidth: .infinity)

            HStack {
                Button(action: onClose) {
                    Circle()
                        .fill(Color(.secondarySystemBackground))
                        .overlay(
                            Circle()
                                .strokeBorder(Color(.separator), lineWidth: 0.5)
                        )
                        .frame(width: 40, height: 40)
                        .overlay(
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.primary)
                        )
                }
                .accessibilityLabel(Text("Close"))

                Spacer()
            }
        }
    }
}

struct RepoSearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("Repo...", text: $text)
                .font(.system(size: 16))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Capsule().fill(Color(.secondarySystemBackground)))
    }
}

struct RepoSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
    }
}

struct RepoRow: Identifiable {
    let id = UUID()
    let name: String
    let branch: String?
    let showsSwitcher: Bool
    var subtitle: String? = nil
}

struct RepoListRow: View {
    let repo: RepoRow

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "folder")
                .font(.system(size: 19, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(repo.name)
                    .font(.system(size: 17))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let subtitle = repo.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if let branch = repo.branch {
                Text(branch)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }

            if repo.showsSwitcher {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(.tertiaryLabel))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

#Preview {
    RepoPickerView(repos: [], selectedCwd: nil, onSelect: { _ in })
}
#endif
