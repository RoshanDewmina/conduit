#if os(iOS)
import SwiftUI
import DesignSystem
import AgentKit
import SettingsFeature

// MARK: - Team org members + invite

struct AgentOrgView: View {
    @Bindable var store: AgentStore

    @State private var inviteEmail = ""
    @State private var inviteSending = false
    @State private var showingRunnerSetup = false
    @Environment(\.lancerTokens) private var t
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                DSDetailHeader(store.teamOrg?.displayName ?? "Team", onBack: { dismiss() })
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        runnerSetupLink
                        membersSection
                        inviteSection
                    }
                    .padding(16)
                }
            }
        }
        .navigationBarHidden(true)
        .task {
            await store.loadOrgMembers()
        }
        .navigationDestination(isPresented: $showingRunnerSetup) {
            RunnerSetupView(selectedChoice: .constant(.sshHost)) {
                // Continue — navigate to provisioning or dismiss
            }
        }
    }

    // MARK: - Runner setup link

    private var runnerSetupLink: some View {
        Button {
            showingRunnerSetup = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "server.rack")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(t.accent)
                    .frame(width: 18)
                Text("Where should agents run?")
                    .font(.dsMonoPt(13, weight: .semibold))
                    .foregroundStyle(t.text)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(t.text4)
            }
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Members

    private var membersSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            DSListSectionHead("MEMBERS")
            if store.orgMembers.isEmpty {
                Text("No members yet.")
                    .font(.dsMonoPt(13))
                    .foregroundStyle(t.text3)
                    .padding(.vertical, 12)
            } else {
                ForEach(store.orgMembers) { member in
                    memberRow(member)
                    DSDivider()
                }
            }
        }
    }

    private func memberRow(_ member: OrgMember) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(member.email)
                    .font(.dsMonoPt(13, weight: .semibold))
                    .foregroundStyle(t.text)
                Text(member.role)
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text3)
                if let invitedAt = member.invitedAt {
                    Text("invited \(invitedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.dsMonoPt(11))
                        .foregroundStyle(t.text4)
                }
            }
            Spacer()
            DSChip(
                member.status,
                tone: member.status == "accepted" ? .ok : .warn,
                variant: .soft,
                size: .sm
            )
        }
        .padding(.vertical, 12)
    }

    // MARK: - Invite

    private var inviteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            DSListSectionHead("INVITE")
            TextField("Email address", text: $inviteEmail)
                .font(.dsMonoPt(13))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .keyboardType(.emailAddress)
                .padding(10)
                .background(t.surface, in: RoundedRectangle(cornerRadius: t.r2))
                .overlay(
                    RoundedRectangle(cornerRadius: t.r2)
                        .strokeBorder(t.border, lineWidth: 1))
            DSButton(inviteSending ? "Sending…" : "Send invite", variant: .secondary, mono: true) {
                Task {
                    inviteSending = true
                    defer { inviteSending = false }
                    try? await store.inviteMember(email: inviteEmail, role: nil)
                    inviteEmail = ""
                }
            }
            .disabled(inviteEmail.isEmpty || inviteSending)
            Text("Invites are recorded on the server; email delivery is not yet enabled.")
                .font(.dsMonoPt(11))
                .foregroundStyle(t.text4)
        }
    }
}
#endif
