import Foundation
import LancerCore

// MARK: - Model

/// Derives a chronologically ordered scrub timeline from a `ProofReceipt`.
public enum ProofReelModel {
    public enum StopKind: Equatable, Sendable {
        case command(ProofReceipt.Command)
        case file(ProofReceipt.FileTouched)
        case criterion(ProofReceipt.Criterion)
        // Reserved for Lane E question-ladder answers once `answersReserved` is typed.
        // case answer(key: String, value: String)
    }

    public struct Stop: Equatable, Sendable, Identifiable {
        public let id: Int
        public let kind: StopKind
        /// Stable ordering key for tests — lower sorts earlier.
        public let orderKey: Int

        public init(id: Int, kind: StopKind, orderKey: Int) {
            self.id = id
            self.kind = kind
            self.orderKey = orderKey
        }
    }

    public struct ScrubState: Equatable, Sendable {
        public let index: Int
        public let stop: Stop
        public let stopCount: Int
        public let progress: Double

        public var isAtStart: Bool { index == 0 }
        public var isAtEnd: Bool { index >= stopCount - 1 }
    }

    /// Builds the proof-reel stop sequence for `receipt`.
    ///
    /// Ordering heuristic (raw receipt data lacks a single global event clock):
    /// 1. **Commands** — those with `startedAt` sort by parsed timestamp ascending;
    ///    ties and commands missing `startedAt` keep receipt-array order after all
    ///    timestamped commands.
    /// 2. **Files touched** — no per-file timestamps; appended in receipt order after
    ///    all commands (files represent work product produced during command execution).
    /// 3. **Criteria** — no timestamps; appended in receipt order after files (criteria
    ///    are evaluated at run completion).
    /// 4. **`answersReserved`** — not rendered until Lane E defines question/answer shape.
    public static func stops(from receipt: ProofReceipt) -> [Stop] {
        var entries: [(orderKey: Int, kind: StopKind)] = []
        var orderKey = 0

        let commands = receipt.commands ?? []
        let dated = commands.enumerated().compactMap { index, command -> (Int, Int, ProofReceipt.Command)? in
            guard let startedAt = command.startedAt,
                  let date = iso8601Date(from: startedAt) else { return nil }
            return (index, Int(date.timeIntervalSince1970), command)
        }
        let undated = commands.enumerated().filter { $0.element.startedAt == nil || iso8601Date(from: $0.element.startedAt) == nil }

        for item in dated.sorted(by: { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
            return lhs.0 < rhs.0
        }) {
            entries.append((orderKey, .command(item.2)))
            orderKey += 1
        }
        for item in undated.sorted(by: { $0.offset < $1.offset }) {
            entries.append((orderKey, .command(item.element)))
            orderKey += 1
        }

        for file in receipt.filesTouched ?? [] {
            entries.append((orderKey, .file(file)))
            orderKey += 1
        }

        for criterion in receipt.criteria ?? [] {
            entries.append((orderKey, .criterion(criterion)))
            orderKey += 1
        }

        return entries.enumerated().map { index, entry in
            Stop(id: index, kind: entry.kind, orderKey: entry.orderKey)
        }
    }

    public static func scrubState(stops: [Stop], index: Int) -> ScrubState? {
        guard !stops.isEmpty, index >= 0, index < stops.count else { return nil }
        let clamped = max(0, min(index, stops.count - 1))
        let progress = stops.count == 1 ? 1.0 : Double(clamped) / Double(stops.count - 1)
        return ScrubState(
            index: clamped,
            stop: stops[clamped],
            stopCount: stops.count,
            progress: progress
        )
    }

    public static func scrubState(stops: [Stop], progress: Double) -> ScrubState? {
        guard !stops.isEmpty else { return nil }
        let clampedProgress = max(0, min(progress, 1))
        let index = Int((clampedProgress * Double(stops.count - 1)).rounded())
        return scrubState(stops: stops, index: index)
    }

    public static func stopLabel(for stop: Stop) -> String {
        switch stop.kind {
        case .command:
            return "Command"
        case .file:
            return "File"
        case .criterion:
            return "Criterion"
        }
    }

    private static func iso8601Date(from raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: raw) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }
}

#if os(iOS)
import SwiftUI
import DesignSystem

/// Structured replay scrubber over a single run's proof receipt events.
public struct ProofReelView: View {
    let receipt: ProofReceipt

