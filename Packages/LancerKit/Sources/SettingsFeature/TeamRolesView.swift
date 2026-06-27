#if os(iOS)
import SwiftUI
import LancerCore
import DesignSystem

public struct TeamRolesView: View {
    @Environment(\.lancerTokens) private var t
    @Environment(\.dismiss) private var dismiss

    @State private var store = TeamRoleStore()
    @State private var members: [TeamMember] = []
    @State private var showAddSheet = false
    @State private var newName = ""
    @State private var newRole: TeamRole = .approver
    @State private var onCallID: String? = nil

    private let embedded: Bool

    public init(embedded: Bool = false) { self.embedded = embedded }

    public var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                if !embedded {
                    DSDetailHeader("team & roles", onBack: { dismiss() })
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        onCallSection

                        ForEach(members) { member in
                            memberCard(member)
                        }

                        DSButton("add teammate", variant: .secondary, size: .sm, mono: true) {
                            newName = ""
                            newRole = .approver
                            showAddSheet = true
                        }
                        .accessibilityIdentifier("team.addTeammate")
                    }
                    .padding(16)
                }
            }
        }
        .navigationBarHidden(!embedded)
        .onAppear { reload() }
        .sheet(isPresented: $showAddSheet) {
            addSheet
        }
    }

    @ViewBuilder
    private var onCallSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("on-call approver")
                .font(.dsMonoPt(11, weight: .bold))
                .foregroundStyle(t.text3)
                .textCase(.uppercase)

            Menu {
                ForEach(members.filter { $0.role.canApprove }) { member in
                    Button(member.name) {
                        store.setOnCall(member.id)
                        onCallID = member.id
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    let name = members.first(where: { $0.id == onCallID })?.name ?? "none"
                    Text(name)
                        .font(.dsSansPt(15))
                        .foregroundStyle(t.text)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.dsMonoPt(12))
                        .foregroundStyle(t.text3)
                }
                .padding(14)
                .background(t.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(t.border, lineWidth: 1))
            }
            .accessibilityIdentifier("team.onCallPicker")
        }
    }

    @ViewBuilder
    private func memberCard(_ member: TeamMember) -> some View {
        let isSelf = member.id == "lancer.self"
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(member.name)
                    .font(.dsDisplayPt(15, weight: .bold))
                    .foregroundStyle(t.text)
                if onCallID == member.id {
                    Text("on-call")
                        .font(.dsMonoPt(10, weight: .bold))
                        .foregroundStyle(t.accent)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(t.surface2, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                Spacer(minLength: 0)
                roleBadge(member.role)
            }

            Text(member.role.capabilities.joined(separator: " · "))
                .font(.dsMonoPt(11))
                .foregroundStyle(t.text3)

            if !isSelf {
                HStack(spacing: 8) {
                    Menu {
                        ForEach(TeamRole.allCases, id: \.self) { role in
                            Button(role.rawValue) {
                                store.setRole(member.id, role: role)
                                reload()
                            }
                        }
                    } label: {
                        Text("change role")
                            .font(.dsMonoPt(12))
                            .foregroundStyle(t.accent)
                    }
                    .accessibilityIdentifier("team.changeRole.\(member.id)")

                    Spacer(minLength: 0)

                    DSButton("remove", variant: .destructive, size: .sm, mono: true) {
                        store.remove(id: member.id)
                        reload()
                    }
                    .accessibilityIdentifier("team.remove.\(member.id)")
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(t.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(t.border, lineWidth: 1))
    }

    @ViewBuilder
    private func roleBadge(_ role: TeamRole) -> some View {
        Text(role.rawValue.uppercased())
            .font(.dsMonoPt(10, weight: .bold))
            .foregroundStyle(badgeColor(role))
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(t.surface2, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func badgeColor(_ role: TeamRole) -> Color {
        switch role {
        case .owner:    t.accent
        case .approver: t.ok
        case .viewer:   t.text3
        }
    }

    @ViewBuilder
    private var addSheet: some View {
        NavigationStack {
            ZStack {
                t.bg.ignoresSafeArea()
                Form {
                    Section("name") {
                        TextField("teammate name", text: $newName)
                            .font(.dsSansPt(15))
                    }
                    Section("role") {
                        Picker("role", selection: $newRole) {
                            ForEach(TeamRole.allCases.filter { $0 != .owner }, id: \.self) { role in
                                Text(role.rawValue).tag(role)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }
            }
            .navigationTitle("add teammate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel") { showAddSheet = false }
                        .font(.dsSansPt(15))
                        .foregroundStyle(t.text2)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("add") {
                        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        store.add(name: trimmed, role: newRole)
                        showAddSheet = false
                        reload()
                    }
                    .font(.dsSansPt(15, weight: .semibold))
                    .foregroundStyle(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? t.text3 : t.accent)
                    .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("team.confirmAdd")
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func reload() {
        members = store.all()
        onCallID = store.onCallMember()?.id
    }
}

#Preview {
    TeamRolesView()
}
#endif
