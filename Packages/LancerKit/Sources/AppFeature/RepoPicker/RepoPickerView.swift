#if os(iOS)
import SwiftUI

/// Section 4 of the frontend rebuild: a faithful, Apple-native recreation of
/// the Cursor-mobile "Repo" picker sheet (owner reference screenshot
/// `IMG_2416`). Presented from the New Chat composer's repo/branch selector.
/// Visual-only for this milestone — the search field does not filter, and
/// tapping a row does nothing (no selection wiring back to the composer).
/// System `SF Symbols` + semantic colors only, no DesignSystem module.
public struct RepoPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    public init() {}

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

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    RepoSectionHeader(title: "Active")
                        .padding(.top, 20)

                    RepoListRow(repo: Self.activeRepo)
                    Divider()
                        .padding(.leading, 58)

                    RepoSectionHeader(title: "Recents")
                        .padding(.top, 20)

                    ForEach(Self.recentRepos) { repo in
                        RepoListRow(repo: repo)
                        Divider()
                            .padding(.leading, 58)
                    }

                    RepoSectionHeader(title: "More")
                        .padding(.top, 20)

                    ForEach(Self.moreRepos) { repo in
                        RepoListRow(repo: repo)
                        Divider()
                            .padding(.leading, 58)
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Static sample data

    private static let activeRepo = RepoRow(name: "conduit", branch: "master", showsSwitcher: true)

    private static let recentRepos: [RepoRow] = [
        RepoRow(name: "personal-web", branch: nil, showsSwitcher: false),
        RepoRow(name: "api-gateway", branch: nil, showsSwitcher: false),
    ]

    private static let moreRepos: [RepoRow] = [
        RepoRow(name: "marketing-site", branch: nil, showsSwitcher: false),
        RepoRow(name: "design-tokens", branch: nil, showsSwitcher: false),
        RepoRow(name: "docs-site", branch: nil, showsSwitcher: false),
        RepoRow(name: "mobile-app", branch: nil, showsSwitcher: false),
        RepoRow(name: "internal-tools", branch: nil, showsSwitcher: false),
        RepoRow(name: "data-pipeline", branch: nil, showsSwitcher: false),
        RepoRow(name: "billing-service", branch: nil, showsSwitcher: false),
    ]
}

// MARK: - Shared sheet chrome (used by RepoPickerView + AddRepoView)

/// Centered bold title with a leading circular close button — matches the
/// close-button chrome established in `ProfileView`.
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

/// Static (non-filtering) search capsule with placeholder "Repo...".
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

// MARK: - Row model + view

struct RepoRow: Identifiable {
    let id = UUID()
    let name: String
    let branch: String?
    let showsSwitcher: Bool
}

struct RepoListRow: View {
    let repo: RepoRow

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "folder")
                .font(.system(size: 19, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: 24)

            Text(repo.name)
                .font(.system(size: 17))
                .foregroundStyle(.primary)
                .lineLimit(1)

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
    RepoPickerView()
}
#endif
