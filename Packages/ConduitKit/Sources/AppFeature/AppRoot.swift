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

    public init() throws {
        self.database = try AppDatabase.openShared()
        self.hostRepo = HostRepository(database)
        self.snippetRepo = SnippetRepository(db: database)
        self.blockRepo = BlockRepository(database)
        self.keyStore = KeyStore()
        self.hostKeyStore = HostKeyStore()
        self.aiKeyStore = KeychainAIKeyStore()
        let cloudSync = CloudSync()
        self.syncEngine = SyncEngine(
            cloudSync: cloudSync,
            hostRepo: HostRepository(database),
            snippetRepo: SnippetRepository(db: database)
        )
        self.approvalRepo = ApprovalRepository(database)
    }

    public func aiClient(provider: AIProvider = .anthropic) async -> (any AIClient)? {
        switch provider {
        case .anthropic:
            guard let key = try? await aiKeyStore.loadAPIKey(provider: .anthropic) else { return nil }
            return AnthropicClient(apiKey: key)
        case .openai:
            guard let key = try? await aiKeyStore.loadAPIKey(provider: .openai) else { return nil }
            return OpenAIClient(apiKey: key)
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
    @State private var selectedTab: Tab = .workspaces
    @State private var sessionViewModel: SessionViewModel?
    @State private var addHostPresented = false
    @State private var passwordPromptHost: Host?
    @State private var connectionError: String?
    @State private var inboxVM = InboxViewModel(approvals: AppRoot.sampleApprovals)
    @State private var liveInboxVM: LiveInboxViewModel?
    @State private var approvalRepository: ApprovalRepository?
    @State private var daemonChannel: DaemonChannel?
    @State private var approvalIngest: ApprovalIngest?
    @State private var showingProvisioningWizard = false
    @AppStorage("onboardingSeen") private var onboardingSeen = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var scenePhaseObserver: ScenePhaseObserver?
    @State private var isUnlocked: Bool = false

    public enum Tab: Hashable, Sendable {
        case workspaces
        case session
        case inbox
        case settings

        static let rootTabs: [Tab] = [.workspaces, .session, .inbox, .settings]

        var title: String {
            switch self {
            case .workspaces: "Workspaces"
            case .session: "Session"
            case .inbox: "Inbox"
            case .settings: "Settings"
            }
        }

        var systemImage: String {
            switch self {
            case .workspaces: "server.rack"
            case .session: "terminal"
            case .inbox: "tray"
            case .settings: "gear"
            }
        }
    }

    private static let sampleApprovals: [Approval] = {
        let session = SessionID()
        return [
            Approval(id: .init(), sessionID: session, agent: .claudeCode, kind: .command,
                     command: "rm -rf ./dist && npm run build:prod", patch: nil,
                     cwd: "/home/ubuntu/myapp", risk: .high,
                     createdAt: Date(timeIntervalSinceNow: -30)),
            Approval(id: .init(), sessionID: session, agent: .claudeCode, kind: .command,
                     command: "git push origin main --force-with-lease", patch: nil,
                     cwd: "/home/ubuntu/myapp", risk: .medium,
                     createdAt: Date(timeIntervalSinceNow: -120)),
            Approval(id: .init(), sessionID: session, agent: .claudeCode, kind: .command,
                     command: "systemctl restart app.service", patch: nil,
                     cwd: "/home/ubuntu/myapp", risk: .low,
                     createdAt: Date(timeIntervalSinceNow: -300),
                     decidedAt: Date(timeIntervalSinceNow: -295),
                     decision: .approved),
        ]
    }()

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
    }

    public var body: some View {
        Group {
            if !isUnlocked {
                LaunchLockView(onUnlock: { await attemptUnlock() })
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
                }
            }
        }
        .task { await attemptUnlock() }
        .task {
            await Notifications.shared.registerCategories()
            _ = await Notifications.shared.requestAuthorization()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if let observer = scenePhaseObserver {
                Task { await observer.scenePhaseChanged(to: newPhase) }
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
                        selectedTab = .workspaces
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
                    selectedTab = .workspaces
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
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(250))
                            openSession(host: host, env: env)
                        }
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
            set: { selectedTab = $0 ?? .workspaces }
        )
    }

    private var activeInboxViewModel: InboxViewModel {
        liveInboxVM ?? inboxVM
    }

    private func compactRoot(env: AppEnvironment) -> some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                rootDestination(.workspaces, env: env)
            }
            .tabItem { Label(Tab.workspaces.title, systemImage: Tab.workspaces.systemImage) }
            .tag(Tab.workspaces)

            NavigationStack {
                rootDestination(.session, env: env)
            }
            .tabItem { Label(Tab.session.title, systemImage: Tab.session.systemImage) }
            .tag(Tab.session)

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
                    Label(tab.title, systemImage: tab.systemImage)
                        .tag(tab)
                }
            }
            .navigationTitle("Conduit")
        } detail: {
            NavigationStack {
                rootDestination(selectedTab, env: env)
            }
        }
    }

    @ViewBuilder
    private func rootDestination(_ tab: Tab, env: AppEnvironment) -> some View {
        switch tab {
        case .workspaces:
            WorkspacesView(
                viewModel: WorkspacesViewModel(repository: env.hostRepo),
                onSelect: { host in openSession(host: host, env: env) },
                onAddHost: { addHostPresented = true }
            )
        case .session:
            SessionShellView(
                viewModel: sessionViewModel,
                inboxViewModel: activeInboxViewModel
            )
        case .inbox:
            InboxView(viewModel: activeInboxViewModel)
        case .settings:
            SettingsView(viewModel: SettingsViewModel(keyStore: env.aiKeyStore), syncEngine: env.syncEngine)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            NavigationLink {
                                SnippetEditorView()
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
        Task {
            let aiClient = await env.aiClient(provider: .anthropic)
            let vm = SessionViewModel(
                host: host,
                sshSession: sshSession,
                credentialProvider: credentialProvider,
                hostKeyStore: env.hostKeyStore,
                aiClient: aiClient,
                blockRepo: env.blockRepo
            )
            let approvalRepo = ApprovalRepository(env.database)
            let channel = DaemonChannel(session: sshSession)
            let ingest = ApprovalIngest(channel: channel, repository: approvalRepo, hostName: host.name)
            let liveVM = LiveInboxViewModel(
                repository: approvalRepo,
                onDecision: { [channel] id, decision in
                    try? await channel.respond(approvalId: id.uuidString, decision: decision)
                }
            )
            await MainActor.run {
                self.sessionViewModel = vm
                self.approvalRepository = approvalRepo
                self.daemonChannel = channel
                self.approvalIngest = ingest
                self.liveInboxVM = liveVM
                self.inboxVM = liveVM  // replace static InboxViewModel
                self.selectedTab = .session
                self.scenePhaseObserver = ScenePhaseObserver(
                    onBecomeActive: { [weak vm] in
                        guard let vm else { return }
                        await vm.handleSceneActive()
                    },
                    onBackground: { [weak vm] in
                        guard let vm else { return }
                        if vm.status == .connected {
                            await Notifications.shared.postSessionSuspended(
                                hostName: vm.host.name
                            )
                        }
                    }
                )
            }
            await vm.connect()
            try? await channel.start()  // launch conduitd serve on remote host
            await ingest.start()
        }
    }
}

private struct LaunchLockView: View {
    let onUnlock: () async -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "lock.fill")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("Conduit is locked")
                .font(.title2.weight(.semibold))
            Button("Unlock") { Task { await onUnlock() } }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
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
