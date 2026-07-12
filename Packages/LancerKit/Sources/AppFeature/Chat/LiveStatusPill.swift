import Foundation
import SessionFeature

#if os(iOS)
import SwiftUI
#endif

/// Pure label / visibility rules for the live status pill (Orca mutual-exclusion
/// with streamed text; stall hint after 30s without a fresh event).
public enum LiveStatusPresentation: Sendable {
    public static let stallThreshold: TimeInterval = 30

    /// Returns nil when the pill should be hidden (terminal turn, or visible
    /// reply text already on screen — mutual exclusion with streaming).
    public static func displayText(
        event: LiveRunStatusParams?,
        firstEventAt: Date?,
        lastEventAt: Date?,
        now: Date,
        hasVisibleReplyText: Bool,
        isTerminalOrIdle: Bool
    ) -> String? {
        guard !isTerminalOrIdle, !hasVisibleReplyText, let event, !event.state.isEmpty else {
            return nil
        }
        let started = firstEventAt ?? now
        let last = lastEventAt ?? started
        if now.timeIntervalSince(last) >= stallThreshold {
            return withElapsed("Still working…", from: started, now: now)
        }
        let base = statusLabel(state: event.state, toolName: event.toolName, target: event.target)
        return withElapsed(base, from: started, now: now)
    }

    public static func statusLabel(state: String, toolName: String?, target: String?) -> String {
        switch state {
        case "starting":
            return "Starting…"
        case "thinking":
            return "Thinking…"
        case "streaming":
            return "Writing…"
        case "tool":
            return toolLabel(toolName: toolName, target: target)
        default:
            return "Working…"
        }
    }

    public static func toolLabel(toolName: String?, target: String?) -> String {
        let name = (toolName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTarget = target.flatMap { t -> String? in
            let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return ChatFileNameDisplay.displayName(for: trimmed)
        }
        switch name.lowercased() {
        case "edit", "write":
            if let displayTarget {
                return "Editing \(displayTarget)…"
            }
            return "Editing…"
        default:
            if !name.isEmpty {
                return "Calling \(name)…"
            }
            if let displayTarget {
                return "Calling \(displayTarget)…"
            }
            return "Working…"
        }
    }

    public static func withElapsed(_ label: String, from start: Date, now: Date) -> String {
        let elapsed = max(0, Int(now.timeIntervalSince(start)))
        guard elapsed > 0 else { return label }
        return "\(label) · \(formatElapsed(elapsed))"
    }

    public static func formatElapsed(_ totalSeconds: Int) -> String {
        let s = max(0, totalSeconds)
        let hours = s / 3600
        let minutes = (s % 3600) / 60
        let seconds = s % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m \(seconds)s"
        }
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }

    public static func parseEventDate(_ at: String?) -> Date? {
        guard let at, !at.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: at) { return d }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: at)
    }

    /// Clear the pill on run end only. Do **not** clear on `.working` —
    /// daemon liveStatus dedupes `(state,tool,target)` per run and will not
    /// re-emit the same key after degraded→working (or any) re-entry, so a
    /// wipe here leaves a blank pill until the next distinct state.
    public static func shouldClearOnSendStatePhase(_ phase: LiveStatusSendPhase) -> Bool {
        switch phase {
        case .idle, .completed, .failed:
            return true
        case .working, .streaming, .degraded:
            return false
        }
    }

    /// Accept a liveStatus notification only when there is a live turn to
    /// attribute it to, run IDs match, and the event's machine matches the
    /// active machine (mirrors other `lancerE2E*` observers).
    public static func shouldAcceptLiveRunStatus(
        eventRunID: String,
        eventMachineID: UUID?,
        liveTurnRunID: String?,
        activeMachineID: UUID?
    ) -> Bool {
        guard let liveTurnRunID, !liveTurnRunID.isEmpty,
              liveTurnRunID == eventRunID,
              let activeMachineID,
              let eventMachineID,
              eventMachineID == activeMachineID
        else {
            return false
        }
        return true
    }
}

/// Send-state phases that drive live-status pill clearing (subset of
/// `ShellLiveBridge.SendState` — kept string-free for unit tests).
public enum LiveStatusSendPhase: Sendable, Equatable {
    case idle
    case working
    case streaming
    case completed
    case failed
    case degraded
}

#if os(iOS)
/// Spinner + live status caption under the streaming area.
struct LiveStatusPill: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(text))
    }
}
#endif
