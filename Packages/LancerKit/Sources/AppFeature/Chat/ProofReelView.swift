#if os(iOS)
import SwiftUI
import LancerCore

/// Structured replay scrubber over a single run's proof receipt events.
/// Workspaces-shell chrome (system colors + outline pills) — no DesignSystem.
public struct ProofReelView: View {
    let receipt: ProofReceipt

    @Environment(\.dismiss) private var dismiss

    @State private var scrubIndex: Int = 0
    @State private var isPlaying = false
    @State private var playTask: Task<Void, Never>?

    private let stops: [ProofReelModel.Stop]

    public init(receipt: ProofReceipt) {
        self.receipt = receipt
        self.stops = ProofReelModel.stops(from: receipt)
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                if stops.isEmpty {
                    emptyState
                } else {
                    stopDetail
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)

                    controls
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color(.systemBackground).ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    Text("Proof Reel")
                        .font(.system(size: 15, weight: .semibold))
                }
            }
        }
        .onAppear {
            #if DEBUG
            applyDebugScrubSeamIfNeeded()
            applyDebugAutoPlayIfNeeded()
            #endif
        }
        .onDisappear {
            playTask?.cancel()
            isPlaying = false
        }
        .accessibilityIdentifier("proof-reel-view")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(receipt.agent)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                if let model = receipt.model, !model.isEmpty {
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(model)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let duration = ProofReelModel.durationText(
                    startedAt: receipt.startedAt,
                    endedAt: receipt.endedAt
                ) {
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(duration)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            if let goal = receipt.contract?.goal, !goal.isEmpty {
                Text("Asked: \(goal)")
                    .font(.system(size: 14))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }

            if !stops.isEmpty, let state = currentScrubState {
                Text("Stop \(state.index + 1) of \(state.stopCount)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("proof-reel-stop-counter")
            }
        }
    }

    @ViewBuilder
    private var stopDetail: some View {
        if let state = currentScrubState {
            VStack(alignment: .leading, spacing: 10) {
                Text(ProofReelModel.stopLabel(for: state.stop).uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)

                stopContent(for: state.stop)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color(.separator), lineWidth: 0.5)
            )
            .accessibilityIdentifier("proof-reel-stop-detail")
        }
    }

    @ViewBuilder
    private func stopContent(for stop: ProofReelModel.Stop) -> some View {
        switch stop.kind {
        case .command(let command):
            VStack(alignment: .leading, spacing: 8) {
                Text(command.command)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                HStack(spacing: 8) {
                    if let kind = command.kind, !kind.isEmpty {
                        Text(kind)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    if let startedAt = command.startedAt,
                       let formatted = ProofReelModel.localizedTimestamp(startedAt) {
                        Text(formatted)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if let code = command.exitCode {
                        Text("exit \(code)")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(code == 0 ? Color.green : Color.red)
                    }
                }
            }
        case .file(let file):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(file.path)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Spacer(minLength: 0)
                Text("+\(file.additions) -\(file.deletions)")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        case .criterion(let criterion):
            HStack(alignment: .top, spacing: 8) {
                criterionIcon(for: criterion.status)
                    .frame(width: 14, height: 14)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 4) {
                    Text(criterion.text)
                        .font(.system(size: 14))
                        .foregroundStyle(.primary)
                    Text(criterionStatusCaption(criterion.status))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    if let evidence = criterion.evidence, !evidence.isEmpty {
                        Text(evidence)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            if stops.count > 1 {
                Slider(
                    value: Binding(
                        get: { Double(scrubIndex) },
                        set: { scrubIndex = Int($0.rounded()) }
                    ),
                    in: 0 ... Double(stops.count - 1),
                    step: 1
                )
                .accessibilityIdentifier("proof-reel-scrubber")
            }

            HStack(spacing: 10) {
                Button(action: stepBackward) {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color(.secondarySystemBackground)))
                        .overlay(Circle().strokeBorder(Color(.separator), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .disabled(scrubIndex == 0)
                .accessibilityIdentifier("proof-reel-step-back")

                Button(action: togglePlayback) {
                    Label(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(Color.primary))
                        .foregroundStyle(Color(.systemBackground))
                }
                .buttonStyle(.plain)
                .disabled(stops.count <= 1)
                .accessibilityIdentifier("proof-reel-play")

                Button(action: stepForward) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color(.secondarySystemBackground)))
                        .overlay(Circle().strokeBorder(Color(.separator), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .disabled(scrubIndex >= stops.count - 1)
                .accessibilityIdentifier("proof-reel-step-forward")
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No replay events")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("This receipt has no commands, files, or criteria to replay.")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var currentScrubState: ProofReelModel.ScrubState? {
        ProofReelModel.scrubState(stops: stops, index: scrubIndex)
    }

    private func stepBackward() {
        scrubIndex = max(0, scrubIndex - 1)
    }

    private func stepForward() {
        scrubIndex = min(stops.count - 1, scrubIndex + 1)
    }

    private func togglePlayback() {
        if isPlaying {
            playTask?.cancel()
            isPlaying = false
            return
        }
        guard stops.count > 1 else { return }
        isPlaying = true
        playTask = Task { @MainActor in
            while !Task.isCancelled, isPlaying {
                try? await Task.sleep(for: .milliseconds(900))
                guard !Task.isCancelled else { break }
                if scrubIndex >= stops.count - 1 {
                    scrubIndex = 0
                } else {
                    scrubIndex += 1
                }
            }
        }
    }

    private func criterionIcon(for status: ProofReceipt.Criterion.Status) -> some View {
        Group {
            switch status {
            case .met:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .unmet:
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
            case .unknown:
                Image(systemName: "questionmark.circle")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 12, weight: .semibold))
    }

    /// Standing rule: criteria are observed/asked outcomes, never "guaranteed".
    private func criterionStatusCaption(_ status: ProofReceipt.Criterion.Status) -> String {
        switch status {
        case .met: return "Observed met"
        case .unmet: return "Observed unmet"
        case .unknown: return "Not observed"
        }
    }

    #if DEBUG
    private func applyDebugScrubSeamIfNeeded() {
        guard let raw = ProcessInfo.processInfo.environment["LANCER_PROOF_REEL_SCRUB_INDEX"],
              let index = Int(raw) else { return }
        scrubIndex = max(0, min(index, max(stops.count - 1, 0)))
    }

    private func applyDebugAutoPlayIfNeeded() {
        guard ProcessInfo.processInfo.environment["LANCER_PROOF_REEL_AUTO_PLAY"] == "1" else { return }
        togglePlayback()
    }
    #endif
}
#endif
