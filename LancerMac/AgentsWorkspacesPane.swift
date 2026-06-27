import SwiftUI
import DesignSystem
import LancerCore

struct AgentsWorkspacesPane: View {
    @Environment(HostModel.self) private var host
    @Environment(\.lancerTokens) private var tokens

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Agents & Workspaces")
                    .font(.dsDisplayPt(22))
                    .foregroundStyle(tokens.text)

                GroupBox("Detected agents") {
                    if let agents = host.status?.agents, !agents.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(agents) { agent in
                                agentRow(agent)
                                Divider()
                            }
                        }
                        .padding(.top, 4)
                    } else {
                        Text("No agents detected. Lancer detects Claude Code, Codex, OpenCode, and Kimi when installed.")
                            .font(.dsSansPt(13))
                            .foregroundStyle(tokens.text3)
                            .padding(.top, 4)
                    }
                }

                GroupBox("Privacy") {
                    privacySection
                        .padding(.top, 4)
                }

                GroupBox("Allowed workspace roots") {
                    Text("Lancer only lets agents act inside roots you allow. Configuring roots from the Mac app is coming soon — manage them in the phone app's Security settings for now.")
                        .font(.dsSansPt(12))
                        .foregroundStyle(tokens.text2)
                        .padding(.top, 4)
                }

                Spacer()
            }
            .padding(24)
        }
    }

    @ViewBuilder
    private var privacySection: some View {
        let agents = host.status?.agents ?? []
        let leaking = agents.filter { $0.dataLeavesHost == true }
        if agents.isEmpty {
            Text("—")
                .font(.dsSansPt(12))
                .foregroundStyle(tokens.text3)
        } else if leaking.isEmpty {
            Text("All detected agents run locally or keep data on this host.")
                .font(.dsSansPt(12))
                .foregroundStyle(tokens.ok)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(leaking) { agent in
                    Text("\(friendlyName(agent.agent)) — sends data off this host")
                        .font(.dsSansPt(12))
                        .foregroundStyle(tokens.text2)
                }
            }
        }
    }

    @ViewBuilder
    private func agentRow(_ a: AgentVendorStatus) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill((a.runningCount ?? 0) > 0 ? tokens.ok : tokens.text3)
                .frame(width: 8, height: 8)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 2) {
                Text(friendlyName(a.agent))
                    .font(.dsSansPt(13, weight: .medium))
                    .foregroundStyle(tokens.text)
                Text(subtitle(for: a))
                    .font(.dsSansPt(12))
                    .foregroundStyle(tokens.text2)
            }

            Spacer()

            if a.loggedIn == true {
                Text("signed in")
                    .font(.dsSansPt(12))
                    .foregroundStyle(tokens.ok)
            } else if a.loggedIn == false {
                Text("signed out")
                    .font(.dsSansPt(12))
                    .foregroundStyle(tokens.warn)
            }
        }
        .padding(.vertical, 8)
    }

    private func subtitle(for a: AgentVendorStatus) -> String {
        var text = "\(a.runningCount ?? 0) running · \(a.sessionCount) session(s)"
        if let model = a.model {
            text += " · \(model)"
        }
        return text
    }

    private func friendlyName(_ raw: String) -> String {
        switch raw {
        case "claudeCode": return "Claude Code"
        case "codex": return "Codex"
        case "opencode": return "OpenCode"
        case "kimi": return "Kimi"
        default: return raw
        }
    }
}
