import SwiftUI
import LancerCore

struct SessionStatusView: View {
    @Environment(WatchStore.self) private var store
    @State private var showStopConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let status = store.sessionStatus {
                    connectedContent(status)
                } else {
                    disconnectedContent
                }
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle("Status")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Stop agent?",
            isPresented: $showStopConfirm,
            titleVisibility: .visible
        ) {
            Button("Stop Agent", role: .destructive) {
                store.emergencyStop()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This disconnects the SSH session and kills any running agent.")
        }
    }

    @ViewBuilder
    private func connectedContent(_ status: WatchSessionStatus) -> some View {
        // Connection status badge
        HStack(spacing: 6) {
            Circle()
                .fill(status.isConnected ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            Text(status.isConnected ? "Connected" : "Disconnected")
                .font(.caption.weight(.semibold))
                .foregroundStyle(status.isConnected ? .green : .red)
        }

        // Host info
        VStack(alignment: .leading, spacing: 3) {
            Text(status.hostName)
                .font(.body.weight(.medium))
                .lineLimit(1)
            Text(status.hostname)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }

        // Agent indicator
        if status.agentActive {
            HStack(spacing: 4) {
                Image(systemName: "waveform")
                    .foregroundStyle(.orange)
                Text("Agent running")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }

        // Uptime
        if let connectedAt = status.connectedAt {
            let uptime = formatUptime(since: connectedAt)
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(uptime)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }

        // Pending approvals count
        if status.pendingCount > 0 {
            HStack(spacing: 4) {
                Image(systemName: "tray.fill")
                    .foregroundStyle(.orange)
                    .font(.caption2)
                Text("\(status.pendingCount) pending")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }

        Spacer(minLength: 8)

        // Emergency stop
        if status.isConnected {
            Button {
                showStopConfirm = true
            } label: {
                Label(
                    store.isStopping ? "Stopping…" : "Emergency Stop",
                    systemImage: "stop.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .disabled(store.isStopping)
        }
    }

    private var disconnectedContent: some View {
        VStack(spacing: 8) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("No active session")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("Open Lancer on iPhone and connect to a host.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private func formatUptime(since interval: TimeInterval) -> String {
        let secs = Int(Date().timeIntervalSinceReferenceDate - interval)
        if secs < 60 { return "\(secs)s" }
        let mins = secs / 60
        if mins < 60 { return "\(mins)m" }
        return "\(mins / 60)h \(mins % 60)m"
    }
}
