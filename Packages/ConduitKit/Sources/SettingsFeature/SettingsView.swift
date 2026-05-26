#if os(iOS)
import SwiftUI
import Observation
import ConduitCore
import AgentKit
import DesignSystem
import SyncKit

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
    public var testKeyResult: String? = nil
    public var isTestingKey = false

    private let keyStore: any AIKeyStoring
    private static let defaultProviderKey = "dev.conduit.defaultAIProvider"

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
            saveMessage = "Saved."
        } catch {
            saveMessage = error.localizedDescription
        }
    }

    public func remove(_ provider: AIProvider) async {
        try? await keyStore.deleteAPIKey(provider: provider)
        await load()
    }

    public func testKey(provider: AIProvider) async {
        guard !isTestingKey else { return }
        isTestingKey = true
        defer { isTestingKey = false }

        do {
            let key = try await keyStore.loadAPIKey(provider: provider)
            let client: any AIClient
            switch provider {
            case .anthropic:
                client = AnthropicClient(apiKey: key)
            case .openai:
                client = OpenAIClient(apiKey: key)
            case .xai:
                testKeyResult = "xAI key test not yet supported."
                return
            }
            let start = Date()
            let response = try await client.complete(
                messages: [.user("Say hello in 5 words")],
                system: nil,
                maxTokens: 20
            )
            let latencyMs = Int(Date().timeIntervalSince(start) * 1000)
            testKeyResult = "OK · \(latencyMs) ms · model: \(client.modelID)\n\"\(response)\""
        } catch {
            testKeyResult = "Error: \(error.localizedDescription)"
        }
    }
}

public struct SettingsView: View {
    @State private var vm: SettingsViewModel
    let syncEngine: SyncEngine?

    public init(viewModel: SettingsViewModel, syncEngine: SyncEngine? = nil) {
        _vm = State(initialValue: viewModel)
        self.syncEngine = syncEngine
    }

    public var body: some View {
        Form {
            Section("Default AI Provider") {
                Picker("Provider", selection: $vm.defaultProvider) {
                    ForEach(AIProvider.allCases, id: \.self) { p in
                        Text(p.displayName).tag(p)
                    }
                }
            }
            providerSection(.anthropic, $vm.anthropicKey, vm.hasAnthropicKey)
            providerSection(.openai,    $vm.openaiKey,    vm.hasOpenAIKey)

            if let engine = syncEngine {
                SyncStatusView(engine: engine)
            }

            Section {
                Button("Save") { Task { await vm.save() } }
            }

            Section("Terminal") {
                NavigationLink("Terminal Settings") {
                    TerminalSettingsView()
                }
            }

            Section("Providers") {
                NavigationLink("Billing & Usage") {
                    BillingView()
                }
            }

            Section {
                Text("Keys are stored on this device only (Keychain, when-unlocked, device-only). They are sent directly to the provider over TLS — never to Conduit.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
        .contentMargins(.bottom, 72, for: .scrollContent)
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 72)
        }
        .task { await vm.load() }
        .alert("Settings", isPresented: .constant(vm.saveMessage != nil), actions: {
            Button("OK") { vm.saveMessage = nil }
        }, message: { Text(vm.saveMessage ?? "") })
        .alert("Key test", isPresented: .constant(vm.testKeyResult != nil), actions: {
            Button("OK") { vm.testKeyResult = nil }
        }, message: { Text(vm.testKeyResult ?? "") })
    }

    private func providerSection(_ provider: AIProvider, _ binding: Binding<String>, _ hasKey: Bool) -> some View {
        Section(provider.displayName) {
            SecureField("API key", text: binding)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            HStack {
                ViewThatFits(in: .horizontal) {
                    providerStatus(provider, hasKey: hasKey, vertical: false)
                    providerStatus(provider, hasKey: hasKey, vertical: true)
                }
            }
            if hasKey {
                Button {
                    Task { await vm.testKey(provider: provider) }
                } label: {
                    HStack {
                        if vm.isTestingKey {
                            ProgressView().scaleEffect(0.8)
                            Text("Testing…")
                        } else {
                            Label("Test key", systemImage: "bolt.fill")
                        }
                    }
                }
                .disabled(vm.isTestingKey)
            }
        }
    }

    @ViewBuilder
    private func providerStatus(_ provider: AIProvider, hasKey: Bool, vertical: Bool) -> some View {
        let layout = vertical ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
        layout {
            if hasKey {
                Label("Configured", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                if !vertical { Spacer() }
                Button("Remove", role: .destructive) {
                    Task { await vm.remove(provider) }
                }
            } else {
                Label("Not configured", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
        }
    }
}

#endif
