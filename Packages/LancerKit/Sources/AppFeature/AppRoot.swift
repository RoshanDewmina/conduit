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

    var id: String {
        switch self {
        case .addMachine: "add-machine"
        case .relayPairing: "relay-pairing"
        case .addHost: "add-host"
        case .editHost(let host): "edit-host-\(host.id)"
        }
    }
}

public struct AppRoot: View {
    @State private var environment: AppEnvironmentResult
    @State private var sessionViewModel: SessionViewModel?
    @State private var drawerRoute: AppDrawerRoute?
    @State private var workspacesRevision = UUID()
    @State private var passwordPromptHost: Host?
    @State private var connectionError: String?
    @State private var inboxVM = InboxViewModel()
    @State private var liveInboxVM: LiveInboxViewModel?
    @State private var runOutputStore = RunOutputStore()
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

    /// Cursor-styled surfaces follow the same appearance control as the sidebar shell.
    private var cursorResolvedScheme: CursorScheme {
        effectiveScheme == .dark ? .dark : .light
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
    @State private var cursorLiveBridge = CursorShellLiveBridge()
    @State private var showingCursorSettings = false
    @State private var showingCursorRelayPairing = false
    /// Presents the Cursor-style approval review sheet (replaces legacy Inbox).
    @State private var showingApprovalReview = false
    /// Idempotency guard for `configureRelayFleetStore` — it used to check
    /// `e2eBridge == nil`, but there's no single bridge anymore.
    @State private var configuredRelayFleetStore = false

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

    /// UI-audit hook: skip the system notification-permission prompt. On this
    /// Xcode-beta/iOS27 headless simulator, that system alert doesn't respond
    /// to HID taps at all (idb `ui_tap`, XcodeBuildMCP `tap`/`key_press` all
    /// no-op on it — a known limitation, see the 2026-07-02 Device Hub matrix
    /// report), permanently blocking automated screenshot/UI passes on any
    /// freshly-installed simulator. Gated `#if DEBUG` like the other launch
    /// seams in `init()` below — never compiled into a release build.
    static var skipNotificationPromptForUITesting: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["LANCER_SKIP_NOTIFICATION_PROMPT"] == "1"
        #else
        false
        #endif
    }

    public init() {
        do {
            let env = try AppEnvironment()
            _environment = State(initialValue: .ready(env))
        } catch {
            _environment = State(initialValue: .failure(error.localizedDescription))
        }
        #if DEBUG
        // UI-test / relay E2E launch seam — skip onboarding so the destination
        // overlay (Inbox sheet, Settings sheet) can appear on first frame.
        if ProcessInfo.processInfo.environment["LANCER_DESTINATION"] != nil {
            UserDefaults.standard.set(true, forKey: "onboardingSeen")
        }
        #endif
    }

    @ViewBuilder
    public var body: some View {
        #if DEBUG
        if usesMockCursorShell {
            CursorAppShell()
        } else {
            mainBody.environment(\.lancerTokens, tokens)
        }
        #else
        mainBody.environment(\.lancerTokens, tokens)
        #endif
    }

