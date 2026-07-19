#if os(iOS)
import SwiftUI
import LancerCore
import SessionFeature

/// Workspaces "Agents" section — live/observed sessions on the paired machine.
/// Polls `agent.sessions.list` + `agent.status` ~every 5s while visible; stops when not.
public struct RunningAgentsSection: View {
    @Environment(RelayFleetStore.self) private var relayFleetStore
    @Environment(ShellLiveBridge.self) private var shellLiveBridge

    /// Called when the user opens an observed session into a Lancer live thread.
    /// Prompt is empty on row tap — the live thread adopts/hydrates; the first
    /// typed follow-up performs `agent.observedSession.continue`.
    private let onContinueInLancer: (ObservedSession, String) -> Void

    @State private var rows: [RunningAgentsMapping.Row] = []
    @State private var tracker = RunningAgentsFreshness.Tracker()
    @State private var statusMessage: String?
    @State private var totalRunningFromStatus: Int = 0

    public init(onContinueInLancer: @escaping (ObservedSession, String) -> Void) {
        self.onContinueInLancer = onContinueInLancer
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader
            Divider().padding(.leading, 20)

            if let statusMessage, rows.isEmpty {
                Text(statusMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                Divider().padding(.leading, 58)
            } else if rows.isEmpty && statusMessage == nil && !tracker.hasEverSucceeded {
                Text("Checking for agents…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                Divider().padding(.leading, 58)
            } else {
                if let statusMessage, tracker.isDegraded {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                        .padding(.bottom, 4)
                }
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    Button {
                        let session = ObservedSession(
                            sessionId: row.sessionId,
                            provider: row.provider,
                            title: row.title,
                            cwd: row.cwd,
                            state: row.state,
                            source: .transcriptObserved,
                            lastActivity: row.lastActivity,
                            messageCount: 0
                        )
                        onContinueInLancer(session, "")
                    } label: {
                        agentRow(row)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("running-agent-row-\(index)")
                    Divider().padding(.leading, 58)
                }
            }
        }
        .accessibilityIdentifier("running-agents-section")
        .task {
            await pollLoop()
        }
    }

    private var sectionHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Agents")
                .font(.title3.weight(.semibold))
            Spacer()
            if totalRunningFromStatus > 0 || rows.contains(where: \.isRunning) {
                Text("\(max(totalRunningFromStatus, rows.filter(\.isRunning).count)) running")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 10)
    }

    private func agentRow(_ row: RunningAgentsMapping.Row) -> some View {
        HStack(spacing: 14) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: row.systemImage)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                if row.isRunning {
                    RunningPulseDot()
                        .offset(x: 4, y: -2)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.system(size: 17))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("\(row.providerLabel) · \(RunningAgentsMapping.cwdSubtitle(row.cwd))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(row.stateLabel)
                    .font(.caption.weight(row.isRunning ? .semibold : .regular))
                    .foregroundStyle(row.isRunning ? Color.accentColor : .secondary)
                Text(relativeTime(row.lastActivity))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(.tertiaryLabel))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: .now)
    }

    private func pollLoop() async {
        while !Task.isCancelled {
            await refreshOnce()
            do {
                try await Task.sleep(nanoseconds: RunningAgentsFreshness.pollIntervalNanoseconds)
            } catch {
                return
            }
        }
    }

    private func refreshOnce() async {
        let now = Date()
        guard let machine = relayFleetStore.firstConnectedMachine else {
            // Cold-launch / reconnect: banner may already say Connected while
            // ConnectionStateStore is still transitional — don't burn failure
            // budget on that tick.
            if isAwaitingConnectedMachine {
                statusMessage = RunningAgentsFreshness.statusMessage(
                    rowCount: rows.count,
                    tracker: tracker,
                    now: now
                )
                return
            }
            _ = RunningAgentsFreshness.recordFailure(&tracker)
            statusMessage = RunningAgentsFreshness.statusMessage(
                rowCount: rows.count,
                tracker: tracker,
                now: now
            )
            return
        }

        do {
            async let sessionsTask = machine.bridge.relayListSessions()
            async let statusTask = machine.bridge.sendStatusQuery(homeDir: nil)
            let sessions = try await sessionsTask
            let status = try? await statusTask

            rows = RunningAgentsMapping.rows(from: sessions)
            totalRunningFromStatus = RunningAgentsMapping.totalRunningCount(from: status)
            _ = RunningAgentsFreshness.recordSuccess(&tracker, at: now)
            statusMessage = RunningAgentsFreshness.statusMessage(
                rowCount: rows.count,
                tracker: tracker,
                now: now
            )
            // Feed Home Screen AgentStatusWidget from the same poll — not
            // from SessionViewModel's Live Activity "connected" status.
            RunningAgentsMapping.writeRunningAgentsWidgetSnapshot(
                rows: rows,
                status: status,
                hostName: machine.record.displayName
            )
        } catch {
            _ = RunningAgentsFreshness.recordFailure(&tracker)
            statusMessage = RunningAgentsFreshness.statusMessage(
                rowCount: rows.count,
                tracker: tracker,
                now: now
            )
        }
    }

    /// True while fleet hydration is incomplete or any machine is still
    /// `.reconnecting` / `.hostOffline` (could become connected without a re-pair).
    private var isAwaitingConnectedMachine: Bool {
        if !shellLiveBridge.isHydrated { return true }
        for machine in relayFleetStore.machines {
            switch relayFleetStore.connectionState(for: machine.id) {
            case .reconnecting, .hostOffline:
                return true
            case .connected, .pairingInvalid, .none:
                continue
            }
        }
        return false
    }
}

// MARK: - Pulse

private struct RunningPulseDot: View {
    @State private var pulsed = false

    var body: some View {
        Circle()
            .fill(Color.green)
            .frame(width: 7, height: 7)
            .opacity(pulsed ? 0.35 : 1)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulsed)
            .onAppear { pulsed = true }
            .accessibilityHidden(true)
    }
}

#endif