    @Environment(\.dismiss) private var dismiss
    @Environment(\.lancerTokens) private var t

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
            .background(t.termSurface.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .font(.dsMonoPt(12, weight: .semibold))
                }
                ToolbarItem(placement: .principal) {
                    Text("Proof Reel")
                        .font(.dsMonoPt(12, weight: .semibold))
                        .foregroundStyle(t.termText)
                }
            }
        }
        .onAppear {
            applyDebugScrubSeamIfNeeded()
            applyDebugAutoPlayIfNeeded()
        }
        .onDisappear {
            playTask?.cancel()
            isPlaying = false
        }
        .accessibilityIdentifier("proof-reel-view")
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(receipt.agent)
                    .font(.dsMonoPt(11, weight: .semibold))
                    .foregroundStyle(t.termText2)
                if let duration = ReceiptCardModel.durationText(
                    startedAt: receipt.startedAt,
                    endedAt: receipt.endedAt
                ) {
                    Text("·")
                        .foregroundStyle(t.termText3)
                    Text(duration)
                        .font(.dsMonoPt(11))
                        .foregroundStyle(t.termText3)
                }
                Spacer(minLength: 0)
                if let code = receipt.exitCode {
                    DSExitChip(code: code)
                }
            }

            if let goal = receipt.contract?.goal, !goal.isEmpty {
                Text(goal)
                    .font(.dsMonoPt(12))
                    .foregroundStyle(t.termText)
                    .lineLimit(2)
            }

            if !stops.isEmpty, let state = currentScrubState {
                Text("Stop \(state.index + 1) of \(state.stopCount)")
                    .font(.dsMonoPt(10))
                    .foregroundStyle(t.termText3)
                    .accessibilityIdentifier("proof-reel-stop-counter")
            }
        }
    }

    @ViewBuilder
    private var stopDetail: some View {
        if let state = currentScrubState {
            VStack(alignment: .leading, spacing: 10) {
                Text(ProofReelModel.stopLabel(for: state.stop).uppercased())
                    .font(.dsMonoPt(10))
                    .tracking(10 * 0.12)
                    .foregroundStyle(t.termText3)

                stopContent(for: state.stop)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(t.termSurface2)
            .clipShape(RoundedRectangle(cornerRadius: t.radiusMD, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: t.radiusMD, style: .continuous)
                    .strokeBorder(t.termBorder, lineWidth: 0.75)
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
                    .font(.dsMonoPt(12))
                    .foregroundStyle(t.termText)
                    .textSelection(.enabled)
                HStack(spacing: 8) {
                    if let kind = command.kind, !kind.isEmpty {
                        Text(kind)
                            .font(.dsMonoPt(10, weight: .semibold))
                            .foregroundStyle(t.termText3)
                    }
                    if let startedAt = command.startedAt {
                        Text(startedAt)
                            .font(.dsMonoPt(10))
                            .foregroundStyle(t.termText3)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if let code = command.exitCode {
                        DSExitChip(code: code)
                    }
                }
            }
        case .file(let file):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(file.path)
                    .font(.dsMonoPt(12))
                    .foregroundStyle(t.termText)
                    .lineLimit(2)
                Spacer(minLength: 0)
                Text("+\(file.additions) -\(file.deletions)")
                    .font(.dsMonoPt(11, weight: .semibold))
                    .foregroundStyle(t.termText2)
            }
        case .criterion(let criterion):
            HStack(alignment: .top, spacing: 8) {
                criterionIcon(for: criterion.status)
                    .frame(width: 14, height: 14)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 4) {
                    Text(criterion.text)
                        .font(.dsMonoPt(12))
                        .foregroundStyle(t.termText)
                    if let evidence = criterion.evidence, !evidence.isEmpty {
                        Text(evidence)
                            .font(.dsMonoPt(10))
                            .foregroundStyle(t.termText3)
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
                .tint(t.termAccent)
                .accessibilityIdentifier("proof-reel-scrubber")
            }

            HStack(spacing: 10) {
                DSButton(
                    "",
                    systemImage: "backward.fill",
                    variant: .secondary,
                    size: .sm,
                    iconOnly: true,
                    action: stepBackward
                )
                .disabled(scrubIndex == 0)
                .accessibilityIdentifier("proof-reel-step-back")

                DSButton(
                    isPlaying ? "Pause" : "Play",
                    systemImage: isPlaying ? "pause.fill" : "play.fill",
                    variant: .accent,
                    size: .md,
                    mono: true,
                    fullWidth: true,
                    action: togglePlayback
                )
                .disabled(stops.count <= 1)
                .accessibilityIdentifier("proof-reel-play")

                DSButton(
                    "",
                    systemImage: "forward.fill",
                    variant: .secondary,
                    size: .sm,
                    iconOnly: true,
                    action: stepForward
                )
                .disabled(scrubIndex >= stops.count - 1)
                .accessibilityIdentifier("proof-reel-step-forward")
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No replay events")
                .font(.dsMonoPt(12, weight: .semibold))
                .foregroundStyle(t.termText2)
            Text("This receipt has no commands, files, or criteria to replay.")
                .font(.dsMonoPt(11))
                .foregroundStyle(t.termText3)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    // MARK: - Playback

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
                DSIconView(.check, size: 12, color: t.termOk)
            case .unmet:
                DSIconView(.close, size: 12, color: t.termErr)
            case .unknown:
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(t.termText3)
            }
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
