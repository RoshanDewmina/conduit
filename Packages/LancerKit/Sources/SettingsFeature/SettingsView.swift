#if os(iOS)
import SwiftUI
import UIKit
import Observation
import AccountKit
import LancerCore
import AgentKit
import DesignSystem
import PersistenceKit
import SecurityKit
import SyncKit
import SSHTransport
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

// MARK: - TrustPrivacyView

public struct TrustPrivacyView: View {
    @Environment(\.lancerTokens) private var t
    @Environment(\.dismiss) private var dismiss

    // Live trust controls consolidated into this surface (the "trust center"):
    // what's paired and how to revoke it, alongside the data-residency cards.
    private let accountSession: AccountSessionController?
    private let backendURL: String
    private let relayMachines: [RelayMachineRow]
    private let onRelayPaired: (E2ERelayClient, RelayMachineRecord) -> Void
    private let onRelayUnpair: (RelayMachineID) -> Void

    public init(
        accountSession: AccountSessionController? = nil,
        backendURL: String = "",
        relayMachines: [RelayMachineRow] = [],
        onRelayPaired: @escaping (E2ERelayClient, RelayMachineRecord) -> Void = { _, _ in },
        onRelayUnpair: @escaping (RelayMachineID) -> Void = { _ in }
    ) {
        self.accountSession = accountSession
        self.backendURL = backendURL
        self.relayMachines = relayMachines
        self.onRelayPaired = onRelayPaired
        self.onRelayUnpair = onRelayUnpair
    }

    public var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    DSDetailHeader("trust & privacy", onBack: { dismiss() })

                    pairingSection

                    sectionHead("STAYS ON YOUR HOST")
                    card {
                        privacyRow(
                            icon: "terminal",
                            title: "SSH session data",
                            detail: "All command output, file contents, and shell history remain on your server. Lancer is a relay — no session data is stored on Lancer servers.",
                            isGreen: true
                        )
                        hairline
                        privacyRow(
                            icon: "key",
                            title: "SSH private keys",
                            detail: "Private keys never leave the device Keychain. Lancer uses them to authenticate but does not transmit them.",
                            isGreen: true
                        )
                        hairline
                        privacyRow(
                            icon: "lock",
                            title: "AI API keys",
                            detail: "Stored in the iOS Keychain (when-unlocked, device-only). Sent directly from your device to the AI provider — never to Lancer servers.",
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
                            detail: "Approval push payloads are routed through Lancer's relay backend to reach your device via APNs. Payload content is encrypted in transit.",
                            isGreen: false
                        )
                        hairline
                        privacyRow(
                            icon: "creditcard",
                            title: "Billing & entitlement",
                            detail: "Lancer Pro purchases and entitlement checks pass through RevenueCat and the Lancer backend. No session data is included.",
                            isGreen: false
                        )
                        hairline
                        privacyRow(
                            icon: "arrow.triangle.2.circlepath",
                            title: "iCloud sync (Pro)",
                            detail: "Host configurations and settings are synced via iCloud CloudKit when Lancer Pro sync is enabled. You can disable this in Settings.",
                            isGreen: false
                        )
                    }

                    Text("Lancer does not sell data or run ads. Questions: privacy@lancersoftware.dev")
                        .font(.dsSansPt(12))
                        .foregroundStyle(t.text3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 18)
                        .padding(.top, 20)

