#if os(iOS)
import SwiftUI

/// Section 5 of the frontend rebuild: a faithful, Apple-native recreation of
/// the Cursor-mobile per-workspace thread list (owner reference screenshot
/// `IMG_2409`). Pushed via `NavigationStack` when tapping a Workspaces row.
/// Visual-only for this milestone — rows are static sample data with no
/// navigation to a thread detail. System `SF Symbols` + semantic colors
/// only, no DesignSystem module.
public struct ThreadListView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isSearchPresented = false
    @State private var isComposerPresented = false
    @State private var activeLiveThread: LiveThreadIdentifier?

    let workspaceName: String

    public init(workspaceName: String) {
        self.workspaceName = workspaceName
    }

    private var workspaceCwd: String {
        LiveThreadCwd.forWorkspace(workspaceName)
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                topBar
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                Text(workspaceName)
                    .font(.largeTitle.bold())
                    .padding(.horizontal, 20)
                    .padding(.top, 28)
                    .padding(.bottom, 8)

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        sectionHeader("Yesterday")

                        ForEach(Self.yesterdayThreads) { thread in
                            NavigationLink {
                                ThreadDetailView(thread: thread, cwd: workspaceCwd)
                            } label: {
                                ThreadListRow(thread: thread)
                            }
                            .buttonStyle(.plain)
                            Divider()
                                .padding(.leading, 40)
                        }

                        sectionHeader("This Week")
                            .padding(.top, 20)

                        ForEach(Self.thisWeekThreads) { thread in
                            NavigationLink {
                                ThreadDetailView(thread: thread, cwd: workspaceCwd)
                            } label: {
                                ThreadListRow(thread: thread)
                            }
                            .buttonStyle(.plain)
                            Divider()
                                .padding(.leading, 40)
                        }
                    }
                    .padding(.bottom, 90)
                }
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
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $isSearchPresented) {
            SearchView()
        }
        .sheet(isPresented: $isComposerPresented) {
            NewChatComposerView(onSend: handleSend)
        }
        .liveThreadPresentation($activeLiveThread)
    }

    private func handleSend(_ prompt: String) {
        activeLiveThread = LiveThreadIdentifier(prompt: prompt, cwd: workspaceCwd)
    }

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                circleButton(systemImage: "chevron.left")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Back"))

            Spacer()

            HStack(spacing: 12) {
                Button {
                    isSearchPresented = true
                } label: {
                    circleButton(systemImage: "magnifyingglass")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Search"))

                circleButton(systemImage: "line.3.horizontal")
                    .accessibilityHidden(true)
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

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
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

    // MARK: - Static sample data

    fileprivate static let yesterdayThreads: [ThreadRow] = [
        ThreadRow(title: "Fix onboarding flow", status: .checksPassed, diffStat: "+142 -18"),
        ThreadRow(title: "Update README", status: .merged, diffStat: nil),
    ]

    fileprivate static let thisWeekThreads: [ThreadRow] = [
        ThreadRow(title: "Refactor auth module", status: .merged, diffStat: "+89 -34"),
        ThreadRow(title: "Investigate flaky CI job", status: .noChanges, diffStat: nil),
        ThreadRow(title: "Add dark mode toggle", status: .checksPassed, diffStat: "+212 -6"),
        ThreadRow(title: "Clean up test fixtures", status: .merged, diffStat: "+54 -201"),
        ThreadRow(title: "Optimize image loading", status: .noChanges, diffStat: nil),
    ]
}

#Preview {
    NavigationStack {
        ThreadListView(workspaceName: "conduit")
    }
}
#endif
