#if os(iOS)
import SwiftUI
import UIKit
import Observation
import ConduitCore
import PersistenceKit
import SecurityKit
import SSHTransport
import AgentKit
import NotificationsKit
import WorkspacesFeature
import SessionFeature
import InboxFeature
import OnboardingFeature
import SettingsFeature
import KeysFeature
import DesignSystem
import PreviewFeature
import FilesFeature
import DiffFeature
import SyncKit

/// The single composition root. The whole app graph is wired in `init`.
/// One source of truth for environment, navigation, and dependencies.
@MainActor @Observable
public final class AppEnvironment {
    public let database: AppDatabase
    public let hostRepo: HostRepository
    public let snippetRepo: SnippetRepository
    public let blockRepo: BlockRepository
    public let snapshotRepo: SessionSnapshotRepository
    public let keyStore: KeyStore
    public let aiKeyStore: any AIKeyStoring
    public let hostKeyStore: HostKeyStore
    public let syncEngine: SyncEngine
    public let tombstoneRepo: SyncTombstoneRepository
    public let approvalRepo: ApprovalRepository
    public let auditRepo: AuditRepository
    public let loopStore: LoopStore
    public let quotaGuardStore: QuotaGuardStore
    public let hostHealthStore: HostHealthStore
    public let e2eRelayClient: E2ERelayClient

    public init() throws {
        self.database = try AppDatabase.openShared()
        self.hostRepo = HostRepository(database)
        self.snippetRepo = SnippetRepository(db: database)
        self.blockRepo = BlockRepository(database)
        self.snapshotRepo = SessionSnapshotRepository(database)
        self.keyStore = KeyStore()
        self.hostKeyStore = HostKeyStore()
        self.aiKeyStore = KeychainAIKeyStore()
        self.tombstoneRepo = SyncTombstoneRepository(database)
        let cloudKitEnabled = Bundle.main.object(forInfoDictionaryKey: "CONDUIT_ICLOUD_ENABLED") as? Bool ?? false
        let cloudSync = CloudSync(cloudKitEnabled: cloudKitEnabled)
        let ks = self.keyStore
        self.syncEngine = SyncEngine(
            cloudSync: cloudSync,
            hostRepo: HostRepository(database),
            snippetRepo: SnippetRepository(db: database),
            tombstoneRepo: SyncTombstoneRepository(database),
            keyStore: ks
        )
        self.approvalRepo = ApprovalRepository(database)
        self.auditRepo = AuditRepository(database)
        self.loopStore = LoopStore(loopRepo: LoopRepository(database))
        self.quotaGuardStore = QuotaGuardStore()
        self.hostHealthStore = HostHealthStore()
        // Start with the configured relay URL and a freshly generated, single-use
        // pairing code. The pairing view regenerates the code per session and the
        // relay URL can be overridden in Settings; the old hardcoded "000000" is
        // gone (it could never actually pair).
        self.e2eRelayClient = E2ERelayClient(
            relayURL: RelaySettings.url(),
            pairingCode: PairingCrypto.generatePairingCode()
        )
    }

    public func aiClient(provider: AIProvider? = nil, managedOpenRouterKey: String? = nil) async -> (any AIClient)? {
        let selectedProvider = provider ?? SettingsViewModel.persistedDefaultProvider()
        switch selectedProvider {
        case .anthropic:
            guard let key = try? await aiKeyStore.loadAPIKey(provider: .anthropic) else { return nil }
            return AnthropicClient(apiKey: key)
        case .openai:
            guard let key = try? await aiKeyStore.loadAPIKey(provider: .openai) else { return nil }
            return OpenAIClient(apiKey: key)
        case .openrouter:
            if let managed = managedOpenRouterKey, !managed.isEmpty {
                return OpenRouterClient(apiKey: managed)
            }
            guard let key = try? await aiKeyStore.loadAPIKey(provider: .openrouter) else { return nil }
            return OpenRouterClient(apiKey: key)
        case .xai:
            return nil  // M5+
        }
    }
}

/// Concrete AIKeyStoring implementation backed by the Keychain.
public struct KeychainAIKeyStore: AIKeyStoring {
    private let keychain: Keychain
    public init() {
        self.keychain = Keychain(service: "dev.conduit.mobile.aikeys")
    }
    public func storeAPIKey(_ key: String, provider: AIProvider) async throws {
        try await keychain.write(Data(key.utf8), account: provider.rawValue)
    }
    public func loadAPIKey(provider: AIProvider) async throws -> String {
        let data = try await keychain.read(account: provider.rawValue)
        return String(data: data, encoding: .utf8) ?? ""
    }
    public func deleteAPIKey(provider: AIProvider) async throws {
        try await keychain.delete(account: provider.rawValue)
    }
    public func hasAPIKey(provider: AIProvider) async -> Bool {
        (try? await keychain.read(account: provider.rawValue)) != nil
    }
}

// MARK: - Root view

public struct AppRoot: View {
    @State private var environment: AppEnvironmentResult
    @State private var selectedTab: Tab = .inbox
    @State private var sessionViewModel: SessionViewModel?
    @State private var addHostPresented = false
    @State private var dispatchPresented = false
    @State private var editingHost: Host?
    @State private var workspacesRevision = UUID()
    @State private var passwordPromptHost: Host?
    @State private var connectionError: String?
    @State private var inboxVM = InboxViewModel()
    @State private var liveInboxVM: LiveInboxViewModel?
    @State private var runOutputStore = RunOutputStore()
    @State private var dispatchFeedback: String?
    @State private var hudStore = AgentHUDStore()
    @State private var approvalRepository: ApprovalRepository?
    @State private var daemonChannel: DaemonChannel?
    @State private var approvalIngest: ApprovalIngest?
    @State private var showingProvisioningWizard = false
    @AppStorage("onboardingSeen") private var onboardingSeen = false
    @AppStorage("conduitColorScheme") private var colorSchemePref: String = "system"
    @AppStorage("appLockEnabled") private var appLockEnabled: Bool = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var systemScheme

    private var preferredScheme: ColorScheme? {
        switch colorSchemePref {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil
        }
    }

    /// The scheme actually in effect: the Settings override if set, else the system.
    /// Drives the token palette so it always matches `preferredScheme`.
    private var effectiveScheme: ColorScheme {
        preferredScheme ?? systemScheme
    }

