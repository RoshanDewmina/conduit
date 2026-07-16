import Foundation
import LancerCore

/// One locally-queued follow-up typed while an agent turn is still in flight.
/// Stored on `ShellLiveBridge` so it survives view re-entry within the session.
public struct MidRunFeedbackItem: Equatable, Identifiable, Sendable {
    public let id: String
    public let text: String
    public let conversationID: String
    public let cwd: String
    public let attachments: [ConversationAttachmentReference]

    public init(
        id: String = UUID().uuidString,
        text: String,
        conversationID: String,
        cwd: String,
        attachments: [ConversationAttachmentReference] = []
    ) {
        self.id = id
        self.text = text
        self.conversationID = conversationID
        self.cwd = cwd
        self.attachments = attachments
    }
}

/// FIFO queue for mid-run feedback. Pure — ordering + flush gating live here so
/// unit tests don't need a live bridge/relay.
public struct MidRunFeedbackQueue: Equatable, Sendable {
    public private(set) var items: [MidRunFeedbackItem]

    public init(items: [MidRunFeedbackItem] = []) {
        self.items = items
    }

    public var isEmpty: Bool { items.isEmpty }
    public var count: Int { items.count }

    @discardableResult
    public mutating func enqueue(_ item: MidRunFeedbackItem) -> MidRunFeedbackItem {
        items.append(item)
        return item
    }

    /// Removes and returns the oldest item, or `nil` when empty.
    public mutating func dequeueFirst() -> MidRunFeedbackItem? {
        guard !items.isEmpty else { return nil }
        return items.removeFirst()
    }

    /// After a turn reaches a terminal state, pop the next item only when the
    /// agent is idle. Returns `nil` while still in flight (or when empty).
    public mutating func flushNext(agentInFlight: Bool) -> MidRunFeedbackItem? {
        guard !agentInFlight else { return nil }
        return dequeueFirst()
    }
}