    #if DEBUG
    /// Mock Cursor shell for UI tests (`LANCER_CURSOR_SHELL=1`) and design review.
    private var usesMockCursorShell: Bool {
        ProcessInfo.processInfo.environment["LANCER_CURSOR_SHELL"] == "1"
    }
    #endif

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
            if onboardingSeen && !Self.skipNotificationPromptForUITesting {
                Notifications.shared.registerCategories()
                _ = await Notifications.shared.requestAuthorization()
            }
        }
        .onChange(of: onboardingSeen) { _, seen in
            if seen && !Self.skipNotificationPromptForUITesting {
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
                  let approvalIDString = note.userInfo?["approvalId"] as? String
            else {
                showingApprovalReview = true
                return
            }
            if let approval = activeInboxViewModel.approvals.first(where: { $0.id.uuidString.lowercased() == approvalIDString.lowercased() }) {
                cursorLiveBridge.pendingApprovalID = approval.id
            } else if let uuid = UUID(uuidString: approvalIDString) {
                cursorLiveBridge.pendingApprovalID = ApprovalID(uuid)
            }
            workspacesRevision = UUID()
            showingApprovalReview = true
            _ = env
        }
        // Relay run output/status: the E2ERelayBridge posts these as typed params.
        // Feed them into runOutputStore so the presented RunDetailView streams live.
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("lancerE2ERunOutput"))) { note in
            guard let params = note.userInfo?["params"] as? RunOutputParams else {
                Logger(subsystem: "dev.lancer.mobile", category: "AppRoot").error("lancerE2ERunOutput: bad params in notification")
                return
            }
            runOutputStore.appendOutput(params)
            Logger(subsystem: "dev.lancer.mobile", category: "AppRoot").info("lancerE2ERunOutput: runId=\(params.runId, privacy: .public) activeRunID=\(cursorLiveBridge.activeRunID ?? "nil", privacy: .public) textLen=\(runOutputStore.run(params.runId)?.text.count ?? -1, privacy: .public)")
            if params.runId == cursorLiveBridge.activeRunID {
                cursorLiveBridge.activeThreadResponse = runOutputStore.run(params.runId)?.text ?? ""
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("lancerE2EToolStart"))) { note in
            guard let params = note.userInfo?["params"] as? ToolStartParams else { return }
            runOutputStore.appendToolStart(params)
            if params.runId == cursorLiveBridge.activeRunID {
                cursorLiveBridge.activeThreadResponse = runOutputStore.run(params.runId)?.text ?? ""
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("lancerE2ERunStatus"))) { note in
            guard let params = note.userInfo?["params"] as? RunStatusParams else {
                Logger(subsystem: "dev.lancer.mobile", category: "AppRoot").error("lancerE2ERunStatus: bad params in notification")
                return
            }
            runOutputStore.updateStatus(params)
            Logger(subsystem: "dev.lancer.mobile", category: "AppRoot").info("lancerE2ERunStatus: runId=\(params.runId, privacy: .public) activeRunID=\(cursorLiveBridge.activeRunID ?? "nil", privacy: .public) status=\(params.status, privacy: .public) exitCode=\(params.exitCode ?? -999, privacy: .public) storedTextLen=\(runOutputStore.run(params.runId)?.text.count ?? -1, privacy: .public)")
            if params.runId == cursorLiveBridge.activeRunID,
               params.status == "exited" || params.status == "failed" {
                cursorLiveBridge.activeThreadIsWorking = false
                if params.status == "failed" || params.exitCode != 0 {
                    cursorLiveBridge.activeThreadError = runOutputStore.run(params.runId)?.text
                }
            }
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
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("lancerE2ERunReceipt"))) { note in
            guard let receipt = note.userInfo?["receipt"] as? ProofReceipt,
                  case .ready(let env) = environment
            else { return }
            Task {
                guard let payloadData = try? JSONEncoder().encode(receipt),
                      let payloadJSON = String(data: payloadData, encoding: .utf8),
                      let conversationID = try? await env.chatRepo.upsertReceipt(
                        runID: receipt.runId,
                        payloadJSON: payloadJSON
                      )
                else { return }
                NotificationCenter.default.post(
                    name: .lancerChatArtifactPersisted,
                    object: nil,
                    userInfo: ["conversationID": conversationID]
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .lancerChatArtifactPersisted)) { note in
            guard let conversationID = note.userInfo?["conversationID"] as? String,
                  case .ready(let env) = environment else { return }
            Task { await reloadActiveThreadArtifacts(env: env, conversationID: conversationID) }
        }
        // Relay-delivered approvals: the E2E bridge posts lancerE2EApprovalReceived,
        // but on a relay-only setup there's no SSH ApprovalIngest to land them in the
        // inbox. Map the ApprovalData into an Approval and surface it in the active
        // inbox VM so the firewall request actually renders.
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("lancerE2EApprovalReceived"))) { note in
            guard let data = note.userInfo?["approvalData"] as? E2ERelayMessage.ApprovalData else { return }
            // Fresh installs may receive a relay approval before the .task{} that
            // calls configureGlobalInbox(env:) has run — configure it defensively
            // here too so the notification never drops onto the static fallback
            // InboxViewModel instead of the live one.
            if case .ready(let env) = environment {
                configureGlobalInbox(env: env)
            }
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
            // Persist to the durable store, not just the in-memory VM below —
            // this is NOT optional durability polish: LiveInboxViewModel.decide()
            // (InboxViewModel+Live.swift) guards its DB UPDATE on `WHERE id=?
            // AND decision IS NULL`, and only calls `onDecision` (which forwards
            // the decision over the relay) when that UPDATE actually matched a
            // row. Without this row existing, a relay-only approval's Approve tap
            // flips the LOCAL UI (via `applyDecision`, unconditional) but the
            // decision never reaches the daemon — reproduced via
            // relay-approval-e2e.sh 2026-07-07: xcodebuild rc=0 (UI showed
            // "Approved") yet the host hook never unblocked and the audit log
            // never gained an "approve" entry. This upsert previously raced
            // `onPendingApprovalsChanged`'s count==0 branch and popped the
            // Review sheet shut before Approve could be tapped at all (a
            // separate bug, fixed above by cross-checking the in-memory list
            // before clearing `pendingApprovalID` rather than by removing this
            // write).
            if case .ready(let env) = environment {
                Task { @MainActor in
                    let repo = approvalRepository ?? ApprovalRepository(env.database)
                    do {
                        try await repo.upsert(approval)
                        Self.logger.info("lancerE2EApprovalReceived: upsert OK id=\(approval.id.uuidString, privacy: .public)")
                    } catch {
                        Self.logger.error("lancerE2EApprovalReceived: upsert FAILED id=\(approval.id.uuidString, privacy: .public) error=\(String(describing: error), privacy: .public)")
                    }
                }
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
                CursorOnboardingView(onComplete: { onboardingSeen = true })
                    .environment(\.cursorScheme, cursorResolvedScheme)
                    .environment(\.cursorShellLiveBridge, cursorLiveBridge)
                    .sheet(isPresented: $showingCursorRelayPairing) {
                        CursorRelayPairingSheet(
                            existingMachineCount: relayFleetStore.machines.count,
                            onPaired: { client, record in
                                addRelayMachine(client: client, record: record, env: env)
                                showingCursorRelayPairing = false
                            }
                        )
                    }
            }
        }
        .sheet(isPresented: $showingQuotaGuard) {
            CursorDrawer(title: "Usage & limits", detents: [.large]) {
                QuotaGuardView(store: env.quotaGuardStore)
            }
        }
        .sheet(isPresented: $showingRelayWorkspaceUnavailable) {
            CursorDrawer(detents: [.large]) {
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
            setupCursorLiveBridge(env: env)
            // Relay auto-pair + bridge registration must complete before the host
            // can deliver an escalation over the production relay (relay-approval-e2e).
            await configureCloudServices(env: env)
#if DEBUG
            if ProcessInfo.processInfo.environment["LANCER_SEED_DEMO"] == "1" {
                await DebugSeeder.seedIfNeeded(env: env)
            }
            await DebugSeeder.resetForUITestIfRequested(env: env)
            await DebugSeeder.seedDaemonE2EHostIfRequested(env: env)
            if ProcessInfo.processInfo.environment["LANCER_UITEST_RESEED"] == "1" {
                // Read pending approvals directly from the repo — the LiveInboxViewModel's
                // observe() stream may not have emitted yet when this .task runs.
                if let pending = try? await env.approvalRepo.pending().first {
                    cursorLiveBridge.pendingApprovalID = pending.id
                } else {
                    cursorLiveBridge.pendingApprovalID = activeInboxViewModel.approvals.first(where: \.isPending)?.id
                }
                if let all = try? await env.approvalRepo.all() {
                    liveInboxVM?.approvals = all
                }
                cursorLiveBridge.relayMachineCount = relayFleetStore.machines.count
                cursorLiveBridge.invalidMachineCount = relayFleetStore.invalidMachines.count
                workspacesRevision = UUID()
            }
#endif
            // MAJOR-6: replay any approval action tapped from a lock-screen banner
            // while the app was killed (its NotificationCenter post had no live
            // subscriber). Done after configureCloudServices so the relay backend
            // is configured.
            await drainPendingApprovalActions(env: env)
#if DEBUG
            applyDebugLaunchSeams()
#endif
            for approvalID in OpenApprovalBuffer.shared.drain() {
                if let uuid = UUID(uuidString: approvalID) {
                    cursorLiveBridge.pendingApprovalID = ApprovalID(uuid)
                }
                showingApprovalReview = true
            }
            await env.syncEngine.start()
            await env.conversationSyncEngine.start()
        }
    }

    @ViewBuilder
    private func rootContainer(env: AppEnvironment) -> some View {
        cursorShellRoot(env: env)
        .onChange(of: fleetStore.attentionItems.count, initial: true) { _, count in
            let highestRisk = fleetStore.attentionItems.map(\.severity.rawValue).max()
            if #available(iOS 16.2, *) {
                Task { await LancerLiveActivityManager.shared.updatePendingApprovals(count, highestRisk: highestRisk) }
            }
        }
        .environment(\.cursorScheme, cursorResolvedScheme)
        .environment(\.cursorShellLiveBridge, cursorLiveBridge)
    }

    @ViewBuilder
    private func cursorShellRoot(env: AppEnvironment) -> some View {
        CursorAppShell(liveBridge: cursorLiveBridge)
            .task(id: workspacesRevision) { await refreshCursorLiveBridge(env: env) }
            .sheet(isPresented: $showingCursorSettings) {
                cursorSettingsSheet(env: env)
            }
            .sheet(isPresented: $showingCursorRelayPairing) {
                CursorRelayPairingSheet(
                    existingMachineCount: relayFleetStore.machines.count,
                    onPaired: { client, record in
                        addRelayMachine(client: client, record: record, env: env)
                        showingCursorRelayPairing = false
                    }
                )
            }
            .sheet(isPresented: $showingApprovalReview) {
                CursorReviewDiffView(onBack: { showingApprovalReview = false })
                    .environment(\.cursorShellLiveBridge, cursorLiveBridge)
            }
            .fullScreenCover(isPresented: $isShowingLiveSession) {
                if let vm = activeSessionViewModel {
                    SessionWorkspaceContainer(
                        viewModel: vm,
                        onSwitchHost: { isShowingLiveSession = false }
                    )
                    .environment(\.lancerTokens, tokens)
                }
            }
    }

    #if DEBUG
    @MainActor
    private func applyDebugLaunchSeams() {
        guard let dest = ProcessInfo.processInfo.environment["LANCER_DESTINATION"] else { return }
        switch dest {
        case "inbox", "approval", "review":
            cursorLiveBridge.pendingApprovalID = activeInboxViewModel.approvals.first(where: \.isPending)?.id
            cursorLiveBridge.relayMachineCount = relayFleetStore.machines.count
            cursorLiveBridge.invalidMachineCount = relayFleetStore.invalidMachines.count
            showingApprovalReview = true
        case "settings", "governance": showingCursorSettings = true
        default: break
        }
    }
    #endif

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
        if relayFleetStore.isConnected(machineID) {
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
        }
    }

    @ViewBuilder
    private func drawerDestination(_ route: AppDrawerRoute, env: AppEnvironment) -> some View {
        switch route {
        case .addMachine:
            CursorDrawer(
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
            CursorDrawer(detents: [.large]) {
                CursorRelayPairingSheet(
                    existingMachineCount: relayFleetStore.machines.count,
                    onPaired: { client, record in
                        addRelayMachine(client: client, record: record, env: env)
                    }
                )
            }
        case .addHost:
            CursorDrawer(detents: [.large]) {
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
            CursorDrawer(detents: [.large]) {
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
        }
    }

    @MainActor
    private func configureGlobalInbox(env: AppEnvironment) {
        guard liveInboxVM == nil else { return }
        let approvalRepo = ApprovalRepository(env.database)
        let liveVM = LiveInboxViewModel(
            repository: approvalRepo,
            onDecision: { id, decision, edited, contentHash in
            Logger(subsystem: "dev.lancer.mobile", category: "AppRoot").info("onDecision: fired id=\(id.uuidString, privacy: .public) decision=\(decision.rawValue, privacy: .public)")
            // Prefer the channel of the slot that owns this approval (multi-slot
            // correct). On a dead/absent channel fall back to the relay's single
            // forwarding chokepoint (backend POST + SSH-drain queue) rather than
            // `try?`-swallowing the write and silently dropping the decision
            // (MAJOR-5). LiveInboxViewModel persists the decision before firing
            // onDecision, so no DB write is needed here.
            if let slot = await MainActor.run(body: { self.fleetStore.slot(forApprovalID: id) }) {
                Logger(subsystem: "dev.lancer.mobile", category: "AppRoot").info("onDecision: routed via fleet slot id=\(id.uuidString, privacy: .public)")
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
        },
            onPendingApprovalsChanged: { [self] count, _, idString in
                await MainActor.run {
                    if let idString, let uuid = UUID(uuidString: idString) {
                        cursorLiveBridge.pendingApprovalID = ApprovalID(uuid)
                    } else if count == 0 {
                        // Cross-check against the in-memory list before trusting a
                        // DB-observation "0 pending" snapshot: a relay approval is
                        // inserted into `vm.approvals` synchronously (below) before
                        // its `repo.upsert` write lands, so an observation re-emit
                        // racing that write can report count==0 for an approval we
                        // already know is genuinely pending — clearing
                        // pendingApprovalID on that stale signal pops the live
                        // Review sheet shut before the user can act (reproduced via
                        // relay-approval-e2e.sh 2026-07-07: button existed, then the
                        // sheet closed ~seconds later, confirmed via the XCUITest's
                        // failure-moment UI-hierarchy dump showing Workspaces root).
                        if !self.activeInboxViewModel.approvals.contains(where: \.isPending) {
                            cursorLiveBridge.pendingApprovalID = nil
                        }
                    }
                }
            }
        )
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

    @MainActor
    private func setupCursorLiveBridge(env: AppEnvironment) {
        cursorLiveBridge.lookupApproval = { [self] id in
            activeInboxViewModel.approvals.first(where: { $0.id == id })
        }
        cursorLiveBridge.onDispatch = { [self] prompt, cwd, model, contract in
            let agentID = defaultDispatchAgentID(env: env)
            cursorLiveBridge.activeThreadError = nil
            cursorLiveBridge.activeThreadIsWorking = true
            let outcome = await performDispatch(
                agentID: agentID,
                cwd: cwd,
                prompt: prompt,
                budgetUSD: nil,
                model: model,
                contract: contract,
                env: env
            )
            switch outcome {
            case .started(let run):
                Logger(subsystem: "dev.lancer.mobile", category: "AppRoot").info("onDispatch: started runId=\(run.runId, privacy: .public) conversationID=\(run.conversationID ?? "nil", privacy: .public)")
                cursorLiveBridge.activeRunID = run.runId
                cursorLiveBridge.selectedThreadID = run.conversationID
            case .blocked(let message):
                Logger(subsystem: "dev.lancer.mobile", category: "AppRoot").info("onDispatch: blocked message=\(message, privacy: .public)")
                // Previously silent — a denied/errored dispatch left the user
                // staring at a screen that never changed, with no indication
                // anything had gone wrong (this is the exact "nothing
                // happened" symptom traced back to a bad cwd on 2026-07-07,
                // before the underlying cwd bug itself was found and fixed).
                cursorLiveBridge.activeThreadIsWorking = false
                cursorLiveBridge.activeThreadError = message
            }
            workspacesRevision = UUID()
        }
        cursorLiveBridge.onOpenThread = { [self] conversationID in
            cursorLiveBridge.activeThreadError = nil
            guard let lastTurn = try? await env.chatRepo.turns(conversationID: conversationID).last else {
                // A thread can legitimately have zero turns yet (e.g. selected
                // right as it's being created) — leave activeThread* alone
                // rather than stomping in-flight state with a false "empty".
                return
            }
            cursorLiveBridge.activeThreadPrompt = lastTurn.prompt
            cursorLiveBridge.activeThreadResponse = lastTurn.assistantText
            cursorLiveBridge.activeRunID = lastTurn.runID
            cursorLiveBridge.activeThreadIsWorking = (lastTurn.status == .running)
            if lastTurn.status == .failed {
                cursorLiveBridge.activeThreadError = lastTurn.errorMessage
            }
            await reloadActiveThreadArtifacts(env: env, conversationID: conversationID)
        }
        cursorLiveBridge.onAcceptReceipt = { [self] artifact in
            guard case .ready(let env) = environment,
                  let updatedPayload = ReceiptCardModel.mergeAcceptedAt(into: artifact.payloadJSON) else { return }
            var updated = artifact
            updated.payloadJSON = updatedPayload
            updated.updatedAt = .now
            try? await env.chatRepo.upsertArtifact(updated)
            await reloadActiveThreadArtifacts(env: env, conversationID: artifact.conversationID)
        }
        cursorLiveBridge.onContinue = { [self] conversationID, prompt, model, contract in
            guard let conv = try? await env.chatRepo.conversation(id: conversationID) else {
                cursorLiveBridge.activeThreadError = "Couldn't find that conversation to continue."
                return
            }
            cursorLiveBridge.activeThreadError = nil
            cursorLiveBridge.activeThreadIsWorking = true
            cursorLiveBridge.activeThreadResponse = ""
            let outcome = await performContinueConversation(
                conversationID: conv.id,
                baseSeq: conv.lastHostSeq,
                prompt: prompt,
                agentID: conv.agentID,
                cwd: conv.cwd,
                model: model ?? conv.model,
                contract: contract,
                env: env
            )
            switch outcome {
            case .started(let run):
                cursorLiveBridge.activeRunID = run.runId
            case .blocked(let message):
                cursorLiveBridge.activeThreadIsWorking = false
                cursorLiveBridge.activeThreadError = message
            }
            workspacesRevision = UUID()
        }
        cursorLiveBridge.onSearch = { query in
            guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
            return (try? await env.chatRepo.search(query)) ?? []
        }
        cursorLiveBridge.onDecide = { [self] id, decision in
            if let slot = fleetStore.slot(forApprovalID: id) {
                slot.inboxVM.decide(id, decision: decision)
            } else {
                activeInboxViewModel.decide(id, decision: decision)
            }
        }
        cursorLiveBridge.onRequestPairing = { showingCursorRelayPairing = true }
        cursorLiveBridge.onPaired = { [self] client, record in
            addRelayMachine(client: client, record: record, env: env)
        }
        cursorLiveBridge.onClearInvalid = { [self] in
            relayFleetStore.removeAllInvalid()
        }
    }

    @MainActor
    private func reloadActiveThreadArtifacts(env: AppEnvironment, conversationID: String) async {
        guard cursorLiveBridge.selectedThreadID == conversationID else { return }
        let turns = (try? await env.chatRepo.turns(conversationID: conversationID)) ?? []
        if let runID = cursorLiveBridge.activeRunID {
            cursorLiveBridge.activeThreadArtifacts = (try? await env.chatRepo.artifacts(runID: runID)) ?? []
        } else if let lastTurn = turns.last {
            cursorLiveBridge.activeRunID = lastTurn.runID
            cursorLiveBridge.activeThreadArtifacts = (try? await env.chatRepo.artifacts(turnID: lastTurn.id)) ?? []
        } else {
            cursorLiveBridge.activeThreadArtifacts = (try? await env.chatRepo.artifacts(conversationID: conversationID)) ?? []
        }
        if let conv = try? await env.chatRepo.conversation(id: conversationID) {
            cursorLiveBridge.activeThreadCWD = conv.cwd
        }
    }

    @ViewBuilder
    private func cursorSettingsSheet(env: AppEnvironment) -> some View {
        CursorSettingsView(
            relayMachineCount: relayFleetStore.machines.count,
            invalidMachineCount: relayFleetStore.invalidMachines.count,
            onPaired: { client, record in
                addRelayMachine(client: client, record: record, env: env)
            },
            onClearInvalid: {
                relayFleetStore.removeAllInvalid()
            }
        )
    }

    @MainActor
    private func refreshCursorLiveBridge(env: AppEnvironment) async {
        do {
            let conversations = try await env.chatRepo.recent(limit: 200)
            var counts: [String: Int] = [:]
            var threads: [String: [CursorShellLiveBridge.ThreadRow]] = [:]
            // machineID → hostName, keyed by repo name. OrderedSet semantics via dict key.
            var runTargetIDsByRepo: [String: [String: String]] = [:]
            // repo display name → its most recent conversation's real absolute cwd
            // (`recent()` is newest-first, so first-seen wins). A fresh dispatch
            // with no existing thread has no `conv.cwd` of its own to reuse — this
            // is how it still gets a real path instead of the bare repo name.
            var repoPaths: [String: String] = [:]
            for conv in conversations {
                let repo = (conv.cwd as NSString).lastPathComponent.isEmpty ? conv.cwd : (conv.cwd as NSString).lastPathComponent
                counts[repo, default: 0] += 1
                if repoPaths[repo] == nil, !conv.cwd.isEmpty {
                    repoPaths[repo] = conv.cwd
                }
                threads[repo, default: []].append(
                    CursorShellLiveBridge.ThreadRow(
                        id: conv.id,
                        title: conv.title,
                        repoName: repo,
                        updatedAt: conv.updatedAt,
                        hostID: conv.hostID,
                        hostName: conv.hostName.isEmpty ? nil : conv.hostName
                    )
                )
                // Accumulate distinct (hostID, hostName) pairs per repo.
                if let hid = conv.hostID, !hid.isEmpty {
                    if runTargetIDsByRepo[repo] == nil { runTargetIDsByRepo[repo] = [:] }
                    // Only record the first-seen hostName for a given hostID.
                    if runTargetIDsByRepo[repo]![hid] == nil {
                        runTargetIDsByRepo[repo]![hid] = conv.hostName
                    }
                }
            }
            // Build sorted RunTarget arrays per repo.
            var runTargetsByRepo: [String: [CursorShellLiveBridge.RunTarget]] = [:]
            for (repo, idToName) in runTargetIDsByRepo {
                runTargetsByRepo[repo] = idToName
                    .sorted { $0.value < $1.value }
                    .map { CursorShellLiveBridge.RunTarget(machineID: $0.key, hostName: $0.value) }
            }
            let names = Array(counts.keys).sorted()
            cursorLiveBridge.reloadWorkspaces(
                from: names.isEmpty ? ["command-center"] : names,
                threadCounts: counts,
                runTargetsByRepo: runTargetsByRepo
            )
            cursorLiveBridge.repoPaths = repoPaths
            for (name, rows) in threads {
                let sorted = rows.sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
                cursorLiveBridge.reloadThreads(workspaceName: name, rows: sorted)
            }
            if let pendingFromVM = activeInboxViewModel.approvals.first(where: \.isPending)?.id {
                cursorLiveBridge.pendingApprovalID = pendingFromVM
            } else if let pendingList = try? await env.approvalRepo.pending() {
                cursorLiveBridge.pendingApprovalID = pendingList.first?.id
            }
            cursorLiveBridge.relayMachineCount = relayFleetStore.machines.count
            cursorLiveBridge.invalidMachineCount = relayFleetStore.invalidMachines.count
            cursorLiveBridge.threadAttention = threadAttentionMap(
                conversations: conversations,
                pendingApprovals: activeInboxViewModel.approvals.filter(\.isPending)
            )
            cursorLiveBridge.connectionPhase = Self.connectionPhase(
                for: relayFleetStore,
                fleetStore: fleetStore
            )
        } catch {
            // Best-effort hydration for the Cursor live shell.
        }
    }

    @MainActor
    private func threadAttentionMap(
        conversations: [ChatConversation],
        pendingApprovals: [Approval]
    ) -> [String: CursorThreadAttention] {
        var map: [String: CursorThreadAttention] = [:]
        for conv in conversations {
            let hasApproval = pendingApprovals.contains { approval in
                approval.cwd == conv.cwd || approval.agentSessionID == conv.id
            }
            if hasApproval {
                map[conv.id] = .needsApproval
            } else if conv.status == .active {
                map[conv.id] = .working
            }
        }
        return map
    }

    private func defaultDispatchAgentID(env: AppEnvironment) -> String {
        if let online = dispatchAgents().first(where: { !$0.isOffline }) {
            return online.id
        }
        return dispatchAgents().first?.id ?? "claude"
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
                    isOffline: !relayFleetStore.isConnected(machine.id),
                    hostID: machine.id.uuidString,
                    hostName: machine.record.displayName
                ))
            }
        }
        return agents
    }

    /// A fresh idempotency key for one `agent.conversations.append` call —
    /// `stable-device-id:random`, per the build handoff's `clientTurnId`
    /// contract. Uniqueness (not the exact device-id prefix format) is what
    /// matters: it only needs to let a replayed append map back to the same
    /// turn instead of creating a duplicate.
    private static let logger = Logger(subsystem: "dev.lancer.mobile", category: "AppRoot")

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
                nextBaseSeq: started.baseSeqForNextTurn,
                worktreePath: started.worktreePath
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

    private func performDispatch(
        agentID: String, cwd: String, prompt: String, budgetUSD: Double?, model: String? = nil,
        contract: ProofReceipt.Contract? = nil, env: AppEnvironment
    ) async -> ChatDispatchOutcome {
        let vendor = agentID.split(separator: "|").last.map(String.init) ?? agentID
        switch resolveAgentTransport(agentID: agentID, cwd: cwd, model: model) {
        case .failure(let message):
            return .blocked(message)
        case .success(let resolved):
            let outcome = await env.conversationSyncCoordinator.startConversation(
                agent: vendor, cwd: cwd, prompt: prompt, model: model, budgetUSD: budgetUSD,
                contract: contract,
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

    /// Appends a follow-up turn to an existing ledger-backed conversation.
    private func performContinueConversation(
        conversationID: String, baseSeq: Int, prompt: String, agentID: String, cwd: String, model: String?,
        contract: ProofReceipt.Contract? = nil, env: AppEnvironment
    ) async -> ChatDispatchOutcome {
        switch resolveAgentTransport(agentID: agentID, cwd: cwd, model: model) {
        case .failure(let message):
            return .blocked(message)
        case .success(let resolved):
            let outcome = await env.conversationSyncCoordinator.continueConversation(
                conversationID: conversationID, baseSeq: baseSeq, prompt: prompt,
                clientTurnID: Self.newClientTurnID(), model: model, budgetUSD: nil,
                contract: contract,
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
                    isShowingLiveSession = false
                } else if let fallback = fleetStore.slots.first {
                    selectFleetSlot(fallback.id)
                }
            }
        }
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
        for machine in relayFleetStore.machines where relayFleetStore.isConnected(machine.id) {
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

        // Reactively mirror connection-state transitions into the banner phase.
        relayFleetStore.connectionStates.addObserver { [relayFleetStore, cursorLiveBridge, fleetStore] _, _ in
            cursorLiveBridge.connectionPhase = AppRoot.connectionPhase(
                for: relayFleetStore,
                fleetStore: fleetStore
            )
        }

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
                for machine in self.relayFleetStore.machines where self.relayFleetStore.isConnected(machine.id) {
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
                for machine in self.relayFleetStore.machines where self.relayFleetStore.isConnected(machine.id) {
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
                // connect() below can complete pairing synchronously before this
                // loop starts consuming $pairingState — check the current value
                // first or the .paired transition is missed forever and the
                // headless observer just hangs.
                if client.pairingState == .paired {
                    addRelayMachine(
                        client: client,
                        record: RelayMachineRecord(id: client.machineID, displayName: "Relay host"),
                        env: env
                    )
                    return
                }
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
        // One launch-time summary of exactly which machines hydration is
        // about to restore. The 2026-07-04 daemon-restart incident took hours
        // to diagnose because there was no way to tell FROM LOGS which
        // pairings the phone still knew about vs. which had quietly never
        // made it into (or been dropped from) this index.
        Self.logger.info("hydrateRelayFleetStore: index has \(records.count, privacy: .public) machine(s): \(records.map { "\($0.id.uuidString.prefix(8))(\($0.displayName))" }.joined(separator: ", "), privacy: .public)")
        for record in records {
            let client = E2ERelayClient(relayURL: RelaySettings.url(), pairingCode: "", machineID: record.id)
            let restored = client.restoreNamespacedStoredPairing()
            addRelayMachine(client: client, record: record, env: env, pairingUsable: restored)
            // Only this restore-from-disk path needs to actively dial out — every
            // other addRelayMachine caller (debug seam, real pairing-UI callbacks)
            // already has a client that just live-paired moments ago, and calling
            // connect() again here tore down that fresh connection out from under
            // it. Gate on the FULL restore succeeding, not just the UserDefaults
            // code existing: the index (Keychain) can outlive the private key, and
            // dialing with a partial pairing spams the relay with unfixable 400s
            // while the UI shows the machine as forever-disconnected. An
            // un-restorable machine stays listed but offline; it needs a re-pair.
            if restored {
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
    private func addRelayMachine(client: E2ERelayClient, record: RelayMachineRecord, env: AppEnvironment, pairingUsable: Bool = true) {
        let bridge = E2ERelayBridge(relayClient: client, approvalRelay: ApprovalRelay.shared, machineID: record.id)
        let machine = RelayFleetStore.Machine(record: record, client: client, bridge: bridge)
        guard relayFleetStore.add(machine, pairingUsable: pairingUsable) else {
            // At the fleet cap the machine was NOT stored — do not start the
            // bridge or register it anywhere. Before this guard, the bridge
            // was started and registered with ApprovalRelay regardless, so a
            // cap-dropped pairing kept working in-memory (approvals, hourly
            // reconnects) and then silently vanished at the next relaunch
            // because it was never in the hydration index.
            Self.logger.fault("addRelayMachine: fleet at cap — machine=\(record.id.uuidString, privacy: .public) NOT added; tearing down its client. Remove a paired machine and re-pair.")
            client.disconnect()
            return
        }
        bridge.start()
        ApprovalRelay.shared.relayBridges[record.id] = bridge
        Task { @MainActor in
            // The bridge's `$isActive` edge remains the trigger for the
            // side-effect actions below (they need the paired bridge to be
            // ready to carry RPCs), but every derived STATE is read back from
            // the authoritative ConnectionStateStore — which updates strictly
            // before this async loop observes the edge.
            for await active in bridge.$isActive.values {
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
            Self.relayState(relayFleetStore.connectionState(for: $0.id))
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

    /// Maps relay + SSH fleet liveness onto the Cursor shell connection banner.
    private static func connectionPhase(
        for relayFleetStore: RelayFleetStore,
        fleetStore: FleetStore
    ) -> CursorShellLiveBridge.ConnectionPhase {
        let hasSSHConnected = fleetStore.slots.contains { $0.sessionViewModel.status == .connected }
        if relayFleetStore.machines.isEmpty, fleetStore.slots.isEmpty {
            return .needsPairing
        }
        if relayFleetStore.connectionStates.anyConnected || hasSSHConnected {
            return .connected
        }
        let states = relayFleetStore.machines.compactMap { relayFleetStore.connectionState(for: $0.id) }
        if !states.isEmpty, states.allSatisfy({ $0 == .pairingInvalid }) {
            return .needsPairing
        }
        if states.contains(where: { $0 == .reconnecting || $0 == .hostOffline }) {
            return .reconnecting
        }
        return .offline
    }

    /// Maps the authoritative per-machine connection state onto the
    /// `Session.RelayState` the status badge renders. Connected wins; a
    /// machine still able to recover on its own (reconnecting, or on the
    /// relay waiting for the daemon peer) reads as `.connecting`; a pairing
    /// that needs a human re-pair reads as `.error`.
    private static func relayState(_ state: ConnectionStateStore.MachineState?) -> Session.RelayState {
        switch state {
        case .connected: return .paired
        case .reconnecting, .hostOffline: return .connecting
        case .pairingInvalid: return .error
        case nil: return .none
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
                // Post-connect: session runs as a monitored fleet slot; the Cursor
                // shell stays on Workspaces — terminal is an intentional drill-in.
                self.workspacesRevision = UUID()
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

private struct PasswordPromptView: View {
    let host: Host
    let onConnect: (String) -> Void

    @State private var password = ""
    @Environment(\.dismiss) private var dismiss
    @Environment(\.cursorScheme) private var cursorScheme
    @FocusState private var passwordFocused: Bool

    private var colors: CursorColors { CursorColors.resolve(cursorScheme) }

    var body: some View {
        VStack(spacing: 0) {
            CursorHeaderBar(
                leading: AnyView(
                    CursorIconButton(systemImageName: "xmark", action: { dismiss() })
                ),
                trailing: []
            )
            .overlay(alignment: .center) {
                Text("Connect")
                    .font(CursorType.sheetTitle)
                    .foregroundColor(colors.primaryText)
                    .padding(.top, CursorMetrics.headerTopPadding)
            }

            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Circle()
                        .fill(colors.composerBackground)
                        .frame(width: 44, height: 44)
                        .overlay(
                            Text(String(host.name.prefix(1)).uppercased())
                                .font(CursorType.cardTitle)
                                .foregroundColor(colors.primaryText)
                        )
                    VStack(alignment: .leading, spacing: 3) {
                        Text(host.name)
                            .font(CursorType.rowTitle)
                            .foregroundColor(colors.primaryText)
                            .lineLimit(1)
                        Text(host.displayAddress)
                            .font(CursorType.inlineCode)
                            .foregroundColor(colors.secondaryText)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
                .background(colors.sheetBackground)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                Text("PASSWORD")
                    .font(CursorType.sectionHeader)
                    .foregroundColor(colors.mutedText)
                SecureField("Password", text: $password)
                    .font(CursorType.bodyText)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($passwordFocused)
                    .submitLabel(.go)
                    .onSubmit(connect)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .background(colors.composerBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                CursorPillButton(title: "Connect", style: .primary, action: connect)
                    .disabled(password.isEmpty)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            Spacer(minLength: 0)
        }
        .background(colors.background.ignoresSafeArea())
        .environment(\.cursorScheme, .light)
        .presentationDetents([.medium])
        .onAppear {
            passwordFocused = true
#if DEBUG
            if ProcessInfo.processInfo.environment["LANCER_DAEMON_E2E"] == "1",
               let pw = ProcessInfo.processInfo.environment["LANCER_TEST_PW"], !pw.isEmpty {
                password = pw
            }
#endif
        }
    }

    private func connect() {
        guard !password.isEmpty else { return }
        let value = password
        dismiss()
        onConnect(value)
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
    /// Daemon-managed per-run worktree path, when the run was dispatched with isolation.
    public let worktreePath: String?
    public init(runId: String, channel: any RunControlling, title: String, subtitle: String, cwd: String, conversationID: String? = nil, nextBaseSeq: Int = 0, worktreePath: String? = nil) {
        self.runId = runId
        self.channel = channel
        self.title = title
        self.subtitle = subtitle
        self.cwd = cwd
        self.conversationID = conversationID
        self.nextBaseSeq = nextBaseSeq
        self.worktreePath = worktreePath
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