    @State private var scenePhaseObserver: ScenePhaseObserver?
    @State private var isUnlocked: Bool = false
    @State private var watchConnector = PhoneWatchConnector()
    @State private var pm = PurchaseManager.shared
    @State private var agentStore: AgentStore?
    @State private var showingPaywall = false
    @State private var paywallFeatureName = ""
    @State private var isShowingLiveSession = false
    @State private var showingHostedAgents = false
    @State private var fleetStore = FleetStore()
    @State private var selectedFleetSlotID: UUID?
    @State private var e2eBridge: E2ERelayBridge?

    private var isPro: Bool {
        #if DEBUG
        // Debug builds default to the REAL purchase state so paywall/Pro gates are
        // exercised exactly as in Release. Opt in to a force-unlock for UX evaluation
        // with CONDUIT_FORCE_PRO=1. No DEBUG path ever grants free Pro in Release.
        if ProcessInfo.processInfo.environment["CONDUIT_FORCE_PRO"] == "1" { return true }
        #endif
        switch pm.purchaseState {
        case .purchased: return true
        // .unknown = purchase state not yet loaded; keep locked rather than granting free Pro.
        default: return false
        }
    }

    public enum Tab: Hashable, Sendable {
        case inbox
        case fleet
        case activity
        case settings

        static let rootTabs: [Tab] = [.inbox, .fleet, .activity, .settings]

        var title: String {
            switch self {
            case .inbox:    "Inbox"
            case .fleet:    "Fleet"
            case .activity: "Activity"
            case .settings: "Settings"
            }
        }

        var systemImage: String {
            switch self {
            case .inbox:    "tray"
            case .fleet:    "square.stack.3d.up"
            case .activity: "clock.arrow.circlepath"
            case .settings: "gear"
            }
        }
    }

    enum AppEnvironmentResult {
        case ready(AppEnvironment)
        case failure(String)
    }

    public init() {
        do {
            let env = try AppEnvironment()
            _environment = State(initialValue: .ready(env))
        } catch {
            _environment = State(initialValue: .failure(error.localizedDescription))
        }
        #if DEBUG
        // UI-audit hook: launch straight into a tab via SIMCTL_CHILD_CONDUIT_TAB.
        if let tab = ProcessInfo.processInfo.environment["CONDUIT_TAB"] {
            switch tab {
            case "inbox":    _selectedTab = State(initialValue: .inbox)
            case "fleet":    _selectedTab = State(initialValue: .fleet)
            case "activity": _selectedTab = State(initialValue: .activity)
            case "settings": _selectedTab = State(initialValue: .settings)
            default:         _selectedTab = State(initialValue: .inbox)
            }
        }
        #endif
    }

    public var body: some View {
        #if DEBUG
        if let gallery = ProcessInfo.processInfo.environment["CONDUIT_GALLERY"] {
            return AnyView(DebugGalleryView(route: gallery).conduitTokens())
        }
        #endif
        return AnyView(mainBody.environment(\.conduitTokens, effectiveScheme == .dark ? .dark : .light))
    }

