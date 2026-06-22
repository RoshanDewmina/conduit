import SwiftUI
import DesignSystem
import LancerCore

struct MenuBarContentView: View {
    @Environment(HostModel.self) private var host
    @Environment(\.openWindow) private var openWindow
    @Environment(\.lancerTokens) private var tokens

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            healthRow

            VStack(alignment: .leading, spacing: 6) {
                statusRow(label: "Relay", check: host.relayCheck)
                statusRow(label: "Direct", check: host.residentDaemonCheck)
                HStack {
                    Text("Active agents")
                        .font(.dsSansPt(12))
                        .foregroundStyle(tokens.text2)
                    Spacer()
                    Text("\(host.activeAgentCount)")
                        .font(.dsMonoPt(12, weight: .medium))
                        .foregroundStyle(tokens.text)
                }
                HStack {
                    Text("Needs attention")
                        .font(.dsSansPt(12))
                        .foregroundStyle(tokens.text2)
                    Spacer()
                    Text("\(host.attentionCount)")
                        .font(.dsMonoPt(12, weight: .medium))
                        .foregroundStyle(host.attentionCount > 0 ? tokens.warn : tokens.text)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 2) {
                Button("Open Management") {
                    openWindow(id: "management")
                }

                Button("Pause All") {
                    // TODO: wire to lancerd — no pause-all RPC exists yet.
                }
                .disabled(true)

                Button("Emergency Stop") {
                    // TODO: wire to lancerd — no emergency-stop RPC exists yet.
                }
                .disabled(true)

                Button("Diagnostics") {
                    openWindow(id: "management")
                }
            }

            Divider()

            Button("Quit Lancer UI") {
                NSApplication.shared.terminate(nil)
            }

            Text("Quitting the UI does not stop the Host Service.")
                .font(.dsSansPt(10))
                .foregroundStyle(tokens.text3)
        }
        .padding(12)
        .frame(width: 260)
    }

    private var healthRow: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(healthColor)
                .frame(width: 8, height: 8)
            Text("Host Service")
                .font(.dsSansPt(13, weight: .medium))
                .foregroundStyle(tokens.text)
            Spacer()
            Text(healthLabel)
                .font(.dsMonoPt(11))
                .foregroundStyle(tokens.text2)
        }
    }

    private var healthColor: Color {
        switch host.connection {
        case .connected: return tokens.ok
        case .unreachable: return tokens.danger
        case .unknown: return tokens.text4
        }
    }

    private var healthLabel: String {
        switch host.connection {
        case .connected: return "Connected"
        case .unreachable: return "Unreachable"
        case .unknown: return "Checking…"
        }
    }

    private func statusRow(label: String, check: DoctorCheckResult?) -> some View {
        HStack {
            Text(label)
                .font(.dsSansPt(12))
                .foregroundStyle(tokens.text2)
            Spacer()
            if let check {
                Text(check.passed ? "OK" : "Issue")
                    .font(.dsMonoPt(12, weight: .medium))
                    .foregroundStyle(check.passed ? tokens.ok : tokens.danger)
            } else {
                Text("—")
                    .font(.dsMonoPt(12))
                    .foregroundStyle(tokens.text4)
            }
        }
    }
}
