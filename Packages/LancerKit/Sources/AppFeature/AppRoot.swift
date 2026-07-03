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
import DesignSystem

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
        self.approvalRepo = ApprovalRepository(database)
        self.auditRepo = AuditRepository(database)
        self.loopStore = LoopStore(loopRepo: LoopRepository(database))
        self.quotaGuardStore = QuotaGuardStore()
        self.hostHealthStore = HostHealthStore()
        // Relay machine hydration (migrate legacy pairing + restore each paired
        // machine's client/bridge) now happens asynchronously after launch, from
        // the machines index — see `AppRoot.hydrateRelayFleetStore`.
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

/// Every secondary app flow enters through this route so presentation behavior
/// does not drift across screens as new sheets are added.
private enum AppDrawerRoute: Identifiable {
    case addMachine
    case relayPairing
    case addHost
    case editHost(Host)
    case activity

    var id: String {
        switch self {
        case .addMachine: "add-machine"
        case .relayPairing: "relay-pairing"
        case .addHost: "add-host"
        case .editHost(let host): "edit-host-\(host.id)"
        case .activity: "activity"
        }
    }
}

public struct AppRoot: View {
    @State private var environment: AppEnvironmentResult
    @State private var sessionViewModel: SessionViewModel?
    @State private var drawerRoute: AppDrawerRoute?
    @State private var workspacesRevision = UUID()
    /// One-shot hint set by Home's "+ New workspace" / a workspace screen's
    /// "New chat here" — consumed by `NewChatTabView.restoreLastSelectionOrDefault()`
    /// via `onMachineHintConsumed`, then cleared so it doesn't leak into the
    /// next unrelated New Chat entry.
    @State private var pendingNewChatMachineKey: String?
    @State private var pendingNewChatCwd: String?
    @State private var allWorkspaces: [Workspace] = []
    @State private var passwordPromptHost: Host?
    @State private var connectionError: String?
    @State private var inboxVM = InboxViewModel()
    @State private var liveInboxVM: LiveInboxViewModel?
    @State private var runOutputStore = RunOutputStore()
    @State private var hudStore = AgentHUDStore()
    @State private var approvalRepository: ApprovalRepository?
    @State private var daemonChannel: DaemonChannel?
    @State private var approvalIngest: ApprovalIngest?
    @State private var showingQuotaGuard = false
    @AppStorage("onboardingSeen") private var onboardingSeen = false
    @AppStorage(LancerAppearance.storageKey) private var colorSchemePref: String = LancerAppearance.light.rawValue
    @AppStorage(LancerAccentTheme.storageKey) private var accentPref: String = LancerAccentTheme.terracotta.rawValue
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var systemScheme

    private var appearance: LancerAppearance {
        LancerAppearance(rawValue: colorSchemePref) ?? .light
    }

    private var preferredScheme: ColorScheme? { appearance.preferredColorScheme }

    /// The scheme actually in effect: the Settings override if set, else the system.
    /// Drives the token palette so it always matches `preferredScheme`.
    private var effectiveScheme: ColorScheme {
        preferredScheme ?? systemScheme
    }

    @State private var scenePhaseObserver: ScenePhaseObserver?
    @State private var watchConnector = PhoneWatchConnector()
    @State private var pm = PurchaseManager.shared
    @State private var agentStore: AgentStore?
    @State private var showingPaywall = false
    @State private var paywallFeatureName = ""
    @State private var isShowingLiveSession = false
    @State private var showingRelayWorkspaceUnavailable = false
    @State private var relayFileBrowserMachineID: RelayMachineID?
    @State private var fleetStore = FleetStore()
    @State private var selectedFleetSlotID: UUID?
    @State private var relayFleetStore = RelayFleetStore()
    /// UI-test seam only: a fake relay entry seeded by `LANCER_FAKE_RELAY_HOST`,
    /// shown in Home in place of `relayFleetStore.machines` (see `homeDestination`).
    @State private var debugFakeRelayEntry: RelayHomeEntry?
    /// Idempotency guard for `configureRelayFleetStore` — it used to check
    /// `e2eBridge == nil`, but there's no single bridge anymore.
    @State private var configuredRelayFleetStore = false
    @State private var sidebarState = SidebarShellState()
    @GestureState private var drawerDrag: CGFloat = 0
    @State private var coachTour = CoachmarkTourState(steps: AppRoot.coachmarkSteps)

    /// One-time interactive tour shown after onboarding. Targets resolve against
    /// the sidebar anchors; steps with an unresolved target render centered.
    private static let coachmarkSteps: [CoachmarkStep] = [
        CoachmarkStep(id: "newChat", targetID: "newChat",
                      title: "Start a new thread",
                      body: "Tap here to spin up a fresh chat and dispatch an agent on one of your machines.",
                      systemImage: "plus.bubble"),
        CoachmarkStep(id: "inbox", targetID: "inbox",
                      title: "Approvals live here",
                      body: "Risky commands and spend limits that need your sign-off appear in the Inbox — approve or reject in a tap.",
                      usesPixelBoxHero: true),
        CoachmarkStep(id: "terminal", targetID: "terminal",
                      title: "Your machines & terminal",
                      body: "Connect a machine to open a live, Warp-style terminal and watch agents work in real time.",
                      systemImage: "desktopcomputer"),
        CoachmarkStep(id: "settings", targetID: "settings",
                      title: "You're all set",
                      body: "Connection, security, and billing all live in Settings. Enjoy Lancer!",
                      systemImage: "checkmark.circle",
                      primaryActionTitle: "Got it"),
    ]

