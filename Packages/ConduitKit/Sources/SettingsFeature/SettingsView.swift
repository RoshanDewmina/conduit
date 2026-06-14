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
import NotificationsKit

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

// MARK: - SettingsView

public struct SettingsView: View {
    @State private var vm: SettingsViewModel
    let syncEngine: SyncEngine?
    let backendURL: String
    let auditRepository: AuditRepository?
    let approvalRepository: ApprovalRepository?
    let bridgeActions: BridgeSessionActions
    public var statusHeaderAgents: [AgentInfo] = []
    public var onTapStatusHeader: () -> Void = {}
    @AppStorage("conduitColorScheme") private var colorSchemePref: String = "system"
    @AppStorage("appLockEnabled") private var appLockEnabled = false
    @AppStorage("redactSavedHistory") private var redactSavedHistory = false
    // Agent approval policy — global preference, shared with the inbox filter.
    @AppStorage("inbox.autonomyPreset") private var autonomyPresetRaw: String = AutonomyPreset.alwaysAsk.rawValue
    @AppStorage("flag.autonomyPresets") private var autonomyPresetsEnabled: Bool = true
    @Environment(\.conduitTokens) private var t
    @State private var notificationFilter = NotificationFilter()
    @State private var alwaysRules: [AlwaysRuleItem] = []
    @State private var revokedRuleSignatures: Set<String> = Self.loadRevokedRuleSignatures()

    private var autonomyPreset: Binding<AutonomyPreset> {
        Binding(
            get: { AutonomyPreset(rawValue: autonomyPresetRaw) ?? .alwaysAsk },
            set: { autonomyPresetRaw = $0.rawValue }
        )
    }

    /// Providers with a working AIClient — keeps the provider picker and the
    /// API Keys list in sync. Add `.xai` here once its client is implemented.
    private static let supportedProviders: [AIProvider] = [.anthropic, .openai]

    /// Gate for paid/stub surfaces not ready for the free TestFlight beta.
    /// Flip to `true` when iCloud sync and billing are production-ready.
    private static let showPaidSurfaces = true

    public init(
        viewModel: SettingsViewModel,
        syncEngine: SyncEngine? = nil,
        backendURL: String = "",
        auditRepository: AuditRepository? = nil,
        approvalRepository: ApprovalRepository? = nil,
        bridgeActions: BridgeSessionActions = BridgeSessionActions(),
        statusHeaderAgents: [AgentInfo] = [],
        onTapStatusHeader: @escaping () -> Void = {}
    ) {
        _vm = State(initialValue: viewModel)
        self.syncEngine = syncEngine
        self.backendURL = backendURL
        self.auditRepository = auditRepository
        self.approvalRepository = approvalRepository
        self.bridgeActions = bridgeActions
        self.statusHeaderAgents = statusHeaderAgents
        self.onTapStatusHeader = onTapStatusHeader
    }

