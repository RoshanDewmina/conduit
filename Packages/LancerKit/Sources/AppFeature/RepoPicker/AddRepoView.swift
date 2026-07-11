#if os(iOS)
import SwiftUI

/// Section 4 of the frontend rebuild: a faithful, Apple-native recreation of
/// the Cursor-mobile "Add Repo" sheet (owner reference screenshot
/// `IMG_2414`). Presented from the Workspaces root's static "Add Repo" row.
/// Visual-only for this milestone — the search field does not filter, and
/// tapping a row does nothing (no selection wiring back to Workspaces).
/// System `SF Symbols` + semantic colors only, no DesignSystem module.
/// Reuses the shared sheet chrome + row view defined in `RepoPickerView.swift`.
public struct AddRepoView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            RepoSheetHeader(title: "Add Repo") { dismiss() }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 12)

            RepoSearchField(text: $searchText)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    RepoSectionHeader(title: "Workspaces")
                        .padding(.top, 20)

                    ForEach(Self.workspaceRepos) { repo in
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

    private static let workspaceRepos: [RepoRow] = [
        RepoRow(name: "marketing-site", branch: nil, showsSwitcher: false),
        RepoRow(name: "api-gateway", branch: nil, showsSwitcher: false),
        RepoRow(name: "design-tokens", branch: nil, showsSwitcher: false),
        RepoRow(name: "docs-site", branch: nil, showsSwitcher: false),
        RepoRow(name: "mobile-app", branch: nil, showsSwitcher: false),
        RepoRow(name: "internal-tools", branch: nil, showsSwitcher: false),
        RepoRow(name: "data-pipeline", branch: nil, showsSwitcher: false),
        RepoRow(name: "onboarding-flow", branch: nil, showsSwitcher: false),
        RepoRow(name: "billing-service", branch: nil, showsSwitcher: false),
    ]
}

#Preview {
    AddRepoView()
}
#endif
