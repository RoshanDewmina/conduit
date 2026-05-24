import Foundation

/// Provider-neutral message shape that the AIClient protocol accepts.
public struct AIMessage: Sendable, Hashable, Codable {
    public enum Role: String, Sendable, Codable { case user, assistant, system, tool }

    public let role: Role
    public let content: String

    public init(role: Role, content: String) {
        self.role = role
        self.content = content
    }

    public static func user(_ s: String)      -> AIMessage { .init(role: .user, content: s) }
    public static func assistant(_ s: String) -> AIMessage { .init(role: .assistant, content: s) }
    public static func system(_ s: String)    -> AIMessage { .init(role: .system, content: s) }
}

/// One streaming delta from a provider. `text` is the most common case;
/// `toolCall` carries structured function calls when providers emit them.
public enum AIDelta: Sendable, Hashable {
    case text(String)
    case toolCall(name: String, arguments: String)
    case usage(inputTokens: Int, outputTokens: Int)
    case done
}
