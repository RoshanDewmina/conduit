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
}

public enum SiriNavigationUserInfoKey {
    public static let action = "action"
    public static let conversationId = "conversationId"
    public static let machineId = "machineId"
    public static let approvalId = "approvalId"
    public static let searchQuery = "searchQuery"
}
