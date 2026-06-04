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
        let cloudSync = CloudSync()
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
    @State private var selectedTab: Tab = .hosts
    @State private var sessionViewModel: SessionViewModel?
    @State private var addHostPresented = false
    @State private var editingHost: Host?
    @State private var workspacesRevision = UUID()
    @State private var passwordPromptHost: Host?
    @State private var connectionError: String?
    @State private var inboxVM = InboxViewModel()
    @State private var liveInboxVM: LiveInboxViewModel?
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

    private var isPro: Bool {
        #if DEBUG
        // RELEASE GATE: Pro is force-unlocked in all debug builds for UX evaluation.
        // Delete this block entirely before submitting to App Store.
        #warning("isPro always returns true in DEBUG — remove before App Store release")
        return true
        #else
        switch pm.purchaseState {
        case .purchased: return true
        // .unknown = purchase state not yet loaded; keep locked rather than granting free Pro.
        default: return false
        }
        #endif
    }

    public enum Tab: Hashable, Sendable {
        case hosts
        case inbox
        case library
        case settings

        static let rootTabs: [Tab] = [.hosts, .inbox, .library, .settings]

        var title: String {
            switch self {
            case .hosts:    "Hosts"
            case .inbox:    "Inbox"
            case .library:  "Library"
            case .settings: "Settings"
            }
        }

        var systemImage: String {
            switch self {
            case .hosts:    "server.rack"
            case .inbox:    "tray"
            case .library:  "square.grid.2x2"
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
            case "hosts":    _selectedTab = State(initialValue: .hosts)
            case "inbox":    _selectedTab = State(initialValue: .inbox)
            case "library":  _selectedTab = State(initialValue: .library)
            case "settings": _selectedTab = State(initialValue: .settings)
            default:         _selectedTab = State(initialValue: .hosts)
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
            Notifications.shared.registerCategories()
            _ = await Notifications.shared.requestAuthorization()
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
        }
        .onReceive(NotificationCenter.default.publisher(for: .conduitRunCompleteAction)) { _ in
            if sessionViewModel != nil { isShowingLiveSession = true }
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
        activeInboxViewModel.decide(ApprovalID(uuid), decision: decision)
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
                        selectedTab = .hosts
                    },
                    onSetupWorkspace: {
                        showingProvisioningWizard = true
                    }
                )
            }
        }
        .sheet(isPresented: $showingProvisioningWizard) {
            ProvisioningWizard(
                hostRepo: env.hostRepo,
                onComplete: { host in
                    showingProvisioningWizard = false
                    onboardingSeen = true
                    selectedTab = .hosts
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
                    AgentsView(store: agentStore)
                }
            }
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
        .sheet(isPresented: Binding(
            get: { sessionViewModel?.pendingHostKeyFingerprint != nil },
            set: { if !$0 { sessionViewModel?.rejectHostKey() } }
        )) {
            if let vm = sessionViewModel, let fp = vm.pendingHostKeyFingerprint {
                HostKeyConfirmSheet(
                    hostName: vm.host.name,
                    fingerprint: fp,
                    onTrust: { Task { await vm.trustHostKey() } },
                    onReject: { vm.rejectHostKey() }
                )
                .presentationDetents([.medium])
            }
        }
        .alert("Connection unavailable", isPresented: .constant(connectionError != nil), actions: {
            Button("OK") { connectionError = nil }
        }, message: {
            Text(connectionError ?? "")
        })
        .task {
            configureGlobalInbox(env: env)
            await configureCloudServices(env: env)
            await env.syncEngine.start()
        }
        .task {
#if DEBUG
            await DebugSeeder.seedIfNeeded(env: env)
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
            set: { selectedTab = $0 ?? .hosts }
        )
    }

    private var activeInboxViewModel: InboxViewModel {
        liveInboxVM ?? inboxVM
    }

    @MainActor
    private func configureGlobalInbox(env: AppEnvironment) {
        guard liveInboxVM == nil else { return }
        let approvalRepo = ApprovalRepository(env.database)
        let liveVM = LiveInboxViewModel(repository: approvalRepo)
        approvalRepository = approvalRepo
        liveInboxVM = liveVM
        inboxVM = liveVM
    }

    @Environment(\.conduitTokens) private var t

    private func compactRoot(env: AppEnvironment) -> some View {
        let inboxBadge = activeInboxViewModel.approvals.filter(\.isPending).count > 0
        let tabItems: [DSTabItem] = [
            DSTabItem(id: "hosts",    icon: .server,   label: "Hosts"),
            DSTabItem(id: "inbox",    icon: .inbox,    label: "Inbox", badge: inboxBadge),
            DSTabItem(id: "library",  icon: .list,     label: "Library"),
            DSTabItem(id: "settings", icon: .settings, label: "Settings"),
        ]

        let tabID = Binding<String>(
            get: {
                switch selectedTab {
                case .hosts:    "hosts"
                case .inbox:    "inbox"
                case .library:  "library"
                case .settings: "settings"
                }
            },
            set: { id in
                switch id {
                case "hosts":    selectedTab = .hosts
                case "inbox":    selectedTab = .inbox
                case "library":  selectedTab = .library
                case "settings": selectedTab = .settings
                default:         selectedTab = .hosts
                }
            }
        )

        return ZStack {
            t.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                PersistentStatusBar(
                    agents: isShowingLiveSession ? [] : hudStore.agents,
                    onTap: { if sessionViewModel != nil { isShowingLiveSession = true } },
                    // Manual retry after the auto-reconnect engine gives up
                    // (maxAttempts). `reconnect()` rebuilds a fresh engine, so this
                    // re-arms a session stuck in `.failed`.
                    onReconnect: sessionViewModel == nil ? nil : {
                        Task { await sessionViewModel?.reconnect() }
                    }
                )
                tabContent(env: env, tabItems: tabItems, tabID: tabID)
            }
        }
        .fullScreenCover(isPresented: $isShowingLiveSession) {
            if let vm = sessionViewModel {
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
        case .hosts:
            NavigationStack {
                rootDestination(.hosts, env: env)
                    .safeAreaInset(edge: .bottom, spacing: 0) { bar }
            }
        case .inbox:
            NavigationStack {
                rootDestination(.inbox, env: env)
                    .safeAreaInset(edge: .bottom, spacing: 0) { bar }
            }
        case .library:
            NavigationStack {
                rootDestination(.library, env: env)
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
                    onTap: { if sessionViewModel != nil { isShowingLiveSession = true } },
                    onReconnect: sessionViewModel == nil ? nil : {
                        Task { await sessionViewModel?.reconnect() }
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
                    rootDestination(selectedTab, env: env)
                }
            }
        }
        .fullScreenCover(isPresented: $isShowingLiveSession) {
            if let vm = sessionViewModel {
                SessionView(viewModel: vm)
                    .environment(\.conduitTokens, effectiveScheme == .dark ? .dark : .light)
            }
        }
    }

    /// Tear down the live session and clear it from the UI. Used by the
    /// active-row long-press menu and (indirectly) the in-session menu.
    private func disconnectLiveSession() {
        guard let vm = sessionViewModel else { return }
        // Capture the fleet slot ID before the async gap so we can remove it.
        let fleetSlotID = fleetStore.slots.first { $0.sessionViewModel === vm }?.id
        Task {
            await vm.disconnect()
            await MainActor.run {
                ApprovalRelay.shared.clearChannel()
                sessionViewModel = nil
                hudStore.session = nil
                if let slotID = fleetSlotID {
                    fleetStore.remove(id: slotID)
                }
            }
        }
    }

    @ViewBuilder
    private func rootDestination(_ tab: Tab, env: AppEnvironment) -> some View {
        switch tab {
        case .hosts:
            HostsView(
                liveSession: sessionViewModel,
                liveInboxVM: liveInboxVM,
                hostRepo: env.hostRepo,
                blockRepo: env.blockRepo,
                snapshotRepo: env.snapshotRepo,
                onTapLiveSession: { isShowingLiveSession = true },
                onDisconnectLiveSession: { disconnectLiveSession() },
                onAddHost: { addHostPresented = true },
                onSelect: { host in openSession(host: host, env: env) },
                onEdit: { host in editingHost = host }
            )
            .id(workspacesRevision)

        case .inbox:
            InboxView(
                viewModel: activeInboxViewModel,
                statusHeaderAgents: [],
                onTapStatusHeader: {}
            )

        case .library:
            if let agentStore {
                LibraryView(
                    snippetRepo: env.snippetRepo,
                    keyStore: env.keyStore,
                    agentStore: agentStore
                )
            } else {
                ProgressView("Loading library…")
            }

        case .settings:
            // The Library tab is the single hub for Library / Hosted Agents /
            // Snippets / SSH Keys — Settings no longer duplicates those routes
            // via an overflow "Manage" menu.
            SettingsView(
                viewModel: SettingsViewModel(keyStore: env.aiKeyStore),
                syncEngine: env.syncEngine,
                backendURL: Self.pushBackendURL(),
                auditRepository: env.auditRepo
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
        let deviceSessionID = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        Task {
            let aiClient = await env.aiClient(managedOpenRouterKey: pm.managedOpenRouterKey)
            let usageReporter: (@Sendable (UsageRecord) async -> Void)? = { [weak agentStore] record in
                await agentStore?.ingestUsage(record, runID: nil, agentID: nil)
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
            let ingest = ApprovalIngest(channel: channel, repository: approvalRepo, hostName: host.name)
            let liveVM = LiveInboxViewModel(
                repository: approvalRepo,
                onDecision: { [channel] id, decision, editedToolInput in
                    try? await env.auditRepo.record(
                        hostID: host.id,
                        type: .approval,
                        metadata: [
                            "approvalId": id.uuidString,
                            "decision": decision.rawValue,
                            "source": "inbox",
                        ]
                    )
                    try? await channel.respond(
                        approvalId: id.uuidString,
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
                    onDecision: { [channel] id, decision in
                        try? await env.auditRepo.record(
                            hostID: host.id,
                            type: .approval,
                            metadata: [
                                "approvalId": id.uuidString,
                                "decision": decision.rawValue,
                                "source": "watch",
                            ]
                        )
                        try? await channel.respond(approvalId: id.uuidString, decision: decision)
                    }
                )
                self.sessionViewModel = vm
                self.hudStore.session = vm
                self.approvalRepository = approvalRepo
                self.daemonChannel = channel
                self.approvalIngest = ingest
                self.liveInboxVM = liveVM
                self.inboxVM = liveVM  // replace static InboxViewModel
                // Fleet: register the new slot (additive — single-slot path above
                // is preserved for backwards compat with the current UI).
                // When the store is full (maxSlots reached), the add is a no-op.
                self.fleetStore.add(FleetStore.Slot(
                    hostID: host.id,
                    hostName: host.name,
                    sessionViewModel: vm,
                    channel: channel,
                    ingest: ingest,
                    inboxVM: liveVM
                ))
                self.selectedTab = .hosts
                self.isShowingLiveSession = true
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
            try? await channel.start()  // launch conduitd serve on remote host
            // Register device with conduitd so APNs alerts reach this device when backgrounded.
            if !backendURL.isEmpty {
                try? await channel.registerDevice(pushBackendURL: backendURL, sessionID: deviceSessionID)
            }
            // Attach the relay so Live Activity / Dynamic Island decisions are
            // forwarded to conduitd, and drain any decisions queued while the
            // channel was absent (e.g. lock-screen tap before app foregrounded).
            await ApprovalRelay.shared.setChannel(channel)
            await ingest.start()
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
                // ── Title row + close
                HStack {
                    Text("Connect")
                        .font(.dsDisplayPt(28, weight: .bold))
                        .foregroundStyle(t.text)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(t.text3)
                            .frame(width: 30, height: 30)
                            .background(t.surfaceSunk, in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 18)

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
        .onAppear { passwordFocused = true }
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
