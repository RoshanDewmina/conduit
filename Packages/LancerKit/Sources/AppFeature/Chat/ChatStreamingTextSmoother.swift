import Foundation

/// Pure streaming-text pacing / anti-flicker / catch-up rules for live assistant replies.
/// No `#if os(iOS)` gate — testable on macOS via `swift test`.
///
/// Ported patterns (logic only — see `docs/product/2026-07-09-chat-ui-port-map.md` §1):
/// - Happier (MIT): coalesce commits; gate markdown re-parse behind a quiet-window settle.
/// - Orca (MIT): overlay wins only while strictly longer than persisted text.
/// Plus Lane K catch-up: character/word reveal between ~1s poll deltas so the UI never
/// lags the persisted target by more than one poll interval.
public enum ChatStreamingTextSmoother: Sendable {
    /// Default frame-pacing window (~50ms) for character/word reveal ticks.
    public static let defaultCommitInterval: Duration = .milliseconds(50)
    /// Quiet window before treating the stream as settled (markdown re-parse safe).
    public static let defaultSettleDelay: Duration = .milliseconds(300)
    /// Never take longer than one live-poll tick to catch up to the latest target.
    public static let defaultMaxCatchUp: Duration = .seconds(1)
    /// Floor for per-tick reveal so short deltas still feel continuous.
    public static let defaultMinCharsPerTick: Int = 1

    /// Orca's anti-flicker rule: the live overlay response is shown only while it is
    /// strictly longer than the persisted turn's final `assistantText`.
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

    /// Happier's frame-pacing gate: true once at least `minInterval` has elapsed since
    /// the last committed paint.
    public static func shouldCommit(elapsedSinceLastCommit: Duration, minInterval: Duration) -> Bool {
        elapsedSinceLastCommit >= minInterval
    }

    /// Happier's settle gate: true once `settleDelay` has passed with no new text delta.
    public static func isSettled(elapsedSinceLastDelta: Duration, settleDelay: Duration) -> Bool {
        elapsedSinceLastDelta >= settleDelay
    }

    /// How many UTF-16-ish `Character`s to reveal this tick so `remaining` finishes
    /// within `maxCatchUp`, paced by `commitInterval`. Prefer word boundaries when
    /// the step would land mid-word.
    public static func charactersToReveal(
        displayed: String,
        target: String,
        commitInterval: Duration = defaultCommitInterval,
        maxCatchUp: Duration = defaultMaxCatchUp,
        minCharsPerTick: Int = defaultMinCharsPerTick
    ) -> Int {
        guard target.hasPrefix(displayed) || displayed.isEmpty || target.isEmpty else {
            // Target rewound / replaced — snap.
            return target.count - displayed.count
        }
        let remaining = target.count - displayed.count
        guard remaining > 0 else { return 0 }

        let intervalNs = Double(commitInterval.components.seconds) * 1_000_000_000
            + Double(commitInterval.components.attoseconds) / 1_000_000_000
        let catchUpNs = Double(maxCatchUp.components.seconds) * 1_000_000_000
            + Double(maxCatchUp.components.attoseconds) / 1_000_000_000
        let ticks = max(1.0, catchUpNs / max(intervalNs, 1))
        // Steady rate against the full target length (not remaining) so catch-up
        // finishes within maxCatchUp instead of asymptotically re-planning.
        let steadyRate = max(minCharsPerTick, Int(ceil(Double(max(target.count, 1)) / ticks)))
        let step = min(remaining, steadyRate)

        let end = displayed.count + step
        if end >= target.count { return remaining }

        // Prefer landing on a word boundary (whitespace / punctuation) when close.
        let targetChars = Array(target)
        let preferred = min(targetChars.count, end + 12)
        if end < preferred {
            for idx in end..<preferred {
                let ch = targetChars[idx]
                if ch.isWhitespace || ch.isPunctuation {
                    return idx + 1 - displayed.count
                }
            }
        }
        return step
    }

    /// Next display string after one reveal tick.
    public static func advancedDisplay(
        displayed: String,
        target: String,
        commitInterval: Duration = defaultCommitInterval,
        maxCatchUp: Duration = defaultMaxCatchUp
    ) -> String {
        if target.isEmpty { return "" }
        if displayed.isEmpty || target.hasPrefix(displayed) {
            let step = charactersToReveal(
                displayed: displayed,
                target: target,
                commitInterval: commitInterval,
                maxCatchUp: maxCatchUp
            )
            guard step > 0 else { return displayed }
            let end = displayed.count + step
            return String(target.prefix(end))
        }
        // Non-prefix update (rare replace) — jump to target.
        return target
    }
}
