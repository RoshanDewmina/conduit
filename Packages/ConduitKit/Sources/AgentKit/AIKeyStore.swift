import Foundation
import ConduitCore

/// Indirect dependency to avoid importing SecurityKit from AgentKit (which
/// would create a circular dep when SecurityKit needs ConduitError types).
/// The app wires a concrete implementation at startup.
public protocol AIKeyStoring: Sendable {
    func storeAPIKey(_ key: String, provider: AIProvider) async throws
    func loadAPIKey(provider: AIProvider) async throws -> String
    func deleteAPIKey(provider: AIProvider) async throws
    func hasAPIKey(provider: AIProvider) async -> Bool
}

public enum AIProvider: String, Sendable, Codable, CaseIterable {
    case anthropic, openai, xai

    public var displayName: String {
        switch self {
        case .anthropic: "Anthropic"
        case .openai:    "OpenAI"
        case .xai:       "xAI"
        }
    }
}
