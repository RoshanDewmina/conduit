import Foundation
import ConduitCore

/// Deterministic AI client for tests and demos. Streams a canned response
/// token-by-token with a configurable per-token delay.
public actor MockAIClient: AIClient {
    public nonisolated let modelID: String = "mock-1"
    public nonisolated var displayName: String { "Mock" }

    public let response: String
    public let perTokenDelay: Duration

    public init(response: String = "echo hello", perTokenDelay: Duration = .milliseconds(10)) {
        self.response = response
        self.perTokenDelay = perTokenDelay
    }

    public func complete(messages: [AIMessage], system: String?, maxTokens: Int) async throws -> String {
        response
    }

    public nonisolated func streamCompletion(
        messages: [AIMessage],
        system: String?,
        maxTokens: Int
    ) -> AsyncThrowingStream<AIDelta, any Error> {
        let response = self.response
        let perTokenDelay = self.perTokenDelay
        return AsyncThrowingStream { continuation in
            let task = Task {
                for token in response.split(separator: " ", omittingEmptySubsequences: false) {
                    try Task.checkCancellation()
                    continuation.yield(.text(String(token) + " "))
                    try await Task.sleep(for: perTokenDelay)
                }
                continuation.yield(.done)
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
