import SwiftUI
import DesignSystem
import LancerCore

private enum Destination: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case diagnostics = "Diagnostics"
    case devices = "Devices"
    case agentsWorkspaces = "Agents & Workspaces"
    case security = "Security"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .diagnostics: return "stethoscope"
        case .devices: return "laptopcomputer"
        case .agentsWorkspaces: return "person.2"
        case .security: return "lock.shield"
        }
    }

    var isEnabled: Bool {
        switch self {
        case .overview, .diagnostics: return true
        case .devices, .agentsWorkspaces, .security: return false
        }
    }
}

struct ManagementView: View {
    @Environment(HostModel.self) private var host
    @State private var selection: Destination? = .overview

    var body: some View {
        NavigationSplitView {
            List(Destination.allCases, selection: $selection) { destination in
                Label(destination.rawValue, systemImage: destination.systemImage)
                    .foregroundStyle(destination.isEnabled ? .primary : .secondary)
                    .opacity(destination.isEnabled ? 1 : 0.5)
                    .disabled(!destination.isEnabled)
                    .tag(destination as Destination?)
            }
            .navigationTitle("Lancer")
        } detail: {
            switch selection {
            case .overview, .none:
                OverviewPane()
            case .diagnostics:
                DiagnosticsPane()
            case .devices, .agentsWorkspaces, .security:
                ComingSoonPane(title: selection?.rawValue ?? "")
            }
        }
        .frame(minWidth: 760, minHeight: 480)
        .task {
            await host.refresh()
        }
    }
}

// MARK: - Overview

private struct OverviewPane: View {
    @Environment(HostModel.self) private var host
    @Environment(\.lancerTokens) private var tokens

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Overview")
                    .font(.dsDisplayPt(22))
                    .foregroundStyle(tokens.text)

                GroupBox("Host Service") {
                    VStack(alignment: .leading, spacing: 10) {
                        labeledRow("Status", value: healthLabel, valueColor: healthColor)
                        labeledRow("Daemon version", value: host.doctor?.daemonVersion ?? "—")
                        labeledRow("Protocol version", value: "—")
                        labeledRow("Relay", value: checkLabel(host.relayCheck))
                        labeledRow("Direct", value: checkLabel(host.residentDaemonCheck))
                    }
                    .padding(.top, 4)
                }

                GroupBox("Agents") {
                    VStack(alignment: .leading, spacing: 10) {
                        labeledRow("Active agents", value: "\(host.activeAgentCount)")
                        labeledRow("Needs attention", value: "\(host.attentionCount)",
                                    valueColor: host.attentionCount > 0 ? tokens.warn : nil)
                    }
                    .padding(.top, 4)
                }

                GroupBox("Controls") {
                    HStack(spacing: 12) {
                        Button("Pause All") {
                            // TODO: wire to lancerd — no pause-all RPC exists yet.
                        }
                        .disabled(true)

                        Button("Emergency Stop", role: .destructive) {
                            // TODO: wire to lancerd — no emergency-stop RPC exists yet.
                        }
                        .disabled(true)
                    }
                    .padding(.top, 4)
                }

                Spacer()
            }
            .padding(24)
        }
    }

    private var healthLabel: String {
        switch host.connection {
        case .connected: return "Connected"
        case .unreachable(let message): return "Unreachable — \(message)"
        case .unknown: return "Checking…"
        }
    }

    private var healthColor: Color? {
        switch host.connection {
        case .connected: return tokens.ok
        case .unreachable: return tokens.danger
        case .unknown: return nil
        }
    }

    private func checkLabel(_ check: DoctorCheckResult?) -> String {
        guard let check else { return "—" }
        return check.passed ? "OK — \(check.message)" : "Issue — \(check.message)"
    }

    private func labeledRow(_ label: String, value: String, valueColor: Color? = nil) -> some View {
        HStack {
            Text(label)
                .font(.dsSansPt(13))
                .foregroundStyle(tokens.text2)
            Spacer()
            Text(value)
                .font(.dsMonoPt(13))
                .foregroundStyle(valueColor ?? tokens.text)
                .multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - Diagnostics

private struct DiagnosticsPane: View {
    @Environment(HostModel.self) private var host
    @Environment(\.lancerTokens) private var tokens
    @State private var isRunning = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Diagnostics")
                        .font(.dsDisplayPt(22))
                        .foregroundStyle(tokens.text)
                    Spacer()
                    Button {
                        Task {
                            isRunning = true
                            await host.refresh()
                            isRunning = false
                        }
                    } label: {
                        if isRunning {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Run Lancer Doctor")
                        }
                    }
                    .disabled(isRunning)
                }

                if let doctor = host.doctor {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(doctor.checks) { check in
                            checkRow(check)
                            Divider()
                        }
                    }
                } else {
                    Text("No diagnostic data yet. Run Lancer Doctor to check the Host Service.")
                        .font(.dsSansPt(13))
                        .foregroundStyle(tokens.text3)
                }

                GroupBox("Service maintenance") {
                    HStack(spacing: 12) {
                        Button("Restart Service") {
                            // TODO: wire to lancerd — later phase.
                        }
                        .disabled(true)
                        Button("Reinstall Service") {
                            // TODO: wire to lancerd — later phase.
                        }
                        .disabled(true)
                        Button("Uninstall") {
                            // TODO: wire to lancerd — later phase.
                        }
                        .disabled(true)
                        Button("Export Diagnostic Bundle") {
                            // TODO: later phase.
                        }
                        .disabled(true)
                    }
                    .padding(.top, 4)
                }

                Spacer()
            }
            .padding(24)
        }
    }

    private func checkRow(_ check: DoctorCheckResult) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(check.passed ? tokens.ok : tokens.danger)
                .frame(width: 8, height: 8)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                Text(check.name)
                    .font(.dsSansPt(13, weight: .medium))
                    .foregroundStyle(tokens.text)
                Text(check.message)
                    .font(.dsSansPt(12))
                    .foregroundStyle(tokens.text2)
            }
            Spacer()
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Coming soon

private struct ComingSoonPane: View {
    let title: String
    @Environment(\.lancerTokens) private var tokens

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.dsDisplayPt(22))
                .foregroundStyle(tokens.text)
            Text("Coming soon")
                .font(.dsSansPt(13))
                .foregroundStyle(tokens.text3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
