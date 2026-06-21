#if os(iOS)
import SwiftUI
import Observation
import AccountKit
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
    @AppStorage("appLockEnabled") private var appLockEnabled = false

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

                    sectionHead("APP LOCK")
                    card {
                        Toggle(isOn: $appLockEnabled) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Require Face ID on launch")
                                    .font(.dsSansPt(15, weight: .semibold))
                                    .foregroundStyle(t.text)
                                Text("Lock Conduit when it leaves the foreground. Your device passcode remains the system fallback.")
                                    .font(.dsSansPt(12))
                                    .foregroundStyle(t.text3)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .tint(t.accent)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                        .accessibilityLabel("Require Face ID on launch")
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
    public var onAccountSignedOut: (() -> Void)? = nil
    private let accountSession: AccountSessionController?
    public var onBack: (() -> Void)? = nil
    @AppStorage(ConduitAppearance.storageKey) private var colorSchemePref: String = ConduitAppearance.light.rawValue
    @State private var showResetConfirmation = false
    @State private var purchases = PurchaseManager.shared
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
        accountSession: AccountSessionController? = nil,
        onAccountSignedOut: (() -> Void)? = nil,
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
        self.accountSession = accountSession
        self.onAccountSignedOut = onAccountSignedOut
        self.onBack = onBack
    }

    public var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    headerSection
                    profileCard
                    policyGovernanceSection
                    generalSection
                    terminalSection
                    connectionSection
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
        .task { await purchases.load() }
    }

    // MARK: - (0) Header

    @ViewBuilder
    private var headerSection: some View {
        DSDetailHeader("Settings", breadcrumb: "make it yours", onBack: onBack)

        if !statusHeaderAgents.isEmpty {
            AgentStatusHeader(agents: statusHeaderAgents, onTap: onTapStatusHeader)
                .padding(.bottom, 8)
        }
    }

    // MARK: - Profile card

    private var profileCard: some View {
        VStack(spacing: 8) {
            NavigationLink {
                BillingView(backendURL: backendURL)
            } label: {
                HStack(spacing: 14) {
                SettingsBrandMark()
                VStack(alignment: .leading, spacing: 2) {
                    Text(accountSession?.email ?? (accountSession?.isOfflineSelfHosted == true ? "Self-hosted offline" : "Conduit"))
                        .font(.dsDisplayPt(17, weight: .bold))
                        .foregroundStyle(t.text)
                    Text(accountSession?.isOfflineSelfHosted == true ? "Local pairing only · no hosted billing" : (purchases.isPro ? "Conduit Pro · manage" : "Free plan · upgrade"))
                        .font(.dsMonoPt(12))
                        // This is actionable account state, not disabled text.  Keep it
                        // legible in Dark mode as well as on the lighter surfaces.
                        .foregroundStyle(t.text3)
                }
                Spacer(minLength: 0)
                Text(purchases.isPro ? "PRO" : "FREE")
                    .font(.dsMonoPt(10, weight: .bold))
                    .foregroundStyle(purchases.isPro ? t.accent : t.text3)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(t.surface2, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(t.text4)
                }
                .padding(16)
                .background(t.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(t.border, lineWidth: 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if accountSession?.isStandardAccount == true {
                Button("sign out") {
                    Task {
                        await accountSession?.signOut()
                        Haptics.success()
                        onAccountSignedOut?()
                    }
                }
                .font(.dsMonoPt(11, weight: .medium))
                .foregroundStyle(t.text3)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityIdentifier("accountSignOut")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    // MARK: - Policy & Governance (folded in from the former Governance root — accent, not green)

    @ViewBuilder
    private var policyGovernanceSection: some View {
        sectionHead("POLICY & GOVERNANCE")
        VStack(spacing: 11) {
            NavigationLink {
                AutonomyLevelView()
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("POLICY BRIDGE")
                            .font(.dsMonoPt(9.5, weight: .medium))
                            .tracking(1.0)
                            .foregroundStyle(t.accentFg.opacity(0.82))
                        Spacer(minLength: 0)
                        DSStatusDot(tone: .ok, pulse: true, size: 9)
                    }
                    Text("All clear")
                        .font(.dsDisplayPt(22, weight: .bold))
                        .foregroundStyle(t.accentFg)
                    Text("Rules enforcing across your connected agents.")
                        .font(.dsSansPt(12))
                        .foregroundStyle(t.accentFg.opacity(0.92))
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    LinearGradient(colors: [t.accent, t.accentInk], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: 8)
            }
            .buttonStyle(.plain)

            // Match the GENERAL section's 2-up cards so these primary governance
            // controls read at the same weight, not as cramped list rows.
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 11), GridItem(.flexible(), spacing: 11)], spacing: 11) {
                NavigationLink { AutonomyLevelView() } label: {
                    settingsGridCard("Default autonomy", icon: "slider.horizontal.3", tint: t.accent, detail: autonomyLabel)
                }.buttonStyle(.plain)
                if auditRepository != nil {
                    NavigationLink {
                        AuditView(viewModel: AuditViewModel(repository: auditRepository!), daemonChannel: daemonChannel)
                    } label: {
                        settingsGridCard("Enforcement log", icon: "list.bullet.clipboard", tint: t.text2, detail: "approval & run history")
                    }.buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    private var autonomyLabel: String {
        let raw = UserDefaults.standard.string(forKey: "inbox.autonomyPreset") ?? AutonomyPreset.alwaysAsk.rawValue
        return (AutonomyPreset(rawValue: raw) ?? .alwaysAsk).shortLabel
    }

    // MARK: - GENERAL (board 2×2 grid)

    @ViewBuilder
    private var generalSection: some View {
        sectionHead("GENERAL")
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 11), GridItem(.flexible(), spacing: 11)], spacing: 11) {
            NavigationLink { AppearanceSettingsView() } label: {
                settingsGridCard("Appearance", icon: "circle.lefthalf.filled", tint: t.accent, detail: "Theme & mode")
            }.buttonStyle(.plain)
            NavigationLink { ProviderKeysView(viewModel: vm) } label: {
                settingsGridCard("Provider keys", icon: "key.horizontal", tint: t.ok, detail: providerKeyDetail)
            }.buttonStyle(.plain)
            NavigationLink { NotificationsSettingsView() } label: {
                settingsGridCard("Notifications", icon: "bell", tint: t.text2, detail: "Push severity")
            }.buttonStyle(.plain)
            NavigationLink { TrustPrivacyView() } label: {
                settingsGridCard("Security", icon: "lock", tint: t.warn, detail: "Face ID · TOFU")
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    private var providerKeyDetail: String {
        let n = (vm.hasAnthropicKey ? 1 : 0) + (vm.hasOpenAIKey ? 1 : 0)
        return n == 0 ? "Not set" : "\(n) connected"
    }

    private func settingsGridCard(_ title: String, icon: String, tint: Color, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(t.surface2, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .padding(.bottom, 11)
            Text(title)
                .font(.dsSansPt(13.5, weight: .semibold))
                .foregroundStyle(t.text)
            Text(detail)
                .font(.dsSansPt(11))
                .foregroundStyle(t.text3)
                .padding(.top, 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(t.surface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(t.border, lineWidth: 1))
        .contentShape(Rectangle())
    }

    // MARK: - TERMINAL & KEYS

    @ViewBuilder
    private var terminalSection: some View {
        sectionHead("TERMINAL & KEYS")
        settingsCard {
            NavigationLink { TerminalSettingsView() } label: {
                settingsNavRow("Terminal", icon: "terminal", detail: "font, scrollback, gestures")
            }
            if let sshKeyStore {
                divider
                NavigationLink { SSHKeysView(keyStore: sshKeyStore) } label: {
                    settingsNavRow("SSH keys", icon: "key.horizontal.fill", detail: "generate, import, manage")
                }
            }
        }
        .padding(.bottom, 16)
    }

    // MARK: - CONNECTION

    @ViewBuilder
    private var connectionSection: some View {
        sectionHead("CONNECTION")
        settingsCard {
            NavigationLink { E2ERelayPairingView(client: e2eRelayClient) } label: {
                settingsNavRow("Relay pairing", icon: "lock.rotation", detail: "E2E encrypted relay")
            }
            if accountSession?.isStandardAccount == true {
                divider
                NavigationLink { DeviceManagementView(backendURL: backendURL, accountSession: accountSession) } label: {
                    settingsNavRow("Devices", icon: "externaldrive.badge.person.crop", detail: "bound daemons")
                }
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
        if daemonChannel != nil || syncEngine != nil {
            sectionHead("DATA")
            VStack(spacing: 11) {
                if let syncEngine {
                    SyncStatusView(engine: syncEngine)
                        .padding(.horizontal, 16)
                }
                if let daemonChannel {
                    settingsCard {
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
            }
            .padding(.bottom, 16)
        }
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

    // MARK: - Layout helpers

    private func sectionHead(_ title: String) -> some View {
        Text(title)
            .font(.dsMonoPt(10, weight: .medium))
            .tracking(1.1)
            .foregroundStyle(t.text3)
            .textCase(.uppercase)
            .padding(.horizontal, 16)
            .padding(.top, 22)
            .padding(.bottom, 6)
    }

    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(t.surface)
        .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: t.r3, style: .continuous)
                .strokeBorder(t.border, lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }

    private func settingsNavRow(_ label: String, icon: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(t.text2)
                .frame(width: 28, height: 28)
                .background(t.surface2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.dsSansPt(16))
                    .foregroundStyle(t.text)
                Text(detail)
                    .font(.dsSansPt(12.5))
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

    private var divider: some View {
        DSDivider(.soft, leadingInset: 56)
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

// MARK: - Lavender pixel brand-mark (matches onboarding / sidebar)

private struct SettingsBrandMark: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(
                AngularGradient(
                    colors: [
                        Color(.sRGB, red: 0.545, green: 0.435, blue: 0.690, opacity: 1),
                        Color(.sRGB, red: 0.690, green: 0.561, blue: 0.808, opacity: 1),
                        Color(.sRGB, red: 0.435, green: 0.353, blue: 0.588, opacity: 1),
                        Color(.sRGB, red: 0.616, green: 0.498, blue: 0.753, opacity: 1),
                        Color(.sRGB, red: 0.545, green: 0.435, blue: 0.690, opacity: 1)
                    ],
                    center: .center, angle: .degrees(45)
                )
            )
            .overlay(
                Canvas { ctx, size in
                    var x: CGFloat = 0
                    while x <= size.width { ctx.fill(Path(CGRect(x: x, y: 0, width: 1, height: size.height)), with: .color(.black.opacity(0.12))); x += 10 }
                    var y: CGFloat = 0
                    while y <= size.height { ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(.black.opacity(0.12))); y += 10 }
                }
            )
            .frame(width: 50, height: 50)
            .accessibilityHidden(true)
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
    @AppStorage(ConduitAppearance.storageKey) private var colorSchemePref: String = ConduitAppearance.light.rawValue
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
                                .background(
                                    colorSchemePref == key ? t.accentSoft : t.surface,
                                    in: RoundedRectangle(cornerRadius: t.r3, style: .continuous)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: t.r3, style: .continuous)
                                        .strokeBorder(colorSchemePref == key ? t.accent : t.border, lineWidth: 1)
                                )
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
