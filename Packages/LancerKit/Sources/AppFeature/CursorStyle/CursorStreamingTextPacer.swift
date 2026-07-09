import Foundation
import Observation

/// Frame-paced commit loop feeding `CursorStreamingTextSmoother`'s decisions into an
/// observable `displayText`. Not `#if os(iOS)` gated — uses only Foundation/Observation,
/// so it stays testable via `swift test` on macOS; the SwiftUI call site in
/// `CursorWorkThreadView` is the iOS-only part.
///
/// Ported pattern (logic only): Happier (MIT) `useStreamingTextSmoothing.ts` — coalesce many
/// chunk deltas into at most one visible commit per pacing window, and flip `isSettled` only
/// after a quiet window with no new deltas.
@MainActor
@Observable
public final class CursorStreamingTextPacer {
    public private(set) var displayText: String = ""
    public private(set) var isSettled: Bool = true

    private var pendingText: String = ""
    private var lastDeltaAt: ContinuousClock.Instant?
    private let clock = ContinuousClock()
    private let commitInterval: Duration
    private let settleDelay: Duration
    private var pacingTask: Task<Void, Never>?

    public init(
        commitInterval: Duration = CursorStreamingTextSmoother.defaultCommitInterval,
        settleDelay: Duration = CursorStreamingTextSmoother.defaultSettleDelay
    ) {
        self.commitInterval = commitInterval
        self.settleDelay = settleDelay
    }

    /// Feed a new (cumulative) streamed text value. Commits are paced, not immediate.
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
        lastDeltaAt = nil
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
        if displayText != pendingText {
            displayText = pendingText
        }
        if let lastDeltaAt {
            isSettled = CursorStreamingTextSmoother.isSettled(
                elapsedSinceLastDelta: lastDeltaAt.duration(to: clock.now),
                settleDelay: settleDelay
            )
        }
        if isSettled {
            pacingTask?.cancel()
            pacingTask = nil
        }
    }
}
