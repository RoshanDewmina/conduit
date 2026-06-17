#if os(iOS)
import SwiftUI
import ConduitCore
import DesignSystem

// MARK: - NewWorktreeView
// Form for creating a new worktree — branch picker, name input, agent assignment.
// Matches design 02 (NewWorktreeSheet).

public struct NewWorktreeView: View {
    let availableBranches: [String]
    let onCreate: (String, String, String?) -> Void
    let onCancel: () -> Void

    @Environment(\.conduitTokens) private var t
    @State private var selectedBaseBranch: String
    @State private var newBranchName: String = ""
    @State private var selectedAgent: String?

    public init(
        availableBranches: [String] = ["master", "main"],
        defaultBaseBranch: String? = nil,
        onCreate: @escaping (String, String, String?) -> Void = { _, _, _ in },
        onCancel: @escaping () -> Void = {}
    ) {
        self.availableBranches = availableBranches
        self.onCreate = onCreate
        self.onCancel = onCancel
        self._selectedBaseBranch = State(initialValue: defaultBaseBranch ?? availableBranches.first ?? "master")
    }

    public var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                DSDetailHeader("new worktree", onBack: onCancel)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Base branch picker
                        sectionLabel("BASE BRANCH")
                        branchPicker

                        // New branch name
                        sectionLabel("NEW BRANCH NAME")
                        branchNameInput

                        // Assign agent
                        sectionLabel("ASSIGN AGENT")
                        agentPicker

                        // Create button
                        DSButton(
                            "Create worktree",
                            systemImage: "plus",
                            variant: .primary,
                            size: .lg,
                            fullWidth: true
                        ) {
                            Haptics.selection()
                            onCreate(selectedBaseBranch, newBranchName, selectedAgent)
                        }
                        .disabled(newBranchName.trimmingCharacters(in: .whitespaces).isEmpty)
                        .padding(.top, 8)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
            }
        }
    }

    // MARK: - Section label

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.dsMonoPt(10))
            .tracking(10 * 0.16)
            .textCase(.uppercase)
            .foregroundStyle(t.text3)
    }

    // MARK: - Branch picker

    private var branchPicker: some View {
        Menu {
            ForEach(availableBranches, id: \.self) { branch in
                Button {
                    selectedBaseBranch = branch
                } label: {
                    HStack {
                        Text(branch)
                        if branch == selectedBaseBranch {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack {
                Text(selectedBaseBranch)
                    .font(.dsMonoPt(12))
                    .foregroundStyle(t.text)
                Spacer()
                DSIconView(.chevronDown, size: 12, color: t.text3)
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(t.surface2)
            .clipShape(RoundedRectangle(cornerRadius: t.r4, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: t.r4, style: .continuous)
                    .strokeBorder(t.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Branch name input

    private var branchNameInput: some View {
        HStack {
            TextField("feat/my-feature", text: $newBranchName)
                .font(.dsMonoPt(12))
                .foregroundStyle(t.text)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(t.surface2)
        .clipShape(RoundedRectangle(cornerRadius: t.r4, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: t.r4, style: .continuous)
                .strokeBorder(t.border, lineWidth: 1)
        )
    }

    // MARK: - Agent picker

    private var agentPicker: some View {
        Menu {
            ForEach(agents, id: \.self) { agent in
                Button {
                    selectedAgent = agent
                } label: {
                    HStack {
                        Text(agent)
                        if agent == selectedAgent {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 10) {
                if let agent = selectedAgent {
                    PixelAvatar(seed: agent, size: 24)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(agent)
                            .font(.dsMonoPt(12))
                            .foregroundStyle(t.text)
                        Text(modelLabel(for: agent))
                            .font(.dsMonoPt(10))
                            .foregroundStyle(t.text3)
                    }
                } else {
                    Text("Select agent")
                        .font(.dsMonoPt(12))
                        .foregroundStyle(t.text3)
                }
                Spacer()
                DSIconView(.chevronDown, size: 12, color: t.text3)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(t.surface2)
            .clipShape(RoundedRectangle(cornerRadius: t.r4, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: t.r4, style: .continuous)
                    .strokeBorder(t.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private let agents = ["Claude Code", "Codex", "Cursor", "OpenCode"]

    private func modelLabel(for agent: String) -> String {
        switch agent {
        case "Claude Code": return "claude-sonnet-4.6"
        case "Codex":       return "gpt-5.1-codex"
        case "Cursor":      return "cursor-default"
        case "OpenCode":    return "deepseek-v4"
        default:            return ""
        }
    }
}

#if DEBUG
#Preview {
    NewWorktreeView()
}
#endif
#endif
