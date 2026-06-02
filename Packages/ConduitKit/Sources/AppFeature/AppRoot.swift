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
    public let keyStore: KeyStore
    public let aiKeyStore: any AIKeyStoring
    public let hostKeyStore: HostKeyStore
    public let syncEngine: SyncEngine
    public let approvalRepo: ApprovalRepository
    public let auditRepo: AuditRepository

    public init() throws {
        self.database = try AppDatabase.openShared()
        self.hostRepo = HostRepository(database)
        self.snippetRepo = SnippetRepository(db: database)
        self.blockRepo = BlockRepository(database)
        self.keyStore = KeyStore()
        self.hostKeyStore = HostKeyStore()
        self.aiKeyStore = KeychainAIKeyStore()
        let cloudKitEnabled = Bundle.main.object(forInfoDictionaryKey: "ConduitCloudKitEnabled") as? Bool == true
        let cloudSync = CloudSync(cloudKitEnabled: cloudKitEnabled)
        self.syncEngine = SyncEngine(
            cloudSync: cloudSync,
            hostRepo: HostRepository(database),
            snippetRepo: SnippetRepository(db: database)
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
    @State private var selectedTab: Tab = .sessions
    @State private var sessionViewModel: SessionViewModel?
    @State private var addHostPresented = false
    @State private var editingHost: Host?
    @State private var workspacesRevision = UUID()
    @State private var passwordPromptHost: Host?
    @State private var connectionError: String?
    @State private var inboxVM = InboxViewModel()
    @State private var liveInboxVM: LiveInboxViewModel?
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

    private var isPro: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["CONDUIT_FORCE_PRO"] == "1" { return true }
        #endif
        switch pm.purchaseState {
        case .purchased, .unknown: return true
        default: return false
        }
    }

    public enum Tab: Hashable, Sendable {
        case sessions    // Sessions Home (was: session)
        case hosts       // Host list (was: workspaces)
        case inbox
        case settings

        static let rootTabs: [Tab] = [.sessions, .hosts, .inbox, .settings]

        var title: String {
            switch self {
            case .sessions:  "Sessions"
            case .hosts:     "Hosts"
            case .inbox:     "Inbox"
            case .settings:  "Settings"
            }
        }

        var systemImage: String {
            switch self {
            case .sessions:  "bubble.left.and.text.bubble.right"
            case .hosts:     "server.rack"
            case .inbox:     "tray"
            case .settings:  "gear"
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
            case "settings": _selectedTab = State(initialValue: .settings)
            default:         _selectedTab = State(initialValue: .sessions)
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
            await Notifications.shared.registerCategories()
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
                HostEditorView(
                    viewModel: HostEditorViewModel(repository: env.hostRepo, keyStore: env.keyStore) { host in
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
        if horizontalSizeClass == .regular {
            regularRoot(env: env)
        } else {
            compactRoot(env: env)
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

    private func compactRoot(env: AppEnvironment) -> some View {
        TabView(selection: $selectedTab) {
            rootDestination(.sessions, env: env)
                .tabItem { Label(Tab.sessions.title, systemImage: Tab.sessions.systemImage) }
                .tag(Tab.sessions)

            NavigationStack {
                rootDestination(.hosts, env: env)
            }
            .tabItem { Label(Tab.hosts.title, systemImage: Tab.hosts.systemImage) }
            .tag(Tab.hosts)

            NavigationStack {
                rootDestination(.inbox, env: env)
            }
            .tabItem { Label(Tab.inbox.title, systemImage: Tab.inbox.systemImage) }
            .badge(activeInboxViewModel.approvals.filter(\.isPending).count)
            .tag(Tab.inbox)

            NavigationStack {
                rootDestination(.settings, env: env)
            }
            .tabItem { Label(Tab.settings.title, systemImage: Tab.settings.systemImage) }
            .tag(Tab.settings)
        }
        .toolbarBackground(Color(uiColor: .systemGroupedBackground), for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }

    private func regularRoot(env: AppEnvironment) -> some View {
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

    @ViewBuilder
    private func sessionsHome(env: AppEnvironment) -> some View {
        SessionsHomeView(
            liveSession: sessionViewModel,
            liveInboxVM: liveInboxVM,
            hostRepo: env.hostRepo,
            blockRepo: env.blockRepo,
            onTapLiveSession: { selectedTab = .sessions },
            onAddSession: {
                addHostPresented = true
                selectedTab = .hosts
            }
        )
    }

    @ViewBuilder
    private func rootDestination(_ tab: Tab, env: AppEnvironment) -> some View {
        switch tab {
        case .sessions:
            sessionsHome(env: env)

        case .hosts:
            WorkspacesView(
                viewModel: WorkspacesViewModel(repository: env.hostRepo),
                onSelect: { host in openSession(host: host, env: env) },
                onEdit: { host in editingHost = host },
                onAddHost: { addHostPresented = true },
                onAddHostGated: isPro ? nil : {
                    paywallFeatureName = "Unlimited SSH Hosts"
                    showingPaywall = true
                }
            )
            .id(workspacesRevision)

        case .inbox:
            if isPro {
                InboxView(viewModel: activeInboxViewModel)
            } else {
                GlobalInboxGateView {
                    paywallFeatureName = "AI Agent Inbox"
                    showingPaywall = true
                }
            }
        case .settings:
            SettingsView(
                viewModel: SettingsViewModel(keyStore: env.aiKeyStore),
                syncEngine: env.syncEngine,
                backendURL: Self.pushBackendURL(),
                auditRepository: env.auditRepo
            )
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            if let agentStore {
                                NavigationLink {
                                    LibraryView(
                                        snippetRepo: env.snippetRepo,
                                        keyStore: env.keyStore,
                                        agentStore: agentStore
                                    )
                                } label: {
                                    Label("Library", systemImage: "square.grid.2x2")
                                }
                                NavigationLink {
                                    AgentsView(store: agentStore)
                                } label: {
                                    Label("Hosted Agents", systemImage: "sparkles")
                                }
                            }
                            NavigationLink {
                                SnippetEditorView(repository: env.snippetRepo)
                            } label: {
                                Label("Snippets", systemImage: "text.quote")
                            }
                            NavigationLink {
                                KeysView(viewModel: KeysViewModel(store: env.keyStore))
                            } label: {
                                Label("SSH Keys", systemImage: "key")
                            }
                        } label: {
                            Label("Manage", systemImage: "ellipsis.circle")
                        }
                    }
                }
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
                onDecision: { [channel] id, decision in
                    try? await env.auditRepo.record(
                        hostID: host.id,
                        type: .approval,
                        metadata: [
                            "approvalId": id.uuidString,
                            "decision": decision.rawValue,
                            "source": "inbox",
                        ]
                    )
                    try? await channel.respond(approvalId: id.uuidString, decision: decision)
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
                self.approvalRepository = approvalRepo
                self.daemonChannel = channel
                self.approvalIngest = ingest
                self.liveInboxVM = liveVM
                self.inboxVM = liveVM  // replace static InboxViewModel
                self.selectedTab = .sessions
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

    var body: some View {
        NavigationStack {
            Form {
                Section("Host") {
                    LabeledContent("Address", value: host.displayAddress)
                }
                Section("Password") {
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                }
            }
            .navigationTitle("Connect")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Connect") {
                        let value = password
                        dismiss()
                        onConnect(value)
                    }
                    .disabled(password.isEmpty)
                }
            }
        }
    }
}

#endif
