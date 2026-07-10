#if os(iOS)
import SwiftUI

/// Section 1 of the frontend rebuild: a faithful, Apple-native recreation of
/// the Cursor-mobile "Workspaces" launch screen (owner reference screenshots
/// `IMG_2408`/`IMG_2423`). Visual-only for this milestone — rows and the
/// composer are static sample data with no navigation, no sheets, and no
/// live wiring. System `SF Symbols` + semantic colors only, no DesignSystem
/// module.
public struct WorkspacesView: View {
    @State private var isProfilePresented = false
    @State private var isComposerPresented = false
    @State private var isAddRepoPresented = false
    @State private var isSearchPresented = false
    #if DEBUG
    @State private var isComposerRepoPickerPresented = false
    @State private var isRepoPickerDirectPresented = false
    @State private var isThreadListDirectPresented = false
    @State private var isContextDirectPresented = false
    @State private var isThreadDetailDirectPresented = false
    @State private var isPRDetailDirectPresented = false
    #endif

    public init() {}

    public var body: some View {
        ZStack(alignment: .bottom) {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                topBar
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                Text("Workspaces")
                    .font(.largeTitle.bold())
                    .padding(.horizontal, 20)
                    .padding(.top, 28)
                    .padding(.bottom, 8)

                VStack(spacing: 0) {
                    ForEach(Self.rows) { row in
                        if row.title == "Add Repo" {
                            Button {
                                isAddRepoPresented = true
                            } label: {
                                WorkspaceRowView(row: row)
                            }
                            .buttonStyle(.plain)
                        } else {
                            NavigationLink {
                                ThreadListView(workspaceName: row.title)
                            } label: {
                                WorkspaceRowView(row: row)
                            }
                            .buttonStyle(.plain)
                        }
                        Divider()
                            .padding(.leading, 58)
                    }
                }

                Spacer(minLength: 0)
            }

            Button {
                isComposerPresented = true
            } label: {
                composer
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("New Chat"))
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .sheet(isPresented: $isProfilePresented) {
            ProfileView()
        }
        .sheet(isPresented: $isComposerPresented) {
            #if DEBUG
            NewChatComposerView(initiallyShowsRepoPicker: isComposerRepoPickerPresented)
            #else
            NewChatComposerView()
            #endif
        }
        .sheet(isPresented: $isAddRepoPresented) {
            AddRepoView()
        }
        .sheet(isPresented: $isSearchPresented) {
            SearchView()
        }
        #if DEBUG
        .sheet(isPresented: $isRepoPickerDirectPresented) {
            RepoPickerView()
        }
        #endif
        #if DEBUG
        .sheet(isPresented: $isContextDirectPresented) {
            ContextAttachView()
        }
        #endif
        #if DEBUG
        .navigationDestination(isPresented: $isThreadListDirectPresented) {
            ThreadListView(workspaceName: "conduit")
        }
        #endif
        #if DEBUG
        .navigationDestination(isPresented: $isThreadDetailDirectPresented) {
            ThreadDetailView(thread: ThreadRow(title: "Fix onboarding flow", status: .checksPassed, diffStat: "+142 -18"))
        }
        #endif
        #if DEBUG
        .navigationDestination(isPresented: $isPRDetailDirectPresented) {
            PRDetailView()
        }
        #endif
        #if DEBUG
        .onAppear {
            switch ProcessInfo.processInfo.environment["LANCER_DESTINATION"] {
            case "profile":
                isProfilePresented = true
            case "composer":
                isComposerPresented = true
            case "repoPicker":
                isComposerRepoPickerPresented = true
                isComposerPresented = true
            case "addRepo":
                isAddRepoPresented = true
            case "repoPickerDirect":
                isRepoPickerDirectPresented = true
            case "context":
                isContextDirectPresented = true
            case "threadList":
                isThreadListDirectPresented = true
            case "threadDetail":
                isThreadDetailDirectPresented = true
            case "prDetail":
                isPRDetailDirectPresented = true
            case "search":
                isSearchPresented = true
            default:
                break
            }
        }
        #endif
    }

    private var topBar: some View {
        HStack {
            Button {
                isProfilePresented = true
            } label: {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.75), Color.purple.opacity(0.65)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(Text("Profile"))

            Spacer()

            HStack(spacing: 12) {
                Button {
                    isSearchPresented = true
                } label: {
                    circleButton(systemImage: "magnifyingglass")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Search"))

                Button {
                    isComposerPresented = true
                } label: {
                    circleButton(systemImage: "plus")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("New Chat"))
            }
        }
    }

    private func circleButton(systemImage: String) -> some View {
        Circle()
            .fill(Color(.secondarySystemBackground))
            .frame(width: 44, height: 44)
            .overlay(
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.primary)
            )
    }

    private var composer: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(.tertiarySystemFill))
                .frame(width: 34, height: 34)
                .overlay(
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                )

            Text("Plan, ask, build…")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)

            Spacer()

            Circle()
                .fill(Color(.tertiarySystemFill))
                .frame(width: 34, height: 34)
                .overlay(
                    Image(systemName: "mic.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color(.secondarySystemBackground)))
        .overlay(Capsule().strokeBorder(Color(.separator), lineWidth: 0.5))
    }

    fileprivate static let rows: [WorkspaceRow] = [
        WorkspaceRow(title: "All Repos", systemImage: "square.stack", showsChevron: true),
        WorkspaceRow(title: "conduit", systemImage: "folder", showsChevron: true),
        WorkspaceRow(title: "personal-web", systemImage: "folder", showsChevron: true),
        WorkspaceRow(title: "Add Repo", systemImage: "folder.badge.plus", showsChevron: false),
    ]
}

private struct WorkspaceRow: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String
    let showsChevron: Bool
}

private struct WorkspaceRowView: View {
    let row: WorkspaceRow

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: row.systemImage)
                .font(.system(size: 19, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: 24)

            Text(row.title)
                .font(.system(size: 17))
                .foregroundStyle(.primary)

            Spacer()

            if row.showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(.tertiaryLabel))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

#Preview {
    NavigationStack {
        WorkspacesView()
    }
}
#endif
