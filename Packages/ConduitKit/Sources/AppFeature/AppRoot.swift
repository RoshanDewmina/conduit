#if os(iOS)
import SwiftUI
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

/// The single composition root. The whole app graph is wired in `init`.
/// One source of truth for environment, navigation, and dependencies.
@MainActor @Observable
public final class AppEnvironment {
    public let database: AppDatabase
    public let hostRepo: HostRepository
    public let blockRepo: BlockRepository
    public let keyStore: KeyStore
    public let aiKeyStore: any AIKeyStoring
    public let hostKeyStore: HostKeyStore

    public init() throws {
        self.database = try AppDatabase.openShared()
        self.hostRepo = HostRepository(database)
        self.blockRepo = BlockRepository(database)
        self.keyStore = KeyStore()
        self.hostKeyStore = HostKeyStore()
        self.aiKeyStore = KeychainAIKeyStore()
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
    @State private var inboxVM = InboxViewModel()
    @AppStorage("onboardingSeen") private var onboardingSeen = false
    @Environment(\.scenePhase) private var scenePhase

    // M3 — ScenePhaseObserver wiring.
    // `onBecomeActive` calls `sessionViewModel?.handleSceneActive()` once
    // SessionViewModel.handleSceneActive() is merged from the M3 VM patch.
    @State private var scenePhaseObserver = ScenePhaseObserver(
        onBecomeActive: {
            // TODO: call sessionViewModel?.handleSceneActive() once M3 VM patch is merged.
        },
        onBackground: {
            // TODO: suspend / detach from tmux when needed.
        }
    )

    public enum Tab: Hashable { case workspaces, session, inbox, settings }

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
        .task { _ = await Notifications.shared.requestAuthorization() }
        // M3 — propagate scene-phase changes to the observer.
        .onChange(of: scenePhase) { _, newPhase in
            Task { await scenePhaseObserver.scenePhaseChanged(to: newPhase) }
        }
    }

    @ViewBuilder
    private func readyRoot(env: AppEnvironment) -> some View {
        Group {
            if onboardingSeen {
                AdaptiveRoot {
                    rootTabs(env: env)
                } detail: {
                    NavigationStack {
                        if let vm = sessionViewModel {
                            SessionView(viewModel: vm)
                        } else {
                            ContentUnavailableView(
                                "No active session",
                                systemImage: "terminal",
                                description: Text("Pick a host from Workspaces to begin.")
                            )
                        }
                    }
                }
            } else {
                OnboardingView {
                    onboardingSeen = true
                    addHostPresented = true
                    selectedTab = .workspaces
                }
            }
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
    }

    @ViewBuilder
    private func rootTabs(env: AppEnvironment) -> some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                WorkspacesView(
                    viewModel: WorkspacesViewModel(repository: env.hostRepo),
                    onSelect: { host in openSession(host: host, env: env) },
                    onAddHost: { addHostPresented = true }
                )
            }
            .tabItem { Label("Workspaces", systemImage: "server.rack") }
            .tag(Tab.workspaces)

            NavigationStack {
                if let vm = sessionViewModel {
                    SessionView(viewModel: vm)
                } else {
                    ContentUnavailableView(
                        "No active session",
                        systemImage: "terminal",
                        description: Text("Pick a host from Workspaces to begin.")
                    )
                }
            }
            .tabItem { Label("Session", systemImage: "terminal") }
            .tag(Tab.session)

            NavigationStack {
                InboxView(viewModel: inboxVM)
            }
            .tabItem { Label("Inbox", systemImage: "tray") }
            .badge(inboxVM.approvals.filter(\.isPending).count)
            .tag(Tab.inbox)

            NavigationStack {
                SettingsView(viewModel: SettingsViewModel(keyStore: env.aiKeyStore))
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            NavigationLink {
                                SnippetEditorView()
                            } label: { Label("Snippets", systemImage: "text.quote") }
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            NavigationLink {
                                KeysView(viewModel: KeysViewModel(store: env.keyStore))
                            } label: { Label("SSH Keys", systemImage: "key") }
                        }
                    }
            }
            .tabItem { Label("Settings", systemImage: "gear") }
            .tag(Tab.settings)
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
            await MainActor.run {
                self.sessionViewModel = vm
                self.selectedTab = .session
            }
        }
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
