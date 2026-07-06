#if os(iOS)
import Foundation
import Observation
import LancerCore
import AgentKit
import SecurityKit

@MainActor @Observable
public final class SettingsViewModel {
    public var anthropicKey: String = ""
    public var openaiKey: String = ""
    public var hasAnthropicKey: Bool = false
    public var hasOpenAIKey: Bool = false
    public var defaultProvider: AIProvider {
        didSet {
            UserDefaults.standard.set(defaultProvider.rawValue, forKey: Self.defaultProviderKey)
        }
    }
    public var saveMessage: String?
    public var saveIsError = false
    public var testKeyResult: String? = nil
    public var testKeyProvider: AIProvider? = nil
    public var isTestingKey = false

    private let keyStore: any AIKeyStoring
    private var lastTestDate: Date? = nil
    private static let defaultProviderKey = "dev.lancer.defaultAIProvider"
    private static let testCooldown: TimeInterval = 10

    public var canTestKey: Bool {
        guard !isTestingKey else { return false }
        guard let last = lastTestDate else { return true }
        return Date().timeIntervalSince(last) >= Self.testCooldown
    }

    public init(keyStore: any AIKeyStoring) {
        self.keyStore = keyStore
        self.defaultProvider = Self.persistedDefaultProvider()
    }

    public static func persistedDefaultProvider(defaults: UserDefaults = .standard) -> AIProvider {
        guard let raw = defaults.string(forKey: defaultProviderKey),
              let provider = AIProvider(rawValue: raw)
        else { return .anthropic }
        return provider
    }

    public func load() async {
        hasAnthropicKey = await keyStore.hasAPIKey(provider: .anthropic)
        hasOpenAIKey    = await keyStore.hasAPIKey(provider: .openai)
    }

    public func save() async {
        saveIsError = false
        if !anthropicKey.isEmpty, let err = validateKey(anthropicKey, provider: .anthropic) {
            saveMessage = err; saveIsError = true; return
        }
        if !openaiKey.isEmpty, let err = validateKey(openaiKey, provider: .openai) {
            saveMessage = err; saveIsError = true; return
        }
        do {
            if !anthropicKey.isEmpty {
                try await keyStore.storeAPIKey(anthropicKey, provider: .anthropic)
                anthropicKey = ""
            }
            if !openaiKey.isEmpty {
                try await keyStore.storeAPIKey(openaiKey, provider: .openai)
                openaiKey = ""
            }
            await load()
            saveMessage = "Keys saved."
            Task { try? await Task.sleep(for: .seconds(3)); saveMessage = nil }
        } catch {
            saveMessage = error.localizedDescription
            saveIsError = true
        }
    }

    public func remove(_ provider: AIProvider) async {
        try? await keyStore.deleteAPIKey(provider: provider)
        await load()
        saveMessage = "\(provider.displayName) key removed."
        saveIsError = false
        Task { try? await Task.sleep(for: .seconds(3)); saveMessage = nil }
    }

    public func testKey(provider: AIProvider) async {
        guard canTestKey else { return }
        isTestingKey = true
        testKeyProvider = provider
        lastTestDate = Date()
        testKeyResult = nil
        defer { isTestingKey = false }
        do {
            let key = try await keyStore.loadAPIKey(provider: provider)
            let client: any AIClient
            switch provider {
            case .anthropic:
                client = AnthropicClient(apiKey: key)
            case .openai:
                client = OpenAIClient(apiKey: key)
            case .openrouter:
                testKeyResult = "OpenRouter key test not yet supported."
                return
            case .xai:
                testKeyResult = "xAI key test not yet supported."
                return
            }
            let start = Date()
            _ = try await client.complete(
                messages: [.user("Say hello in 5 words")],
                system: nil,
                maxTokens: 20
            )
            let latencyMs = Int(Date().timeIntervalSince(start) * 1000)
            testKeyResult = "OK · \(latencyMs) ms · \(client.modelID)"
        } catch {
            testKeyResult = "Error: \(error.localizedDescription)"
        }
    }

    private func validateKey(_ key: String, provider: AIProvider) -> String? {
        switch provider {
        case .anthropic:
            guard key.hasPrefix("sk-ant-"), key.count >= 40 else {
                return "Anthropic keys must start with \"sk-ant-\" and be at least 40 characters."
            }
            return nil
        case .openai:
            let validPrefix = key.hasPrefix("sk-proj-") || (key.hasPrefix("sk-") && !key.hasPrefix("sk-ant-"))
            guard validPrefix, key.count >= 40 else {
                return "OpenAI keys must start with \"sk-\" and be at least 40 characters."
            }
            return nil
        case .openrouter:
            guard key.hasPrefix("sk-or-"), key.count >= 20 else {
                return "OpenRouter keys must start with \"sk-or-\"."
            }
            return nil
        case .xai:
            return nil
        }
    }
}
#endif
