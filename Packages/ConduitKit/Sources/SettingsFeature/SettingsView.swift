#if os(iOS)
import SwiftUI
import Observation
import ConduitCore
import AgentKit
import DesignSystem
import PersistenceKit
import SecurityKit
import SyncKit
import SSHTransport

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

// MARK: - TrustPrivacyView

struct TrustPrivacyView: View {
    @Environment(\.conduitTokens) private var t
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    DSDetailHeader("trust & privacy", onBack: { dismiss() })

                    sectionHead("STAYS ON YOUR HOST")
                    card {
                        privacyRow(
                            icon: "terminal",
                            title: "SSH session data",
                            detail: "All command output, file contents, and shell history remain on your server. Conduit is a relay — no session data is stored on Conduit servers.",
                            isGreen: true
                        )
                        hairline
                        privacyRow(
                            icon: "key",
                            title: "SSH private keys",
                            detail: "Private keys never leave the device Keychain. Conduit uses them to authenticate but does not transmit them.",
                            isGreen: true
                        )
                        hairline
                        privacyRow(
                            icon: "lock",
                            title: "AI API keys",
                            detail: "Stored in the iOS Keychain (when-unlocked, device-only). Sent directly from your device to the AI provider — never to Conduit servers.",
                            isGreen: true
                        )
                        hairline
                        privacyRow(
                            icon: "externaldrive",
                            title: "Approval history",
                            detail: "On-device only. The approval log, allow-always rules, and inbox history are stored locally via SwiftData.",
                            isGreen: true
                        )
                    }

                    sectionHead("CROSSES THE WIRE")
                    card {
                        privacyRow(
                            icon: "network",
                            title: "Push notification relay",
                            detail: "Approval push payloads are routed through Conduit's relay backend to reach your device via APNs. Payload content is encrypted in transit.",
                            isGreen: false
                        )
                        hairline
                        privacyRow(
                            icon: "creditcard",
                            title: "Billing & entitlement",
                            detail: "Conduit Pro purchases and entitlement checks pass through RevenueCat and the Conduit backend. No session data is included.",
                            isGreen: false
                        )
                        hairline
                        privacyRow(
                            icon: "arrow.triangle.2.circlepath",
                            title: "iCloud sync (Pro)",
                            detail: "Host configurations and settings are synced via iCloud CloudKit when Conduit Pro sync is enabled. You can disable this in Settings.",
                            isGreen: false
                        )
                    }

                    Text("Conduit does not sell data or run ads. Questions: privacy@conduit.dev")
                        .font(.dsSansPt(12))
                        .foregroundStyle(t.text3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 18)
                        .padding(.top, 20)

                    sectionHead("CONNECTIVITY")
                    card {
                        connRow(active: true, title: "Conduit relay", detail: "End-to-end encrypted (default). The relay forwards ciphertext it can't read.")
                        hairline
                        connRow(active: false, title: "Self-hosted relay", detail: "Run the relay container yourself for full control.")
                        hairline
                        connRow(active: false, title: "Direct / same network", detail: "Skip the relay entirely when on the same LAN.")
                    }

                    sectionHead("HOW IT COMPARES")
                    comparisonTable

