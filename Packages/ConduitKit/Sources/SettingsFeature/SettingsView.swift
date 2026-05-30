#if os(iOS)
import SwiftUI
import Observation
import ConduitCore
import AgentKit
import DesignSystem
import KeysFeature
import PersistenceKit
import SecurityKit
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

// MARK: - SettingsView

public struct SettingsView: View {
    @State private var vm: SettingsViewModel
    let syncEngine: SyncEngine?
    let snippetRepo: SnippetRepository?
    let keyStore: KeyStore?

    @AppStorage("conduitColorScheme") private var colorSchemePref: String = "system"
    @Environment(\.conduitTokens) private var t

    /// Providers with a working AIClient — keeps the provider picker and the
    /// API Keys list in sync. Add `.xai` here once its client is implemented.
    private static let supportedProviders: [AIProvider] = [.anthropic, .openai]

    public init(
        viewModel: SettingsViewModel,
        syncEngine: SyncEngine? = nil,
        snippetRepo: SnippetRepository? = nil,
        keyStore: KeyStore? = nil
    ) {
        _vm = State(initialValue: viewModel)
        self.syncEngine = syncEngine
        self.snippetRepo = snippetRepo
        self.keyStore = keyStore
    }

    public var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // ── Title row
                    HStack {
                        Text("Settings")
                            .font(.dsDisplayPt(30, weight: .bold))
                            .foregroundStyle(t.text)
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 20)

                    // ── AI Provider
                    // Only providers with a working client are listed, so this
                    // list stays in sync with the API Keys section below (xAI is
                    // not wired yet — AppEnvironment.aiClient returns nil for it).
                    sectionHead("AI Provider")
                    settingsCard {
                        ForEach(Self.supportedProviders, id: \.self) { provider in
                            HStack {
                                Text(provider.displayName)
                                    .font(.dsSansPt(15))
                                    .foregroundStyle(t.text)
                                Spacer()
                                if vm.defaultProvider == provider {
                                    DSIconView(.check, size: 14, color: t.accent)
                                }
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 16)
                            .contentShape(Rectangle())
                            .onTapGesture { vm.defaultProvider = provider }
                            if provider != Self.supportedProviders.last {
                                divider
                            }
                        }
                    }
                    .padding(.bottom, 16)

                    // ── API Keys
                    sectionHead("API Keys")
                    settingsCard {
                        providerRow(.anthropic, binding: $vm.anthropicKey, hasKey: vm.hasAnthropicKey)
                        divider
                        providerRow(.openai, binding: $vm.openaiKey, hasKey: vm.hasOpenAIKey)
                    }
                    .padding(.bottom, 4)

                    HStack {
                        Spacer()
                        DSButton("Save keys", variant: .primary, action: { Task { await vm.save() } })
                            .padding(.trailing, 16)
                    }
                    .padding(.bottom, 16)

                    // ── Appearance
                    sectionHead("Appearance")
                    settingsCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Theme")
                                .font(.dsSansPt(13))
                                .foregroundStyle(t.text3)
                            Picker("Theme", selection: $colorSchemePref) {
                                Text("System").tag("system")
                                Text("Light").tag("light")
                                Text("Dark").tag("dark")
                            }
                            .pickerStyle(.segmented)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .padding(.bottom, 16)

                    // ── Library (Snippets + SSH Keys)
                    if snippetRepo != nil || keyStore != nil {
                        sectionHead("Library")
                        settingsCard {
                            if let repo = snippetRepo {
                                NavigationLink { SnippetEditorView(repository: repo) } label: {
                                    settingsNavRow("Snippets", icon: "text.append")
                                }
                            }
                            if let store = keyStore {
                                if snippetRepo != nil { divider }
                                NavigationLink { KeysView(viewModel: KeysViewModel(store: store)) } label: {
                                    settingsNavRow("SSH Keys", icon: "key")
                                }
                            }
                        }
                        .padding(.bottom, 16)
                    }

                    // ── Integrations
                    sectionHead("Integrations")
                    settingsCard {
                        NavigationLink { TerminalSettingsView() } label: {
                            settingsNavRow("Terminal settings", icon: "terminal")
                        }
                        divider
                        NavigationLink { BillingView() } label: {
                            settingsNavRow("Billing & usage", icon: "creditcard")
                        }
                        if let engine = syncEngine {
                            divider
                            SyncStatusView(engine: engine)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                        }
                    }
                    .padding(.bottom, 16)

                    // ── Privacy note
                    Text("Keys are stored on-device (Keychain, when-unlocked, device-only) and sent directly to the provider over TLS — never to Conduit servers.")
                        .font(.dsSansPt(12))
                        .foregroundStyle(t.text3)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 32)
                }
            }
        }
        .task { await vm.load() }
        .alert("Settings", isPresented: .constant(vm.saveMessage != nil), actions: {
            Button("OK") { vm.saveMessage = nil }
        }, message: { Text(vm.saveMessage ?? "") })
        .alert("Key test", isPresented: .constant(vm.testKeyResult != nil), actions: {
            Button("OK") { vm.testKeyResult = nil }
        }, message: { Text(vm.testKeyResult ?? "") })
    }

    // MARK: - Provider row

    @ViewBuilder
    private func providerRow(_ provider: AIProvider, binding: Binding<String>, hasKey: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(provider.displayName)
                    .font(.dsSansPt(14, weight: .semibold))
                    .foregroundStyle(t.text)
                Spacer()
                if hasKey {
                    DSChip("configured", tone: .ok, variant: .soft, size: .sm)
                    Button("Remove", role: .destructive) {
                        Task { await vm.remove(provider) }
                    }
                    .font(.dsSansPt(13))
                    .foregroundStyle(t.danger)
                } else {
                    DSChip("not set", tone: .neutral, variant: .soft, size: .sm)
                }
            }
            SecureField(hasKey ? "Replace API key" : "Paste API key", text: binding)
                .font(.dsMonoPt(13))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(10)
                .background(t.surfaceSunk)
                .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))
            if hasKey {
                Button {
                    Task { await vm.testKey(provider: provider) }
                } label: {
                    HStack(spacing: 6) {
                        if vm.isTestingKey {
                            ProgressView().scaleEffect(0.75)
                            Text("Testing…")
                        } else {
                            Image(systemName: "bolt.fill").font(.system(size: 12))
                            Text("Test key")
                        }
                    }
                    .font(.dsSansPt(13, weight: .medium))
                    .foregroundStyle(t.accent)
                }
                .disabled(vm.isTestingKey)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Layout helpers

    private func sectionHead(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.dsMonoPt(11))
            .tracking(0.8)
            .foregroundStyle(t.text3)
            .padding(.horizontal, 20)
            .padding(.bottom, 6)
    }

    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(t.surface)
        .clipShape(RoundedRectangle(cornerRadius: t.r4, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: t.r4, style: .continuous)
                .strokeBorder(t.border, lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }

    private func settingsNavRow(_ label: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(t.text2)
                .frame(width: 20)
            Text(label)
                .font(.dsSansPt(15))
                .foregroundStyle(t.text)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(t.text4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    private var divider: some View {
        Rectangle().fill(t.divider).frame(height: 1).padding(.leading, 16)
    }
}

#endif
