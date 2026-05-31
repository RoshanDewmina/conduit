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
    public var saveIsError = false
    public var testKeyResult: String? = nil
    public var testKeyProvider: AIProvider? = nil
    public var isTestingKey = false

    private let keyStore: any AIKeyStoring
    private var lastTestDate: Date? = nil
    private static let defaultProviderKey = "dev.conduit.defaultAIProvider"
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
        case .xai:
            return nil
        }
    }
}

// MARK: - SettingsView

public struct SettingsView: View {
    @State private var vm: SettingsViewModel
    let syncEngine: SyncEngine?
    let snippetRepo: SnippetRepository?
    let keyStore: KeyStore?
    public var statusHeaderAgents: [AgentInfo] = []
    public var onTapStatusHeader: () -> Void = {}

    @AppStorage("conduitColorScheme") private var colorSchemePref: String = "system"
    @Environment(\.conduitTokens) private var t

    /// Providers with a working AIClient — keeps the provider picker and the
    /// API Keys list in sync. Add `.xai` here once its client is implemented.
    private static let supportedProviders: [AIProvider] = [.anthropic, .openai]

    /// Gate for paid/stub surfaces not ready for the free TestFlight beta.
    /// Flip to `true` when iCloud sync and billing are production-ready.
    private static let showPaidSurfaces = true

    public init(
        viewModel: SettingsViewModel,
        syncEngine: SyncEngine? = nil,
        snippetRepo: SnippetRepository? = nil,
        keyStore: KeyStore? = nil,
        statusHeaderAgents: [AgentInfo] = [],
        onTapStatusHeader: @escaping () -> Void = {}
    ) {
        _vm = State(initialValue: viewModel)
        self.syncEngine = syncEngine
        self.snippetRepo = snippetRepo
        self.keyStore = keyStore
        self.statusHeaderAgents = statusHeaderAgents
        self.onTapStatusHeader = onTapStatusHeader
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
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, statusHeaderAgents.isEmpty ? 20 : 0)

                    if !statusHeaderAgents.isEmpty {
                        AgentStatusHeader(agents: statusHeaderAgents, onTap: onTapStatusHeader)
                            .padding(.bottom, 20)
                    }

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

                    VStack(alignment: .trailing, spacing: 6) {
                        if let msg = vm.saveMessage {
                            Text(msg)
                                .font(.dsSansPt(13))
                                .foregroundStyle(vm.saveIsError ? t.danger : t.accent)
                                .padding(.horizontal, 20)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .transition(.opacity)
                        }
                        HStack {
                            Spacer()
                            DSButton("Save keys", variant: .primary, action: { Task { await vm.save() } })
                                .padding(.trailing, 16)
                        }
                    }
                    .animation(.easeInOut(duration: 0.2), value: vm.saveMessage)
                    .padding(.bottom, 16)

                    // ── Appearance
                    sectionHead("Appearance")
                    settingsCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Theme")
                                .font(.dsSansPt(13))
                                .foregroundStyle(t.text3)
                            DSSegmentedPicker(
                                options: [
                                    (label: "System", value: "system"),
                                    (label: "Light",  value: "light"),
                                    (label: "Dark",   value: "dark"),
                                ],
                                selection: $colorSchemePref
                            )
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
                                NavigationLink { KeysView(viewModel: KeysViewModel(store: store), store: store) } label: {
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
                        NavigationLink { PremiumComparisonView() } label: {
                            settingsNavRow("Compare Free vs Pro", icon: "star.circle")
                        }
                        // Billing and iCloud sync are not ready for the free beta.
                        // showPaidSurfaces gates them back in when production-ready.
                        if Self.showPaidSurfaces {
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
                    }
                    .padding(.bottom, 16)

                    // ── About Conduit
                    sectionHead("About Conduit")
                    settingsCard {
                        VStack(alignment: .leading, spacing: 0) {
                            aboutRow(icon: "server.rack", title: "BYO host",
                                     detail: "Connect to any SSH server you own or rent. Conduit does not provision or manage your infrastructure.")
                            divider
                            aboutRow(icon: "key", title: "BYO API key",
                                     detail: "Your Anthropic or OpenAI key is stored in the device Keychain and sent directly to the provider.")
                            divider
                            aboutRow(icon: "person.badge.minus", title: "No account required",
                                     detail: "No Conduit login. No subscription. All session data stays on-device.")
                        }
                    }
                    .padding(.bottom, 16)

                    // ── Privacy note
                    Text("Keys are stored on-device (Keychain, when-unlocked, device-only) and sent directly to the provider over TLS — never to Conduit servers.")
                        .font(.dsSansPt(12))
                        .foregroundStyle(t.text3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 32)
                }
            }
        }
        .task { await vm.load() }
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
                HStack(alignment: .top, spacing: 8) {
                    Button {
                        Task { await vm.testKey(provider: provider) }
                    } label: {
                        HStack(spacing: 6) {
                            if vm.isTestingKey && vm.testKeyProvider == provider {
                                ProgressView().scaleEffect(0.75)
                                Text("Testing…")
                            } else {
                                Image(systemName: "bolt.fill").font(.system(size: 12))
                                Text("Test key")
                            }
                        }
                        .font(.dsSansPt(13, weight: .medium))
                        .foregroundStyle(vm.canTestKey ? t.accent : t.text3)
                    }
                    .disabled(!vm.canTestKey)
                    if let result = vm.testKeyResult, vm.testKeyProvider == provider {
                        Text(result)
                            .font(.dsMonoPt(12))
                            .foregroundStyle(result.hasPrefix("Error") ? t.danger : t.accent)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
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

    private func aboutRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(t.accent)
                .frame(width: 20, alignment: .center)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.dsSansPt(14, weight: .semibold))
                    .foregroundStyle(t.text)
                Text(detail)
                    .font(.dsSansPt(13))
                    .foregroundStyle(t.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

#endif
