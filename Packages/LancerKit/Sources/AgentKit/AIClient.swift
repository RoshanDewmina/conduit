import Foundation
import LancerCore

// MARK: - Token usage

/// Aggregated token counts returned after a completion call.
public struct TokenUsage: Sendable, Equatable {
    public let inputTokens: Int
    public let outputTokens: Int

    public init(inputTokens: Int, outputTokens: Int) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }

    public static let zero = TokenUsage(inputTokens: 0, outputTokens: 0)

    public func adding(_ other: TokenUsage) -> TokenUsage {
        TokenUsage(inputTokens: inputTokens + other.inputTokens,
                   outputTokens: outputTokens + other.outputTokens)
    }
}

// MARK: - Protocol

/// Provider-neutral chat / completion abstraction.
public protocol AIClient: Sendable {
    var modelID: String { get }
    var displayName: String { get }

    func complete(messages: [AIMessage], system: String?, maxTokens: Int) async throws -> String

    func streamCompletion(
        messages: [AIMessage],
        system: String?,
        maxTokens: Int
    ) -> AsyncThrowingStream<AIDelta, any Error>

    /// Returns the cumulative token usage across all calls made to this client
    /// since it was created (or since the last reset, if supported).
    /// Implementations that don't track tokens return `.zero`.
    func latestTokenUsage() -> TokenUsage
}

public extension AIClient {
    var displayName: String { modelID }

    func complete(messages: [AIMessage], system: String? = nil, maxTokens: Int = 1024) async throws -> String {
        try await complete(messages: messages, system: system, maxTokens: maxTokens)
    }

    /// Default no-op implementation so existing conformers don't have to change.
    func latestTokenUsage() -> TokenUsage { .zero }
}