    private var mainBody: some View {
        Group {
            if appLockEnabled && !isUnlocked {
                LaunchLockView(onUnlock: { await attemptUnlock() })
                    .preferredColorScheme(preferredScheme)
            } else {
                switch environment {
                case .failure(let msg):
                    ContentUnavailableView(
                        "Failed to start",
                        systemImage: "exclamationmark.triangle",
                        description: Text(msg)
                    )
                case .ready(let env):
                    readyRoot(env: env)
                        .preferredColorScheme(preferredScheme)
                }
            }
        }
        .task {
            if appLockEnabled {
                await attemptUnlock()
            } else {
                isUnlocked = true
            }
        }
        .task { watchConnector.activate() }
        .task { await pm.load() }
        .task {
            if case .ready(let env) = environment {
                await configureCloudServices(env: env)
            }
        }
        .task {
            if onboardingSeen {
                Notifications.shared.registerCategories()
            }
        }
        .onChange(of: onboardingSeen) { _, seen in
            if seen {
                Notifications.shared.registerCategories()
            }
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallSheet(featureName: paywallFeatureName)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background, #available(iOS 16.2, *) {
                Task { await ConduitLiveActivityManager.shared.endAll() }
            }
            if appLockEnabled {
                switch newPhase {
                case .active:
                    isUnlocked = false
                    Task { await attemptUnlock() }
                case .background:
                    isUnlocked = false
                default:
                    break
                }
            }
            if let observer = scenePhaseObserver {
                Task { await observer.scenePhaseChanged(to: newPhase) }
            }
        }
        .onChange(of: appLockEnabled) { _, enabled in
            if !enabled {
                isUnlocked = true
            }
        }
        // Route lock-screen Approve/Reject notification actions into the same
        // decision path the in-app Inbox uses. ConduitNotificationDelegate posts
        // these names; without an observer the buttons were silently dead.
        .onReceive(NotificationCenter.default.publisher(for: .conduitApprovalAction)) { note in
            handleApprovalAction(note)
            // Also drain the cold-launch buffer (MAJOR-6) so the decision is
            // persisted durably and the buffer never accumulates. Idempotent with
            // the line above (first-decision-wins).
            if case .ready(let env) = environment {
                Task { await drainPendingApprovalActions(env: env) }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .conduitRunCompleteAction)) { note in
            if
                let sessionID = note.userInfo?["sessionId"] as? String,
                let uuid = UUID(uuidString: sessionID),
                let slot = fleetStore.slots.first(where: { $0.sessionViewModel.sessionID.raw == uuid })
            {
                selectFleetSlot(slot.id)
            }
            if activeSessionViewModel != nil { isShowingLiveSession = true }
        }
    }

    /// Applies an Approve/Reject decision delivered from a notification action
    /// button via `Notification.Name.conduitApprovalAction`. Routes through
    /// `activeInboxViewModel.decide` — the live VM forwards to the daemon channel
    /// and persists; the static fallback updates in-memory state.
    private func handleApprovalAction(_ note: Notification) {
        guard
            let info = note.userInfo,
            let idString = info["approvalId"] as? String,
            let uuid = UUID(uuidString: idString),
            let action = info["action"] as? String
        else { return }
        let decision: Approval.Decision = (action == "approve") ? .approved : .rejected
        let approvalID = ApprovalID(uuid)
        if let slot = fleetStore.slot(forApprovalID: approvalID) {
            selectFleetSlot(slot.id)
            slot.inboxVM.decide(approvalID, decision: decision)
            return
        }
        activeInboxViewModel.decide(approvalID, decision: decision)
    }

    /// Drain buffered cold-launch approval actions (MAJOR-6) and apply each one
    /// durably. A killed app's lock-screen Approve/Reject is recorded by
    /// `ConduitNotificationDelegate` into `ApprovalActionBuffer` because the
    /// `NotificationCenter` post races AppRoot's subscriber. Routing through
    /// `ApprovalRelay.enqueue` persists the decision (first-decision-wins) and
    /// forwards it (live channel → backend relay → SSH-drain queue), so a
    /// cold-launched decision is never silently dropped. Idempotent: replaying an
    /// already-resolved gate is a no-op.
    private func drainPendingApprovalActions(env: AppEnvironment) async {
        for action in ApprovalActionBuffer.shared.drain() {
            guard UUID(uuidString: action.approvalID) != nil else { continue }
            let decision: Approval.Decision = (action.action == "approve") ? .approved : .rejected
            await ApprovalRelay.shared.enqueue(
                approvalID: action.approvalID,
                decision: decision,
                db: env.database,
                hostID: ""
            )
        }
    }

    private func attemptUnlock() async {
        do {
            try await BiometricGate.shared.unlock(reason: "Authenticate to open Conduit")
            isUnlocked = true
        } catch {
            // User cancelled or biometrics failed — lock screen stays visible.
        }
    }

    @ViewBuilder
    private func readyRoot(env: AppEnvironment) -> some View {
        Group {
            if onboardingSeen {
                rootContainer(env: env)
            } else {
                OnboardingView(
                    onContinue: {
                        onboardingSeen = true
                        addHostPresented = true
                        selectedTab = .fleet
                    },
                    onSetupWorkspace: {
                        showingProvisioningWizard = true
                    },
                    relayClient: env.e2eRelayClient
                )
            }
        }
        .sheet(isPresented: $showingProvisioningWizard) {
            ProvisioningWizard(
                hostRepo: env.hostRepo,
                onComplete: { host in
                    showingProvisioningWizard = false
                    onboardingSeen = true
                    selectedTab = .fleet
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(250))
                        openSession(host: host, env: env)
                    }
                },
                onCancel: { showingProvisioningWizard = false }
            )
        }
        .sheet(isPresented: $addHostPresented) {
            NavigationStack {
                AddHostView(
                    repository: env.hostRepo,
                    keyStore: env.keyStore,
                    hasCloudEntitlement: pm.hasCloudEntitlement,
                    cloudUpgradeEligible: pm.externalStripeEligible,
                    onCancel: { addHostPresented = false },
                    onUseHosted: {
                        // Dismiss the add-host sheet, then open the Hosted Agents
                        // screen so the user lands on the cloud surface directly
                        // (a sheet can't present over another mid-dismiss, so we
                        // sequence it after a short delay — same pattern as
                        // openSession below).
                        addHostPresented = false
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(350))
                            showingHostedAgents = true
                        }
                    },
                    onConnectAndSave: { host in
                        addHostPresented = false
                        workspacesRevision = UUID()
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(250))
                            openSession(host: host, env: env)
                        }
                    }
                )
            }
        }
        .sheet(isPresented: $showingHostedAgents) {
            if let agentStore {
                NavigationStack {
                    AgentsView(store: agentStore, statusChannel: fleetStore.slots.first?.channel)
                }
            }
        }
        .sheet(isPresented: $dispatchPresented) {
            NavigationStack {
                DispatchView(
                    agents: dispatchAgents(),
                    onDispatch: { agentID, cwd, prompt, budget, model in
                        performDispatch(agentID: agentID, cwd: cwd, prompt: prompt, budgetUSD: budget, model: model)
                    }
                )
            }
        }
        .alert("Dispatch", isPresented: Binding(get: { dispatchFeedback != nil }, set: { if !$0 { dispatchFeedback = nil } })) {
            Button("OK", role: .cancel) { dispatchFeedback = nil }
        } message: {
            Text(dispatchFeedback ?? "")
        }
        .sheet(item: $editingHost) { host in
            NavigationStack {
                HostEditorView(
                    viewModel: HostEditorViewModel(
                        repository: env.hostRepo,
                        keyStore: env.keyStore,
                        existingHost: host
                    ) { _ in
                        editingHost = nil
                        workspacesRevision = UUID()
                    }
                )
            }
        }
        .sheet(item: $passwordPromptHost) { host in
            PasswordPromptView(host: host) { password in
                passwordPromptHost = nil
                startSession(
                    host: host,
                    env: env,
                    credentialProvider: { .password(password) }
                )
            }
            .environment(\.conduitTokens, effectiveScheme == .dark ? .dark : .light)
            .preferredColorScheme(preferredScheme)
        }
        // Re-prompt after consecutive auth failures on an existing session,
        // reusing the same SessionViewModel rather than creating a new one.
        .sheet(isPresented: Binding(
            get: { sessionViewModel?.awaitingPasswordRetry == true },
            set: { if !$0 { sessionViewModel?.cancelPasswordRetry() } }
        )) {
            if let vm = sessionViewModel {
                PasswordPromptView(host: vm.host) { password in
                    Task { await vm.retryWithNewPassword(password) }
                }
                .environment(\.conduitTokens, effectiveScheme == .dark ? .dark : .light)
                .preferredColorScheme(preferredScheme)
            }
        }
        // NOTE: the TOFU host-key confirmation is presented from INSIDE
        // `SessionView` (above the fullScreenCover) — see B1. Presenting it here
        // on `readyRoot` could not appear over the cover and caused a hard hang.
        .alert("Connection unavailable", isPresented: .constant(connectionError != nil), actions: {
            Button("OK") { connectionError = nil }
        }, message: {
            Text(connectionError ?? "")
        })
        .task {
            configureGlobalInbox(env: env)
            await configureCloudServices(env: env)
            // MAJOR-6: replay any approval action tapped from a lock-screen banner
            // while the app was killed (its NotificationCenter post had no live
            // subscriber). Done after configureCloudServices so the relay backend
            // is configured.
            await drainPendingApprovalActions(env: env)
            await env.syncEngine.start()
        }
        .task {
#if DEBUG
            await DebugSeeder.seedIfNeeded(env: env)
            await DebugSeeder.resetForUITestIfRequested(env: env)
            await DebugSeeder.seedDaemonE2EHostIfRequested(env: env)
#endif
        }
    }

    @ViewBuilder
    private func rootContainer(env: AppEnvironment) -> some View {
        Group {
            if horizontalSizeClass == .regular {
                regularRoot(env: env)
            } else {
                compactRoot(env: env)
            }
        }
        // Agent status header — a slim, in-layout strip shown only while a live
        // session exists (the store returns no agents when idle). Each tab renders
        // it below its own title row — passed as statusHeaderAgents to every tab
        // view so placement is consistent. Hidden behind the live SessionView cover.
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: hudStore.agents.isEmpty)
        .onChange(of: activeInboxViewModel.approvals.filter(\.isPending).count, initial: true) { _, count in
            hudStore.pendingApprovals = count
            // Keep the real Dynamic Island / lock-screen Live Activity badge
            // live — this is the glanceable signal while Conduit is backgrounded.
            if #available(iOS 16.2, *) {
                Task { await ConduitLiveActivityManager.shared.updatePendingApprovals(count) }
            }
        }
    }

    private var splitSelection: Binding<Tab?> {
        Binding(
            get: { selectedTab },
            set: { selectedTab = $0 ?? .inbox }
        )
    }

    private var activeInboxViewModel: InboxViewModel {
        selectedFleetSlot?.inboxVM ?? liveInboxVM ?? inboxVM
    }

    private var selectedFleetSlot: FleetStore.Slot? {
        guard let selectedFleetSlotID else { return fleetStore.slots.first }
        return fleetStore.slots.first { $0.id == selectedFleetSlotID } ?? fleetStore.slots.first
    }

    private var activeSessionViewModel: SessionViewModel? {
        selectedFleetSlot?.sessionViewModel ?? sessionViewModel
    }

    @MainActor
    private func selectFleetSlot(_ id: UUID) {
        selectedFleetSlotID = id
        if let slot = fleetStore.slots.first(where: { $0.id == id }) {
            sessionViewModel = slot.sessionViewModel
            daemonChannel = slot.channel
            approvalIngest = slot.ingest
            hudStore.session = slot.sessionViewModel
        }
    }

    @MainActor
    private func configureGlobalInbox(env: AppEnvironment) {
        guard liveInboxVM == nil else { return }
        let approvalRepo = ApprovalRepository(env.database)
        let liveVM = LiveInboxViewModel(repository: approvalRepo) { id, decision, edited in
            // Prefer the channel of the slot that owns this approval (multi-slot
            // correct). On a dead/absent channel fall back to the relay's single
            // forwarding chokepoint (backend POST + SSH-drain queue) rather than
            // `try?`-swallowing the write and silently dropping the decision
            // (MAJOR-5). LiveInboxViewModel persists the decision before firing
            // onDecision, so no DB write is needed here.
            if let slot = await MainActor.run(body: { self.fleetStore.slot(forApprovalID: id) }) {
                do {
                    try await slot.channel.respond(
                        approvalId: id.uuidString,
                        decision: decision,
                        editedToolInput: edited
                    )
                    return
                } catch {
                    // dead/stopped channel — fall through to the relay
                }
            }
            await ApprovalRelay.shared.forwardDecisionOnly(
                approvalID: id.uuidString,
                decision: decision,
                editedToolInput: edited
            )
        }
        approvalRepository = approvalRepo
        liveInboxVM = liveVM
        inboxVM = liveVM
    }

    /// Bridge RPC actions for the selected (or first) fleet slot.
    @MainActor
    private func bridgeSessionActions() -> BridgeSessionActions {
        guard let slot = selectedFleetSlot ?? fleetStore.slots.first,
              slot.sessionViewModel.status == .connected
        else {
            return BridgeSessionActions()
        }
        let cwd = slot.sessionViewModel.cwd.isEmpty ? "~" : slot.sessionViewModel.cwd
        return BridgeSessionActions(
            isConnected: true,
            policyCWD: cwd,
            loadPolicyYAML: { try await slot.channel.fetchPolicyYAML(cwd: cwd) },
            savePolicyYAML: { yaml in try await slot.channel.savePolicyYAML(cwd: cwd, yaml: yaml) },
            reloadPolicy: { try await slot.channel.reloadPolicy(cwd: cwd) },
            tailAudit: { limit in
                let tail = try await slot.channel.tailAudit(limit: limit)
                return tail.entries
            },
            dispatch: { agent, workdir, prompt in
                try await slot.channel.dispatchAgent(
                    agent: agent,
                    cwd: workdir,
                    prompt: prompt
                )
            },
            runDoctor: {
                try await slot.channel.runDoctor()
            }
        )
    }

    /// Dispatchable agents across all connected fleet slots. Each id encodes
    /// `slotUUID|vendor` so `performDispatch` can route back to the right channel.
    @MainActor
    private func dispatchAgents() -> [DispatchAgent] {
        fleetStore.slots.flatMap { slot -> [DispatchAgent] in
            let offline = slot.sessionViewModel.status != .connected
            let cwd = slot.sessionViewModel.cwd.isEmpty ? "~" : slot.sessionViewModel.cwd
            return (slot.bridgeStatus?.agents ?? []).map { agent in
                DispatchAgent(
                    id: "\(slot.id.uuidString)|\(agent.agent)",
                    name: "\(agent.displayName) · \(slot.hostName)",
                    cwd: cwd,
                    isOffline: offline || !(agent.loggedIn ?? true)
                )
            }
        }
    }

    @MainActor
    private func performDispatch(agentID: String, cwd: String, prompt: String, budgetUSD: Double?, model: String? = nil) {
        let parts = agentID.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let slotUUID = UUID(uuidString: parts[0]),
              let slot = fleetStore.slots.first(where: { $0.id == slotUUID })
        else { return }
        let vendor = parts[1]
        dispatchPresented = false
        Task {
            do {
                let result = try await slot.channel.dispatchAgent(
                    agent: vendor,
                    cwd: cwd,
                    prompt: prompt,
                    budgetUSD: budgetUSD ?? 0,
                    model: model
                )
                await MainActor.run {
                    switch result.status {
                    case "started":
                        if let runId = result.runId {
                            runOutputStore.register(runId: runId)
                            dispatchFeedback = "Run started — output is streaming to this session."
                        }
                    case "denied":
                        dispatchFeedback = "Blocked by policy\(result.rule.map { " (\($0))" } ?? "")."
                    case "needsApproval":
                        dispatchFeedback = "Awaiting your approval — check the Inbox."
                    case "budgetExceeded":
                        dispatchFeedback = result.message ?? "Daily budget cap reached."
                    default:
                        dispatchFeedback = result.message ?? "Couldn't start the run."
                    }
                }
            } catch {
                await MainActor.run { dispatchFeedback = "Dispatch failed: \(error.localizedDescription)" }
            }
        }
    }

    @Environment(\.conduitTokens) private var t

    private func compactRoot(env: AppEnvironment) -> some View {
        let inboxBadge = activeInboxViewModel.approvals.filter(\.isPending).count > 0
        let tabItems: [DSTabItem] = [
            DSTabItem(id: "inbox",    icon: .inbox,    label: "Inbox", badge: inboxBadge),
            DSTabItem(id: "fleet",    icon: .server,   label: "Fleet"),
            DSTabItem(id: "activity", icon: .list,     label: "Activity"),
            DSTabItem(id: "settings", icon: .settings, label: "Settings"),
        ]

        let tabID = Binding<String>(
            get: {
                switch selectedTab {
                case .inbox:    "inbox"
                case .fleet:    "fleet"
                case .activity: "activity"
                case .settings: "settings"
                }
            },
            set: { id in
                switch id {
                case "inbox":    selectedTab = .inbox
                case "fleet":    selectedTab = .fleet
                case "activity": selectedTab = .activity
                case "settings": selectedTab = .settings
                default:         selectedTab = .inbox
                }
            }
        )

        return ZStack {
            t.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                PersistentStatusBar(
                    agents: isShowingLiveSession ? [] : hudStore.agents,
                    relayState: selectedFleetSlot.map { .init(relayState: $0.relayState) },
                    onTap: { if activeSessionViewModel != nil { isShowingLiveSession = true } },
                    // Manual retry after the auto-reconnect engine gives up
                    // (maxAttempts). `reconnect()` rebuilds a fresh engine, so this
                    // re-arms a session stuck in `.failed`.
                    onReconnect: activeSessionViewModel == nil ? nil : {
                        Task { await activeSessionViewModel?.reconnect() }
                    }
                )
                tabContent(env: env, tabItems: tabItems, tabID: tabID)
            }
        }
        .fullScreenCover(isPresented: $isShowingLiveSession) {
            if let vm = activeSessionViewModel {
                SessionView(viewModel: vm)
                    .environment(\.conduitTokens, effectiveScheme == .dark ? .dark : .light)
            }
        }
    }

    // Tab bar is placed INSIDE each tab's root view so NavigationStack push
    // naturally hides it — pushed detail views don't inherit the safeAreaInset.
    @ViewBuilder
    private func tabContent(env: AppEnvironment, tabItems: [DSTabItem], tabID: Binding<String>) -> some View {
        let bar = DSTabBar(items: tabItems, selectedID: tabID)

        switch selectedTab {
        case .inbox:
            NavigationStack {
                rootDestination(.inbox, env: env)
                    .safeAreaInset(edge: .bottom, spacing: 0) { bar }
            }
        case .fleet:
            NavigationStack {
                rootDestination(.fleet, env: env)
                    .safeAreaInset(edge: .bottom, spacing: 0) { bar }
            }
        case .activity:
            NavigationStack {
                rootDestination(.activity, env: env)
                    .safeAreaInset(edge: .bottom, spacing: 0) { bar }
            }
        case .settings:
            NavigationStack {
                rootDestination(.settings, env: env)
                    .safeAreaInset(edge: .bottom, spacing: 0) { bar }
            }
        }
    }

    private func regularRoot(env: AppEnvironment) -> some View {
        ZStack {
            t.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                PersistentStatusBar(
                    agents: isShowingLiveSession ? [] : hudStore.agents,
                    relayState: selectedFleetSlot.map { .init(relayState: $0.relayState) },
                    onTap: { if activeSessionViewModel != nil { isShowingLiveSession = true } },
                    onReconnect: activeSessionViewModel == nil ? nil : {
                        Task { await activeSessionViewModel?.reconnect() }
                    }
                )
                NavigationSplitView {
                    List(selection: splitSelection) {
                        ForEach(Tab.rootTabs, id: \.self) { tab in
                            Label(tab.title, systemImage: tab.systemImage).tag(tab)
                        }
                    }
                    .navigationTitle("Conduit")
                } detail: {
                    NavigationStack {
                        rootDestination(selectedTab, env: env)
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $isShowingLiveSession) {
            if let vm = activeSessionViewModel {
                SessionView(viewModel: vm)
                    .environment(\.conduitTokens, effectiveScheme == .dark ? .dark : .light)
            }
        }
    }

    /// Tear down a fleet slot and remove it from Hosts ACTIVE.
    private func disconnectLiveSession(slotID: UUID? = nil) {
        let resolvedID = slotID ?? selectedFleetSlot?.id
        guard let resolvedID, let slot = fleetStore.slots.first(where: { $0.id == resolvedID }) else { return }
        Task {
            await slot.sessionViewModel.disconnect()
            await slot.ingest.stop()
            await slot.channel.stop()
            await MainActor.run {
                fleetStore.remove(id: resolvedID)
                if fleetStore.slots.isEmpty {
                    ApprovalRelay.shared.clearChannel()
                    selectedFleetSlotID = nil
                    sessionViewModel = nil
                    daemonChannel = nil
                    approvalIngest = nil
                    hudStore.session = nil
                    isShowingLiveSession = false
                } else if let fallback = fleetStore.slots.first {
                    selectFleetSlot(fallback.id)
                }
            }
        }
    }

    private func jumpToUnreadLiveSession() {
        guard let slot = fleetStore.firstSlotWithPendingApprovals() else { return }
        selectFleetSlot(slot.id)
        selectedTab = .inbox
        isShowingLiveSession = true
    }

    @ViewBuilder
    private func rootDestination(_ tab: Tab, env: AppEnvironment) -> some View {
        switch tab {
        case .inbox:
            let actions = bridgeSessionActions()
            InboxView(
                viewModel: activeInboxViewModel,
                statusHeaderAgents: [],
                onTapStatusHeader: {},
                bridgeConnected: actions.isConnected,
                bridgePolicy: "balanced",
                todaySpend: "$0.00",
                onSetPolicy: { yaml in try? await actions.savePolicyYAML(yaml) }
            )

        case .fleet:
            FleetView(
                store: fleetStore,
                hostRepo: env.hostRepo,
                loopStore: env.loopStore,
                quotaGuardStore: env.quotaGuardStore,
                hostHealthStore: env.hostHealthStore,
                onConnectHost: { addHostPresented = true },
                onReconnect: { host in openSession(host: host, env: env) },
                onDelete: { host in Task { try? await env.hostRepo.delete(id: host.id) } },
                onNewTask: { dispatchPresented = true },
                onQuotaGuard: nil,
                onOpenTerminal: { slotID in
                    // Finding #5: intentional drill-in — select the slot and
                    // present its live block terminal full-screen.
                    selectFleetSlot(slotID)
                    isShowingLiveSession = true
                }
            )
            .id(workspacesRevision)

        case .activity:
            ActivityView(actions: bridgeSessionActions())

        case .settings:
            SettingsWithLibraryView(
                viewModel: SettingsViewModel(keyStore: env.aiKeyStore),
                syncEngine: env.syncEngine,
                backendURL: Self.pushBackendURL(),
                auditRepository: env.auditRepo,
                approvalRepository: approvalRepository,
                sshKeyStore: env.keyStore,
                daemonChannel: daemonChannel,
                e2eRelayClient: env.e2eRelayClient
            )
        }
    }

    private func configureCloudServices(env: AppEnvironment) async {
        let url = Self.pushBackendURL()
        pm.configure(backendURL: url)
        await pm.refreshCloudEntitlement(backendURL: url)
        if agentStore == nil {
            agentStore = AgentStore(
                backendURL: url,
                hostRepo: env.hostRepo,
                keyStore: env.keyStore,
                hostKeyStore: env.hostKeyStore,
                purchaseManager: pm
            )
        }
        ApprovalRelay.shared.configureBackend(
            url: url,
            sessionID: DeviceIdentity.sessionID()
        )
        configureE2ERelayBridge(env: env)
    }

    /// Activate the E2E relay decision path. Builds a single `E2ERelayBridge`
    /// over the app-wide `E2ERelayClient`, hands it to `ApprovalRelay` so paired
    /// decisions route through E2E first, and mirrors the client's pairing /
    /// connection state onto the selected fleet slot so `E2ERelayStatusBadge`
    /// reflects live state. Idempotent — only the first call builds the bridge.
    @MainActor
    private func configureE2ERelayBridge(env: AppEnvironment) {
        guard e2eBridge == nil else { return }
        let bridge = E2ERelayBridge(
            relayClient: env.e2eRelayClient,
            approvalRelay: ApprovalRelay.shared
        )
        bridge.start()
        ApprovalRelay.shared.e2eBridge = bridge
        e2eBridge = bridge

        // These Tasks inherit @MainActor isolation, so client reads and the
        // fleet mutation are already main-actor-confined.
        let client = env.e2eRelayClient
        let fleet = fleetStore
        Task { @MainActor in
            for await pairing in client.$pairingState.values {
                fleet.setRelayStateOnAllSlots(
                    Self.relayState(pairing: pairing, connection: client.connectionState)
                )
            }
        }
        Task { @MainActor in
            for await connection in client.$connectionState.values {
                fleet.setRelayStateOnAllSlots(
                    Self.relayState(pairing: client.pairingState, connection: connection)
                )
            }
        }
    }

    /// Maps the E2E relay client's pairing + connection state onto the
    /// `Session.RelayState` the status badge renders. Paired wins; otherwise an
    /// active (connecting / reconnecting) socket reads as `.connecting`; a
    /// pairing failure reads as `.error`; everything else is `.none`.
    private static func relayState(
        pairing: E2ERelayClient.PairingState,
        connection: E2ERelayClient.ConnectionState
    ) -> Session.RelayState {
        switch pairing {
        case .paired:
            return .paired
        case .pairingFailed:
            return .error
        case .waitingForPeer:
            return .connecting
        case .unpaired:
            switch connection {
            case .connecting, .reconnecting:
                return .connecting
            case .connected:
                return .connecting
            case .disconnected:
                return .none
            }
        }
    }

    private static func pushBackendURL() -> String {
        #if DEBUG
        if let envURL = ProcessInfo.processInfo.environment["CONDUIT_PUSH_BACKEND_URL"],
           !envURL.isEmpty {
            return envURL
        }
        #endif
        return Bundle.main.infoDictionary?["CONDUIT_PUSH_BACKEND_URL"] as? String ?? ""
    }

    private func openSession(host: Host, env: AppEnvironment) {
        switch host.authMethod {
        case .password:
            passwordPromptHost = host
        case .ed25519(let keyID):
            let keyStore = env.keyStore
            startSession(host: host, env: env) {
                try await BiometricGate.shared.unlock()
                let key = try await keyStore.loadEd25519(tag: keyID.uuidString)
                return .ed25519(key)
            }
        case .agent:
            connectionError = "SSH agent forwarding is not implemented yet. Edit the host and choose password or Ed25519 key authentication."
        }
    }

    private func startSession(
        host: Host,
        env: AppEnvironment,
        credentialProvider: @escaping @Sendable () async throws -> SSHCredential
    ) {
        let sshSession = SSHSession(host: host)
        let snapshotRepo = SessionSnapshotRepository(env.database)
        let backendURL = Self.pushBackendURL()
        // One stable id everywhere (MAJOR-8): the value sent to
        // `registerDevice` MUST equal the relay decision POST `sessionId` so the
        // backend per-session token lookup keys match.
        let deviceSessionID = DeviceIdentity.sessionID()
        // Capture the agent store as an explicit local strong reference. It is
        // owned for the app lifetime by AppRoot's @State and never retains the
        // session, so there is no cycle; a weak capture here only risked silently
        // dropping usage records if the optional read deallocated. (#ImplicitStrongCapture)
        let agentStoreRef = agentStore
        Task {
            let aiClient = await env.aiClient(managedOpenRouterKey: pm.managedOpenRouterKey)
            let usageReporter: (@Sendable (UsageRecord) async -> Void)? = { record in
                await agentStoreRef?.ingestUsage(record, runID: nil, agentID: nil)
            }
            let vm = SessionViewModel(
                host: host,
                sshSession: sshSession,
                credentialProvider: credentialProvider,
                hostKeyStore: env.hostKeyStore,
                aiClient: aiClient,
                onAIUsage: usageReporter,
                blockRepo: env.blockRepo,
                auditRepo: env.auditRepo,
                snapshotRepo: snapshotRepo
            )
            let approvalRepo = ApprovalRepository(env.database)
            let channel = DaemonChannel(session: sshSession)
            let ingest = ApprovalIngest(channel: channel, repository: approvalRepo, hostName: host.name, runOutputStore: runOutputStore)
            let liveVM = LiveInboxViewModel(
                repository: approvalRepo,
                onDecision: { id, decision, editedToolInput in
                    try? await env.auditRepo.record(
                        hostID: host.id,
                        type: .approval,
                        metadata: [
                            "approvalId": id.uuidString,
                            "decision": decision.rawValue,
                            "source": "inbox",
                        ]
                    )
                    // Route through the relay's single forwarding chokepoint so a
                    // dead/re-armed channel falls back to the backend relay rather
                    // than dropping the decision (MAJOR-5). LiveInboxViewModel only
                    // fires onDecision when the DB row actually changed (B3).
                    await ApprovalRelay.shared.forwardDecisionOnly(
                        approvalID: id.uuidString,
                        decision: decision,
                        editedToolInput: editedToolInput
                    )
                },
                onPendingApprovalsChanged: { [weak vm] pendingCount, agentName, approvalID in
                    await vm?.setLiveActivityPendingApprovals(
                        pendingCount,
                        agentName: agentName,
                        approvalID: approvalID
                    )
                }
            )
            await MainActor.run {
                self.watchConnector.onEmergencyStop = { [weak vm] in
                    await vm?.disconnect()
                }
                self.watchConnector.onRunSnippet = { [weak vm] body in
                    await vm?.runCommand(body)
                }
                self.watchConnector.startSyncing(
                    approvalRepo: approvalRepo,
                    blockRepo: env.blockRepo,
                    snippetRepo: env.snippetRepo,
                    sessionViewModel: vm,
                    onDecision: { id, decision in
                        // Persist the watch decision to the local DB first
                        // (first-decision-wins). Only audit + forward when this
                        // call actually resolved the gate, so the inbox reflects
                        // watch decisions and a stale watch tap can't flip a
                        // decided gate (MAJOR-15 + B3).
                        let changed = (try? await approvalRepo.decide(id: id, decision: decision)) ?? false
                        guard changed else { return }
                        Notifications.shared.clearDeliveredApproval(id: id.uuidString)
                        try? await env.auditRepo.record(
                            hostID: host.id,
                            type: .approval,
                            metadata: [
                                "approvalId": id.uuidString,
                                "decision": decision.rawValue,
                                "source": "watch",
                            ]
                        )
                        await ApprovalRelay.shared.forwardDecisionOnly(
                            approvalID: id.uuidString,
                            decision: decision,
                            editedToolInput: nil
                        )
                    }
                )
                self.approvalRepository = approvalRepo
                self.liveInboxVM = liveVM
                self.inboxVM = liveVM  // replace static InboxViewModel
                // Fleet: register the new slot (additive — single-slot path above
                // is preserved for backwards compat with the current UI).
                // When the store is full (maxSlots reached), the add is a no-op.
                let slot = FleetStore.Slot(
                    hostID: host.id,
                    hostName: host.name,
                    sessionViewModel: vm,
                    channel: channel,
                    ingest: ingest,
                    inboxVM: liveVM
                )
                self.fleetStore.add(slot)
                if self.fleetStore.slots.contains(where: { $0.id == slot.id }) {
                    self.selectFleetSlot(slot.id)
                }
                // Finding #5: post-connect lands on MONITORING (Fleet), not the
                // full-screen block terminal. The session runs in the background
                // as a monitored slot; the terminal becomes an intentional
                // drill-in via the per-slot "open terminal" affordance (which
                // sets `isShowingLiveSession`). Do NOT auto-present it here.
                self.selectedTab = .fleet
                // MAJOR-4: re-arm the approval pipeline after a reconnect. The
                // DaemonChannel/ApprovalIngest die when the SSH client is swapped;
                // recreate + restart them and re-point the relay so new approvals
                // are ingested and decisions are delivered post-reconnect. Captures
                // only Sendable values (no `vm`, so no retain cycle).
                let fleet = self.fleetStore
                let quotaGuard = env.quotaGuardStore
                vm.onReconnected = { [fleet, quotaGuard, runOutputStore, slotID = slot.id, sshSession, host, approvalRepo, backendURL, deviceSessionID] in
                    if let existing = await fleet.slots.first(where: { $0.id == slotID }) {
                        await existing.ingest.stop()
                        await existing.channel.stop()
                    }
                    let newChannel = DaemonChannel(session: sshSession)
                    let newIngest = ApprovalIngest(channel: newChannel, repository: approvalRepo, hostName: host.name, runOutputStore: runOutputStore)
                    await fleet.rearm(slotID: slotID, channel: newChannel, ingest: newIngest)
                    try? await newChannel.start()
                    if !backendURL.isEmpty {
                        // registerDevice stores the per-session relayToken on the channel
                        // (currentRelayToken); setChannel below refreshes the relay from it.
                        _ = try? await newChannel.registerDevice(pushBackendURL: backendURL, sessionID: deviceSessionID)
                    }
                    await ApprovalRelay.shared.setChannel(newChannel)
                    await quotaGuard.setChannel(newChannel)
                    await newIngest.start()
                }
                self.scenePhaseObserver = ScenePhaseObserver(
                    onBecomeActive: { [weak vm] in
                        guard let vm else { return }
                        await vm.handleSceneActive()
                    },
                    onBackground: { [weak vm] in
                        guard let vm else { return }
                        let wasConnected = vm.status == .connected
                        await vm.handleSceneBackground()
                        if wasConnected {
                            await Notifications.shared.postSessionSuspended(
                                hostName: vm.host.name
                            )
                        }
                    }
                )
            }
            await vm.connect()
            if vm.status == .connected {
                try? await env.hostRepo.touch(id: host.id)
            }
            let daemonPath = (try? await DaemonBootstrap.ensureInstalled(session: sshSession, manifest: DaemonBootstrap.loadManifest())) ?? "$HOME/.conduit/bin/conduitd"
            try? await channel.start(daemonPath: daemonPath)  // launch conduitd serve on remote host
            // Register device with conduitd so APNs alerts reach this device when
            // backgrounded. The handshake reply carries the per-session relay
            // capability token — store it so backend-relayed decisions can
            // authenticate (B2). Same `deviceSessionID` is used here and for the
            // decision POST body so the backend looks up the right record.
            if !backendURL.isEmpty {
                let token = (try? await channel.registerDevice(pushBackendURL: backendURL, sessionID: deviceSessionID)) ?? nil
                if let token { ApprovalRelay.shared.setRelayToken(token) }
            }
            // Attach the relay so Live Activity / Dynamic Island decisions are
            // forwarded to conduitd, and drain any decisions queued while the
            // channel was absent (e.g. lock-screen tap before app foregrounded).
            await ApprovalRelay.shared.setChannel(channel)
            ApprovalRelay.shared.configureBackend(url: backendURL, sessionID: deviceSessionID)
            await ingest.start()
            await MainActor.run {
                env.quotaGuardStore.setChannel(channel)
                env.hostHealthStore.startPolling(fleetStore: self.fleetStore)
            }
            await env.quotaGuardStore.refresh()
        }
    }
}

private struct LaunchLockView: View {
    let onUnlock: () async -> Void
    @Environment(\.conduitTokens) private var t

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            PixelAvatar(seed: "conduit-lock", size: 64)
                .opacity(0.7)
            VStack(spacing: 8) {
                Text("Conduit")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(t.text1)
                Text("Authenticate to continue")
                    .font(.subheadline)
                    .foregroundStyle(t.text3)
            }
            Button("Unlock") { Task { await onUnlock() } }
                .buttonStyle(.borderedProminent)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(t.surf0)
    }
}

