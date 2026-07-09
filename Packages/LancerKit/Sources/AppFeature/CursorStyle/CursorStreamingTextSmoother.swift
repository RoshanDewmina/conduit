import Foundation

/// Pure streaming-text pacing/anti-flicker rules for the Work Thread transcript.
/// No `#if os(iOS)` gate — testable on macOS via `swift test`.
///
/// Ported patterns (logic only, not code — see `docs/product/2026-07-09-chat-ui-port-map.md` §1):
/// - Happier (MIT, `apps/ui/sources/components/sessions/transcript/streaming/useStreamingTextSmoothing.ts`,
///   `useThrottledStreamingMarkdownText.ts`): coalesce chunk arrivals to one commit per pacing
///   window, and gate expensive re-render behind a quiet-window "settle" timer.
/// - Orca (MIT, `src/shared/native-chat-streaming.ts`): the synthetic streaming overlay only
///   wins over the persisted turn text while it is strictly longer, so the UI never visibly
///   shrinks when the persisted row lands (kills swap-flicker on turn completion).
public enum CursorStreamingTextSmoother {
    /// Default frame-pacing window: one visible commit at most every ~100ms, inside the
    /// 80-120ms band the port map recommends for SwiftUI-native pacing.
    public static let defaultCommitInterval: Duration = .milliseconds(100)
    /// Default quiet-window before treating the stream as settled (Happier's `settleDelayMs`).
    public static let defaultSettleDelay: Duration = .milliseconds(320)

    /// Orca's anti-flicker rule: the live overlay response is shown only while it is
    /// strictly longer than the persisted turn's final `assistantText`. Once the persisted
    /// row catches up (equal length or the overlay clears), the persisted text wins and the
    /// row never visibly shrinks or swaps mid-animation.
    public static func resolvedDisplayText(
        overlayResponse: String?,
        persistedAssistantText: String
    ) -> String {
        guard let overlayResponse, !overlayResponse.isEmpty else {
            return persistedAssistantText
        }
        guard overlayResponse.count > persistedAssistantText.count else {
            return persistedAssistantText.isEmpty ? overlayResponse : persistedAssistantText
        }
        return overlayResponse
    }

    /// Happier's frame-pacing gate: true once at least `minInterval` has elapsed since the
    /// last committed paint, so N chunk arrivals within a window collapse to one commit.
    public static func shouldCommit(elapsedSinceLastCommit: Duration, minInterval: Duration) -> Bool {
        elapsedSinceLastCommit >= minInterval
    }

    /// Happier's settle gate: true once `settleDelay` has passed with no new text delta —
    /// the point at which it's safe to run markdown re-parse/highlighting.
    public static func isSettled(elapsedSinceLastDelta: Duration, settleDelay: Duration) -> Bool {
        elapsedSinceLastDelta >= settleDelay
    }
}
