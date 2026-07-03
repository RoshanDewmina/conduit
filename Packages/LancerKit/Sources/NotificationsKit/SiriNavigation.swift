import Foundation

/// Posted by App Intents in the Lancer app target so `AppRoot` can route Siri
/// navigation without importing AppIntents into AppFeature.
public enum SiriNavigationAction: String, Sendable {
    case search
    case openConversation
    case openMachine
    case openApproval
    case continueConversation
}

public extension Notification.Name {
    /// userInfo keys: `action` (String raw value), plus optional
    /// `conversationId`, `machineId`, `approvalId`, `searchQuery`.
    static let lancerSiriNavigation = Notification.Name("dev.lancer.siriNavigation")

    /// Posted when Spotlight/relevance donations should refresh (iOS 27 fast-follow).
    /// Handled in the Lancer app target — AppFeature must not import AppIntents.
    static let lancerSiriSurfaceRefresh = Notification.Name("dev.lancer.siriSurfaceRefresh")
}

public enum SiriSurfaceRefreshReason: String, Sendable {
    case launch
    case attentionChanged
    case activeRunsChanged
    case conversationChanged
}

public enum SiriSurfaceDefaultsKey {
    public static let recentConversationID = "dev.lancer.siri.recentConversationID"
}

public enum SiriNavigationUserInfoKey {
    public static let action = "action"
    public static let conversationId = "conversationId"
    public static let machineId = "machineId"
    public static let approvalId = "approvalId"
    public static let searchQuery = "searchQuery"
}

/// Durable Siri navigation payload — survives cold launch when NotificationCenter
/// has no live subscriber yet (mirrors `OpenApprovalBuffer`).
public struct SiriNavigationPayload: Sendable, Equatable {
    public let action: SiriNavigationAction
    public let conversationId: String?
    public let machineId: String?
    public let approvalId: String?
    public let searchQuery: String?

    public init(
        action: SiriNavigationAction,
        conversationId: String? = nil,
        machineId: String? = nil,
        approvalId: String? = nil,
        searchQuery: String? = nil
    ) {
        self.action = action
        self.conversationId = conversationId
        self.machineId = machineId
        self.approvalId = approvalId
        self.searchQuery = searchQuery
    }

    public var userInfo: [String: Any] {
        var info: [String: Any] = [SiriNavigationUserInfoKey.action: action.rawValue]
        if let conversationId { info[SiriNavigationUserInfoKey.conversationId] = conversationId }
        if let machineId { info[SiriNavigationUserInfoKey.machineId] = machineId }
        if let approvalId { info[SiriNavigationUserInfoKey.approvalId] = approvalId }
        if let searchQuery { info[SiriNavigationUserInfoKey.searchQuery] = searchQuery }
        return info
    }

    public init?(userInfo: [AnyHashable: Any]) {
        guard let actionRaw = userInfo[SiriNavigationUserInfoKey.action] as? String,
              let action = SiriNavigationAction(rawValue: actionRaw)
        else { return nil }
        self.action = action
        conversationId = userInfo[SiriNavigationUserInfoKey.conversationId] as? String
        machineId = userInfo[SiriNavigationUserInfoKey.machineId] as? String
        approvalId = userInfo[SiriNavigationUserInfoKey.approvalId] as? String
        searchQuery = userInfo[SiriNavigationUserInfoKey.searchQuery] as? String
    }
}

/// Buffers Siri navigation intents so a cold-launched route is not lost before
/// `AppRoot` subscribes to `.lancerSiriNavigation`.
public final class SiriNavigationBuffer: @unchecked Sendable {
    public static let shared = SiriNavigationBuffer()

    private let lock = NSLock()
    private var pending: [SiriNavigationPayload] = []

    private init() {}

    public func record(_ payload: SiriNavigationPayload) {
        lock.lock()
        defer { lock.unlock() }
        pending.append(payload)
    }

    public func drain() -> [SiriNavigationPayload] {
        lock.lock()
        defer { lock.unlock() }
        let snapshot = pending
        pending.removeAll()
        return snapshot
    }
}