    private var isPro: Bool {
        #if DEBUG
        // Debug builds default to the REAL purchase state so paywall/Pro gates are
        // exercised exactly as in Release. Opt in to a force-unlock for UX evaluation
        // with LANCER_FORCE_PRO=1. No DEBUG path ever grants free Pro in Release.
        if ProcessInfo.processInfo.environment["LANCER_FORCE_PRO"] == "1" { return true }
        #endif
        switch pm.purchaseState {
        case .purchased: return true
        // .unknown = purchase state not yet loaded; keep locked rather than granting free Pro.
        default: return false
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
        // UI-audit hook: launch directly into the sidebar shell. The legacy tab
        // router was removed; destinations are now the sole root navigation model.
        if let destination = ProcessInfo.processInfo.environment["LANCER_DESTINATION"] {
            // Launch seam lands directly in the shell — skip onboarding so the
            // destination is actually reached.
            UserDefaults.standard.set(true, forKey: "onboardingSeen")
            let state = SidebarShellState()
            switch destination {
            case "inbox": state.navigate(to: .needsAttention)
            // Governance folded into Settings (no longer a standalone sidebar root);
            // keep the launch seam value working by landing on Settings.
            case "governance": state.navigate(to: .settings)
            case "machines": state.navigate(to: .machines)
            case "sessions": state.navigate(to: .home)
            case "settings": state.navigate(to: .settings)
            default: state.navigate(to: .home)
            }
            _sidebarState = State(initialValue: state)
        }
        // UI-test seam: simulate a paired, live relay host so Home's machine list can
        // be verified without a live relay. `configureRelayFleetStore` early-returns
        // when this is set so the real bridge subscription doesn't clobber it.
        if let fakeRelayHost = ProcessInfo.processInfo.environment["LANCER_FAKE_RELAY_HOST"] {
            _debugFakeRelayEntry = State(initialValue: RelayHomeEntry(
                id: RelayMachineID(), name: fakeRelayHost, connected: true
            ))
        }
        #endif
    }

    @ViewBuilder
    public var body: some View {
        mainBody.environment(\.lancerTokens, tokens)
    }

    // The content tree, split out of mainBody so the Swift type-checker handles the
    // view hierarchy and the long .task/.onChange/.onReceive modifier chain as two
    // separate (faster) units instead of one expression that exceeded the limit.
    @ViewBuilder
    private var mainContent: some View {
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

    private var mainBody: some View {
        // Split into two modifier groups (ARCH-1): the Swift type-checker handles
        // each generic helper as its own unit, so neither one re-exceeds the
        // expression type-check limit the single 160-line chain used to hit.
        relayEventModifiers(lifecycleModifiers(mainContent))
    }

    /// App-lifecycle modifiers: launch tasks, onboarding/notification setup,
    /// scene-phase + app-lock handling, and the paywall sheet. Order within the
    /// group is immaterial — these are independent tasks/observers and one sheet.
    private func lifecycleModifiers(_ content: some View) -> some View {
        content
        .task { watchConnector.activate() }
        .task { await pm.load() }
        .task {
            if case .ready(let env) = environment {
                await env.accountSession.restore()
            }
        }
        .task {
            if case .ready(let env) = environment {
                await configureCloudServices(env: env)
            }
        }
        .task {
            if onboardingSeen {
                Notifications.shared.registerCategories()
                _ = await Notifications.shared.requestAuthorization()
            }
        }
        .onChange(of: onboardingSeen) { _, seen in
            if seen {
                Notifications.shared.registerCategories()
                Task { _ = await Notifications.shared.requestAuthorization() }
            }
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallSheet(featureName: paywallFeatureName)
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Live Activities are NOT ended on background: `.end()` is a one-way,
            // terminal ActivityKit call, and pushType: .token exists precisely so
            // push-backend can keep updating the activity while the app is
            // backgrounded or fully closed (ARCHITECTURE.md's documented
            // push-driven lifecycle). Only end an activity when the underlying
            // session/run actually terminates — see the LancerLiveActivityManager
            // .end(activityKey:) call sites elsewhere in this file.
            if let observer = scenePhaseObserver {
                Task { await observer.scenePhaseChanged(to: newPhase) }
            }
            // Re-register the APNs token on every foreground. Registration otherwise
            // only fired on a cold launch or relay-activation edge, so a warm
            // foreground — or any time the backend's in-memory session registry was
            // reset (e.g. a redeploy) — left the device unregistered and push silently
            // dropped. Cheap idempotent POST; covers both transports.
            if newPhase == .active {
                Task { @MainActor in await registerPushTokenForActiveTransport() }
            }
        }
    }

    /// Notification/relay-event observers: lock-screen approval actions and the
    /// E2E relay bridge's run-output/status/artifact/approval events, routed into
    /// the inbox + run stores.
    private func relayEventModifiers(_ content: some View) -> some View {
        content
        // Route lock-screen Approve/Reject notification actions into the same
        // decision path the in-app Inbox uses. LancerNotificationDelegate posts
        // these names; without an observer the buttons were silently dead.
        .onReceive(NotificationCenter.default.publisher(for: .lancerApprovalAction)) { note in
            handleApprovalAction(note)
            // Also drain the cold-launch buffer (MAJOR-6) so the decision is
            // persisted durably and the buffer never accumulates. Idempotent with
            // the line above (first-decision-wins).
            if case .ready(let env) = environment {
                Task { await drainPendingApprovalActions(env: env) }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .lancerRunCompleteAction)) { note in
            if
                let sessionID = note.userInfo?["sessionId"] as? String,
                let uuid = UUID(uuidString: sessionID),
                let slot = fleetStore.slots.first(where: { $0.sessionViewModel.sessionID.raw == uuid })
            {
                selectFleetSlot(slot.id)
            }
            if activeSessionViewModel != nil { isShowingLiveSession = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .lancerOpenApproval)) { note in
            // Route to the specific thread the approval belongs to (where the
            // in-chat approval card lives) rather than the generic Inbox list —
            // a notification is about ONE actionable thing, not "browse everything."
            // Inbox itself is unchanged and still reachable for browsing history.
            guard case .ready(let env) = environment,
                  let approvalIDString = note.userInfo?["approvalId"] as? String,
                  let approval = activeInboxViewModel.approvals.first(where: { $0.id.uuidString.lowercased() == approvalIDString.lowercased() })
            else {
                sidebarState.navigate(to: .needsAttention)
                return
            }
            let hostName = relayFleetStore.machines.first?.record.displayName ?? "Mac"
            Task { @MainActor in
                if let conversation = await FleetThreadMapper.findConversation(
                    hostName: hostName,
                    agentID: approval.agent.rawValue,
                    cwd: approval.cwd,
                    chatRepo: env.chatRepo
                ) {
                    sidebarState.navigate(to: .thread(id: conversation.id))
                } else {
                    sidebarState.navigate(to: .needsAttention)
                }
            }
        }
        // Relay run output/status: the E2ERelayBridge posts these as typed params.
        // Feed them into runOutputStore so the presented RunDetailView streams live.
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("lancerE2ERunOutput"))) { note in
            guard let params = note.userInfo?["params"] as? RunOutputParams else { return }
            runOutputStore.appendOutput(params)
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("lancerE2EToolStart"))) { note in
            guard let params = note.userInfo?["params"] as? ToolStartParams else { return }
            runOutputStore.appendToolStart(params)
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("lancerE2ERunStatus"))) { note in
            guard let params = note.userInfo?["params"] as? RunStatusParams else { return }
            runOutputStore.updateStatus(params)
            if case .ready(let env) = environment,
               params.status == "exited" || params.status == "failed" {
                // Persist the run's accumulated output back onto the turn so the
                // history view shows the real reply on reopen instead of
                // "(no output recorded)". (The live store is in-memory only.)
                let finalText = runOutputStore.run(params.runId)?.text ?? ""
                Task {
                    try? await env.chatRepo.updateTurnOutput(
                        runID: params.runId,
                        assistantText: finalText,
                        status: params.status == "exited" && params.exitCode == 0 ? .completed : .failed
                    )
                    try? await env.chatRepo.updateArtifactStatuses(
                        runID: params.runId,
                        status: params.status == "exited" && params.exitCode == 0 ? .done : .failed
                    )
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("lancerE2EArtifact"))) { note in
            guard let event = note.userInfo?["params"] as? AgentArtifactEvent,
                  case .ready(let env) = environment
            else { return }
            Task {
                guard let turn = try? await env.chatRepo.turnByRunID(event.runID) else { return }
                let artifact = ChatArtifact(
                    id: event.artifactID,
                    conversationID: turn.conversationID,
                    turnID: turn.id,
                    runID: event.runID,
                    kind: ChatArtifact.Kind(rawValue: event.kind) ?? .tool,
                    title: event.title,
                    summary: event.summary,
                    payloadJSON: event.payloadJSON,
                    status: ChatArtifact.Status(rawValue: event.status) ?? .running
                )
                try? await env.chatRepo.upsertArtifact(artifact)
                NotificationCenter.default.post(
                    name: .lancerChatArtifactPersisted,
                    object: nil,
                    userInfo: ["conversationID": turn.conversationID]
                )
            }
        }
        // Relay-delivered approvals: the E2E bridge posts lancerE2EApprovalReceived,
        // but on a relay-only setup there's no SSH ApprovalIngest to land them in the
        // inbox. Map the ApprovalData into an Approval and surface it in the active
        // inbox VM so the firewall request actually renders.
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("lancerE2EApprovalReceived"))) { note in
            guard let data = note.userInfo?["approvalData"] as? E2ERelayMessage.ApprovalData else { return }
            let approval = Approval(
                id: ApprovalID(UUID(uuidString: data.approvalID) ?? UUID()),
                sessionID: SessionID(),
                agent: Approval.AgentSource(rawValue: data.agent) ?? .unknown,
                kind: Approval.Kind(rawValue: data.kind) ?? .command,
                command: data.command,
                cwd: data.cwd ?? "",
                risk: Approval.Risk(rawValue: data.risk) ?? .medium,
                toolName: data.toolName,
                contentHash: data.contentHash
            )
            // Tag this approval with the machine it arrived from BEFORE inserting
            // it into the inbox VM, so the eventual decision routes back to that
            // specific machine's bridge (ApprovalRelay.forwardDecisionOnly step 0).
            if let machineID = note.userInfo?["machineID"] as? RelayMachineID {
                ApprovalRelay.shared.registerRelayOrigin(approvalID: data.approvalID, machineID: machineID)
            }
            let vm = activeInboxViewModel
            if !vm.approvals.contains(where: { $0.id == approval.id }) {
                vm.approvals.insert(approval, at: 0)
            }
            // Only a true relay-only setup (no fleet/SSH slot) needs this —
            // a slot's own inboxVM is already covered by FleetStore's
            // per-slot loop, so pointing relayInboxVM at it too would be
            // redundant (harmless, since attentionItems dedupes by approval
            // id, but there's no reason to point it at slot state at all).
            if selectedFleetSlot == nil {
                fleetStore.relayInboxVM = vm
            }
        }
        // The daemon resolved a pending approval without ever hearing back from
        // this client (its 120s fail-closed timeout fired). Mark it expired so
        // the stale card drops out of Home's pending list instead of sitting
        // there forever with no explanation — attentionItems already renders
        // .expired as a distinct, read-only state.
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("lancerE2EApprovalResolved"))) { note in
            guard let approvalIDString = note.userInfo?["approvalID"] as? String,
                  let uuid = UUID(uuidString: approvalIDString)
            else { return }
            let id = ApprovalID(uuid)
            for slot in fleetStore.slots {
                if let idx = slot.inboxVM.approvals.firstIndex(where: { $0.id == id }), slot.inboxVM.approvals[idx].isPending {
                    slot.inboxVM.approvals[idx].decision = .expired
                    slot.inboxVM.approvals[idx].decidedAt = .now
                }
            }
            if let vm = fleetStore.relayInboxVM,
               let idx = vm.approvals.firstIndex(where: { $0.id == id }), vm.approvals[idx].isPending {
                vm.approvals[idx].decision = .expired
                vm.approvals[idx].decidedAt = .now
            }
        }
    }

    /// Applies an Approve/Reject decision delivered from a notification action
    /// button via `Notification.Name.lancerApprovalAction`. Routes through
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
    /// `LancerNotificationDelegate` into `ApprovalActionBuffer` because the
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

    @ViewBuilder
    private func readyRoot(env: AppEnvironment) -> some View {
        Group {
            if onboardingSeen {
                rootContainer(env: env)
            } else {
                OnboardingRedesignView(
                    onContinue: {
                        onboardingSeen = true
                        sidebarState.navigate(to: .home)
                    },
                    accountSession: env.accountSession,
                    onPaired: { client, record in addRelayMachine(client: client, record: record, env: env) }
                )
            }
        }
        .sheet(isPresented: $showingQuotaGuard) {
            LancerDrawer(title: "Usage & limits", detents: [.large]) {
                QuotaGuardView(store: env.quotaGuardStore)
            }
        }
        .sheet(isPresented: $showingRelayWorkspaceUnavailable) {
            LancerDrawer(detents: [.large]) {
                RelayWorkspaceUnavailableView(onConnectSSH: { drawerRoute = .addMachine })
            }
        }
        .sheet(isPresented: Binding(
            get: { relayFileBrowserMachineID != nil },
            set: { if !$0 { relayFileBrowserMachineID = nil } }
        )) {
            if let machineID = relayFileBrowserMachineID, let bridge = relayFleetStore.machine(machineID)?.bridge {
                RelayFileBrowserView(bridge: bridge)
                    .environment(\.lancerTokens, tokens)
                    .preferredColorScheme(preferredScheme)
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
            .environment(\.lancerTokens, tokens)
            .preferredColorScheme(preferredScheme)
        }
        .sheet(item: $drawerRoute) { route in
            drawerDestination(route, env: env)
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
                .environment(\.lancerTokens, tokens)
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
            sidebarState.configure(chatRepo: env.chatRepo)
            await sidebarState.loadRecent()
            await configureCloudServices(env: env)
            // MAJOR-6: replay any approval action tapped from a lock-screen banner
            // while the app was killed (its NotificationCenter post had no live
            // subscriber). Done after configureCloudServices so the relay backend
            // is configured.
            await drainPendingApprovalActions(env: env)
            for approvalID in OpenApprovalBuffer.shared.drain() {
                // Cold launch: route to Inbox, then re-post so the now-mounted
                // InboxView observer opens the detail sheet. REVIEW intent only —
                // never auto-decides (ApprovalActionBuffer handles decisions separately).
                sidebarState.navigate(to: .needsAttention)
                NotificationCenter.default.post(
                    name: .lancerOpenApproval, object: nil,
                    userInfo: ["approvalId": approvalID]
                )
            }
            await env.syncEngine.start()
        }
        .task {
#if DEBUG
            if ProcessInfo.processInfo.environment["LANCER_SEED_DEMO"] == "1" {
                await DebugSeeder.seedIfNeeded(env: env)
            }
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
        // Single source of truth for "needs attention": fleetStore.attentionItems is
        // also what Home's attention list renders from, so the headline/sidebar badge
        // and the list can never disagree (previously this read activeInboxViewModel,
        // a single-slot fallback chain that could report a nonzero count while the
        // fleet-wide attention list rendered nothing).
        .onChange(of: fleetStore.attentionItems.count, initial: true) { _, count in
            hudStore.pendingApprovals = count
            sidebarState.pendingApprovalCount = count
            // Keep the real Dynamic Island / lock-screen Live Activity badge
            // live — this is the glanceable signal while Lancer is backgrounded.
            // Carry the most severe risk among current attention items so the
            // widget can visually distinguish a high/critical approval from a
            // routine one instead of rendering them identically.
            let highestRisk = fleetStore.attentionItems.map(\.severity.rawValue).max()
            if #available(iOS 16.2, *) {
                Task { await LancerLiveActivityManager.shared.updatePendingApprovals(count, highestRisk: highestRisk) }
            }
        }
        .onChange(of: fleetStore.slots.count, initial: true) { _, count in
            sidebarState.fleetSlotCount = count
        }
        // One-time interactive coach-mark tour. Overlay stays installed (cheap,
        // inert while inactive) but auto-start is OFF: on-device it mis-rendered
        // and trapped all input (auto-opened the drawer, then ate every tap with
        // no visible step to advance). ponytail: re-enable auto-start only after
        // the tour is verified working on a physical device.
        .coachmarkTour(coachTour)
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

    /// A workspace is a direct SSH capability. Relay dispatch keeps its governed
    /// control loop, but it does not become a shell or HTTP proxy — V1's Work
    /// Thread is a read-only activity log, so this never opens the live
    /// interactive terminal (`SessionView`), regardless of agent/host.
    ///
    /// `agent.hostID` is populated for relay agents with the owning machine's
    /// `RelayMachineID` (see `dispatchAgents()`), so this now routes to the
    /// correct machine's file browser instead of "the" single relay bridge. An
    /// SSH agent's `hostID` is an SSH `HostID`, which never matches a relay
    /// machine id — that falls through to "unavailable", same visible behavior
    /// as before (Work Thread's terminal is deferred to V2 regardless of transport).
    private func openWorkspace(for agent: DispatchAgent?) {
        guard let hostIDString = agent?.hostID, let uuid = UUID(uuidString: hostIDString) else {
            showingRelayWorkspaceUnavailable = true
            return
        }
        presentRelayWorkspace(machineID: RelayMachineID(uuid))
    }

    /// A relay-backed agent has no live SSH terminal, but a paired relay can still
    /// browse the host's files (read-only) over `agent.fs.ls`. Prefer that over the
    /// dead-end "workspace unavailable" sheet when the machine's bridge is active.
    @MainActor
    private func presentRelayWorkspace(machineID: RelayMachineID) {
        if relayFleetStore.machine(machineID)?.bridge.isActive == true {
            relayFileBrowserMachineID = machineID
        } else {
            showingRelayWorkspaceUnavailable = true
        }
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

    @ViewBuilder
    private func drawerDestination(_ route: AppDrawerRoute, env: AppEnvironment) -> some View {
        switch route {
        case .addMachine:
            LancerDrawer(
                title: "Add a machine",
                subtitle: "Relay is the recommended path. SSH adds a live terminal.",
                detents: [.medium, .large]
            ) {
                MachineConnectionChooser(
                    onRelay: { drawerRoute = .relayPairing },
                    onSSH: { drawerRoute = .addHost }
                )
            }
        case .relayPairing:
            LancerDrawer(detents: [.large]) {
                E2ERelayPairingView(
                    existingMachineCount: relayFleetStore.machines.count,
                    onPaired: { client, record in
                        addRelayMachine(client: client, record: record, env: env)
                    }
                )
            }
        case .addHost:
            LancerDrawer(detents: [.large]) {
                AddHostView(
                    repository: env.hostRepo,
                    keyStore: env.keyStore,
                    onCancel: { drawerRoute = nil },
                    onConnectAndSave: { host in
                        drawerRoute = nil
                        workspacesRevision = UUID()
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(250))
                            openSession(host: host, env: env)
                        }
                    }
                )
            }
        case .editHost(let host):
            LancerDrawer(detents: [.large]) {
                HostEditorView(
                    viewModel: HostEditorViewModel(
                        repository: env.hostRepo,
                        keyStore: env.keyStore,
                        existingHost: host
                    ) { _ in
                        drawerRoute = nil
                        workspacesRevision = UUID()
                    }
                )
            }
        case .activity:
            LancerDrawer(
                title: "Activity",
                subtitle: "What Lancer recorded while you were away.",
                detents: [.large]
            ) {
                ActivityView(
                    actions: bridgeSessionActions(),
                    auditRepository: env.auditRepo,
                    daemonChannel: daemonChannel,
                    showsHeader: false
                )
            }
        }
    }

    @MainActor
    private func configureGlobalInbox(env: AppEnvironment) {
        guard liveInboxVM == nil else { return }
        let approvalRepo = ApprovalRepository(env.database)
        let liveVM = LiveInboxViewModel(repository: approvalRepo) { id, decision, edited, contentHash in
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
                        editedToolInput: edited,
                        contentHash: contentHash
                    )
                    return
                } catch {
                    // dead/stopped channel — fall through to the relay
                }
            }
            await ApprovalRelay.shared.forwardDecisionOnly(
                approvalID: id.uuidString,
                decision: decision,
                editedToolInput: edited,
                contentHash: contentHash
            )
        }
        approvalRepository = approvalRepo
        liveInboxVM = liveVM
        inboxVM = liveVM
        // Wire Home's attention feed to the SAME live-observed VM immediately,
        // not only after the first live relay approval notification arrives
        // (the previous behavior — see the narrower reassignment in the
        // .lancerE2EApprovalReceived handler below). LiveInboxViewModel starts
        // observing the persisted approvals table the instant it's created, so
        // any approval that existed BEFORE this app launch (e.g. the app was
        // killed with one pending, or it was written while fully backgrounded)
        // was already visible in the real Inbox screen but invisible to Home's
        // "attentionItems"/headline until a brand-new live notification
        // happened to fire — a user could see "All clear tonight" while a
        // real, already-pending high-risk approval sat unreviewed. Safe to set
        // unconditionally per the dedupe-by-id note at the other call site.
        fleetStore.relayInboxVM = liveVM
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
    /// When the E2E relay is paired, a relay-mediated agent is also surfaced.
    @MainActor
    private func dispatchAgents() -> [DispatchAgent] {
        var agents: [DispatchAgent] = fleetStore.slots.flatMap { slot -> [DispatchAgent] in
            let offline = slot.sessionViewModel.status != .connected
            let cwd = slot.sessionViewModel.cwd.isEmpty ? "~" : slot.sessionViewModel.cwd
            return (slot.bridgeStatus?.agents ?? []).map { agent in
                DispatchAgent(
                    id: "\(slot.id.uuidString)|\(agent.agent)",
                    name: "\(agent.displayName) · \(slot.hostName)",
                    cwd: cwd,
                    isOffline: offline || !(agent.loggedIn ?? true),
                    hostID: slot.hostID.uuidString,
                    hostName: slot.hostName
                )
            }
        }
        // Each paired relay machine contributes its own agent set. The 3-part id
        // ("relay|<machineID>|<agentID>") gives every machine a distinct hostID,
        // which NewChatTabView's existing hostID-keyed grouping needs to show N
        // separate machine sections in the picker.
        for machine in relayFleetStore.machines {
            // Only offer agents the host actually has installed (reported over the
            // relay). Until that's known, show all four so a freshly-paired host
            // isn't empty.
            let vendors = machine.installedAgentVendors ?? ["claudeCode", "codex", "opencode", "kimi"]
            for agentID in vendors {
                let displayName: String
                switch agentID {
                case "claudeCode": displayName = "Claude Code"
                case "codex": displayName = "Codex"
                case "kimi": displayName = "Kimi"
                default: displayName = "OpenCode"
                }
                agents.append(DispatchAgent(
                    id: "relay|\(machine.id.uuidString)|\(agentID)",
                    // Just the agent name — the picker groups by machine and shows
                    // the host name as the section header. "Relay" is the transport,
                    // not the machine's name, so it must never be the label.
                    name: displayName,
                    cwd: "~",
                    isOffline: !machine.bridge.isActive,
                    hostID: machine.id.uuidString,
                    hostName: machine.record.displayName
                ))
            }
        }
        return agents
    }

    @MainActor
    /// Fetch an agent's live slash-commands for the composer autocomplete. Prefers a
    /// connected SSH slot's daemon channel; falls back to the relay bridge so a
    /// relay-paired host (no direct SSH) still lights up live commands. Returns []
    /// if neither transport is available — Lancer's own app-commands still
    /// autocomplete client-side.
    private func loadAgentCommands(cwd: String, vendor: String) async -> [AgentCommand] {
        if let slot = fleetStore.slots.first(where: { fleetStore.connectionState(for: $0) == .connected })
                ?? fleetStore.slots.first,
           let cmds = try? await slot.channel.listCommands(cwd: cwd, vendor: vendor), !cmds.isEmpty {
            return cmds
        }
        if let bridge = relayFleetStore.machines.first(where: { $0.bridge.isActive })?.bridge {
            return (try? await bridge.relayListCommands(cwd: cwd, vendor: vendor)) ?? []
        }
        return []
    }

    /// Continue a persisted conversation from History. A ledger-backed conversation
    /// (Task 6/7 — `syncState != .localOnly`) appends through the host's conversation
    /// ledger so another device sees the turn too; a legacy pre-ledger conversation
    /// falls back to continuing directly via the run's channel. Returns nil if no
    /// live transport can reach the conversation's host.
    private func resumeConversation(_ conv: ChatConversation, lastRunID: String, prompt: String, env: AppEnvironment) async -> ActiveChatRun? {
        if conv.syncState != .localOnly {
            // Ledger conversations live on ONE host's SQLite ledger — unlike the
            // legacy fallback below, there's no safe "any active machine" retry
            // if the exact owning host (SSH slot, else the paired relay machine)
            // isn't reachable.
            if let hostID = conv.hostID, let uuid = UUID(uuidString: hostID),
               let slot = fleetStore.slots.first(where: { $0.id == uuid }) {
                let channel = slot.channel
                let transport = ConversationTransport(
                    append: { try await channel.appendConversation($0) },
                    fetch: { try await channel.fetchConversation($0) },
                    archive: { try await channel.archiveConversation($0) }
                )
                let outcome = await env.conversationSyncCoordinator.continueConversation(
                    conversationID: conv.id, baseSeq: conv.lastHostSeq, prompt: prompt,
                    clientTurnID: Self.newClientTurnID(), model: conv.model, budgetUSD: conv.budgetUSD,
                    hostName: slot.hostName, hostID: slot.hostID.uuidString, transport: transport
                )
                if case .started(let run) = chatDispatchOutcome(from: outcome, channel: slot.channel, title: conv.title) {
                    return run
                }
                return nil
            }
            if let sourceHostID = conv.sourceHostID, let uuid = UUID(uuidString: sourceHostID),
               let machine = relayFleetStore.machine(RelayMachineID(uuid)) {
                let bridge = machine.bridge
                let transport = ConversationTransport(
                    append: { try await bridge.relayAppendConversation($0) },
                    fetch: { try await bridge.relayFetchConversation($0) },
                    archive: { try await bridge.relayArchiveConversation($0) }
                )
                let channel = RelayRunControl(
                    send: { rid, action in await bridge.sendRunControl(runId: rid, action: action) },
                    onContinue: { rid, p in try await bridge.sendRunContinue(runId: rid, prompt: p, agent: conv.agentID, cwd: conv.cwd, model: conv.model) }
                )
                let outcome = await env.conversationSyncCoordinator.continueConversation(
                    conversationID: conv.id, baseSeq: conv.lastHostSeq, prompt: prompt,
                    clientTurnID: Self.newClientTurnID(), model: conv.model, budgetUSD: conv.budgetUSD,
                    hostName: machine.record.displayName, hostID: uuid.uuidString, transport: transport
                )
                if case .started(let run) = chatDispatchOutcome(from: outcome, channel: channel, title: conv.title) {
                    return run
                }
                return nil
            }
            return nil
        }

        // Legacy (pre-ledger) conversation: continue from the persisted context
        // (agent/cwd/model) directly via the run's channel, so a reopened chat
        // still continues after the daemon forgot the run (process ended or
        // daemon restarted) instead of "no longer has this run". Prefer the SSH
        // slot that owns this host.
        if let hostID = conv.hostID, let uuid = UUID(uuidString: hostID),
           let slot = fleetStore.slots.first(where: { $0.id == uuid }) {
            guard let result = try? await slot.channel.continueRun(
                runId: lastRunID, prompt: prompt,
                agent: conv.agentID, cwd: conv.cwd, model: conv.model, budgetUSD: conv.budgetUSD),
                  result.status == "started", let newRunID = result.runId else { return nil }
            runOutputStore.register(runId: newRunID)
            return ActiveChatRun(runId: newRunID, channel: slot.channel,
                                 title: conv.title, subtitle: prompt, cwd: result.cwd ?? conv.cwd)
        }
        // Fall back to the first active relay machine's bridge (interim
        // limitation — see AppRoot's report on first-machine-only fallbacks).
        if let bridge = relayFleetStore.machines.first(where: { $0.bridge.isActive })?.bridge {
            guard let result = try? await bridge.sendRunContinue(
                runId: lastRunID, prompt: prompt,
                agent: conv.agentID, cwd: conv.cwd, model: conv.model, budgetUSD: conv.budgetUSD),
                  result.status == "started", let newRunID = result.runId else { return nil }
            runOutputStore.register(runId: newRunID)
            let channel = RelayRunControl(
                send: { rid, action in await bridge.sendRunControl(runId: rid, action: action) },
                onContinue: { rid, p in try await bridge.sendRunContinue(runId: rid, prompt: p) }
            )
            return ActiveChatRun(runId: newRunID, channel: channel, title: conv.title, subtitle: prompt, cwd: result.cwd ?? conv.cwd)
        }
        return nil
    }

    /// List a workspace's files/dirs for the composer's @-mention autocomplete.
    /// Uses the relay bridge's read-only agent.fs.ls (the only fs-listing transport
    /// today). Dirs get a trailing "/". Returns [] if no relay is active.
    private func loadWorkspaceFiles(cwd: String) async -> [String] {
        guard let bridge = relayFleetStore.machines.first(where: { $0.bridge.isActive })?.bridge,
              let listing = try? await bridge.relayListDir(cwd) else { return [] }
        return listing.entries.map { $0.isDir ? $0.name + "/" : $0.name }
    }

    /// A fresh idempotency key for one `agent.conversations.append` call —
    /// `stable-device-id:random`, per the build handoff's `clientTurnId`
    /// contract. Uniqueness (not the exact device-id prefix format) is what
    /// matters: it only needs to let a replayed append map back to the same
    /// turn instead of creating a duplicate.
    private static func newClientTurnID() -> String {
        "\(DeviceIdentity.sessionID()):\(UUID().uuidString)"
    }

    /// Maps a `ConversationSyncCoordinator.TurnOutcome` to the `ChatDispatchOutcome`
    /// NewChatTabView already knows how to render, registering the run for
    /// streaming and attaching the ledger's `conversationID`/`nextBaseSeq` so
    /// follow-ups can continue through the ledger too (see `continueConversationTurn`).
    private func chatDispatchOutcome(
        from outcome: ConversationSyncCoordinator.TurnOutcome, channel: any RunControlling, title: String
    ) -> ChatDispatchOutcome {
        switch outcome {
        case .started(let started):
            guard !started.runID.isEmpty else { return .blocked("Couldn't start the run.") }
            runOutputStore.register(runId: started.runID)
            return .started(ActiveChatRun(
                runId: started.runID,
                channel: channel,
                title: title,
                subtitle: "",
                cwd: started.cwd,
                conversationID: started.conversationID,
                nextBaseSeq: started.baseSeqForNextTurn
            ))
        case .blocked(let message):
            return .blocked(message)
        }
    }

    /// A transport + run-control channel resolved for one agent id, shared by
    /// both the initial dispatch and every follow-up continuation so a thread
    /// never has to re-derive "which bridge/slot owns this conversation".
    private struct ResolvedAgentTransport {
        let transport: ConversationTransport
        let hostName: String
        let hostID: String?
        let channel: any RunControlling
        let title: String
    }

    /// `resolveAgentTransport`'s outcome — a plain success/failure enum (not
    /// `Result<_, Error>`) since the failure side is just a user-facing message,
    /// not a thrown error.
    private enum ResolvedAgentTransportOutcome {
        case success(ResolvedAgentTransport)
        case failure(String)
    }

    /// Resolves `agentID` (either "relay|<machineID>|<vendor>" or "<slotUUID>|<vendor>",
    /// see `dispatchAgents()`) to the transport + run-control channel the
    /// `ConversationSyncCoordinator` and `ActiveChatRun` need. `cwd`/`model` are
    /// only used to build the relay channel's `onContinue` fallback closure (the
    /// pre-sync path for the rare case a mirror write silently failed).
    private func resolveAgentTransport(agentID: String, cwd: String, model: String?) -> ResolvedAgentTransportOutcome {
        let parts = agentID.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return .failure("Unknown agent.") }

        // Relay-paired: the id is 3-part ("relay|<machineID>|<agentID>") so it
        // can route to the exact machine (see `dispatchAgents()`).
        if parts[0] == "relay" {
            let relayParts = agentID.split(separator: "|", maxSplits: 2).map(String.init)
            guard relayParts.count == 3, let uuid = UUID(uuidString: relayParts[1]) else {
                return .failure("Unknown agent.")
            }
            guard let machine = relayFleetStore.machine(RelayMachineID(uuid)) else {
                return .failure("Relay bridge not available.")
            }
            let bridge = machine.bridge
            let vendor = relayParts[2]
            let transport = ConversationTransport(
                append: { try await bridge.relayAppendConversation($0) },
                fetch: { try await bridge.relayFetchConversation($0) },
                archive: { try await bridge.relayArchiveConversation($0) }
            )
            let channel = RelayRunControl(send: { runId, action in
                await bridge.sendRunControl(runId: runId, action: action)
            }, onContinue: { runId, prompt in
                try await bridge.sendRunContinue(runId: runId, prompt: prompt, agent: vendor, cwd: cwd, model: model)
            })
            return .success(ResolvedAgentTransport(
                transport: transport, hostName: machine.record.displayName, hostID: uuid.uuidString,
                channel: channel, title: "Relay · \(vendor)"
            ))
        }

        // SSH: route through the fleet slot's daemon channel.
        guard let slotUUID = UUID(uuidString: parts[0]),
              let slot = fleetStore.slots.first(where: { $0.id == slotUUID })
        else { return .failure("Host is no longer connected.") }
        let vendor = parts[1]
        let channel = slot.channel
        let transport = ConversationTransport(
            append: { try await channel.appendConversation($0) },
            fetch: { try await channel.fetchConversation($0) },
            archive: { try await channel.archiveConversation($0) }
        )
        return .success(ResolvedAgentTransport(
            transport: transport, hostName: slot.hostName, hostID: slot.hostID.uuidString,
            channel: slot.channel, title: "\(vendor) · \(slot.hostName)"
        ))
    }

    private func performDispatch(agentID: String, cwd: String, prompt: String, budgetUSD: Double?, model: String? = nil, env: AppEnvironment) async -> ChatDispatchOutcome {
        let vendor = agentID.split(separator: "|").last.map(String.init) ?? agentID
        switch resolveAgentTransport(agentID: agentID, cwd: cwd, model: model) {
        case .failure(let message):
            return .blocked(message)
        case .success(let resolved):
            let outcome = await env.conversationSyncCoordinator.startConversation(
                agent: vendor, cwd: cwd, prompt: prompt, model: model, budgetUSD: budgetUSD,
                hostName: resolved.hostName, hostID: resolved.hostID,
                clientTurnID: Self.newClientTurnID(), transport: resolved.transport
            )
            return chatDispatchOutcome(from: outcome, channel: resolved.channel, title: resolved.title)
        }
    }

    /// Resolves just the `ConversationTransport` (no run-control channel) for a
    /// persisted conversation's ledger host, by its `hostID` (SSH slot) or
    /// `sourceHostID` (paired relay machine) — used for refresh-only calls
    /// (the sync banner's Refresh action, streaming-handoff polling) that
    /// don't start or continue a run. `nil` if neither host is reachable.
    private func resolveTransport(forConversation conv: ChatConversation) -> ConversationTransport? {
        if let hostID = conv.hostID, let uuid = UUID(uuidString: hostID),
           let slot = fleetStore.slots.first(where: { $0.id == uuid }) {
            let channel = slot.channel
            return ConversationTransport(
                append: { try await channel.appendConversation($0) },
                fetch: { try await channel.fetchConversation($0) },
                archive: { try await channel.archiveConversation($0) }
            )
        }
        if let sourceHostID = conv.sourceHostID, let uuid = UUID(uuidString: sourceHostID),
           let machine = relayFleetStore.machine(RelayMachineID(uuid)) {
            let bridge = machine.bridge
            return ConversationTransport(
                append: { try await bridge.relayAppendConversation($0) },
                fetch: { try await bridge.relayFetchConversation($0) },
                archive: { try await bridge.relayArchiveConversation($0) }
            )
        }
        return nil
    }

    /// Re-pulls a conversation from its host ledger and merges it into the
    /// mirror — shared by `NewChatTabView`'s and `ChatHistoryView`'s sync
    /// banners (Refresh/Resend) and by streaming-handoff polling. Returns the
    /// fresh `nextSeq`, or `nil` if the conversation or its host transport
    /// can't be resolved.
    private func refreshConversationMirror(conversationID: String, env: AppEnvironment) async -> Int? {
        guard let conv = try? await env.chatRepo.conversation(id: conversationID),
              let transport = resolveTransport(forConversation: conv)
        else { return nil }
        return try? await env.conversationSyncCoordinator.refreshConversation(conversationID: conversationID, transport: transport)
    }

    /// Appends a follow-up turn to an existing ledger-backed conversation —
    /// `NewChatTabView.sendFollowUp`'s ledger path, used whenever the active
    /// run carries a `conversationID` (see `ActiveChatRun.conversationID`).
    private func performContinueConversation(
        conversationID: String, baseSeq: Int, prompt: String, agentID: String, cwd: String, model: String?, env: AppEnvironment
    ) async -> ChatDispatchOutcome {
        switch resolveAgentTransport(agentID: agentID, cwd: cwd, model: model) {
        case .failure(let message):
            return .blocked(message)
        case .success(let resolved):
            let outcome = await env.conversationSyncCoordinator.continueConversation(
                conversationID: conversationID, baseSeq: baseSeq, prompt: prompt,
                clientTurnID: Self.newClientTurnID(), model: model,
                hostName: resolved.hostName, hostID: resolved.hostID, transport: resolved.transport
            )
            return chatDispatchOutcome(from: outcome, channel: resolved.channel, title: resolved.title)
        }
    }

    // The single source of truth for the app's tokens: the resolved light/dark
    // palette with the user-selected accent applied. Every `.environment(\.lancerTokens,…)`
    // injection point and the local `t` helper read this, so changing the accent in
    // Settings re-themes the whole app.
    private var tokens: LancerTokens {
        let base = effectiveScheme == .dark ? LancerTokens.dark : .light
        let theme = LancerAccentTheme(rawValue: accentPref) ?? .terracotta
        return base.withAccent(theme, scheme: effectiveScheme == .dark ? .dark : .light)
    }

    // Derive shell tokens directly (reading @Environment(\.lancerTokens) here would
    // resolve ABOVE AppRoot and yield the default palette, leaking a white status-bar
    // strip on inset pages).
    private var t: LancerTokens { tokens }

    private func openDrawer() {
        Task { await sidebarState.loadRecent() }
        sidebarState.isDrawerOpen = true
    }

    /// Chat destinations render their own top chrome (a dark transcript header or
    /// the composer landing's own bar), so the shell must NOT add its beige
    /// hamburger inset above them — that was the beige seam over the dark chat.
    private func isChatDestination(_ dest: SidebarDestination) -> Bool {
        switch dest {
        case .thread, .newChat: return true
        default: return false
        }
    }

    /// Left-edge swipe that opens the drawer. Attached only to a thin leading strip
    /// (not the whole screen) so it can't intercept button taps in the page body.
    private func openDragGesture(drawerWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .updating($drawerDrag) { value, state, _ in
                state = max(0, value.translation.width)
            }
            .onEnded { value in
                if value.predictedEndTranslation.width > drawerWidth * 0.3 { openDrawer() }
            }
    }

    /// Leftward swipe on the scrim that closes the drawer (only attached while open).
    private func closeDragGesture(drawerWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .updating($drawerDrag) { value, state, _ in
                state = min(0, value.translation.width)
            }
            .onEnded { value in
                if value.predictedEndTranslation.width < -drawerWidth * 0.3 {
                    sidebarState.isDrawerOpen = false
                }
            }
    }

    private func compactRoot(env: AppEnvironment) -> some View {
        GeometryReader { proxy in
            let drawerWidth = min(340, proxy.size.width * 0.8)
            let isOpen = sidebarState.isDrawerOpen
            // A single 0…1 driver: the open/closed bool, nudged by the live drag so
            // the card, scrim, corner radius, and scale all move together — the
            // ChatGPT/Claude drawer feel comes from one transform, not four.
            let resting = isOpen ? drawerWidth : 0
            let translate = max(0, min(drawerWidth, resting + drawerDrag))
            let progress = drawerWidth > 0 ? translate / drawerWidth : 0
            ZStack(alignment: .leading) {
                t.bg.ignoresSafeArea()

                // Sidebar pinned left, revealed underneath as the content slides away.
                LancerSidebarView(state: sidebarState, profileLabel: profileLabel(for: env)) { dest in
                    sidebarState.navigate(to: dest)
                }
                .frame(width: drawerWidth)
                .frame(maxHeight: .infinity, alignment: .top)

                // Main content — slides right at full size (ChatGPT/Claude style:
                // pure translation, no scale or corner rounding), dimmed by a scrim
                // when the drawer is open.
                NavigationStack {
                    sidebarDetail(for: sidebarState.selectedDestination, env: env)
                        // Every Lancer page brings its own header and the shell
                        // supplies the hamburger below, so the system navigation
                        // bar is never wanted — hiding it here (once) removes the
                        // empty-bar hairline that showed on pages (Inbox, Machines)
                        // which didn't individually hide it.
                        .toolbar(.hidden, for: .navigationBar)
                        // Do not place a glass control in the navigation toolbar:
                        // UIKit wraps it in a second circular chrome layer. Root
                        // surfaces own exactly one shared control instead.
                        .safeAreaInset(edge: .top, spacing: 0) {
                            // Chat destinations own their top chrome; everything else
                            // (Inbox, Machines, Settings) gets the shell hamburger bar.
                            if sidebarState.selectedDestination != .home,
                               !isChatDestination(sidebarState.selectedDestination) {
                                HStack {
                                    DSCircleButton(
                                        "line.3.horizontal",
                                        diameter: 40,
                                        accessibilityLabel: "Open navigation",
                                        action: openDrawer
                                    )
                                    Spacer()
                                }
                                .padding(.horizontal, 18)
                                .padding(.vertical, 8)
                                .background(t.bg.opacity(0.96))
                            }
                        }
                }
                .background(t.bg)
                .overlay {
                    // Scrim dims the page as it slides aside; while open the whole
                    // page is the tap-to-close target AND a swipe-to-close surface.
                    // Strictly non-interactive when closed so it never swallows taps
                    // on the page's own buttons.
                    Color.black.opacity(0.32 * progress)
                        .contentShape(Rectangle())
                        .onTapGesture { sidebarState.isDrawerOpen = false }
                        .gesture(isOpen ? closeDragGesture(drawerWidth: drawerWidth) : nil)
                        // Outermost so it gates the WHOLE composed overlay (tap +
                        // gesture + shape), not just the inner Color. Applied earlier
                        // it left the tap-to-close gesture live while closed — an
                        // invisible full-content tap-eater that killed every page
                        // button (the real "dead buttons" cause).
                        .allowsHitTesting(isOpen)
                }
                .offset(x: translate)
                .shadow(color: .black.opacity(0.18 * progress), radius: 16, x: -8, y: 0)
            }
            // Swipe-to-OPEN lives on a thin leading-edge strip ONLY (never the whole
            // screen) so the root no longer runs a global DragGesture that competed
            // with — and on a real device swallowed — taps on the page's buttons.
            .overlay(alignment: .leading) {
                if !isOpen {
                    Color.clear
                        .frame(width: 20)
                        .frame(maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .gesture(openDragGesture(drawerWidth: drawerWidth))
                }
            }
            .lancerMotion(LancerMotion.navigation, value: sidebarState.isDrawerOpen)
        }
        .ignoresSafeArea(.container)
        .task {
#if DEBUG
            if ProcessInfo.processInfo.environment["LANCER_DRAWER_OPEN"] == "1" {
                sidebarState.isDrawerOpen = true
            }
#endif
        }
        .fullScreenCover(isPresented: $isShowingLiveSession) {
            if let vm = activeSessionViewModel {
                SessionWorkspaceContainer(
                    viewModel: vm,
                    onSwitchHost: {
                        isShowingLiveSession = false
                        sidebarState.navigate(to: .machines)
                    }
                )
                    .environment(\.lancerTokens, tokens)
            }
        }
    }

    private func regularRoot(env: AppEnvironment) -> some View {
        ZStack {
            t.bg.ignoresSafeArea()
            NavigationSplitView {
                LancerSidebarView(state: sidebarState, profileLabel: profileLabel(for: env)) { dest in
                    sidebarState.navigate(to: dest)
                }
            } detail: {
                NavigationStack {
                    sidebarDetail(for: sidebarState.selectedDestination, env: env)
                        .toolbar(.hidden, for: .navigationBar)
                }
            }
            .task { await sidebarState.loadRecent() }
        }
        .fullScreenCover(isPresented: $isShowingLiveSession) {
            if let vm = activeSessionViewModel {
                SessionWorkspaceContainer(
                    viewModel: vm,
                    onSwitchHost: {
                        isShowingLiveSession = false
                        sidebarState.navigate(to: .machines)
                    }
                )
                    .environment(\.lancerTokens, tokens)
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

    private func inboxDestination(env: AppEnvironment) -> some View {
        let actions = bridgeSessionActions()
        return InboxView(
            viewModel: activeInboxViewModel,
            statusHeaderAgents: [],
            onTapStatusHeader: {},
            onSetPolicy: { yaml in try? await actions.savePolicyYAML(yaml) },
            onOpenHistory: { drawerRoute = .activity }
        )
    }

    /// Human-readable labels for a machine's `installedAgentVendors`, same
    /// mapping/fallback as the dispatch-agent picker (see the `agentID switch`
    /// above) so the Machines relay card converges to real installed agents
    /// once the host reports them.
    private func relayAgentDisplayLabels(for installedAgentVendors: [String]?) -> [String] {
        let vendors = installedAgentVendors ?? ["claudeCode", "codex", "opencode", "kimi"]
        return vendors.map { agentID in
            switch agentID {
            case "claudeCode": return "Claude Code"
            case "codex": return "Codex"
            case "kimi": return "Kimi"
            default: return "OpenCode"
            }
        }
    }

    private func fleetDestination(env: AppEnvironment) -> some View {
        FleetView(
            store: fleetStore,
            hostRepo: env.hostRepo,
            chatRepo: env.chatRepo,
            loopStore: env.loopStore,
            quotaGuardStore: env.quotaGuardStore,
            hostHealthStore: env.hostHealthStore,
            onConnectHost: { drawerRoute = .relayPairing },
            onReconnect: { host in openSession(host: host, env: env) },
            onDelete: { host in Task { try? await env.hostRepo.delete(id: host.id) } },
            onQuotaGuard: { showingQuotaGuard = true },
            // V1's Work Thread/Machines are a read-only activity log — the live
            // interactive terminal (SessionView) is deferred to V2 and intentionally
            // not wired into nav here. FleetView hides/no-ops its terminal-drill-in
            // affordances when this is nil.
            onOpenThread: { id in
                sidebarState.navigate(to: .thread(id: id))
            },
            relayMachines: relayFleetStore.machines.map {
                FleetRelayMachine(
                    id: $0.id,
                    name: $0.record.displayName,
                    isActive: $0.bridge.isActive,
                    agentLabels: $0.bridge.isActive ? relayAgentDisplayLabels(for: $0.installedAgentVendors) : []
                )
            },
            onOpenRelayChat: { _ in sidebarState.navigate(to: .newChat) }
        )
        .id(workspacesRevision)
    }

    /// Stop every running agent: disconnect SSH sessions and send a relay stop for
    /// each non-terminal run.
    private func performEmergencyStop() {
        Task {
            for slot in fleetStore.slots where slot.sessionViewModel.status == .connected {
                await slot.sessionViewModel.disconnect()
            }
            for machine in relayFleetStore.machines where machine.bridge.isActive {
                for run in runOutputStore.runs.values where !run.isTerminal {
                    _ = await machine.bridge.sendRunControl(runId: run.runId, action: "stop")
                }
            }
        }
    }

    /// Best-effort YAML for a normalized cross-provider policy. ponytail: the daemon
    /// validates the real schema (fail-closed), so this stays a thin serializer — upgrade
    /// to per-provider compilation when the matrix moves past MVP.
    private func normalizedPolicyYAML(_ p: NormalizedPolicy) -> String {
        var lines = ["# Normalized cross-provider policy", "rules:"]
        for r in p.rules {
            lines.append("  - id: \(r.id)")
            lines.append("    description: \"\(r.description)\"")
        }
        return lines.joined(separator: "\n")
    }

    private func settingsDestination(env: AppEnvironment) -> some View {
        SettingsWithLibraryView(
            viewModel: SettingsViewModel(keyStore: env.aiKeyStore),
            syncEngine: env.syncEngine,
            backendURL: Self.pushBackendURL(),
            auditRepository: env.auditRepo,
            approvalRepository: approvalRepository,
            sshKeyStore: env.keyStore,
            daemonChannel: daemonChannel,
            relayMachines: relayFleetStore.machines.map {
                RelayMachineRow(id: $0.id, displayName: $0.record.displayName, isConnected: $0.bridge.isActive)
            },
            onRelayPaired: { client, record in addRelayMachine(client: client, record: record, env: env) },
            onRelayUnpair: { id in
                ApprovalRelay.shared.relayBridges.removeValue(forKey: id)
                relayFleetStore.remove(id)
            },
            onRelayRename: { id, name in relayFleetStore.updateDisplayName(name, for: id) },
            accountSession: env.accountSession,
            quotaGuardStore: env.quotaGuardStore,
            onResetApp: {
                let db = env.database
                Task {
                    try? await db.wipeAll()
                    await MainActor.run {
                        UserDefaults.standard.removeObject(forKey: "dev.lancer.debugSeeded")
                        sidebarState.navigate(to: .home)
                        onboardingSeen = false
                    }
                }
            },
            onEmergencyStop: { performEmergencyStop() },
            onAccountSignedOut: {
                onboardingSeen = false
            },
            sidebarShellState: sidebarState,
            onApplyPolicyPreset: { preset, _ in
                let actions = bridgeSessionActions()
                Task { try? await actions.savePolicyYAML(preset.ruleYAML) }
            },
            onApplyNormalizedPolicy: { policy in
                let actions = bridgeSessionActions()
                Task { try? await actions.savePolicyYAML(normalizedPolicyYAML(policy)) }
            }
        )
    }

    @ViewBuilder
    private func sidebarDetail(for dest: SidebarDestination, env: AppEnvironment) -> some View {
        switch dest {
        case .home:
            homeDestination(env: env)
        case .newChat:
            NewChatTabView(
                agents: dispatchAgents(),
                runOutputStore: runOutputStore,
                chatRepo: env.chatRepo,
                workspaceRepo: env.workspaceRepo,
                fleetStore: fleetStore,
                conversationSyncCoordinator: env.conversationSyncCoordinator,
                preferredMachineKey: pendingNewChatMachineKey,
                preferredCwd: pendingNewChatCwd,
                onMachineHintConsumed: {
                    pendingNewChatMachineKey = nil
                    pendingNewChatCwd = nil
                },
                onDispatch: { agentID, cwd, prompt, budget, model in
                    await performDispatch(agentID: agentID, cwd: cwd, prompt: prompt, budgetUSD: budget, model: model, env: env)
                },
                onContinueConversation: { conversationID, baseSeq, prompt, agentID, cwd, model in
                    await performContinueConversation(
                        conversationID: conversationID, baseSeq: baseSeq, prompt: prompt,
                        agentID: agentID, cwd: cwd, model: model, env: env
                    )
                },
                onRefreshConversation: { conversationID in
                    await refreshConversationMirror(conversationID: conversationID, env: env)
                },
                onNewTask: { sidebarState.navigate(to: .newChat) },
                onOpenWorkspace: { agent in openWorkspace(for: agent) },
                onOpenSidebar: openDrawer,
                onConnectSSH: { drawerRoute = .addMachine },
                loadCommands: { cwd, vendor in await loadAgentCommands(cwd: cwd, vendor: vendor) },
                loadFiles: { cwd in await loadWorkspaceFiles(cwd: cwd) },
                inboxViewModel: activeInboxViewModel,
                onDecideApproval: { approvalID, decision in
                    if let slot = fleetStore.slot(forApprovalID: approvalID) {
                        slot.inboxVM.decide(approvalID, decision: decision)
                    } else {
                        activeInboxViewModel.decide(approvalID, decision: decision)
                    }
                }
            )
        case .thread(let id):
            ChatHistoryView(
                conversationID: id,
                chatRepo: env.chatRepo,
                runOutputStore: runOutputStore,
                conversationSyncCoordinator: env.conversationSyncCoordinator,
                onBack: { sidebarState.navigate(to: .home) },
                onNewChat: { sidebarState.navigate(to: .newChat) },
                onContinue: { conv, lastRunID, prompt in
                    await resumeConversation(conv, lastRunID: lastRunID, prompt: prompt, env: env)
                },
                onRefreshConversation: { conversationID in
                    await refreshConversationMirror(conversationID: conversationID, env: env)
                }
            )
            .id(id)
        case .needsAttention:
            inboxDestination(env: env)
        case .machines:
            fleetDestination(env: env)
        case .settings:
            settingsDestination(env: env)
        case .observedSession(let sessionId, let title, let hostName, let vendor, let cwd):
            ObservedSessionView(
                sessionId: sessionId,
                title: title,
                hostName: hostName,
                vendor: vendor,
                cwd: cwd,
                loadTranscript: { sinceLine in await fetchObservedTranscript(sessionId: sessionId, sinceLine: sinceLine) },
                onSendFollowUp: { prompt in
                    await sendObservedSessionFollowUp(vendor: vendor, sessionId: sessionId, cwd: cwd, prompt: prompt)
                },
                onBack: { sidebarState.navigate(to: .home) }
            )
        case .workspace(let machineKey, let machineName, let path, let displayName, _):
            WorkspaceDetailView(
                machineName: machineName,
                path: path,
                displayName: displayName,
                sessions: sidebarState.recentThreads.filter { $0.hostName == machineName && $0.cwd == path },
                onOpenThread: { id in sidebarState.navigate(to: .thread(id: id)) },
                onNewChatHere: {
                    pendingNewChatMachineKey = machineKey
                    pendingNewChatCwd = path
                    sidebarState.navigate(to: .newChat)
                },
                onBack: { sidebarState.navigate(to: .home) }
            )
        }
    }

    private func homeDestination(env: AppEnvironment) -> some View {
        LancerHomeView(
            fleetStore: fleetStore,
            defaultInboxVM: activeInboxViewModel,
            recentThreads: sidebarState.recentThreads,
            pendingApprovalCount: fleetStore.attentionItems.count,
            profileEmail: env.accountSession.email,
            relayMachines: debugFakeRelayEntry.map { [$0] } ?? relayFleetStore.machines.map {
                RelayHomeEntry(id: $0.id, name: $0.record.displayName, connected: $0.bridge.isActive)
            },
            workspaces: allWorkspaces,
            onOpenSidebar: homeSidebarAction,
            onNewChat: { sidebarState.navigate(to: .newChat) },
            onOpenInbox: { sidebarState.navigate(to: .needsAttention) },
            onOpenMachines: { sidebarState.navigate(to: .machines) },
            onOpenThread: { id in sidebarState.navigate(to: .thread(id: id)) },
            onOpenObservedSession: { session in
                sidebarState.navigate(to: .observedSession(
                    sessionId: session.sessionId,
                    title: session.title,
                    // LancerHomeView's callback doesn't carry which host the session
                    // came from (pre-existing gap, out of scope here) — first-machine
                    // fallback, same class as the other interim limitations below.
                    hostName: relayFleetStore.machines.first?.record.displayName ?? "Mac",
                    vendor: session.provider,
                    cwd: session.cwd
                ))
            },
            onOpenWorkspace: { ref in
                sidebarState.navigate(to: .workspace(
                    machineKey: ref.machineKey,
                    machineName: ref.machineName,
                    path: ref.path,
                    displayName: ref.displayName,
                    workspaceID: ref.workspaceID
                ))
            },
            onCreateWorkspace: { machineKey in
                pendingNewChatMachineKey = machineKey
                pendingNewChatCwd = nil
                sidebarState.navigate(to: .newChat)
            },
            loadSessions: { hostName in await loadObservedSessions(hostName: hostName) }
        )
        // Refreshes every time Home is (re)entered — e.g. after creating a new
        // workspace from New Chat and navigating back — matching the simple
        // reload-on-appear approach `LancerHomeView`'s own `.task` already uses
        // for observed sessions, rather than a more invasive change-notification.
        .task(id: sidebarState.selectedDestination) {
            await loadAllWorkspaces(env: env)
        }
    }

    /// Every persisted `Workspace` across every currently-paired relay machine,
    /// for `LancerHomeView`'s workspace cards. Best-effort per machine so one
    /// unreachable host's repo query doesn't blank out every other machine's list.
    private func loadAllWorkspaces(env: AppEnvironment) async {
        var all: [Workspace] = []
        for machine in relayFleetStore.machines {
            if let list = try? await env.workspaceRepo.list(machineID: machine.id) {
                all.append(contentsOf: list)
            }
        }
        allWorkspaces = all
    }

    /// Lists sessions discovered on the host (Claude Code, etc.) for Home's
    /// "Sessions on this Mac" section, for the given host name. Resolution order:
    /// an SSH slot whose `hostName` matches (regardless of connection state,
    /// matching the previous fallback-to-any-slot behavior but scoped to the
    /// matching name), else a relay machine whose display name matches.
    private func loadObservedSessions(hostName: String) async -> [ObservedSession] {
        if let slot = fleetStore.slots.first(where: { $0.hostName == hostName }),
           let sessions = try? await slot.channel.listSessions() {
            return sessions
        }
        if let machine = relayFleetStore.machines.first(where: { $0.record.displayName == hostName }),
           machine.bridge.isActive {
            return (try? await machine.bridge.relayListSessions()) ?? []
        }
        return []
    }

    /// Fetches transcript turns for an observed session, using the same
    /// transport-selection order as `loadObservedSessions`.
    private func fetchObservedTranscript(sessionId: String, sinceLine: Int) async -> (messages: [SessionMessage], nextLine: Int, resetRequired: Bool) {
        if let slot = fleetStore.slots.first(where: { fleetStore.connectionState(for: $0) == .connected })
                ?? fleetStore.slots.first,
           let result = try? await slot.channel.fetchTranscript(sessionId: sessionId, sinceLine: sinceLine) {
            return result
        }
        if let bridge = relayFleetStore.machines.first(where: { $0.bridge.isActive })?.bridge,
           let result = try? await bridge.relayFetchTranscript(sessionId: sessionId, sinceLine: sinceLine) {
            return result
        }
        return ([], 0, false)
    }

    /// Sends a follow-up prompt into an observed (not Lancer-dispatched) session
    /// by its exact vendor session id + cwd. Mirrors `loadObservedSessions` /
    /// `fetchObservedTranscript`: prefers a connected SSH fleet slot, falls back
    /// to the relay bridge (`agentSessionContinue` / `sessionContinueResult`) so
    /// a relay-only (V1) setup can continue an observed session too.
    private func sendObservedSessionFollowUp(vendor: String, sessionId: String, cwd: String, prompt: String) async -> DispatchResult {
        if let slot = fleetStore.slots.first(where: { fleetStore.connectionState(for: $0) == .connected })
                ?? fleetStore.slots.first {
            do {
                return try await slot.channel.continueObservedSession(vendor: vendor, sessionId: sessionId, cwd: cwd, prompt: prompt)
            } catch {
                return DispatchResult(status: "error", message: error.localizedDescription)
            }
        }
        if let bridge = relayFleetStore.machines.first(where: { $0.bridge.isActive })?.bridge {
            do {
                return try await bridge.relayContinueObservedSession(vendor: vendor, sessionId: sessionId, cwd: cwd, prompt: prompt)
            } catch {
                return DispatchResult(status: "error", message: error.localizedDescription)
            }
        }
        return DispatchResult(status: "error", message: "No direct connection to this machine.")
    }

    private func profileLabel(for env: AppEnvironment) -> String {
        // Prefer the user's name (captured at onboarding for both account and
        // offline users), then fall back to email, then a neutral default.
        if let name = env.accountSession.displayName { return name }
        return env.accountSession.email ?? (env.accountSession.isOfflineSelfHosted ? "Self-hosted offline" : "Lancer")
    }

    private var homeSidebarAction: (() -> Void)? {
        guard horizontalSizeClass != .regular else { return nil }
        return { openDrawer() }
    }

    private func configureCloudServices(env: AppEnvironment) async {
        let url = Self.pushBackendURL()
        await env.accountSession.restore()
        pm.configure(backendURL: url, accountAccessToken: env.accountSession.session?.accessToken)
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
        // Begin monitoring the push-to-start token now that the stable sessionID is
        // available — lets push-backend remotely START a Live Activity when an approval
        // arrives and none is running (app fully closed). Tokens flow out via the
        // .lancerLiveActivityTokenReady subscriber in configureRelayFleetStore.
        if #available(iOS 17.2, *) {
            LancerLiveActivityManager.shared.startPushToStartMonitor(
                sessionID: DeviceIdentity.sessionID()
            )
        }
        configureRelayFleetStore(env: env)
    }

    /// Activate the E2E relay decision path. Idempotent — only the first call
    /// wires notification subscriptions/hydration.
    @MainActor
    /// Register this device's APNs token with whichever transport is live, so
    /// approvals can be pushed when the app is closed. Idempotent — safe to call on
    /// every foreground. Relay path uses the bridge's `deviceRegister` message; SSH
    /// path uses the daemon channel RPC. No-op until an APNs token exists.
    private func registerPushTokenForActiveTransport() async {
        let backendURL = Self.pushBackendURL()
        guard !backendURL.isEmpty, let token = await Notifications.shared.pendingAPNSTokenHex else { return }
        let sessionID = DeviceIdentity.sessionID()
        for machine in relayFleetStore.machines where machine.bridge.isActive {
            await machine.bridge.registerDevice(apnsToken: token, sessionID: sessionID, pushBackendURL: backendURL)
        }
        if let channel = daemonChannel {
            try? await channel.registerAPNSToken(hexToken: token, sessionID: sessionID, pushBackendURL: backendURL)
        }
    }

    private func configureRelayFleetStore(env: AppEnvironment) {
        guard !configuredRelayFleetStore else { return }
        configuredRelayFleetStore = true
#if DEBUG
        // Honor the UI-test relay seam: keep the seeded fake host/active state instead
        // of letting real hydration/bridge setup clobber it.
        if ProcessInfo.processInfo.environment["LANCER_FAKE_RELAY_HOST"] != nil { return }
#endif
        // Migrate the legacy single pairing (if any) and restore every known
        // machine's client/bridge. Notification subscriptions below don't need
        // to wait on this completing — a notification for a not-yet-hydrated
        // machine simply won't find it in `relayFleetStore.machine(id)` and is
        // dropped (same fail-closed spirit as everywhere else in this feature).
        Task { await hydrateRelayFleetStore(env: env) }

        // lancerE2EStatusUpdate is posted by every machine's bridge; route each
        // to the machine it named via userInfo["machineID"].
        Task { @MainActor in
            for await notification in NotificationCenter.default.notifications(named: Notification.Name("lancerE2EStatusUpdate")) {
                guard let machineID = notification.userInfo?["machineID"] as? RelayMachineID,
                      let status = notification.userInfo?["status"] as? E2ERelayMessage.StatusData,
                      let hostName = status.hostName
                else { continue }
                relayFleetStore.updateDisplayName(hostName, for: machineID)
            }
        }

        Task { @MainActor in
            for await notification in NotificationCenter.default.notifications(named: .lancerAPNSTokenReceived) {
                guard let token = notification.userInfo?["token"] as? String else { continue }
                let backendURL = Self.pushBackendURL()
                // SSH path: register over the daemon channel.
                if let channel = self.daemonChannel {
                    try? await channel.registerAPNSToken(
                        hexToken: token,
                        sessionID: DeviceIdentity.sessionID(),
                        pushBackendURL: backendURL
                    )
                }
                // Relay path: the token may arrive after a bridge is already active
                // (each machine's own isActive handler in `addRelayMachine` covers
                // the reverse order). Register over every active machine's relay so
                // closed-app push works on relay-only devices.
                guard !backendURL.isEmpty else { continue }
                for machine in self.relayFleetStore.machines where machine.bridge.isActive {
                    await machine.bridge.registerDevice(
                        apnsToken: token,
                        sessionID: DeviceIdentity.sessionID(),
                        pushBackendURL: backendURL
                    )
                }
            }
        }

        // Forward Live Activity push tokens to push-backend through lancerd, so the
        // daemon (which holds APPROVAL_RELAY_SECRET) does the authenticated POST — the
        // app never holds that secret. Producer: LancerApp.configureLiveActivityTokens
        // posts .lancerLiveActivityTokenReady when ActivityKit issues/refreshes a
        // per-activity or push-to-start token. Without this the push-driven Live
        // Activity has no registered token and can never receive a push.
        //
        // Registers over BOTH transports (mirrors registerPushTokenForActiveTransport):
        // the SSH daemonChannel when present, AND every active relay machine's bridge.
        // Previously this was gated on `let channel = self.daemonChannel` alone, so a
        // relay-only pairing (no SSH host — V1's primary configuration) silently never
        // registered its Live Activity token at all.
        Task { @MainActor in
            for await notification in NotificationCenter.default.notifications(named: .lancerLiveActivityTokenReady) {
                guard let sessionID = notification.userInfo?["sessionID"] as? String,
                      let activityToken = notification.userInfo?["activityToken"] as? String,
                      let isPushToStart = notification.userInfo?["isPushToStart"] as? Bool
                else { continue }
                let backendURL = Self.pushBackendURL()
                if let channel = self.daemonChannel {
                    try? await channel.registerActivityToken(
                        activityToken: activityToken,
                        sessionID: sessionID,
                        isPushToStart: isPushToStart,
                        pushBackendURL: backendURL
                    )
                }
                guard !backendURL.isEmpty else { continue }
                for machine in self.relayFleetStore.machines where machine.bridge.isActive {
                    await machine.bridge.registerActivityToken(
                        sessionID: sessionID,
                        activityToken: activityToken,
                        isPushToStart: isPushToStart,
                        pushBackendURL: backendURL
                    )
                }
            }
        }

        // Route the relay/default inbox's decisions to the daemon. Without this the
        // base InboxViewModel only updated local UI state, so approving a relay-
        // delivered approval never released the daemon's blocked hook.
        inboxVM.decisionSink = { id, decision, editedToolInput, contentHash in
            Task {
                await ApprovalRelay.shared.forwardDecisionOnly(
                    approvalID: id.uuidString,
                    decision: decision,
                    editedToolInput: editedToolInput,
                    contentHash: contentHash
                )
            }
        }

        #if DEBUG
        // Headless auto-pair for testing the relay loop in the simulator (where
        // synthesized taps don't reach the app, so the code can't be typed). Set
        // SIMCTL_CHILD_LANCER_RELAY_CODE=<6-digit daemon code>; this replicates the
        // manual-code path (client.pairingCode = code; connect()). Debug-only.
        if let code = ProcessInfo.processInfo.environment["LANCER_RELAY_CODE"],
           code.count == 6 {
            let client = E2ERelayClient(relayURL: RelaySettings.url(), pairingCode: PairingCrypto.generatePairingCode())
            // Fresh keypair for this pairing (beginPairingSession also rotates the
            // code, so apply the daemon's code afterward). This avoids reusing a
            // restored keypair from a prior pairing, which — combined with the old
            // non-idempotent connect() — produced a stale session key the daemon's
            // frames couldn't decrypt. connect() is now idempotent, so this is the
            // single authoritative channel.
            client.beginPairingSession()
            client.pairingCode = code
            Task { @MainActor in
                for await state in client.$pairingState.values {
                    if state == .paired {
                        addRelayMachine(
                            client: client,
                            record: RelayMachineRecord(id: client.machineID, displayName: "Relay host"),
                            env: env
                        )
                        break
                    }
                }
            }
            client.connect()
        }
        #endif
    }

    /// Migrates the legacy single relay pairing (if any) into the namespaced
    /// index, then restores + wires every known machine's client/bridge. Called
    /// once from `configureRelayFleetStore` via a detached `Task` — hydration is
    /// async so it doesn't block the rest of that method's synchronous setup.
    private func hydrateRelayFleetStore(env: AppEnvironment) async {
        _ = await RelayMachineMigration.migrateLegacyIfNeeded()
        let records = await RelayMachineMigration.readIndex()
        for record in records {
            let client = E2ERelayClient(relayURL: RelaySettings.url(), pairingCode: "", machineID: record.id)
            client.restoreNamespacedStoredPairing()
            addRelayMachine(client: client, record: record, env: env)
            // Only this restore-from-disk path needs to actively dial out — every
            // other addRelayMachine caller (debug seam, real pairing-UI callbacks)
            // already has a client that just live-paired moments ago, and calling
            // connect() again here tore down that fresh connection out from under
            // it (the client's own just-written credentials made hasStoredPairing
            // true immediately, so this used to fire on every single pairing).
            if E2ERelayClient.hasStoredPairing(machineID: record.id) {
                client.connect()
            }
        }
    }

    /// Builds an `E2ERelayBridge` over `client`, registers it with
    /// `ApprovalRelay` and `relayFleetStore`, and wires its per-bridge
    /// subscriptions (installed-agents fetch + push-token registration on
    /// activation, plus mirroring pairing/connection state into the fleet-wide
    /// aggregate). Called from launch hydration, the pairing-UI callbacks, and
    /// the `LANCER_RELAY_CODE` debug seam.
    @MainActor
    private func addRelayMachine(client: E2ERelayClient, record: RelayMachineRecord, env: AppEnvironment) {
        let bridge = E2ERelayBridge(relayClient: client, approvalRelay: ApprovalRelay.shared, machineID: record.id)
        bridge.start()
        let machine = RelayFleetStore.Machine(record: record, client: client, bridge: bridge)
        relayFleetStore.add(machine)
        ApprovalRelay.shared.relayBridges[record.id] = bridge
        Task { @MainActor in
            for await active in bridge.$isActive.values {
                // Recompute every derived aggregate that used to come from the
                // single relayBridgeIsActive bool, now folded across ALL machines.
                sidebarState.relayConnected = relayFleetStore.machines.contains { $0.bridge.isActive }
                if active { sidebarState.relayLastConnectedAt = Date() }
                fleetStore.setRelayStateOnAllSlots(aggregateRelayState())
                if active {
                    // When a relay machine goes live, ask the host which agent CLIs
                    // are actually installed so the picker only offers those.
                    if let installed = try? await bridge.relayInstalledAgents(), !installed.isEmpty {
                        relayFleetStore.setInstalledAgentVendors(installed, for: record.id)
                    }
                    // Register this device's APNs token over the relay so approvals
                    // can be pushed when the app is closed (the relay path's
                    // equivalent of the SSH channel.registerAPNSToken). Without this
                    // the daemon never learns the token and push never fires.
                    let backendURL = Self.pushBackendURL()
                    if !backendURL.isEmpty, let token = await Notifications.shared.pendingAPNSTokenHex {
                        await bridge.registerDevice(apnsToken: token, sessionID: DeviceIdentity.sessionID(), pushBackendURL: backendURL)
                    }
                }
            }
        }
    }

    /// Fleet-wide "most live wins" relay state, folded across every paired
    /// machine's client pairing/connection state — mirrors what the single-bridge
    /// `Self.relayState` used to compute for the one app-wide client. Ordering
    /// (most → least live), matching `Session.RelayState`'s cases: paired >
    /// degraded > connecting > error > none.
    private func aggregateRelayState() -> Session.RelayState {
        let states = relayFleetStore.machines.map {
            Self.relayState(pairing: $0.client.pairingState, connection: $0.client.connectionState)
        }
        let rank: (Session.RelayState) -> Int = { state in
            switch state {
            case .paired: return 4
            case .degraded: return 3
            case .connecting: return 2
            case .error: return 1
            case .none: return 0
            }
        }
        return states.max(by: { rank($0) < rank($1) }) ?? .none
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
        if let envURL = ProcessInfo.processInfo.environment["LANCER_PUSH_BACKEND_URL"],
           !envURL.isEmpty {
            return envURL
        }
        #endif
        return Bundle.main.infoDictionary?["LANCER_PUSH_BACKEND_URL"] as? String ?? ""
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
            let chatSink = ChatRunPersistenceSink(chatRepo: env.chatRepo)
            let ingest = ApprovalIngest(channel: channel, repository: approvalRepo, hostName: host.name, runOutputStore: runOutputStore, chatPersistenceSink: chatSink)
            let liveVM = LiveInboxViewModel(
                repository: approvalRepo,
                onDecision: { id, decision, editedToolInput, contentHash in
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
                        editedToolInput: editedToolInput,
                        contentHash: contentHash
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
                        // The Watch has no in-memory Approval row to read a
                        // contentHash off (its onDecision signature is (id, decision)
                        // only) — fetch the just-decided row back from the DB so the
                        // forwarded decision still echoes the hash lancerd verifies.
                        let contentHash = (try? await approvalRepo.find(id: id))?.contentHash
                        await ApprovalRelay.shared.forwardDecisionOnly(
                            approvalID: id.uuidString,
                            decision: decision,
                            editedToolInput: nil,
                            contentHash: contentHash
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
                self.sidebarState.navigate(to: .machines)
                // MAJOR-4: re-arm the approval pipeline after a reconnect. The
                // DaemonChannel/ApprovalIngest die when the SSH client is swapped;
                // recreate + restart them and re-point the relay so new approvals
                // are ingested and decisions are delivered post-reconnect. Captures
                // only Sendable values (no `vm`, so no retain cycle).
                let fleet = self.fleetStore
                let quotaGuard = env.quotaGuardStore
                let chatRepo = env.chatRepo
                vm.onReconnected = { [fleet, quotaGuard, runOutputStore, chatRepo, slotID = slot.id, sshSession, host, approvalRepo, backendURL, deviceSessionID] in
                    if let existing = await fleet.slots.first(where: { $0.id == slotID }) {
                        await existing.ingest.stop()
                        await existing.channel.stop()
                    }
                    let newChannel = DaemonChannel(session: sshSession)
                    let newChatSink = ChatRunPersistenceSink(chatRepo: chatRepo)
                    let newIngest = ApprovalIngest(channel: newChannel, repository: approvalRepo, hostName: host.name, runOutputStore: runOutputStore, chatPersistenceSink: newChatSink)
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
            let daemonPath = (try? await DaemonBootstrap.ensureInstalled(session: sshSession, manifest: DaemonBootstrap.loadManifest())) ?? "$HOME/.lancer/bin/lancerd"
            try? await channel.start(daemonPath: daemonPath)  // launch lancerd serve on remote host
            // First connect after onboarding: flush the chosen tier's starter policy
            // to the daemon (it wasn't reachable during pairing). Idempotent — no-op
            // once applied; a failed push retries on the next connect.
            await OnboardingPolicy.applyPendingIfNeeded { yaml in
                try await channel.savePolicyYAML(cwd: "", yaml: yaml)
                try await channel.reloadPolicy(cwd: "")
            }
            // Register device with lancerd so APNs alerts reach this device when
            // backgrounded. The handshake reply carries the per-session relay
            // capability token — store it so backend-relayed decisions can
            // authenticate (B2). Same `deviceSessionID` is used here and for the
            // decision POST body so the backend looks up the right record.
            if !backendURL.isEmpty {
                let token = (try? await channel.registerDevice(pushBackendURL: backendURL, sessionID: deviceSessionID)) ?? nil
                if let token { ApprovalRelay.shared.setRelayToken(token) }
            }
            // Forward any APNs token that arrived before the channel was ready.
            if !backendURL.isEmpty, let hexToken = await Notifications.shared.pendingAPNSTokenHex {
                try? await channel.registerAPNSToken(
                    hexToken: hexToken,
                    sessionID: deviceSessionID,
                    pushBackendURL: backendURL
                )
            }
            // Attach the relay so Live Activity / Dynamic Island decisions are
            // forwarded to lancerd, and drain any decisions queued while the
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

extension Notification.Name {
    static let lancerChatArtifactPersisted = Notification.Name("lancerChatArtifactPersisted")
    static let lancerSavedHostsDidChange = Notification.Name("lancerSavedHostsDidChange")
}

private struct MachineConnectionChooser: View {
    let onRelay: () -> Void
    let onSSH: () -> Void

    @Environment(\.lancerTokens) private var t

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            choice(
                title: "Pair over relay",
                detail: "Recommended. Run agents and receive approvals without configuring SSH.",
                icon: "link",
                action: onRelay,
                emphasized: true
            )
            choice(
                title: "Connect over SSH",
                detail: "Advanced. Adds a live terminal, files, diffs, and browser preview.",
                icon: "terminal",
                action: onSSH,
                emphasized: false
            )
            Text("You can add SSH later from Machines. Relay never becomes a remote shell.")
                .font(.dsSansPt(12))
                .foregroundStyle(t.text3)
                .padding(.top, 2)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private func choice(
        title: String,
        detail: String,
        icon: String,
        action: @escaping () -> Void,
        emphasized: Bool
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(emphasized ? t.accentFg : t.accent)
                    .frame(width: 40, height: 40)
                    .background(emphasized ? t.accent : t.accentSoft, in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.dsSansPt(16, weight: .semibold))
                        .foregroundStyle(t.text)
                    Text(detail)
                        .font(.dsSansPt(12.5))
                        .foregroundStyle(t.text3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(t.text4)
                    .padding(.top, 14)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(t.surface, in: RoundedRectangle(cornerRadius: t.r4, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: t.r4, style: .continuous)
                    .strokeBorder(emphasized ? t.accent.opacity(0.6) : t.border, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .lancerGlassChrome(cornerRadius: t.r4, interactive: true)
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
    var relayMachines: [RelayMachineRow] = []
    var onRelayPaired: (E2ERelayClient, RelayMachineRecord) -> Void = { _, _ in }
    var onRelayUnpair: (RelayMachineID) -> Void = { _ in }
    var onRelayRename: (RelayMachineID, String) -> Void = { _, _ in }
    let accountSession: AccountSessionController
    var quotaGuardStore: QuotaGuardStore? = nil
    var onResetApp: (() -> Void)? = nil
    var onEmergencyStop: (() -> Void)? = nil
    var onAccountSignedOut: (() -> Void)? = nil
    // Sidebar back navigation — use @Bindable so the mutation goes through the
    // observable directly, avoiding closure-capture staleness through deep view trees.
    @Bindable var sidebarShellState: SidebarShellState
    var onApplyPolicyPreset: ((PolicyPreset, String) -> Void)? = nil
    var onApplyNormalizedPolicy: ((NormalizedPolicy) -> Void)? = nil
    @State private var showLimits = false

    var body: some View {
        SettingsView(
            viewModel: viewModel,
            syncEngine: syncEngine,
            backendURL: backendURL,
            auditRepository: auditRepository,
            approvalRepository: approvalRepository,
            sshKeyStore: sshKeyStore,
            daemonChannel: daemonChannel,
            relayMachines: relayMachines,
            onRelayPaired: onRelayPaired,
            onRelayUnpair: onRelayUnpair,
            onRelayRename: onRelayRename,
            onResetApp: onResetApp,
            onShowLimits: quotaGuardStore != nil ? { showLimits = true } : nil,
            onEmergencyStop: onEmergencyStop,
            accountSession: accountSession,
            onAccountSignedOut: onAccountSignedOut,
            // Settings is a top-level sidebar destination. The compact shell
            // provides the single glass navigation button, so suppress an
            // in-content back affordance here.
            onBack: nil,
            onApplyPolicyPreset: onApplyPolicyPreset,
            onApplyNormalizedPolicy: onApplyNormalizedPolicy
        )
        .sheet(isPresented: $showLimits) {
            if let store = quotaGuardStore {
                LancerDrawer(title: "Usage & limits", detents: [.large]) {
                    QuotaGuardView(store: store)
                }
            }
        }
    }
}

private struct GlobalInboxGateView: View {
    let onUpgrade: () -> Void
    @Environment(\.lancerTokens) private var t

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
    @Environment(\.lancerTokens) private var t
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
            // Live-loop E2E (LANCER_DAEMON_E2E=1): prefill the localhost password
            // from the launch env so the real connect flow can be driven without
            // typing into a secure field. DEBUG-only; never affects shipping.
            let e = ProcessInfo.processInfo.environment
            if e["LANCER_DAEMON_E2E"] == "1", password.isEmpty,
               let pw = e["LANCER_TEST_PW"], !pw.isEmpty {
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

/// A dispatched run NewChatTabView is rendering inline. Transport-agnostic: `channel`
/// is whichever RunControlling the dispatch used (relay or a fleet slot's DaemonChannel),
/// so the inline thread's Stop/Pause/Budget controls work the same either way.
public struct ActiveChatRun: Identifiable {
    public let runId: String
    public let channel: any RunControlling
    public let title: String
    public let subtitle: String
    /// The daemon-resolved, ~-expanded absolute cwd the run actually launched
    /// in — persist THIS into `ChatConversation.cwd`, not the raw string the
    /// composer sent (which may be the literal "~" for a fresh relay dispatch).
    /// See `DispatchResult.cwd`.
    public let cwd: String
    /// The host ledger conversation this run belongs to, once `performDispatch`
    /// routed the initial turn through `agent.conversations.append` (Task 7).
    /// `nil` only if the mirror write itself failed (best-effort) — callers
    /// should treat that as "can't continue via the ledger", not as a hard
    /// error, and fall back to `channel.continueRun` for follow-ups.
    public let conversationID: String?
    /// The `nextSeq` the host returned for this turn — the `baseSeq` the next
    /// follow-up's `agent.conversations.append` call must send.
    public let nextBaseSeq: Int
    public init(runId: String, channel: any RunControlling, title: String, subtitle: String, cwd: String, conversationID: String? = nil, nextBaseSeq: Int = 0) {
        self.runId = runId
        self.channel = channel
        self.title = title
        self.subtitle = subtitle
        self.cwd = cwd
        self.conversationID = conversationID
        self.nextBaseSeq = nextBaseSeq
    }
    public var id: String { runId }
}

/// What performDispatch resolved to, returned directly to the caller (NewChatTabView)
/// instead of mutating shared AppRoot state — so the inline thread owns its own
/// run lifecycle rather than a separate sheet-presented page reacting to it.
public enum ChatDispatchOutcome {
    case started(ActiveChatRun)
    case blocked(String)
}

/// RunControlling for relay-dispatched runs. Stop/pause/resume route over the
/// relay to the daemon's dispatcher; the resulting status streams back over
/// agent.run.status. Budget-over-relay isn't wired yet (returns false).
struct RelayRunControl: RunControlling {
    let send: @Sendable (_ runId: String, _ action: String) async -> Bool
    let onContinue: @Sendable (_ runId: String, _ prompt: String) async throws -> DispatchResult
    func pauseRun(runId: String) async throws -> Bool { await send(runId, "pause") }
    func resumeRun(runId: String) async throws -> Bool { await send(runId, "resume") }
    func stopRun(runId: String) async throws -> Bool { await send(runId, "stop") }
    func setRunBudget(runId: String, budgetUSD: Double) async throws -> Bool { false }
    func continueRun(runId: String, prompt: String) async throws -> DispatchResult {
        try await onContinue(runId, prompt)
    }
}

#endif
