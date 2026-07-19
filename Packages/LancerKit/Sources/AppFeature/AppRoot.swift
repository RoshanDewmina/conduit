#if os(iOS)
import SwiftUI
import UIKit
import Observation
import LancerCore
import AccountKit
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
import os

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
    /// CloudKit private-database mirror for the conversation ledger's
    /// already host-confirmed rows (Task 8) — separate zone and cadence
    /// from `syncEngine`'s Hosts/Snippets sync; see `ConversationSyncEngine`.
    public let conversationSyncEngine: ConversationSyncEngine
    public let tombstoneRepo: SyncTombstoneRepository
    public let approvalRepo: ApprovalRepository
    public let auditRepo: AuditRepository
    public let quotaGuardStore: QuotaGuardStore
    public let chatRepo: ChatConversationRepository
    public let workspaceRepo: WorkspaceRepository
    public let accountSession: AccountSessionController
    /// Host-mediated conversation turn orchestration (Task 7) — the only place
    /// that should call `agent.conversations.append`/`.fetch` for UI-driven
    /// turns. Lives on the environment (not `AppRoot`, a `View` struct) so its
    /// per-conversation sync-state subscriptions survive view re-creation.
    public let conversationSyncCoordinator: ConversationSyncCoordinator

    public init() throws {
        self.database = try AppDatabase.openShared()
        self.hostRepo = HostRepository(database)
        self.snippetRepo = SnippetRepository(db: database)
        self.blockRepo = BlockRepository(database)
        self.snapshotRepo = SessionSnapshotRepository(database)
        self.chatRepo = ChatConversationRepository(database)
        self.workspaceRepo = WorkspaceRepository(database)
        self.conversationSyncCoordinator = ConversationSyncCoordinator(chatRepo: chatRepo)
        self.keyStore = KeyStore()
        self.hostKeyStore = HostKeyStore()
        self.aiKeyStore = KeychainAIKeyStore()
        self.tombstoneRepo = SyncTombstoneRepository(database)
        let cloudKitEnabled = Bundle.main.object(forInfoDictionaryKey: "LANCER_ICLOUD_ENABLED") as? Bool ?? false
        let cloudSync = CloudSync(cloudKitEnabled: cloudKitEnabled)
        let ks = self.keyStore
        self.syncEngine = SyncEngine(
            cloudSync: cloudSync,
            hostRepo: HostRepository(database),
            snippetRepo: SnippetRepository(db: database),
            tombstoneRepo: SyncTombstoneRepository(database),
            keyStore: ks
        )
        self.conversationSyncEngine = ConversationSyncEngine(
            cloudSync: cloudSync,
            chatRepo: chatRepo
        )
        self.approvalRepo = ApprovalRepository(database)
        self.auditRepo = AuditRepository(database)
        self.quotaGuardStore = QuotaGuardStore()
        self.accountSession = AccountSessionController(
            client: SupabaseAccountClient(configuration: .fromBundle())
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
        self.keychain = Keychain(service: "dev.lancer.mobile.aikeys")
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

/// Thin composition root: first-run onboarding gate, then the Workspaces
/// shell (owner override — no tab bar). `AppEnvironment` is constructed here
/// so engines survive view recreation; pairing / chat / approvals wire in via
/// environment objects on `readyRoot`.
public struct AppRoot: View {
    @State private var environment: AppEnvironmentResult
    /// M2: relay pairing / trusted-machines fleet state, hydrated from the
    /// persisted pairing index on launch and injected via `.environment(_:)`
    /// so Settings can pair/list/remove real (non-mocked) machines.
    @State private var relayFleetStore = RelayFleetStore()
    /// M3: constructed in `init()` (needs `conversationSyncCoordinator`/
    /// `chatRepo` from `AppEnvironment`, so only non-nil when `environment`
    /// is `.ready`) and injected via `.environment(_:)` alongside
    /// `relayFleetStore`, same pattern.
    @State private var shellLiveBridge: ShellLiveBridge?
    /// M4: listens for relay-delivered pending approvals and publishes them
    /// for `LiveThreadView`'s approval card. Same construction constraint as
    /// `shellLiveBridge` — needs `env.database`, so only non-nil once
    /// `AppEnvironment` construction has succeeded.
    @State private var relayApprovalIngest: RelayApprovalIngest?
    /// In-thread questions: listens for relay-delivered pending questions and
    /// publishes them for `LiveThreadView`'s question card. Same construction
    /// constraint as `relayApprovalIngest` — needs `env.chatRepo`.
    @State private var relayQuestionIngest: RelayQuestionIngest?
    /// Live tool artifacts over relay → local mirror (background-tasks pill / chips).
    @State private var relayArtifactIngest: RelayArtifactIngest?
    /// Forwards the APNs device token / Live Activity push token to every
    /// currently-paired daemon once each is available — see
    /// `DevicePushRegistrationCoordinator`. Doesn't actually need
    /// `AppEnvironment` (only `relayFleetStore`), but is scoped optional like
    /// its siblings above for construction-order consistency.
    @State private var devicePushRegistration: DevicePushRegistrationCoordinator?
    /// Derived + user-added workspace repos for the Workspaces shell.
    @State private var workspaceDataStore: WorkspaceDataStore?
    /// Phase 1 interactive SSH terminal presentation.
    @State private var terminalCoordinator: TerminalSessionCoordinator?
    /// First-run onboarding gate — once true, `readyRoot` is shown thereafter.
    /// Launch arg `-onboardingSeen YES` registers into UserDefaults automatically;
    /// UITests also set `LANCER_SKIP_CURSOR_ONBOARDING`.
    @AppStorage("onboardingSeen") private var onboardingSeen = false
    #if DEBUG
    /// Prevents child destination hooks from racing the deterministic UITest reset.
    @State private var isUITestSeedReady: Bool
    #endif

    enum AppEnvironmentResult {
        case ready(AppEnvironment)
        case failure(String)
    }

    public init() {
        let fleetStore = RelayFleetStore()
        _relayFleetStore = State(initialValue: fleetStore)
        #if DEBUG
        _isUITestSeedReady = State(
            initialValue: ProcessInfo.processInfo.environment["LANCER_UITEST_RESEED"] != "1"
        )
        #endif
        do {
            let env = try AppEnvironment()
            _environment = State(initialValue: .ready(env))
            let failedCwds = FailedCwdStore()
            // M3: constructed here (not lazily in `body`) because mutating
            // `@State` during view-body evaluation is disallowed — needs
            // `env.conversationSyncCoordinator`/`env.chatRepo`, only
            // available once `AppEnvironment` construction has succeeded.
            _shellLiveBridge = State(initialValue: ShellLiveBridge(
                relayFleetStore: fleetStore,
                conversationSyncCoordinator: env.conversationSyncCoordinator,
                chatRepo: env.chatRepo,
                failedCwds: failedCwds
            ))
            _relayApprovalIngest = State(initialValue: RelayApprovalIngest(database: env.database))
            _relayQuestionIngest = State(initialValue: RelayQuestionIngest(chatRepo: env.chatRepo))
            _relayArtifactIngest = State(initialValue: RelayArtifactIngest(chatRepo: env.chatRepo))
            _devicePushRegistration = State(initialValue: DevicePushRegistrationCoordinator(fleetStore: fleetStore))
            let workspaceStore = WorkspaceDataStore(
                chatRepo: env.chatRepo,
                failedCwds: failedCwds
            )
            let coordinator = env.conversationSyncCoordinator
            // Capture the same fleet instance wired into ShellLiveBridge so
            // list-status refresh uses the live relay bridge when connected.
            let fleet = fleetStore
            workspaceStore.syncRunningStatuses = {
                // Same hydration race as ShellLiveBridge.waitForConnectedMachine
                // (2026-07-10): firstConnectedMachine read once at call time is
                // nil during launch/reconnect. Wait briefly for the relay to
                // come back before giving up on this refresh cycle.
                var connected = fleet.firstConnectedMachine
                let deadline = Date().addingTimeInterval(8)
                while connected == nil, Date() < deadline {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    connected = fleet.firstConnectedMachine
                }
                guard let machine = connected else { return }
                do {
                    let response = try await machine.bridge.relayListConversations(
                        ConversationListRequest(limit: 50)
                    )
                    if let error = response.error, !error.isEmpty { return }
                    await coordinator.mergeConversationSummaries(
                        response.conversations,
                        hostName: machine.record.displayName,
                        hostID: machine.id.uuidString
                    )
                } catch {
                    // No transport / not connected — list keeps rendering local rows.
                }
            }
            workspaceStore.refreshThreadFromHost = { conversationID in
                var connected = fleet.firstConnectedMachine
                let deadline = Date().addingTimeInterval(8)
                while connected == nil, Date() < deadline {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    connected = fleet.firstConnectedMachine
                }
                guard let machine = connected else {
                    throw E2EError.notPaired
                }
                let transport = ConversationTransport(
                    append: { try await machine.bridge.relayAppendConversation($0) },
                    fetch: { try await machine.bridge.relayFetchConversation($0) },
                    archive: { try await machine.bridge.relayArchiveConversation($0) }
                )
                // Never `try?` — a timed-out/partial import must surface so
                // ThreadDetail can keep local text and offer retry.
                _ = try await coordinator.refreshConversation(
                    conversationID: conversationID, transport: transport
                )
            }
            _workspaceDataStore = State(initialValue: workspaceStore)
            _terminalCoordinator = State(initialValue: TerminalSessionCoordinator(
                relayFleetStore: fleetStore
            ))
        } catch {
            _environment = State(initialValue: .failure(error.localizedDescription))
            _shellLiveBridge = State(initialValue: nil)
            _relayApprovalIngest = State(initialValue: nil)
            _relayQuestionIngest = State(initialValue: nil)
            _relayArtifactIngest = State(initialValue: nil)
            _devicePushRegistration = State(initialValue: nil)
            _workspaceDataStore = State(initialValue: nil)
            _terminalCoordinator = State(initialValue: nil)
        }
    }

    public var body: some View {
        switch environment {
        case .failure(let message):
            ContentUnavailableView(
                "Failed to start",
                systemImage: "exclamationmark.triangle",
                description: Text(message)
            )
        case .ready(let env):
            #if DEBUG
            if isUITestSeedReady {
                gatedRoot
            } else {
                ProgressView()
                    .task {
                        await DebugSeeder.resetForUITestIfRequested(env: env)
                        await DebugSeeder.seedIfNeeded(env: env)
                        await DebugSeeder.seedTranscriptIfRequested(env: env)
                        await DebugSeeder.seedLongTranscriptIfRequested(env: env)
                        isUITestSeedReady = true
                    }
            }
            #else
            gatedRoot
            #endif
        }
    }

    /// Shows the 2-screen first-run gate until dismissed; DEBUG deep-links
    /// (`LANCER_DESTINATION`) and the UITest seam (`LANCER_SKIP_CURSOR_ONBOARDING=1`)
    /// skip it so tests still land on Workspaces.
    @ViewBuilder
    private var gatedRoot: some View {
        if shouldShowOnboarding {
            OnboardingGateView {
                onboardingSeen = true
            }
            .environment(relayFleetStore)
        } else {
            readyRoot
        }
    }

    private var shouldShowOnboarding: Bool {
        if onboardingSeen { return false }
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        if env["LANCER_DESTINATION"] != nil || env["LANCER_SKIP_CURSOR_ONBOARDING"] == "1" {
            return false
        }
        #endif
        return true
    }


    @ViewBuilder
    private var readyRoot: some View {
        if let shellLiveBridge, let relayApprovalIngest, let relayQuestionIngest, let workspaceDataStore, let terminalCoordinator {
            NavigationStack {
                WorkspacesView()
            }
            .environment(relayFleetStore)
            .environment(shellLiveBridge)
            .environment(relayApprovalIngest)
            .environment(relayQuestionIngest)
            .environment(workspaceDataStore)
            .environment(terminalCoordinator)
            .fullScreenCover(
                isPresented: Binding(
                    get: { terminalCoordinator.presentedModel != nil },
                    set: { presented in
                        if !presented { terminalCoordinator.dismissTerminal() }
                    }
                ),
                onDismiss: { terminalCoordinator.dismissTerminal() }
            ) {
                if let model = terminalCoordinator.presentedModel {
                    LiveTerminalView(model: model)
                }
            }
            .task {
                relayApprovalIngest.start()
                relayQuestionIngest.start()
                relayArtifactIngest?.start()
                devicePushRegistration?.start()
                // Fire-and-forget: registerForRemoteNotifications() (AppDelegate) captures a
                // device token without this, but iOS silently drops every alert-payload push
                // (approvals, questions, run-complete) unless the user has actually granted
                // alert authorization — with no system UI ever surfacing to explain why, since
                // an app that has never called this has no Notifications row in Settings at
                // all. Found 2026-07-19 live-testing PR #176's app-closed push fix: the whole
                // daemon->push-backend->APNs pipeline reported success (backend 204, Apple 200)
                // but nothing ever appeared on a locked phone because this call was missing
                // entirely. Detached so the first-launch system permission sheet doesn't block
                // the rest of hydration below.
                Task { _ = await Notifications.shared.requestAuthorization() }
                await RelayFleetHydration.hydrate(into: relayFleetStore)
                shellLiveBridge.markHydrated()
                await workspaceDataStore.refresh()
                // Wait briefly for the relay to become connected, then
                // cache installed vendor CLIs for the New Chat agent picker.
                var connected = relayFleetStore.firstConnectedMachine
                let deadline = Date().addingTimeInterval(8)
                while connected == nil, Date() < deadline {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    connected = relayFleetStore.firstConnectedMachine
                }
                await RelayFleetHydration.refreshInstalledAgents(into: relayFleetStore)
                #if DEBUG
                await DebugSeeder.autoPairRelayIfRequested(into: relayFleetStore)
                #endif
            }
        }
    }
}

extension Notification.Name {
    static let lancerChatArtifactPersisted = Notification.Name("lancerChatArtifactPersisted")
    static let lancerSavedHostsDidChange = Notification.Name("lancerSavedHostsDidChange")
}

#endif
