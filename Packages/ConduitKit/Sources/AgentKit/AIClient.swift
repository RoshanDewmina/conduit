import Foundation
import ConduitCore

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
}

public extension AIClient {
    var displayName: String { modelID }

    func complete(messages: [AIMessage], system: String? = nil, maxTokens: Int = 1024) async throws -> String {
        try await complete(messages: messages, system: system, maxTokens: maxTokens)
    }
}
