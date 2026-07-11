import Foundation
import LancerCore

public enum AttentionReason: String, Codable, Sendable, Equatable {
    case pendingApproval
    case blockingQuestion
    case runFailed
    case providerAuth
    case outOfCredits
    case modelUnavailable
    case providerError
    case receiptReady
    case none

    /// Higher values sort first. Provider failures share one tier.
    public var priority: Int {
        switch self {
        case .pendingApproval: return 800
        case .blockingQuestion: return 700
        case .runFailed: return 600
        case .providerAuth, .outOfCredits, .modelUnavailable, .providerError: return 500
        case .receiptReady: return 400
        case .none: return 0
        }
    }
}

public enum CursorThreadAttention: Sendable, Equatable {
    case needsApproval
    case awaitingInput
    case working
    case ready
    case failed
    case idle

    public var label: String {
        switch self {
        case .needsApproval: return "Needs Approval"
        case .awaitingInput: return "Awaiting Input"
        case .working: return "Working"
        case .ready: return "Ready"
        case .failed: return "Failed"
        case .idle: return "Idle"
        }
    }

    /// Published bridge inputs for a single thread row.
    public struct ThreadState: Sendable {
        public var hasPendingApproval: Bool
        public var hasBlockingQuestion: Bool
        public var conversationStatus: ChatConversation.Status
        public var hasUnacknowledgedReceipt: Bool
        public var statusText: String?
        public var errorDetail: String?

        public init(
            hasPendingApproval: Bool = false,
            hasBlockingQuestion: Bool = false,
            conversationStatus: ChatConversation.Status = .active,
            hasUnacknowledgedReceipt: Bool = false,
            statusText: String? = nil,
            errorDetail: String? = nil
        ) {
            self.hasPendingApproval = hasPendingApproval
            self.hasBlockingQuestion = hasBlockingQuestion
            self.conversationStatus = conversationStatus
            self.hasUnacknowledgedReceipt = hasUnacknowledgedReceipt
            self.statusText = statusText
            self.errorDetail = errorDetail
        }
    }

    /// Pure derivation from published bridge state.
    public static func derive(
        _ threadState: ThreadState
    ) -> (CursorThreadAttention, AttentionReason, String?) {
        if threadState.hasPendingApproval {
            return (.needsApproval, .pendingApproval, cappedDetail(threadState.errorDetail))
        }
        if threadState.hasBlockingQuestion {
            return (.awaitingInput, .blockingQuestion, cappedDetail(threadState.statusText ?? threadState.errorDetail))
        }
        if threadState.conversationStatus == .failed {
            return (.failed, .runFailed, cappedDetail(threadState.errorDetail ?? threadState.statusText))
        }
        if let providerReason = parseProviderFailure(threadState.statusText) {
            return (.failed, providerReason, cappedDetail(threadState.statusText))
        }
        if threadState.hasUnacknowledgedReceipt {
            return (.ready, .receiptReady, cappedDetail(threadState.statusText))
        }
        switch threadState.conversationStatus {
        case .active:
            return (.working, .none, nil)
        case .completed:
            return (.ready, .none, nil)
        case .failed:
            return (.failed, .runFailed, cappedDetail(threadState.errorDetail ?? threadState.statusText))
        case .archived:
            return (.idle, .none, nil)
        }
    }

    /// Combined sort priority for a derived attention tuple.
    public static func sortPriority(
        attention: CursorThreadAttention,
        reason: AttentionReason
    ) -> Int {
        if reason != .none {
            return reason.priority
        }
        switch attention {
        case .working: return 300
        case .ready: return 200
        case .idle: return 100
        default: return reason.priority
        }
    }

    private static let detailCap = 180

    private static func cappedDetail(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        if raw.count <= detailCap { return raw }
        return String(raw.prefix(detailCap))
    }

    private static func parseProviderFailure(_ statusText: String?) -> AttentionReason? {
        guard let statusText, !statusText.isEmpty else { return nil }
        let normalized = statusText.lowercased()
        if normalized.contains("provider_auth") || normalized.contains("provider auth") {
            return .providerAuth
        }
        if normalized.contains("out_of_credits") || normalized.contains("out of credits") {
            return .outOfCredits
        }
        if normalized.contains("model_unavailable") || normalized.contains("model unavailable") {
            return .modelUnavailable
        }
        if normalized.contains("provider_error") || normalized.contains("provider error") {
            return .providerError
        }
        return nil
    }
}

#if os(iOS)
import SwiftUI
import DesignSystem

extension CursorThreadAttention {
    public func color(for scheme: CursorScheme) -> Color {
        let c = CursorColors.resolve(scheme)
        switch self {
        case .needsApproval: return c.riskHigh
        case .awaitingInput: return c.riskMedium
        case .working: return c.statusDotActive
        case .ready: return c.successGreen
        case .failed: return c.dangerRed
        case .idle: return c.mutedText
        }
    }
}
#endif

public struct ThreadAttentionSortKey: Sendable, Comparable {
    public let priority: Int
    public let updatedAt: Date

    public init(priority: Int, updatedAt: Date?) {
        self.priority = priority
        self.updatedAt = updatedAt ?? .distantPast
    }

    public static func < (lhs: ThreadAttentionSortKey, rhs: ThreadAttentionSortKey) -> Bool {
        if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
        return lhs.updatedAt < rhs.updatedAt
    }
}

extension ThreadAttentionSortKey {
    public init(threadState: CursorThreadAttention.ThreadState, updatedAt: Date?) {
        let derived = CursorThreadAttention.derive(threadState)
        let priority = CursorThreadAttention.sortPriority(
            attention: derived.0,
            reason: derived.1
        )
        self.init(priority: priority, updatedAt: updatedAt)
    }
}

/// Sort threads by attention priority (desc), then `updatedAt` (desc).
public func sortThreadsByAttention<Thread>(
    _ threads: [Thread],
    updatedAt: (Thread) -> Date?,
    threadState: (Thread) -> CursorThreadAttention.ThreadState
) -> [Thread] {
    threads.sorted { lhs, rhs in
        let lhsKey = ThreadAttentionSortKey(
            threadState: threadState(lhs),
            updatedAt: updatedAt(lhs)
        )
        let rhsKey = ThreadAttentionSortKey(
            threadState: threadState(rhs),
            updatedAt: updatedAt(rhs)
        )
        if lhsKey.priority != rhsKey.priority {
            return lhsKey.priority > rhsKey.priority
        }
        return lhsKey.updatedAt > rhsKey.updatedAt
    }
}

/// Whether a derived thread state belongs in the Home "Needs you" section.
public func isNeedsYouThread(_ state: CursorThreadAttention.ThreadState) -> Bool {
    let (_, reason, _) = CursorThreadAttention.derive(state)
    return reason.priority > 0
}

/// Status copy for the Home attention module — never "all clear" on stale relay.
public func homeAttentionStatusMessage(
    needsYouCount: Int,
    relayHealthy: Bool,
    lastSnapshotAt: Date?,
    now: Date = .now,
    relativeTime: (Date, Date) -> String = HomeAttentionRelativeTime.format
) -> String? {
    if !relayHealthy {
        let stamp = lastSnapshotAt.map { relativeTime($0, now) } ?? "earlier"
        return "As of \(stamp) — reconnecting"
    }
    guard needsYouCount == 0 else { return nil }
    return "All clear — nothing needs you"
}

public enum HomeAttentionRelativeTime {
    public static func format(_ date: Date, relativeTo now: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