private struct SettingsWithLibraryView: View {
    let viewModel: SettingsViewModel
    let syncEngine: SyncEngine?
    let backendURL: String
    let auditRepository: AuditRepository?
    let approvalRepository: ApprovalRepository?
    var sshKeyStore: KeyStore? = nil
    var daemonChannel: DaemonChannel? = nil
    var e2eRelayClient: E2ERelayClient? = nil

    var body: some View {
        SettingsView(
            viewModel: viewModel,
            syncEngine: syncEngine,
            backendURL: backendURL,
            auditRepository: auditRepository,
            approvalRepository: approvalRepository,
            sshKeyStore: sshKeyStore,
            daemonChannel: daemonChannel,
            e2eRelayClient: e2eRelayClient
        )
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct GlobalInboxGateView: View {
    let onUpgrade: () -> Void
    @Environment(\.conduitTokens) private var t

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 48))
                .foregroundStyle(t.accent)
            Text("AI Agent Inbox · Pro")
                .font(.title3.weight(.semibold))
                .foregroundStyle(t.text1)
            Text("Review and approve AI agent actions from your sessions.")
                .font(.body)
                .foregroundStyle(t.text3)
                .multilineTextAlignment(.center)
            DSButton("Upgrade to Pro", systemImage: "sparkles", variant: .primary, action: onUpgrade)
            Spacer()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(t.surf0)
        .navigationTitle("Inbox")
    }
}

