import Foundation
import LancerCore

/// Minimal OpenAI Chat Completions client with SSE streaming. Same
/// rationale as `AnthropicClient`: hand-rolled, ~80 lines, no SDK weight.
public actor OpenAIClient: AIClient {
    public nonisolated let modelID: String
    public nonisolated var displayName: String { "OpenAI · \(modelID)" }

    private let apiKey: String
    private let session: URLSession
    private static let baseURL = URL(string: "https://api.openai.com/v1/chat/completions")!

    public init(
        apiKey: String,
        modelID: String = "gpt-5.5-mini",
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
                            : LancerError.providerUnavailable(name: "OpenAI", status: http.statusCode)
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
            throw LancerError.providerUnavailable(name: "OpenAI", status: (response as? HTTPURLResponse)?.statusCode)
        }
        struct Resp: Decodable {
            let choices: [Choice]
            struct Choice: Decodable { let message: Msg; struct Msg: Decodable { let content: String } }
        }
        let resp = try JSONDecoder().decode(Resp.self, from: data)
        return resp.choices.first?.message.content ?? ""
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
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        var msgs: [[String: Any]] = []
        if let system { msgs.append(["role": "system", "content": system]) }
        msgs.append(contentsOf: messages.map { ["role": $0.role.rawValue, "content": $0.content] })

        let payload: [String: Any] = [
            "model": modelID,
            "max_tokens": maxTokens,
            "stream": stream,
            "messages": msgs,
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        return req
    }

    private static func parseDelta(_ json: String) -> AIDelta? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]],
              let first = choices.first,
              let delta = first["delta"] as? [String: Any]
        else { return nil }
        if let text = delta["content"] as? String, !text.isEmpty {
            return .text(text)
        }
        return nil
    }
}
