import Foundation
import LancerCore

/// Hand-rolled Anthropic Messages API client with SSE streaming. We avoid
/// the official SDK because (a) it pulls in significant binary weight,
/// (b) parsing SSE is ~30 lines and trivially maintainable, (c) we can keep
/// per-provider code symmetrical and identical to the OpenAI client below.
public actor AnthropicClient: AIClient {
    public nonisolated let modelID: String
    public nonisolated var displayName: String { "Anthropic · \(modelID)" }

    private let apiKey: String
    private let session: URLSession
    private static let baseURL = URL(string: "https://api.anthropic.com/v1/messages")!

    /// Accumulated token usage across all calls made on this actor instance.
    /// `nonisolated(unsafe)` lets `latestTokenUsage()` read it without actor hop.
    /// It is only ever mutated from within the actor (inside `complete`), so
    /// there are no concurrent writes.
    nonisolated(unsafe) private var sessionTokens: TokenUsage = .zero

    public init(
        apiKey: String,
        modelID: String = "claude-sonnet-4-6",
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.modelID = modelID
        self.session = session
    }

    public nonisolated func streamCompletion(
        messages: [AIMessage],
        system: String?,
        maxTokens: Int
    ) -> AsyncThrowingStream<AIDelta, any Error> {
        let apiKey = self.apiKey
        let modelID = self.modelID
        let session = self.session

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try Self.buildRequest(
                        apiKey: apiKey, modelID: modelID,
                        messages: messages, system: system,
                        maxTokens: maxTokens, stream: true
                    )
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw LancerError.invalidResponse(detail: "non-HTTP response")
                    }
                    guard http.statusCode == 200 else {
                        throw http.statusCode == 429
                            ? LancerError.rateLimited
                            : LancerError.providerUnavailable(name: "Anthropic", status: http.statusCode)
                    }
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard line.hasPrefix("data: ") else { continue }
                        let body = String(line.dropFirst(6))
                        if body == "[DONE]" {
                            continuation.yield(.done)
                            break
                        }
                        if let delta = Self.parseDelta(body) {
                            continuation.yield(delta)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func complete(messages: [AIMessage], system: String?, maxTokens: Int) async throws -> String {
        let request = try Self.buildRequest(
            apiKey: apiKey, modelID: modelID,
            messages: messages, system: system,
            maxTokens: maxTokens, stream: false
        )
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode
            throw LancerError.providerUnavailable(name: "Anthropic", status: code)
        }
        struct Resp: Decodable {
            let content: [Block]
            let usage: Usage?
            struct Block: Decodable { let type: String; let text: String? }
            struct Usage: Decodable {
                let input_tokens: Int
                let output_tokens: Int
            }
        }
        let resp = try JSONDecoder().decode(Resp.self, from: data)
        if let usage = resp.usage {
            let callUsage = TokenUsage(inputTokens: usage.input_tokens, outputTokens: usage.output_tokens)
            sessionTokens = sessionTokens.adding(callUsage)
        }
        return resp.content.compactMap(\.text).joined()
    }

    /// Returns the cumulative token usage for this client session.
    /// `nonisolated` so it satisfies the protocol requirement without an actor hop.
    /// `sessionTokens` is `nonisolated(unsafe)` and only mutated inside the actor,
    /// so reading it here is safe in practice.
    public nonisolated func latestTokenUsage() -> TokenUsage {
        return sessionTokens
    }

    // MARK: - Helpers

    private static func buildRequest(
        apiKey: String, modelID: String,
        messages: [AIMessage], system: String?,
        maxTokens: Int, stream: Bool
    ) throws -> URLRequest {
        var req = URLRequest(url: baseURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        var payload: [String: Any] = [
            "model": modelID,
            "max_tokens": maxTokens,
            "stream": stream,
            "messages": messages
                .filter { $0.role != .system }
                .map { ["role": $0.role.rawValue, "content": $0.content] },
        ]
        if let system { payload["system"] = system }
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        return req
    }

    /// Parse one SSE event payload. Anthropic events come typed as
    /// `content_block_delta`, `message_start`, etc. We extract the
    /// `delta.text` field if present, ignore the rest.
    private static func parseDelta(_ json: String) -> AIDelta? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        if let delta = obj["delta"] as? [String: Any],
           let text = delta["text"] as? String, !text.isEmpty {
            return .text(text)
        }
        if let usage = obj["usage"] as? [String: Any],
           let input = usage["input_tokens"] as? Int,
           let output = usage["output_tokens"] as? Int {
            return .usage(inputTokens: input, outputTokens: output)
        }
        return nil
    }
}