private struct PasswordPromptView: View {
    let host: Host
    let onConnect: (String) -> Void

    @State private var password = ""
    @Environment(\.dismiss) private var dismiss
    @Environment(\.conduitTokens) private var t
    @FocusState private var passwordFocused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                DSDetailHeader("connect", onBack: { dismiss() })

                // ── Host identity card
                card {
                    HStack(spacing: 12) {
                        PixelAvatar(seed: host.name, size: 44)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(host.name)
                                .font(.dsSansPt(16, weight: .semibold))
                                .foregroundStyle(t.text)
                                .lineLimit(1)
                            Text(host.displayAddress)
                                .font(.dsMonoPt(12))
                                .foregroundStyle(t.text3)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(14)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 18)

                // ── Password
                Text("PASSWORD")
                    .font(.dsMonoPt(11))
                    .tracking(0.8)
                    .foregroundStyle(t.text3)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 6)
                SecureField("Password", text: $password)
                    .font(.dsMonoPt(14))
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($passwordFocused)
                    .submitLabel(.go)
                    .onSubmit(connect)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .background(t.surfaceSunk)
                    .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: t.r3, style: .continuous)
                            .strokeBorder(t.border, lineWidth: 1)
                    )
                    .padding(.horizontal, 16)

                Spacer()

                // ── Connect CTA (content-width, centered — house style)
                HStack {
                    Spacer()
                    DSButton("Connect", variant: .primary, size: .lg, action: connect)
                        .disabled(password.isEmpty)
                    Spacer()
                }
                .padding(.bottom, 28)
            }
        }
        .presentationDetents([.medium])
        .onAppear {
            #if DEBUG
            // Live-loop E2E (CONDUIT_DAEMON_E2E=1): prefill the localhost password
            // from the launch env so the real connect flow can be driven without
            // typing into a secure field. DEBUG-only; never affects shipping.
            let e = ProcessInfo.processInfo.environment
            if e["CONDUIT_DAEMON_E2E"] == "1", password.isEmpty,
               let pw = e["CONDUIT_TEST_PW"], !pw.isEmpty {
                password = pw
            }
            #endif
            passwordFocused = true
        }
    }

    private func connect() {
        guard !password.isEmpty else { return }
        let value = password
        dismiss()
        onConnect(value)
    }

    @ViewBuilder
    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .background(t.surface)
            .clipShape(RoundedRectangle(cornerRadius: t.r4, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: t.r4, style: .continuous)
                    .strokeBorder(t.border, lineWidth: 1)
            )
    }
}

#endif