                    Text("Vendor- and model-agnostic, with a thin E2E relay — a stance no single-vendor app can match.")
                        .font(.dsSansPt(12))
                        .foregroundStyle(t.text3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 18)
                        .padding(.top, 16)
                        .padding(.bottom, 36)
                }
            }
        }
        .navigationBarHidden(true)
    }

    private func sectionHead(_ title: String) -> some View {
        Text(title)
            .font(.dsMonoPt(11, weight: .medium))
            .tracking(11 * 0.10)
            .foregroundStyle(t.text3)
            .padding(.horizontal, 18)
            .padding(.top, 22)
            .padding(.bottom, 6)
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(t.surface)
            .clipShape(RoundedRectangle(cornerRadius: t.r4, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: t.r4, style: .continuous)
                    .strokeBorder(t.border, lineWidth: 1)
            )
            .padding(.horizontal, 18)
    }

    private var hairline: some View {
        DSDivider(.soft, leadingInset: 16)
    }

    private func privacyRow(icon: String, title: String, detail: String, isGreen: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(isGreen ? t.risk(0) : t.text2)
                .frame(width: 20, alignment: .center)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.dsSansPt(14, weight: .semibold))
                    .foregroundStyle(isGreen ? t.risk(0) : t.text)
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

    private func connRow(active: Bool, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Circle()
                .strokeBorder(active ? t.accent : t.text4, lineWidth: 2)
                .frame(width: 18, height: 18)
                .overlay(
                    Circle()
                        .fill(active ? t.accent : Color.clear)
                        .frame(width: 8, height: 8)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.dsSansPt(14, weight: .semibold))
                    .foregroundStyle(t.text)
                Text(detail)
                    .font(.dsSansPt(12.5))
                    .foregroundStyle(t.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var comparisonTable: some View {
        let vendors: [(name: String, code: String, model: String, relay: String, good: Bool)] = [
            ("Omnara", "yes", "yes", "yes", false),
            ("Anthropic", "yes", "yes", "yes", false),
            ("Conduit", "no", "no", "no", true),
        ]
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Text("")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("code\nleaves?")
                    .frame(width: 55, alignment: .center)
                Text("model\ncloud?")
                    .frame(width: 55, alignment: .center)
                Text("relay\nreads?")
                    .frame(width: 55, alignment: .center)
            }
            .font(.dsMonoPt(9))
            .foregroundStyle(t.text4)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            ForEach(Array(vendors.enumerated()), id: \.offset) { _, v in
                VStack(spacing: 0) {
                    DSDivider(.soft, leadingInset: 16)
                    HStack(spacing: 4) {
                        Text(v.name)
                            .font(.dsSansPt(13, weight: v.good ? .bold : .medium))
                            .foregroundStyle(v.good ? t.risk(0) : t.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(v.code)
                            .frame(width: 55, alignment: .center)
                        Text(v.model)
                            .frame(width: 55, alignment: .center)
                        Text(v.relay)
                            .frame(width: 55, alignment: .center)
                    }
                    .font(.dsMonoPt(11))
                    .foregroundStyle(v.good ? t.risk(0) : t.text3)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
            }
        }
        .background(t.surface)
        .clipShape(RoundedRectangle(cornerRadius: t.r4, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: t.r4, style: .continuous)
                .strokeBorder(t.border, lineWidth: 1)
        )
        .padding(.horizontal, 18)
    }
}

// MARK: - SettingsView

public struct SettingsView: View {
    @State private var vm: SettingsViewModel
    let syncEngine: SyncEngine?
    let backendURL: String
    let auditRepository: AuditRepository?
    let approvalRepository: ApprovalRepository?
    let sshKeyStore: KeyStore?
    let bridgeActions: BridgeSessionActions
    let daemonChannel: DaemonChannel?
    let e2eRelayClient: E2ERelayClient?
    public var statusHeaderAgents: [AgentInfo] = []
    public var onTapStatusHeader: () -> Void = {}
    public var onResetApp: (() -> Void)? = nil
    public var onShowLimits: (() -> Void)? = nil
    public var onEmergencyStop: (() -> Void)? = nil
    public var onBack: (() -> Void)? = nil
    @AppStorage("conduitColorScheme") private var colorSchemePref: String = "system"
    @AppStorage("appLockEnabled") private var appLockEnabled = false
    @State private var showResetConfirmation = false
    @State private var confirmingStop = false
    @Environment(\.conduitTokens) private var t

    private static let supportedProviders: [AIProvider] = [.anthropic, .openai]

    public init(
        viewModel: SettingsViewModel,
        syncEngine: SyncEngine? = nil,
        backendURL: String = "",
        auditRepository: AuditRepository? = nil,
        approvalRepository: ApprovalRepository? = nil,
        sshKeyStore: KeyStore? = nil,
        bridgeActions: BridgeSessionActions = BridgeSessionActions(),
        daemonChannel: DaemonChannel? = nil,
        e2eRelayClient: E2ERelayClient? = nil,
        statusHeaderAgents: [AgentInfo] = [],
        onTapStatusHeader: @escaping () -> Void = {},
        onResetApp: (() -> Void)? = nil,
        onShowLimits: (() -> Void)? = nil,
        onBack: (() -> Void)? = nil
    ) {
        _vm = State(initialValue: viewModel)
        self.syncEngine = syncEngine
        self.backendURL = backendURL
        self.auditRepository = auditRepository
        self.approvalRepository = approvalRepository
        self.sshKeyStore = sshKeyStore
        self.bridgeActions = bridgeActions
        self.daemonChannel = daemonChannel
        self.e2eRelayClient = e2eRelayClient
        self.statusHeaderAgents = statusHeaderAgents
        self.onTapStatusHeader = onTapStatusHeader
        self.onResetApp = onResetApp
        self.onShowLimits = onShowLimits
        self.onBack = onBack
    }

    public var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    headerSection
                    generalSection
                    policyHostsSection
                    dataSection
                    resetSection
                    versionFooter
                }
            }
            .alert("Reset app", isPresented: $showResetConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) { onResetApp?() }
            } message: {
                Text("This deletes all hosts, sessions and approvals and returns to onboarding. This cannot be undone.")
            }
        }
        .task { await vm.load() }
    }

    // MARK: - (0) Header

    @ViewBuilder
    private var headerSection: some View {
        if let onBack {
            HStack {
                Button(action: onBack) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Back")
                            .font(.dsMono(.callout, weight: .medium))
                    }
                    .foregroundStyle(t.text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(t.surface2)
                    .overlay(Rectangle().strokeBorder(t.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
        }
        DSScreenHeader("settings", breadcrumb: "device & agent")

        if !statusHeaderAgents.isEmpty {
            AgentStatusHeader(agents: statusHeaderAgents, onTap: onTapStatusHeader)
                .padding(.bottom, 8)
        }
    }

    // MARK: - (1) GENERAL

    @ViewBuilder
    private var generalSection: some View {
        sectionHead("GENERAL")
        settingsCard {
            NavigationLink { NotificationsSettingsView() } label: {
                settingsNavRow("Notifications", icon: "bell", detail: "push severity & quiet hours")
            }
            divider
            NavigationLink { AppearanceSettingsView() } label: {
                settingsNavRow("Appearance", icon: "paintbrush", detail: colorSchemeLabel)
            }
            divider
            NavigationLink { TrustPrivacyView() } label: {
                settingsNavRow("Security & privacy", icon: "checkmark.shield", detail: "data handling · host-key TOFU")
            }
            divider
            NavigationLink { ProviderKeysView(viewModel: vm) } label: {
                settingsNavRow("Provider keys", icon: "key.horizontal", detail: "Anthropic · OpenAI — sent direct to provider")
            }
        }
        .padding(.bottom, 16)
    }

    private var colorSchemeLabel: String {
        switch colorSchemePref {
        case "light": return "light"
        case "dark":  return "dark"
        default:      return "system"
        }
    }

    // MARK: - (2) POLICY & HOSTS

    @ViewBuilder
    private var policyHostsSection: some View {
        sectionHead("POLICY & HOSTS")
        settingsCard {
            NavigationLink { E2ERelayPairingView(client: e2eRelayClient) } label: {
                settingsNavRow("Relay pairing", icon: "lock.rotation", detail: "E2E encrypted relay")
            }
            divider
            NavigationLink { DoctorView(viewModel: DoctorViewModel(actions: bridgeActions)) } label: {
                settingsNavRow("Health check", icon: "stethoscope", detail: "diagnose daemon setup")
            }
        }
        .padding(.bottom, 16)
    }

    // MARK: - (3) DATA

    @ViewBuilder
    private var dataSection: some View {
        sectionHead("DATA")
        settingsCard {
            if let auditRepository {
                NavigationLink {
                    AuditView(viewModel: AuditViewModel(repository: auditRepository), daemonChannel: daemonChannel)
                } label: {
                    settingsNavRow("Audit & proof", icon: "list.bullet.clipboard", detail: "approval & run history")
                }
                divider
            }
            if let daemonChannel {
                NavigationLink {
                    SecretsView(viewModel: {
                        let svm = SecretsViewModel()
                        svm.attach(channel: daemonChannel)
                        return svm
                    }())
                } label: {
                    settingsNavRow("Secrets", icon: "key.fill", detail: "brokered credentials")
                }
            }
        }
        .padding(.bottom, 16)
    }

    // MARK: - (4) RESET

    @ViewBuilder
    private var resetSection: some View {
        if onResetApp != nil {
            sectionHead("DANGER ZONE")
            settingsCard {
                Button(role: .destructive) {
                    showResetConfirmation = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 14))
                            .frame(width: 20)
                        Text("Reset app")
                            .font(.dsSansPt(15))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(t.text4)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .foregroundStyle(t.danger)
            }
            .padding(.bottom, 16)
        }
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
        Text(title)
            .font(.dsMonoPt(11, weight: .medium))
            .tracking(11 * 0.10)
            .foregroundStyle(t.text3)
            .padding(.horizontal, 16)
            .padding(.top, 22)
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
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(t.text4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private func settingsNavRow(_ label: String, icon: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(t.text2)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.dsSansPt(15))
                    .foregroundStyle(t.text)
                Text(detail)
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text3)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(t.text4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private func settingsInfoRow(_ label: String, icon: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(t.text2)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.dsSansPt(15))
                    .foregroundStyle(t.text)
                Text(detail)
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text3)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var divider: some View {
        DSDivider(.soft, leadingInset: 16)
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

}

// MARK: - Autonomy Level Detail

private struct AutonomyLevelView: View {
    @AppStorage("inbox.autonomyPreset") private var autonomyPresetRaw: String = AutonomyPreset.alwaysAsk.rawValue
    @Environment(\.conduitTokens) private var t
    @Environment(\.dismiss) private var dismiss

    private var autonomy: AutonomyPreset {
        AutonomyPreset(rawValue: autonomyPresetRaw) ?? .alwaysAsk
    }

    var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    DSDetailHeader("autonomy level", onBack: { dismiss() })

                    VStack(spacing: 8) {
                        ForEach(AutonomyPreset.allCases, id: \.self) { preset in
                            Button {
                                Haptics.selection()
                                withAnimation(.easeInOut(duration: 0.14)) { autonomyPresetRaw = preset.rawValue }
                            } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    DSStatusDot(tone: autonomy == preset ? .accent : .off, size: 9)
                                        .padding(.top, 5)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(preset.label)
                                            .font(.dsSansPt(15, weight: .semibold))
                                            .foregroundStyle(t.text)
                                        Text(preset.description)
                                            .font(.dsSansPt(13))
                                            .foregroundStyle(t.text3)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(autonomy == preset ? t.accentSoft : t.surface)
                                .overlay(Rectangle().strokeBorder(autonomy == preset ? t.accent : t.border, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("autonomy_\(preset.rawValue)")
                            .accessibilityValue(autonomy == preset ? "selected" : "unselected")
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                }
            }
        }
        .navigationBarHidden(true)
    }
}

// MARK: - Notifications Settings

private struct NotificationsSettingsView: View {
    @AppStorage("notif.push.high")   private var pushHigh   = true
    @AppStorage("notif.push.medium") private var pushMedium = false
    @AppStorage("notif.push.low")    private var pushLow    = false
    @AppStorage("notif.quietHours")  private var quietHoursOn = false
    @AppStorage("notif.quietStart")  private var quietStart  = "23:00"
    @AppStorage("notif.quietEnd")    private var quietEnd    = "08:00"
    @Environment(\.conduitTokens) private var t
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    DSDetailHeader("notifications", onBack: { dismiss() })

                    sectionHead("PUSH WHEN AN ACTION IS")
                    card {
                        severityRow(
                            label: "Critical",
                            detail: "secrets · network · destructive",
                            isAlways: true,
                            binding: .constant(true)
                        )
                        hairline
                        severityRow(label: "High", detail: "deletes, broad writes", isAlways: false, binding: $pushHigh)
                        hairline
                        severityRow(label: "Medium", detail: "ordinary writes & patches", isAlways: false, binding: $pushMedium)
                        hairline
                        severityRow(label: "Low", detail: "read-only — rarely escalated", isAlways: false, binding: $pushLow)
                    }

                    Text("Everything else resolves under policy, silently.")
                        .font(.dsSansPt(12))
                        .foregroundStyle(t.text3)
                        .padding(.horizontal, 18)
                        .padding(.top, 10)

                    sectionHead("QUIET HOURS")
                    card {
                        Toggle(isOn: $quietHoursOn) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Mute high & below")
                                    .font(.dsSansPt(15))
                                    .foregroundStyle(t.text)
                                Text("\(quietStart) – \(quietEnd)")
                                    .font(.dsMonoPt(11))
                                    .foregroundStyle(t.text3)
                            }
                        }
                        .tint(t.accent)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }

                    Text("Critical notifications always break through quiet hours.")
                        .font(.dsSansPt(12))
                        .foregroundStyle(t.text3)
                        .padding(.horizontal, 18)
                        .padding(.top, 10)
                        .padding(.bottom, 36)
                }
            }
        }
        .navigationBarHidden(true)
    }

    private func sectionHead(_ title: String) -> some View {
        Text(title)
            .font(.dsMonoPt(11, weight: .medium))
            .tracking(11 * 0.10)
            .foregroundStyle(t.text3)
            .padding(.horizontal, 18)
            .padding(.top, 22)
            .padding(.bottom, 6)
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(t.surface)
            .clipShape(RoundedRectangle(cornerRadius: t.r4, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: t.r4, style: .continuous).strokeBorder(t.border, lineWidth: 1))
            .padding(.horizontal, 18)
    }

    private var hairline: some View { DSDivider(.soft, leadingInset: 16) }

    private func severityRow(label: String, detail: String, isAlways: Bool, binding: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.dsSansPt(15, weight: .semibold))
                    .foregroundStyle(t.text)
                Text(detail)
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text3)
            }
            Spacer()
            if isAlways {
                Text("always")
                    .font(.dsMonoPt(11, weight: .medium))
                    .foregroundStyle(t.text3)
            } else {
                Toggle("", isOn: binding)
                    .labelsHidden()
                    .tint(t.accent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Appearance Settings

private struct AppearanceSettingsView: View {
    @AppStorage("conduitColorScheme") private var colorSchemePref: String = "system"
    @Environment(\.conduitTokens) private var t
    @Environment(\.dismiss) private var dismiss

    private let options: [(String, String, String)] = [
        ("system", "System",  "Follows your iOS appearance setting"),
        ("light",  "Light",   "Always use the light theme"),
        ("dark",   "Dark",    "Always use the dark theme"),
    ]

    var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    DSDetailHeader("appearance", onBack: { dismiss() })

                    VStack(spacing: 8) {
                        ForEach(options, id: \.0) { key, label, desc in
                            Button {
                                Haptics.selection()
                                withAnimation(.easeInOut(duration: 0.14)) {
                                    colorSchemePref = key
                                }
                            } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    DSStatusDot(tone: colorSchemePref == key ? .accent : .off, size: 9)
                                        .padding(.top, 5)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(label)
                                            .font(.dsSansPt(15, weight: .semibold))
                                            .foregroundStyle(t.text)
                                        Text(desc)
                                            .font(.dsSansPt(13))
                                            .foregroundStyle(t.text3)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(colorSchemePref == key ? t.accentSoft : t.surface)
                                .overlay(Rectangle().strokeBorder(colorSchemePref == key ? t.accent : t.border, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                }
            }
        }
        .navigationBarHidden(true)
    }
}

#endif
