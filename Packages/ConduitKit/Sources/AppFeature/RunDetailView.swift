#if os(iOS)
import SwiftUI
import DesignSystem
import SSHTransport

// MARK: - DaemonChannel conforms to RunControlling
// DaemonChannel already exposes pauseRun/resumeRun/stopRun/setRunBudget (the run-control
// RPC calls), so the conformance is structural — the bridge IS the production channel.
extension DaemonChannel: RunControlling {}

// MARK: - Run Detail
// Two-way control surface for a dispatched bridge run: live status + stop / pause-resume /
// set-budget. Mirrors the migration board's `AgentRunDetailScreen`.

public struct RunDetailView: View {
    @State private var store: RunControlStore
    @State private var confirmStop = false
    @State private var showBudgetSheet = false

    private let title: String
    private let subtitle: String

    public init(
        channel: any RunControlling,
        runId: String,
        title: String,
        subtitle: String,
        status: RunControlStatus = .running
    ) {
        _store = State(initialValue: RunControlStore(channel: channel, runId: runId, status: status))
        self.title = title
        self.subtitle = subtitle
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if let err = store.lastError {
                    Text(err)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
        }
        .navigationTitle("run")
        .safeAreaInset(edge: .bottom) { controlBar }
        .confirmationDialog("Stop this run?", isPresented: $confirmStop, titleVisibility: .visible) {
            Button("Stop run", role: .destructive) {
                Haptics.warning()
                Task { await store.stop() }
            }
            Button("Keep running", role: .cancel) {}
        } message: {
            Text("The agent process is terminated. This can't be undone.")
        }
        .sheet(isPresented: $showBudgetSheet) {
            BudgetSheet { usd in Task { await store.setBudget(usd) } }
                .presentationDetents([.height(260)])
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 16, weight: .semibold, design: .monospaced))
            Text(subtitle).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
            statusPill
        }
    }

    private var statusPill: some View {
        let (label, color): (String, Color) = {
            switch store.status {
            case .running: return ("working", .blue)
            case .paused: return ("paused", .orange)
            case .stopped: return ("stopped", .secondary)
            case .budgetExceeded: return ("budget exceeded", .red)
            }
        }()
        return HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
        }
        .padding(.top, 2)
    }

    // Destructive-left ordering per CONDUIT_UI_CONSISTENCY_RULES R3.3; equal-width row.
    private var controlBar: some View {
        HStack(spacing: 8) {
            DSButton("Stop", systemImage: "stop.fill", variant: .destructive, fullWidth: true) {
                // Warning haptic on the destructive path (R6.2) — matches the confirm button below.
                Haptics.warning()
                confirmStop = true
            }
            .disabled(!store.canStop)

            if store.canResume {
                DSButton("Resume", systemImage: "play.fill", variant: .secondary, fullWidth: true) {
                    Haptics.selection()
                    Task { await store.resume() }
                }
            } else {
                DSButton("Pause", systemImage: "pause.fill", variant: .secondary, fullWidth: true) {
                    Haptics.selection()
                    Task { await store.pause() }
                }
                .disabled(!store.canPause)
            }

            DSButton("Budget", systemImage: "gauge.with.dots.needle.50percent", variant: .secondary, fullWidth: true) {
                Haptics.selection()
                showBudgetSheet = true
            }
            .disabled(!store.canSetBudget)
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 28)
        .background(.bar)
        .overlay(Divider(), alignment: .top)
    }
}

// MARK: - Budget sheet

private struct BudgetSheet: View {
    let onSet: (Double) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var amount = "5.00"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Set daily budget")
                .font(.system(size: 17, weight: .semibold, design: .monospaced))
            HStack(spacing: 8) {
                Text("$").font(.system(size: 16, design: .monospaced)).foregroundStyle(.secondary)
                TextField("5.00", text: $amount)
                    .font(.system(size: 16, design: .monospaced))
                    .keyboardType(.decimalPad)
            }
            .padding(.horizontal, 13).frame(height: 46)
            .background(RoundedRectangle(cornerRadius: 2).stroke(.secondary.opacity(0.3)))

            // Disabled until the input parses, so "Set cap" can't silently dismiss on bad input.
            DSButton("Set cap", variant: .primary, fullWidth: true) {
                guard let usd = Double(amount) else { return }
                Haptics.success()
                onSet(usd)
                dismiss()
            }
            .disabled(Double(amount) == nil)
        }
        .padding(18)
    }
}

#Preview {
    // Sendable fake so the preview compiles without a live bridge.
    final class PreviewChannel: RunControlling, @unchecked Sendable {
        func pauseRun(runId: String) async throws -> Bool { true }
        func resumeRun(runId: String) async throws -> Bool { true }
        func stopRun(runId: String) async throws -> Bool { true }
        func setRunBudget(runId: String, budgetUSD: Double) async throws -> Bool { true }
    }
    return NavigationStack {
        RunDetailView(
            channel: PreviewChannel(),
            runId: "r1",
            title: "Claude Code · conduit",
            subtitle: "Dev VPS · claude-sonnet-4.6"
        )
    }
}
#endif
