import Foundation
import Observation

/// Frame-paced reveal loop feeding `ChatStreamingTextSmoother`'s decisions into an
/// observable `displayText` / `markdownText`. Not `#if os(iOS)` gated — Foundation /
/// Observation only, so `swift test` on macOS can exercise the pure smoother; this
/// type's timing loop is integration-tested lightly via ingest/reset.
///
/// Between ~1s poll deltas, characters/words drip toward the latest target so the
/// transcript flows instead of jumping. `markdownText` updates only once settled
/// (~300ms quiet + caught up) to avoid re-parse flicker. Reveal never plans to lag
/// the target by more than one poll interval (`defaultMaxCatchUp`).
@MainActor
@Observable
public final class ChatStreamingTextPacer {
    /// Character/word-paced text shown while streaming.
    public private(set) var displayText: String = ""
    /// Throttled source for markdown re-parse — snaps to `displayText` when settled.
    public private(set) var markdownText: String = ""
    public private(set) var isSettled: Bool = true

    private var pendingText: String = ""
    private var lastDeltaAt: ContinuousClock.Instant?
    private var lastCommitAt: ContinuousClock.Instant?
    private let clock = ContinuousClock()
    private let commitInterval: Duration
    private let settleDelay: Duration
    private let maxCatchUp: Duration
    private var pacingTask: Task<Void, Never>?

    public init(
        commitInterval: Duration = ChatStreamingTextSmoother.defaultCommitInterval,
        settleDelay: Duration = ChatStreamingTextSmoother.defaultSettleDelay,
        maxCatchUp: Duration = ChatStreamingTextSmoother.defaultMaxCatchUp
    ) {
        self.commitInterval = commitInterval
        self.settleDelay = settleDelay
        self.maxCatchUp = maxCatchUp
    }

    /// Feed a new (cumulative) streamed text value. Reveal is paced, not immediate.
    public func ingest(_ text: String) {
        guard text != pendingText else { return }
        pendingText = text
        lastDeltaAt = clock.now
        isSettled = false
        startPacingLoopIfNeeded()
    }

    /// Snap immediately to `text` and cancel any in-flight pacing (turn switch / completion).
    public func reset(to text: String = "") {
        pacingTask?.cancel()
        pacingTask = nil
        pendingText = text
        displayText = text
        markdownText = text
        lastDeltaAt = nil
        lastCommitAt = nil
        isSettled = true
    }

    private func startPacingLoopIfNeeded() {
        guard pacingTask == nil else { return }
        pacingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: self.commitInterval)
                if Task.isCancelled { return }
                self.commitTick()
            }
        }
    }

    private func commitTick() {
        let now = clock.now
        if let lastCommitAt,
           !ChatStreamingTextSmoother.shouldCommit(
               elapsedSinceLastCommit: lastCommitAt.duration(to: now),
               minInterval: commitInterval
           ) {
            // Sleep already approximates the interval; still guard for coalescing.
        }

        if displayText != pendingText {
            displayText = ChatStreamingTextSmoother.advancedDisplay(
                displayed: displayText,
                target: pendingText,
                commitInterval: commitInterval,
                maxCatchUp: maxCatchUp
            )
            lastCommitAt = now
        }

        let caughtUp = displayText == pendingText
        let quiet: Bool
        if let lastDeltaAt {
            quiet = ChatStreamingTextSmoother.isSettled(
                elapsedSinceLastDelta: lastDeltaAt.duration(to: now),
                settleDelay: settleDelay
            )
        } else {
            quiet = true
        }

        if caughtUp && quiet {
            isSettled = true
            markdownText = displayText
            pacingTask?.cancel()
            pacingTask = nil
        } else {
            isSettled = false
            // While catching up, keep markdown on the last settled snapshot to avoid flicker.
            // Once caught up but still inside settleDelay, refresh markdown to the full text
            // so the quiet window can finish with correct structure.
            if caughtUp {
                markdownText = displayText
            }
        }
    }
}
