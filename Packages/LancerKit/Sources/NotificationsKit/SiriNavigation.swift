import Foundation

/// Siri → in-app navigation bridge (I2, ported from the parked
/// `cursor/siri-phase2-fixes-9257` branch's `SiriNavigation.swift`).
///
/// The old branch's version targeted the now-deprecated sidebar `AppRoot`
/// shell; this port is consumed by the current Cursor-style shell
/// (`AppFeature/CursorStyle/CursorAppShell.swift`), which owns its own
/// private `NavigationPath`/overlay state and observes `.lancerSiriNavigation`
/// directly rather than routing through `AppRoot`.
///
/// Only the actions that have a real destination AND a real caller today are
/// ported:
///  - `.search` — `SearchLancerIntent` already opens the app but previously
///    left it on whatever screen was already showing.
///  - `.openConversation` — `OpenConversationIntent` has the same gap.
/// `.openMachine` and `.continueConversation` (present on the old branch)
/// are deliberately NOT ported: the Cursor shell has no per-machine detail
/// screen to open, and there is no `ContinueConversationIntent` in the
/// current intents surface — porting either would mean routing to a
/// destination that doesn't exist or inventing new intent scope beyond this
/// navigation-bridge port. `.openApproval` is also not carried by this
/// payload: opening a specific approval already has a fully-wired path via
/// `Notification.Name.lancerOpenApproval` (`AppRoot`'s existing
/// `cursorLiveBridge.pendingApprovalID` + review-sheet seam, used today by
/// the lock-screen notification tap) — duplicating that here would create a
/// second, parallel mechanism for the same destination.
public enum SiriNavigationAction: String, Sendable {
    case search
    case openConversation
}

public extension Notification.Name {
    /// userInfo keys: `action` (String raw value), plus optional
    /// `conversationId`/`searchQuery` depending on the action.
    static let lancerSiriNavigation = Notification.Name("dev.lancer.siriNavigation")
}

public enum SiriNavigationUserInfoKey {
    public static let action = "action"
    public static let conversationId = "conversationId"
    public static let searchQuery = "searchQuery"
}

/// Durable Siri navigation payload — survives cold launch when NotificationCenter
/// has no live subscriber yet (mirrors `OpenApprovalBuffer`'s cold-launch buffering).
public struct SiriNavigationPayload: Sendable, Equatable {
    public let action: SiriNavigationAction
    public let conversationId: String?
    public let searchQuery: String?

    public init(
        action: SiriNavigationAction,
        conversationId: String? = nil,
        searchQuery: String? = nil
    ) {
        self.action = action
        self.conversationId = conversationId
        self.searchQuery = searchQuery
    }

    public var userInfo: [String: Any] {
        var info: [String: Any] = [SiriNavigationUserInfoKey.action: action.rawValue]
        if let conversationId { info[SiriNavigationUserInfoKey.conversationId] = conversationId }
        if let searchQuery { info[SiriNavigationUserInfoKey.searchQuery] = searchQuery }
        return info
    }

    public init?(userInfo: [AnyHashable: Any]) {
        guard let actionRaw = userInfo[SiriNavigationUserInfoKey.action] as? String,
              let action = SiriNavigationAction(rawValue: actionRaw)
        else { return nil }
        self.action = action
        conversationId = userInfo[SiriNavigationUserInfoKey.conversationId] as? String
        searchQuery = userInfo[SiriNavigationUserInfoKey.searchQuery] as? String
    }
}

/// Buffers Siri navigation intents so a cold-launched route is not lost before
/// the Cursor shell subscribes to `.lancerSiriNavigation`.
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

/// One-call convenience for App Intents (the `Lancer` app target) to record +
/// broadcast a navigation payload without each intent re-deriving the
/// buffer/post pairing. Kept here (not the app target's `SiriIntentSupport`)
/// since it's pure `Foundation`/`NotificationCenter` plumbing with no
/// `AppIntents` dependency — any intent that already imports `NotificationsKit`
/// transitively (all of them do, via `SessionFeature`) can call it directly.
public enum SiriNavigationDispatch {
    public static func post(_ payload: SiriNavigationPayload) {
        SiriNavigationBuffer.shared.record(payload)
        NotificationCenter.default.post(
            name: .lancerSiriNavigation,
            object: nil,
            userInfo: payload.userInfo
        )
    }
}