                    sectionHead("CONNECTIVITY")
                    card {
                        connRow(active: true, title: "Lancer relay", detail: "End-to-end encrypted (default). The relay forwards ciphertext it can't read.")
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

    // The actionable trust controls — what's paired and how to revoke — live
    // here so the trust surface answers "who can act on this" in one place,
    // not just "what data goes where". Reuses the existing pairing/device views.
    @ViewBuilder
    private var pairingSection: some View {
        sectionHead("PAIRINGS & REVOCATION")
        card {
            NavigationLink {
                RelayMachinesListView(machines: relayMachines, onPaired: onRelayPaired, onUnpair: onRelayUnpair)
            } label: {
                trustNavRow(icon: "lock.rotation", title: "Relay pairing",
                            detail: "End-to-end encrypted relay between this phone and your daemon.")
            }
            if accountSession?.isStandardAccount == true {
                hairline
                NavigationLink {
                    DeviceManagementView(backendURL: backendURL, accountSession: accountSession)
                } label: {
                    trustNavRow(icon: "externaldrive.badge.person.crop", title: "Paired devices",
                                detail: "See every daemon bound to your account and revoke any of them.")
                }
            }
        }
    }

    private func trustNavRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.dsSansPt(14))
                .foregroundStyle(t.text2)
                .frame(width: 20, alignment: .center)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.dsSansPt(14, weight: .semibold))
                    .foregroundStyle(t.text)
                Text(detail)
                    .font(.dsSansPt(13))
                    .foregroundStyle(t.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.dsSansPt(12, weight: .semibold))
                .foregroundStyle(t.text4)
                .padding(.top, 2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(detail)")
    }

    private func privacyRow(icon: String, title: String, detail: String, isGreen: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.dsSansPt(14))
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(detail)")
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
                .accessibilityLabel(active ? "Active" : "Inactive")
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(active ? "active" : "inactive"), \(detail)")
    }

    private var comparisonTable: some View {
        let vendors: [(name: String, code: String, model: String, relay: String, good: Bool)] = [
            ("Omnara", "yes", "yes", "yes", false),
            ("Anthropic", "yes", "yes", "yes", false),
            ("Lancer", "no", "no", "no", true),
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
    let conversationSyncEngine: ConversationSyncEngine?
    let backendURL: String
    let auditRepository: AuditRepository?
    let approvalRepository: ApprovalRepository?
    let sshKeyStore: KeyStore?
    let bridgeActions: BridgeSessionActions
    let daemonChannel: DaemonChannel?
    let relayMachines: [RelayMachineRow]
    let onRelayPaired: (E2ERelayClient, RelayMachineRecord) -> Void
    let onRelayUnpair: (RelayMachineID) -> Void
    let onRelayRename: (RelayMachineID, String) -> Void
    public var statusHeaderAgents: [AgentInfo] = []
    public var onTapStatusHeader: () -> Void = {}
    public var onResetApp: (() -> Void)? = nil
    public var onShowLimits: (() -> Void)? = nil
    public var onEmergencyStop: (() -> Void)? = nil
    public var onAccountSignedOut: (() -> Void)? = nil
    private let accountSession: AccountSessionController?
    public var onBack: (() -> Void)? = nil
    /// Policy preset/matrix apply, threaded from AppRoot (via `bridgeSessionActions`)
    /// the same way the former standalone Governance root wired them.
    public var onApplyPolicyPreset: ((PolicyPreset, String) -> Void)? = nil
    public var onApplyNormalizedPolicy: ((NormalizedPolicy) -> Void)? = nil
    public var onRequestProUpgrade: ((String) -> Void)? = nil
    @AppStorage(LancerAppearance.storageKey) private var colorSchemePref: String = LancerAppearance.light.rawValue
    @State private var showResetConfirmation = false
    @State private var showPolicyHome = false
    @State private var purchases = PurchaseManager.shared
    @Environment(\.lancerTokens) private var t

    private static let supportedProviders: [AIProvider] = [.anthropic, .openai]

    public init(
        viewModel: SettingsViewModel,
        syncEngine: SyncEngine? = nil,
        conversationSyncEngine: ConversationSyncEngine? = nil,
        backendURL: String = "",
        auditRepository: AuditRepository? = nil,
        approvalRepository: ApprovalRepository? = nil,
        sshKeyStore: KeyStore? = nil,
        bridgeActions: BridgeSessionActions = BridgeSessionActions(),
        daemonChannel: DaemonChannel? = nil,
        relayMachines: [RelayMachineRow] = [],
        onRelayPaired: @escaping (E2ERelayClient, RelayMachineRecord) -> Void = { _, _ in },
        onRelayUnpair: @escaping (RelayMachineID) -> Void = { _ in },
        onRelayRename: @escaping (RelayMachineID, String) -> Void = { _, _ in },
        statusHeaderAgents: [AgentInfo] = [],
        onTapStatusHeader: @escaping () -> Void = {},
        onResetApp: (() -> Void)? = nil,
        onShowLimits: (() -> Void)? = nil,
        onEmergencyStop: (() -> Void)? = nil,
        accountSession: AccountSessionController? = nil,
        onAccountSignedOut: (() -> Void)? = nil,
        onBack: (() -> Void)? = nil,
        onApplyPolicyPreset: ((PolicyPreset, String) -> Void)? = nil,
        onApplyNormalizedPolicy: ((NormalizedPolicy) -> Void)? = nil,
        onRequestProUpgrade: ((String) -> Void)? = nil
    ) {
        _vm = State(initialValue: viewModel)
        self.syncEngine = syncEngine
        self.conversationSyncEngine = conversationSyncEngine
        self.backendURL = backendURL
        self.auditRepository = auditRepository
        self.approvalRepository = approvalRepository
        self.sshKeyStore = sshKeyStore
        self.bridgeActions = bridgeActions
        self.daemonChannel = daemonChannel
        self.relayMachines = relayMachines
        self.onRelayPaired = onRelayPaired
        self.onRelayUnpair = onRelayUnpair
        self.onRelayRename = onRelayRename
        self.statusHeaderAgents = statusHeaderAgents
        self.onTapStatusHeader = onTapStatusHeader
        self.onResetApp = onResetApp
        self.onShowLimits = onShowLimits
        self.onEmergencyStop = onEmergencyStop
        self.accountSession = accountSession
        self.onAccountSignedOut = onAccountSignedOut
        self.onBack = onBack
        self.onApplyPolicyPreset = onApplyPolicyPreset
        self.onApplyNormalizedPolicy = onApplyNormalizedPolicy
        self.onRequestProUpgrade = onRequestProUpgrade
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
                    keysSection
                    connectionSection
                    dataSection
                    resetSection
                    versionFooter
                }
            }
            .navigationDestination(isPresented: $showPolicyHome) {
                PolicyHomeView(
                    hosts: ["All hosts"],
                    onApplyPreset: onApplyPolicyPreset ?? { _, _ in },
                    onApplyNormalized: onApplyNormalizedPolicy ?? { _ in }
                )
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
                    Text(accountSession?.email ?? (accountSession?.isOfflineSelfHosted == true ? "Self-hosted offline" : "Lancer"))
                        .font(.dsDisplayPt(17, weight: .bold))
                        .foregroundStyle(t.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(accountSession?.isOfflineSelfHosted == true ? "Local pairing only · no hosted billing" : (purchases.isPro ? "Lancer Pro · manage" : "Free plan · upgrade"))
                        .font(.dsMonoPt(12))
                        // This is actionable account state, not disabled text.  Keep it
                        // legible in Dark mode as well as on the lighter surfaces.
                        .foregroundStyle(t.text3)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                }
                Spacer(minLength: 0)
                Text(purchases.isPro ? "PRO" : "FREE")
                    .font(.dsMonoPt(10, weight: .bold))
                    .foregroundStyle(purchases.isPro ? t.accent : t.text3)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(t.surface2, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                Image(systemName: "chevron.right")
                    .font(.dsSansPt(11, weight: .semibold))
                    .foregroundStyle(t.text4)
                }
                .padding(16)
                .background(t.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(t.border, lineWidth: 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(accountSession?.email ?? (accountSession?.isOfflineSelfHosted == true ? "Self-hosted offline" : "Lancer")), \(purchases.isPro ? "Lancer Pro" : "Free plan")")
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

    private func openPolicyHome(featureName: String = "Policy presets") {
        if BillingEligibility.requiresPaywallForProFeature(isPro: purchases.isPro) {
            onRequestProUpgrade?(featureName)
        } else {
            showPolicyHome = true
        }
    }

    @ViewBuilder
    private var policyGovernanceSection: some View {
        sectionHead("POLICY & GOVERNANCE")
        VStack(spacing: 11) {
            Button { openPolicyHome(featureName: "Policy bridge") } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("POLICY BRIDGE")
                            .font(.dsMonoPt(9.5, weight: .medium))
                            .tracking(1.0)
                            .foregroundStyle(t.accentFg.opacity(0.82))
                        Spacer(minLength: 0)
                        DSStatusDot(tone: .ok, pulse: true, size: 9)
                            .accessibilityLabel("Policy enforcing")
                    }
                    // Real state, not a static "All clear" — every autonomy preset
                    // (including "Always ask") is an enforcing policy, so this always
                    // names which one is active rather than a decorative claim.
                    Text(autonomyLabel)
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
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Policy bridge, \(autonomyLabel), rules enforcing across your connected agents")
            .padding(.horizontal, 16)

            // Calm native grouped list instead of a 2-up card grid — matches the
            // rest of Settings (terminal/connection/data/reset sections already
            // use this settingsCard/settingsNavRow pattern).
            settingsCard {
                NavigationLink { AutonomyLevelView() } label: {
                    settingsNavRow("Default autonomy", icon: "slider.horizontal.3", detail: autonomyLabel)
                }
                divider
                Button { openPolicyHome(featureName: "Policy presets") } label: {
                    settingsNavRow("Policy presets", icon: "checklist", detail: "rules · cross-provider matrix")
                }
                .buttonStyle(.plain)
                if let auditRepository {
                    divider
                    NavigationLink {
                        AuditVerifyExportView(repository: auditRepository)
                    } label: {
                        settingsNavRow("Enforcement log", icon: "list.bullet.clipboard", detail: "verify & export the audit trail")
                    }
                }
                divider
                NavigationLink { TeamRolesView() } label: {
                    settingsNavRow("Team & roles", icon: "person.2", detail: "who can approve, edit, stop")
                }
            }

            // Emergency stop — the operator's panic button. Halts every running
            // agent (SSH sessions + relay-dispatched runs). The closure was wired but
            // never surfaced; without a control it was unreachable from the phone.
            if let onEmergencyStop {
                Button(role: .destructive) {
                    Haptics.warning()
                    onEmergencyStop()
                } label: {
                    HStack(spacing: 11) {
                        Image(systemName: "stop.circle.fill")
                            .font(.dsSansPt(17, weight: .semibold))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Emergency stop")
                                .font(.dsSansPt(15, weight: .semibold))
                            Text("Halt every running agent — SSH and relay.")
                                .font(.dsSansPt(12))
                                .foregroundStyle(t.danger.opacity(0.85))
                                .lineLimit(2)
                                .minimumScaleFactor(0.8)
                        }
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(t.danger)
                    .padding(.horizontal, 15).padding(.vertical, 13)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(t.danger.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(t.danger.opacity(0.4), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Emergency stop — halt all agents")
                .padding(.horizontal, 16)
            }
        }
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
        settingsCard {
            NavigationLink { AppearanceSettingsView() } label: {
                settingsNavRow("Appearance", icon: "circle.lefthalf.filled", detail: "Theme & mode")
            }
            divider
            NavigationLink { AccentSettingsView() } label: {
                settingsNavRow("Accent", icon: "paintpalette.fill", detail: "Brand color")
            }
            divider
            NavigationLink { ProviderKeysView(viewModel: vm) } label: {
                settingsNavRow("Provider keys", icon: "key.horizontal", detail: providerKeyDetail)
            }
            divider
            NavigationLink { NotificationsSettingsView() } label: {
                settingsNavRow("Notifications", icon: "bell", detail: "Push severity")
            }
            divider
            NavigationLink {
                TrustPrivacyView(
                    accountSession: accountSession,
                    backendURL: backendURL,
                    relayMachines: relayMachines,
                    onRelayPaired: onRelayPaired,
                    onRelayUnpair: onRelayUnpair
                )
            } label: {
                settingsNavRow("Security & Trust", icon: "lock", detail: "pairings · revoke")
            }
        }
        .padding(.bottom, 16)
    }

    private var providerKeyDetail: String {
        let n = (vm.hasAnthropicKey ? 1 : 0) + (vm.hasOpenAIKey ? 1 : 0)
        return n == 0 ? "Not set" : "\(n) connected"
    }

    // MARK: - KEYS

    @ViewBuilder
    private var keysSection: some View {
        if let sshKeyStore {
            sectionHead("KEYS")
            settingsCard {
                NavigationLink { SSHKeysView(keyStore: sshKeyStore) } label: {
                    settingsNavRow("SSH keys", icon: "key.horizontal.fill", detail: "generate, import, manage")
                }
            }
            .padding(.bottom, 16)
        }
    }

    // MARK: - CONNECTION

    @ViewBuilder
    private var connectionSection: some View {
        sectionHead("CONNECTION")
        settingsCard {
            NavigationLink {
                RelayMachinesListView(
                    machines: relayMachines,
                    isPro: purchases.isPro,
                    onPaired: onRelayPaired,
                    onUnpair: onRelayUnpair,
                    onRename: onRelayRename,
                    onRequestProUpgrade: onRequestProUpgrade
                )
            } label: {
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
                    if purchases.isPro {
                        SyncStatusView(engine: syncEngine, conversationEngine: conversationSyncEngine)
                            .padding(.horizontal, 16)
                    } else {
                        settingsCard {
                            VStack(alignment: .leading, spacing: 8) {
                                settingsNavRow("iCloud sync (Pro)", icon: "icloud", detail: "host configs · conversation mirror")
                                Text("CloudKit sync unlocks with Lancer Pro.")
                                    .font(.dsMonoPt(10))
                                    .foregroundStyle(t.text3)
                                    .padding(.horizontal, 16)
                                    .padding(.bottom, 12)
                                DSButton("unlock lancer pro", variant: .primary, size: .sm, mono: true) {
                                    onRequestProUpgrade?("CloudKit sync")
                                }
                                .padding(.horizontal, 16)
                                .padding(.bottom, 12)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
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
                            .font(.dsSansPt(14))
                            .frame(width: 20)
                        Text("Reset app")
                            .font(.dsSansPt(15))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.dsSansPt(11, weight: .semibold))
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
                .font(.dsSansPt(15, weight: .medium))
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
                .font(.dsSansPt(11, weight: .semibold))
                .foregroundStyle(t.text4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(detail)")
    }

    private var divider: some View {
        DSDivider(.soft, leadingInset: 56)
    }

    private var versionFooter: some View {
        Group {
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
            let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
            Text("lancer \(version) (\(build))")
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
    @Environment(\.lancerTokens) private var t
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
                                        .accessibilityHidden(true)
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
                            .accessibilityLabel(preset.label)
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
    @Environment(\.lancerTokens) private var t
    @Environment(\.dismiss) private var dismiss
    @State private var notificationsDenied = false

    var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    DSDetailHeader("notifications", onBack: { dismiss() })

                    if notificationsDenied {
                        deniedBanner
                    }

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
        .task { notificationsDenied = await Notifications.shared.isAuthorizationDenied() }
    }

    private var deniedBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "bell.slash")
                .font(.dsSansPt(15, weight: .semibold))
                .foregroundStyle(t.warn)
            VStack(alignment: .leading, spacing: 2) {
                Text("Notifications are off")
                    .font(.dsSansPt(14, weight: .semibold))
                    .foregroundStyle(t.text)
                Text("Turn them on in iOS Settings to get approval alerts.")
                    .font(.dsSansPt(12))
                    .foregroundStyle(t.text3)
            }
            Spacer(minLength: 0)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.dsSansPt(12.5, weight: .semibold))
            .foregroundStyle(t.accent)
        }
        .padding(14)
        .background(t.warn.opacity(0.12), in: RoundedRectangle(cornerRadius: t.r3, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: t.r3, style: .continuous).strokeBorder(t.warn.opacity(0.35), lineWidth: 1))
        .padding(.horizontal, 18)
        .padding(.top, 14)
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

// MARK: - Accent Settings

private struct AccentSettingsView: View {
    @AppStorage(LancerAccentTheme.storageKey) private var accentPref: String = LancerAccentTheme.terracotta.rawValue
    @Environment(\.lancerTokens) private var t
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    DSDetailHeader("accent", onBack: { dismiss() })

                    VStack(spacing: 8) {
                        ForEach(LancerAccentTheme.allCases) { theme in
                            let selected = accentPref == theme.rawValue
                            Button {
                                Haptics.selection()
                                withAnimation(.easeInOut(duration: 0.14)) {
                                    accentPref = theme.rawValue
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Circle()
                                        .fill(theme.accent(scheme))
                                        .frame(width: 22, height: 22)
                                        .overlay(Circle().strokeBorder(t.border, lineWidth: 1))
                                    Text(theme.displayName)
                                        .font(.dsSansPt(15, weight: .semibold))
                                        .foregroundStyle(t.text)
                                    Spacer(minLength: 0)
                                    if selected {
                                        Image(systemName: "checkmark")
                                            .font(.dsSansPt(13, weight: .bold))
                                            .foregroundStyle(theme.accent(scheme))
                                    }
                                }
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    selected ? theme.accent(scheme).opacity(scheme == .dark ? 0.22 : 0.14) : t.surface,
                                    in: RoundedRectangle(cornerRadius: t.r3, style: .continuous)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: t.r3, style: .continuous)
                                        .strokeBorder(selected ? theme.accent(scheme) : t.border, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(theme.displayName)
                            .accessibilityValue(selected ? "selected" : "unselected")
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

// MARK: - Appearance Settings

private struct AppearanceSettingsView: View {
    @AppStorage(LancerAppearance.storageKey) private var colorSchemePref: String = LancerAppearance.light.rawValue
    @Environment(\.lancerTokens) private var t
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
                                        .accessibilityHidden(true)
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
                            .accessibilityLabel("\(label), \(desc)")
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
