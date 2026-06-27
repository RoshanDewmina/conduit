import SwiftUI
import DesignSystem
import LancerCore
import UniformTypeIdentifiers

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

}

struct ManagementView: View {
    @Environment(HostModel.self) private var host
    @State private var selection: Destination? = .overview
    @AppStorage("lancer.mac.firstRunComplete") private var firstRunComplete = false
    @State private var showFirstRun = false

    var body: some View {
        NavigationSplitView {
            List(Destination.allCases, selection: $selection) { destination in
                Label(destination.rawValue, systemImage: destination.systemImage)
                    .tag(destination as Destination?)
            }
            .navigationTitle("Lancer")
        } detail: {
            switch selection {
            case .overview, .none:
                OverviewPane()
            case .diagnostics:
                DiagnosticsPane()
            case .devices:
                DevicesPane()
            case .agentsWorkspaces:
                AgentsWorkspacesPane()
            case .security:
                SecurityPane()
            }
        }
        .frame(minWidth: 760, minHeight: 480)
        .task {
            await host.refresh()
        }
        .onAppear {
            if host.pendingPairingRequest {
                selection = .devices
            }
            showFirstRun = !firstRunComplete
        }
        .sheet(isPresented: $showFirstRun) {
            FirstRunView(onFinish: {
                firstRunComplete = true
                showFirstRun = false
            })
            .environment(host)
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
    @State private var pickingFolder = false
    @State private var scanning = false

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

                driftSection

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

    @ViewBuilder
    private var driftSection: some View {
        GroupBox("Setup drift") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Dead imports & links across CLAUDE.md, AGENTS.md, skills, and rules.")
                        .font(.dsSansPt(12))
                        .foregroundStyle(tokens.text2)
                    Spacer()
                    Button {
                        pickingFolder = true
                    } label: {
                        if scanning {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Scan Folder…")
                        }
                    }
                    .disabled(scanning)
                }

                if let error = host.driftError {
                    Text(error)
                        .font(.dsSansPt(12))
                        .foregroundStyle(tokens.danger)
                } else if let drift = host.drift {
                    if drift.findings.isEmpty {
                        Text("No drift — \(drift.scanned) instruction files clean.")
                            .font(.dsSansPt(12, weight: .medium))
                            .foregroundStyle(tokens.ok)
                    } else {
                        Text("\(drift.findings.count) finding(s) across \(drift.scanned) files")
                            .font(.dsSansPt(12, weight: .medium))
                            .foregroundStyle(tokens.danger)
                        ForEach(drift.findings) { finding in
                            driftRow(finding)
                            Divider()
                        }
                    }
                }
            }
            .padding(.top, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fileImporter(isPresented: $pickingFolder, allowedContentTypes: [.folder]) { result in
            guard case let .success(url) = result else { return }
            Task {
                scanning = true
                let scoped = url.startAccessingSecurityScopedResource()
                await host.scanDrift(root: url.path)
                if scoped { url.stopAccessingSecurityScopedResource() }
                scanning = false
            }
        }
    }

    private func driftRow(_ finding: DriftFinding) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(tokens.danger)
                .frame(width: 8, height: 8)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(finding.file):\(finding.line)")
                    .font(.dsSansPt(12, weight: .medium))
                    .foregroundStyle(tokens.text)
                Text("\(finding.kind) — \(finding.ref)")
                    .font(.dsSansPt(11))
                    .foregroundStyle(tokens.text2)
            }
            Spacer()
        }
        .padding(.vertical, 6)
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

// MARK: - Devices

private struct DevicesPane: View {
    @Environment(HostModel.self) private var host
    @Environment(\.lancerTokens) private var tokens
    @State private var showingPairing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Devices")
                        .font(.dsDisplayPt(22))
                        .foregroundStyle(tokens.text)
                    Spacer()
                    DSButton("Pair device", systemImage: "qrcode", variant: .primary) {
                        showingPairing = true
                    }
                }

                Text("Paired-device management is coming soon. For now, pair a new iPhone by scanning a one-time QR code.")
                    .font(.dsSansPt(13))
                    .foregroundStyle(tokens.text3)

                Spacer()
            }
            .padding(24)
        }
        .onAppear {
            if host.pendingPairingRequest {
                host.pendingPairingRequest = false
                showingPairing = true
            }
        }
        .sheet(isPresented: $showingPairing) {
            PairingView()
        }
    }
}

