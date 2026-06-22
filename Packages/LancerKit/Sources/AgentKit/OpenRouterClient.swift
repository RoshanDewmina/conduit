import Foundation
import LancerCore

/// OpenRouter chat-completions client (OpenAI-compatible) with inline cost tracking.
public actor OpenRouterClient: AIClient {
    public nonisolated let modelID: String
    public nonisolated var displayName: String { "OpenRouter · \(modelID)" }

    private let apiKey: String
    private let session: URLSession
    private static let baseURL = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

    nonisolated(unsafe) private var sessionTokens: TokenUsage = .zero
    nonisolated(unsafe) private var sessionCostUSD: Double = 0

    public init(
        apiKey: String,
        modelID: String = "anthropic/claude-sonnet-4",
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
                            : LancerError.providerUnavailable(name: "OpenRouter", status: http.statusCode)
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
            throw LancerError.providerUnavailable(
                name: "OpenRouter",
                status: (response as? HTTPURLResponse)?.statusCode
            )
        }
        let parsed = try Self.parseCompletion(data)
        sessionTokens = sessionTokens.adding(parsed.tokens)
        sessionCostUSD += parsed.costUSD ?? 0
        return parsed.text
    }

    public nonisolated func latestTokenUsage() -> TokenUsage {
        sessionTokens
    }

    /// Cumulative USD spend from OpenRouter inline `usage.cost` fields.
    public nonisolated func latestCostUSD() -> Double {
        sessionCostUSD
    }

    /// Latest usage as a `UsageRecord` suitable for control-plane ingest.
    public nonisolated func latestUsageRecord(model: String? = nil) -> UsageRecord {
        UsageRecord(
            inputTokens: sessionTokens.inputTokens,
            outputTokens: sessionTokens.outputTokens,
            costUSD: sessionCostUSD > 0 ? sessionCostUSD : nil,
            model: model ?? modelID
        )
    }

    // MARK: - Parsing (testable)

    struct ParsedCompletion: Equatable, Sendable {
        let text: String
        let tokens: TokenUsage
        let costUSD: Double?
    }

    static func parseCompletion(_ data: Data) throws -> ParsedCompletion {
        struct Resp: Decodable {
            let choices: [Choice]
            let usage: Usage?
            struct Choice: Decodable {
                let message: Message?
                struct Message: Decodable { let content: String? }
            }
            struct Usage: Decodable {
                let prompt_tokens: Int?
                let completion_tokens: Int?
                let cost: Double?
            }
        }
        let resp = try JSONDecoder().decode(Resp.self, from: data)
        let text = resp.choices.compactMap { $0.message?.content }.joined()
        let usage = resp.usage
        let tokens = TokenUsage(
            inputTokens: usage?.prompt_tokens ?? 0,
            outputTokens: usage?.completion_tokens ?? 0
        )
        return ParsedCompletion(text: text, tokens: tokens, costUSD: usage?.cost)
    }

    static func parseDelta(_ json: String) -> AIDelta? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        if let choices = obj["choices"] as? [[String: Any]],
           let delta = choices.first?["delta"] as? [String: Any],
           let content = delta["content"] as? String, !content.isEmpty {
            return .text(content)
        }
        if let usage = obj["usage"] as? [String: Any] {
            let input = usage["prompt_tokens"] as? Int ?? 0
            let output = usage["completion_tokens"] as? Int ?? 0
            return .usage(inputTokens: input, outputTokens: output)
        }
        return nil
    }

    private static func buildRequest(
        apiKey: String, modelID: String,
        messages: [AIMessage], system: String?,
        maxTokens: Int, stream: Bool
    ) throws -> URLRequest {
        var req = URLRequest(url: baseURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("https://conduit.dev", forHTTPHeaderField: "HTTP-Referer")
        req.setValue("Lancer", forHTTPHeaderField: "X-Title")

        var chatMessages: [[String: String]] = []
        if let system {
            chatMessages.append(["role": "system", "content": system])
        }
        chatMessages += messages.map { ["role": $0.role.rawValue, "content": $0.content] }

        let payload: [String: Any] = [
            "model": modelID,
            "max_tokens": maxTokens,
            "stream": stream,
            "messages": chatMessages,
            "transforms": ["middle-out"],
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        return req
    }
}