    public var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    headerSection
                    providerPickerSection
                    apiKeysSection
                    saveKeysSection
                    appearanceSection
                    securitySection
                    if autonomyPresetsEnabled {
                        agentApprovalsSection
                    }
                    notificationFilterSection
                    allowAlwaysRulesSection
                    integrationsSection
                    aboutConduitSection
                    privacyNote
                    versionFooter
                }
            }
        }
        .task {
            await vm.load()
            await loadNotificationFilter()
            await refreshAlwaysRules()
        }
        .onChange(of: notificationFilter) { _, _ in
            Task { await persistNotificationFilter() }
        }
    }

    // MARK: - Main sections

    @ViewBuilder
    private var headerSection: some View {
        DSScreenHeader("settings", breadcrumb: "device & agent")

        if !statusHeaderAgents.isEmpty {
            AgentStatusHeader(agents: statusHeaderAgents, onTap: onTapStatusHeader)
                .padding(.bottom, 8)
        }
    }

    private var providerPickerSection: some View {
        VStack(alignment: .leading, spacing: 0) {
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
        }
    }

    private var apiKeysSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHead("API Keys")
            settingsCard {
                providerRow(.anthropic, binding: $vm.anthropicKey, hasKey: vm.hasAnthropicKey)
                divider
                providerRow(.openai, binding: $vm.openaiKey, hasKey: vm.hasOpenAIKey)
            }
            .padding(.bottom, 4)
        }
    }

    @ViewBuilder
    private var saveKeysSection: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if let msg = vm.saveMessage {
                Text(msg)
                    .font(.dsSansPt(13))
                    .foregroundStyle(vm.saveIsError ? t.danger : t.accent)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .transition(.opacity)
            }
            HStack {
                Spacer()
                DSButton("Save keys", variant: .primary, action: { Task { await vm.save() } })
            }
        }
        .padding(.horizontal, 16)
        .animation(.easeInOut(duration: 0.2), value: vm.saveMessage)
        .padding(.bottom, 16)
    }

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHead("Appearance")
            settingsCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Theme")
                        .font(.dsSansPt(13, weight: .medium))
                        .foregroundStyle(t.text2)
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
        }
    }

    @ViewBuilder
    private var securitySection: some View {
        sectionHead("Security")
        settingsCard {
            Toggle(isOn: $appLockEnabled) {
                Text("Require Face ID on launch")
                    .font(.dsSansPt(15))
                    .foregroundStyle(t.text)
            }
            .tint(t.accent)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            divider

            Toggle(isOn: $redactSavedHistory) {
                Text("Redact secrets in saved history")
                    .font(.dsSansPt(15))
                    .foregroundStyle(t.text)
            }
            .tint(t.accent)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if let auditRepository {
                divider
                NavigationLink {
                    AuditView(viewModel: AuditViewModel(repository: auditRepository))
                } label: {
                    settingsNavRow("Security audit log", icon: "lock.shield")
                }
            }
        }
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private var integrationsSection: some View {
        sectionHead("Integrations")
        settingsCard {
            NavigationLink { TerminalSettingsView() } label: {
                settingsNavRow("Terminal settings", icon: "terminal")
            }
            divider
            NavigationLink { PremiumComparisonView() } label: {
                settingsNavRow("Compare Free vs Pro", icon: "star.circle")
            }
            if Self.showPaidSurfaces {
                divider
                NavigationLink { BillingView(backendURL: backendURL) } label: {
                    settingsNavRow("Billing & usage", icon: "creditcard")
                }
                if let org = PurchaseManager.shared.cloudEntitlement?.teamOrg {
                    divider
                    teamOrgRow(org)
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
    }

    private var aboutConduitSection: some View {
        VStack(alignment: .leading, spacing: 0) {
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
        }
    }

    private var privacyNote: some View {
        Text("Keys are stored on-device (Keychain, when-unlocked, device-only) and sent directly to the provider over TLS — never to Conduit servers.")
            .font(.dsSansPt(12))
            .foregroundStyle(t.text3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
    }

    private var versionFooter: some View {
        Group {
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
            let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
            Text("conduit \(version) (\(build))")
                .font(.dsMonoPt(10))
                .foregroundStyle(t.text4)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.bottom, 36)
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

    // MARK: - Agent approvals

    // Extracted from `body` so the main view's type-check stays within budget.
    @ViewBuilder
    private var agentApprovalsSection: some View {
        sectionHead("Agent approvals")
        settingsCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Approval policy")
                    .font(.dsSansPt(13, weight: .medium))
                    .foregroundStyle(t.text2)
                DSSegmentedPicker(
                    options: AutonomyPreset.allCases.map {
                        (label: $0.shortLabel, value: $0)
                    },
                    selection: autonomyPreset
                )
                Text(autonomyPreset.wrappedValue.description)
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text3)
                    .fixedSize(horizontal: false, vertical: true)
                    .animation(.easeInOut(duration: 0.15), value: autonomyPresetRaw)

                NavigationLink {
                    PolicyEditorBridgeScreen(actions: bridgeActions)
                } label: {
                    Text(bridgeActions.isConnected
                         ? "Edit bridge policy.yaml"
                         : "Edit bridge policy.yaml (connect SSH)")
                        .font(.dsSansPt(14, weight: .medium))
                        .foregroundStyle(bridgeActions.isConnected ? t.accent : t.text3)
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .padding(.bottom, 16)
        .onChange(of: autonomyPresetRaw) { _, _ in Haptics.selection() }
    }

    // MARK: - Notifications

    @ViewBuilder
    private var notificationFilterSection: some View {
        sectionHead("Notification filters")
        settingsCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Minimum risk")
                    .font(.dsSansPt(13, weight: .medium))
                    .foregroundStyle(t.text2)
                DSSegmentedPicker(
                    options: [
                        (label: "Low+", value: Approval.Risk.low),
                        (label: "Med+", value: Approval.Risk.medium),
                        (label: "High+", value: Approval.Risk.high),
                        (label: "Crit", value: Approval.Risk.critical),
                    ],
                    selection: Binding(
                        get: { notificationFilter.minRisk },
                        set: { notificationFilter.minRisk = $0 }
                    )
                )
                Text("These filters only affect lock-screen notifications. Approval cards still appear in Inbox.")
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text3)
                    .fixedSize(horizontal: false, vertical: true)

                DSDivider(.soft, leadingInset: 0)

                Text("Agent filter")
                    .font(.dsSansPt(13, weight: .medium))
                    .foregroundStyle(t.text2)
                ForEach(approvalAgents, id: \.rawValue) { agent in
                    Toggle(isOn: Binding(
                        get: { isAgentEnabled(agent) },
                        set: { setAgent(agent, enabled: $0) }
                    )) {
                        Text(agentLabel(agent))
                            .font(.dsSansPt(14))
                            .foregroundStyle(t.text)
                    }
                    .tint(t.accent)
                }

                DSDivider(.soft, leadingInset: 0)

                Toggle(isOn: Binding(
                    get: { notificationFilter.quietHoursEnabled },
                    set: { notificationFilter.quietHoursEnabled = $0 }
                )) {
                    Text("Quiet hours")
                        .font(.dsSansPt(14))
                        .foregroundStyle(t.text)
                }
                .tint(t.accent)

                if notificationFilter.quietHoursEnabled {
                    HStack(spacing: 8) {
                        Text("From")
                            .font(.dsMonoPt(11))
                            .foregroundStyle(t.text3)
                        Picker("Quiet start", selection: Binding(
                            get: { notificationFilter.quietHoursStart },
                            set: { notificationFilter.quietHoursStart = $0 }
                        )) {
                            ForEach(0..<24, id: \.self) { hour in
                                Text(Self.hourLabel(hour)).tag(hour)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        Text("to")
                            .font(.dsMonoPt(11))
                            .foregroundStyle(t.text3)
                        Picker("Quiet end", selection: Binding(
                            get: { notificationFilter.quietHoursEnd },
                            set: { notificationFilter.quietHoursEnd = $0 }
                        )) {
                            ForEach(0..<24, id: \.self) { hour in
                                Text(Self.hourLabel(hour)).tag(hour)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .padding(.bottom, 16)
    }

    // MARK: - Allow-always rules

    @ViewBuilder
    private var allowAlwaysRulesSection: some View {
        sectionHead("Allow-always rules")
        settingsCard {
            if alwaysRules.isEmpty {
                Text("No persisted allow-always rules yet.")
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text3)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            } else {
                ForEach(alwaysRules) { rule in
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(rule.title)
                                .font(.dsMonoPt(12, weight: .medium))
                                .foregroundStyle(t.text)
                            Text(rule.subtitle)
                                .font(.dsMonoPt(11))
                                .foregroundStyle(t.text3)
                            if rule.count > 1 {
                                Text("\(rule.count)x approvals")
                                    .font(.dsMonoPt(10.5))
                                    .foregroundStyle(t.text4)
                            }
                        }
                        Spacer()
                        Button("Revoke") {
                            revokeRule(rule)
                        }
                        .font(.dsSansPt(13, weight: .medium))
                        .foregroundStyle(t.danger)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    if rule.id != alwaysRules.last?.id {
                        divider
                    }
                }
            }
        }
        .padding(.bottom, 16)
    }

    // MARK: - Layout helpers

    /// Grouped section label — matches the shared `DSListSectionHead` used by
    /// Inbox / Fleet (mono 11/medium, 16pt gutter) so section labels align across tabs.
    private func sectionHead(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.dsMonoPt(11, weight: .medium))
            .tracking(11 * 0.10)
            .foregroundStyle(t.text3)
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 6)
    }

    /// Square bordered container — 1px t.border, bg t.surface, zero corner radius (BLOCKS square style).
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

    private func teamOrgRow(_ org: TeamOrgInfo) -> some View {
        HStack(spacing: 12) {
            DSIconView(.server, size: 16, color: t.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Team")
                    .font(.dsSansPt(14))
                    .foregroundStyle(t.text)
                Text(org.displayName)
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text3)
            }
            Spacer()
            DSChip("org", tone: .accent, variant: .soft, size: .sm)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(t.text4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    /// Canonical 1px row separator — DSDivider with 16pt leading inset to align with content.
    private var divider: some View {
        DSDivider(.soft, leadingInset: 16)
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

    // MARK: - Persistence helpers

    private static let revokedRulesKey = "settings.revokedAlwaysRuleSignatures"
    private static func loadRevokedRuleSignatures() -> Set<String> {
        let values = UserDefaults.standard.stringArray(forKey: revokedRulesKey) ?? []
        return Set(values)
    }

    private static func hourLabel(_ hour: Int) -> String {
        let normalized = hour % 24
        return String(format: "%02d:00", normalized)
    }

    private var approvalAgents: [Approval.AgentSource] {
        [.claudeCode, .codex, .cursor, .opencode, .devin, .unknown]
    }

    private func agentLabel(_ source: Approval.AgentSource) -> String {
        switch source {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .cursor: "Cursor"
        case .opencode: "OpenCode"
        case .devin: "Devin"
        case .unknown: "Unknown"
        }
    }

    private func isAgentEnabled(_ source: Approval.AgentSource) -> Bool {
        notificationFilter.enabledAgents?.contains(source.rawValue) ?? true
    }

    private func setAgent(_ source: Approval.AgentSource, enabled: Bool) {
        var set = notificationFilter.enabledAgents ?? Set(approvalAgents.map(\.rawValue))
        if enabled { set.insert(source.rawValue) } else { set.remove(source.rawValue) }
        notificationFilter.enabledAgents = set.count == approvalAgents.count ? nil : set
    }

    private func loadNotificationFilter() async {
        notificationFilter = await Notifications.shared.loadFilter()
    }

    private func persistNotificationFilter() async {
        await Notifications.shared.saveFilter(notificationFilter)
    }

    private func refreshAlwaysRules() async {
        guard let approvalRepository else {
            alwaysRules = []
            return
        }
        let approvals = (try? await approvalRepository.all()) ?? []
        let approvedAlways = approvals.filter { $0.decision == .approvedAlways }
        var grouped: [String: AlwaysRuleItem] = [:]
        for approval in approvedAlways {
            let signature = ruleSignature(for: approval)
            if revokedRuleSignatures.contains(signature) { continue }
            if var existing = grouped[signature] {
                existing.count += 1
                grouped[signature] = existing
                continue
            }
            grouped[signature] = AlwaysRuleItem(
                id: signature,
                title: approval.toolName ?? approval.command ?? approval.kind.rawValue,
                subtitle: approval.cwd,
                count: 1
            )
        }
        alwaysRules = grouped.values.sorted { $0.title < $1.title }
    }

    private func ruleSignature(for approval: Approval) -> String {
        [
            approval.kind.rawValue,
            approval.toolName ?? "",
            approval.command ?? "",
            approval.cwd,
            approval.toolInput ?? ""
        ].joined(separator: "|")
    }

    private func revokeRule(_ rule: AlwaysRuleItem) {
        revokedRuleSignatures.insert(rule.id)
        UserDefaults.standard.set(Array(revokedRuleSignatures), forKey: Self.revokedRulesKey)
        alwaysRules.removeAll { $0.id == rule.id }
    }
}

private struct AlwaysRuleItem: Identifiable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    var count: Int
}

#endif
