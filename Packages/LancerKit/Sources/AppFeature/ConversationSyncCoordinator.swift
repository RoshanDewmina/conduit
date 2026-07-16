import Foundation
import LancerCore

// MARK: - Turn transcript assembly (Z1 event kinds → ordered items)
//
// Patterns informed by Orca `native-chat-tool-fold` / `native-chat-tool-summary`
// (MIT — stablyai/orca). UI rendering is original SwiftUI.

/// One ordered segment inside a turn's assistant transcript.
public enum TurnTranscriptItem: Sendable, Hashable, Identifiable {
    case prose(TurnProseItem)
    case toolChip(ToolChipItem)
    case thinking(TurnThinkingItem)

    public var id: String {
        switch self {
        case .prose(let item): return item.id
        case .toolChip(let item): return item.id
        case .thinking(let item): return item.id
        }
    }
}

public struct TurnProseItem: Sendable, Hashable, Identifiable {
    public let id: String
    public let text: String

    public init(id: String, text: String) {
        self.id = id
        self.text = text
    }
}

public struct TurnThinkingItem: Sendable, Hashable, Identifiable {
    public let id: String
    public let text: String

    public init(id: String, text: String) {
        self.id = id
        self.text = text
    }
}

/// Collapsed-by-default thinking caption (matches ThinkingRow).
public enum ThinkingPresentation: Sendable {
    public static let collapsedCaption = "Thinking…"
    public static let isExpandedByDefault = false
}

public struct ToolChipItem: Sendable, Hashable, Identifiable {
    public enum Status: String, Sendable, Hashable {
        case running
        case done
        case failed
    }

    public let id: String
    public let toolUseId: String
    public let name: String
    public let inputJSON: String?
    public let resultText: String?
    public let added: Int?
    public let removed: Int?
    public let isError: Bool
    public let status: Status

    public init(
        id: String,
        toolUseId: String,
        name: String,
        inputJSON: String? = nil,
        resultText: String? = nil,
        added: Int? = nil,
        removed: Int? = nil,
        isError: Bool = false,
        status: Status = .done
    ) {
        self.id = id
        self.toolUseId = toolUseId
        self.name = name
        self.inputJSON = inputJSON
        self.resultText = resultText
        self.added = added
        self.removed = removed
        self.isError = isError
        self.status = isError ? .failed : status
    }

    /// Live `ChatArtifact.kind == .tool` → chip (persisted-but-never-rendered path).
    public init(artifact: ChatArtifact) {
        let payload = Self.parseObject(artifact.payloadJSON)
        let toolUseId = (payload?["toolUseId"] as? String)
            ?? (payload?["tool_use_id"] as? String)
            ?? artifact.id
        let name = (payload?["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? artifact.title
        let inputJSON: String? = {
            if let input = payload?["input"] {
                if let s = input as? String { return s }
                if JSONSerialization.isValidJSONObject(input),
                   let data = try? JSONSerialization.data(withJSONObject: input),
                   let s = String(data: data, encoding: .utf8) {
                    return s
                }
            }
            return artifact.payloadJSON == "{}" ? nil : artifact.payloadJSON
        }()
        let added = Self.intValue(payload?["added"])
        let removed = Self.intValue(payload?["removed"])
        let isError = (payload?["isError"] as? Bool) ?? (artifact.status == .failed)
        let status: Status = {
            switch artifact.status {
            case .running: return .running
            case .failed: return .failed
            case .done: return .done
            }
        }()
        self.init(
            id: artifact.id,
            toolUseId: toolUseId,
            name: name,
            inputJSON: inputJSON,
            resultText: artifact.summary,
            added: added,
            removed: removed,
            isError: isError,
            status: status
        )
    }

    private static func parseObject(_ json: String?) -> [String: Any]? {
        guard let json, let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return obj
    }

    private static func intValue(_ any: Any?) -> Int? {
        if let i = any as? Int { return i }
        if let n = any as? NSNumber { return n.intValue }
        return nil
    }
}

/// Render units after consecutive tool chips are grouped (view-layer input).
public enum TurnTranscriptRenderItem: Sendable, Hashable, Identifiable {
    case prose(TurnProseItem)
    case thinking(TurnThinkingItem)
    case toolChips([ToolChipItem])

    public var id: String {
        switch self {
        case .prose(let item): return item.id
        case .thinking(let item): return item.id
        case .toolChips(let chips): return chips.map(\.id).joined(separator: "|")
        }
    }
}

/// Near-bottom / jump-to-latest policy — Orca `native-chat-autoscroll.ts` (MIT).
public enum ChatScrollPolicy: Sendable {
    /// Orca `NATIVE_CHAT_BOTTOM_THRESHOLD_PX`.
    public static let nearBottomThreshold: Double = 48

    public static func distanceFromBottom(
        contentHeight: Double,
        viewportHeight: Double,
        contentOffsetY: Double
    ) -> Double {
        max(0, contentHeight - viewportHeight - contentOffsetY)
    }

    public static func isNearBottom(distanceFromBottom: Double) -> Bool {
        distanceFromBottom <= nearBottomThreshold
    }

    public static func shouldShowJumpToLatest(distanceFromBottom: Double) -> Bool {
        distanceFromBottom > nearBottomThreshold
    }
}

/// Pure events → ordered turn items + chip title helpers.
public enum TurnTranscriptAssembler: Sendable {
    /// Matches Orca `MAX_TOOL_RESULT_CHARS = 4000`.
    public static let detailByteCap = 4096

    /// Prose-only concatenation for `ChatTurn.assistantText` (existing consumers).
    public static func assistantText(from events: [ChatEvent]) -> String {
        events
            .filter { $0.kind == "output" }
            .sorted { $0.seq < $1.seq }
            .compactMap(\.text)
            .joined()
    }

    /// Ordered `[prose | toolChip | thinking]`. Unknown kinds ignored (never invent).
    public static func items(from events: [ChatEvent]) -> [TurnTranscriptItem] {
        let sorted = events.sorted { $0.seq < $1.seq }
        var resultsByToolUseId: [String: ToolResultBits] = [:]
        for event in sorted where event.kind == "tool_result" {
            let payload = parsePayload(event.payloadJSON)
            let toolUseId = stringValue(payload, "toolUseId")
                ?? stringValue(payload, "tool_use_id")
                ?? event.text
            guard let toolUseId, !toolUseId.isEmpty else { continue }
            resultsByToolUseId[toolUseId] = ToolResultBits(
                text: event.text ?? stringValue(payload, "content") ?? stringValue(payload, "result"),
                isError: boolValue(payload, "isError") ?? boolValue(payload, "is_error") ?? false,
                added: intValue(payload, "added"),
                removed: intValue(payload, "removed")
            )
        }

        var items: [TurnTranscriptItem] = []
        var proseBuffer = ""
        var proseStartSeq: Int?

        func flushProse() {
            let trimmed = proseBuffer
            guard !trimmed.isEmpty, let start = proseStartSeq else {
                proseBuffer = ""
                proseStartSeq = nil
                return
            }
            items.append(.prose(TurnProseItem(id: "prose-\(start)", text: trimmed)))
            proseBuffer = ""
            proseStartSeq = nil
        }

        for event in sorted {
            switch event.kind {
            case "output":
                if let text = event.text, !text.isEmpty {
                    if proseStartSeq == nil { proseStartSeq = event.seq }
                    proseBuffer += text
                }

            case "thinking":
                flushProse()
                let text = event.text
                    ?? stringValue(parsePayload(event.payloadJSON), "text")
                    ?? ""
                guard !text.isEmpty else { continue }
                items.append(.thinking(TurnThinkingItem(id: "thinking-\(event.seq)", text: text)))

            case "tool_call":
                flushProse()
                let payload = parsePayload(event.payloadJSON)
                let name = stringValue(payload, "name")
                    ?? event.text
                    ?? "Tool"
                let toolUseId = stringValue(payload, "toolUseId")
                    ?? stringValue(payload, "tool_use_id")
                    ?? "seq-\(event.seq)"
                let inputJSON: String? = {
                    guard let input = payload?["input"] else {
                        return event.payloadJSON
                    }
                    if let s = input as? String { return s }
                    if JSONSerialization.isValidJSONObject(input),
                       let data = try? JSONSerialization.data(withJSONObject: input),
                       let s = String(data: data, encoding: .utf8) {
                        return s
                    }
                    return event.payloadJSON
                }()
                let result = resultsByToolUseId[toolUseId]
                let added = intValue(payload, "added") ?? result?.added
                let removed = intValue(payload, "removed") ?? result?.removed
                let isError = result?.isError
                    ?? boolValue(payload, "isError")
                    ?? false
                let status: ToolChipItem.Status = {
                    if isError { return .failed }
                    if result != nil { return .done }
                    return .running
                }()
                items.append(.toolChip(ToolChipItem(
                    id: "tool-\(event.seq)",
                    toolUseId: toolUseId,
                    name: name,
                    inputJSON: inputJSON,
                    resultText: result?.text,
                    added: added,
                    removed: removed,
                    isError: isError,
                    status: status
                )))

            default:
                // Unknown kinds (status, receipt, approval, …): ignore for transcript items.
                continue
            }
        }
        flushProse()
        return items
    }

    /// Collapse consecutive tool chips into groups for the compact chip row.
    public static func groupedForDisplay(_ items: [TurnTranscriptItem]) -> [TurnTranscriptRenderItem] {
        var out: [TurnTranscriptRenderItem] = []
        var chipRun: [ToolChipItem] = []

        func flushChips() {
            guard !chipRun.isEmpty else { return }
            out.append(.toolChips(chipRun))
            chipRun = []
        }

        for item in items {
            switch item {
            case .prose(let prose):
                flushChips()
                out.append(.prose(prose))
            case .thinking(let thinking):
                flushChips()
                out.append(.thinking(thinking))
            case .toolChip(let chip):
                chipRun.append(chip)
            }
        }
        flushChips()
        return out
    }

    /// Standalone one-line chip title (no trailing chevron).
    public static func chipTitle(name: String, inputJSON: String?) -> String {
        let normalized = normalizeToolName(name)
        let target = briefTarget(from: inputJSON)
        switch normalized {
        case "edit":
            return "Edited \(target ?? "a file")"
        case "write":
            return "Wrote \(target ?? "a file")"
        case "read":
            return "Read \(target ?? "a file")"
        case "bash", "shell", "command":
            return "Ran a command"
        default:
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Tool" : trimmed
        }
    }

    /// SF Symbol for a tool's normalized name — one switch, shared by every
    /// vendor (Claude Code, Codex, OpenCode, …) since they all report into the
    /// same `ToolChipItem.name` field. No per-provider icon code needed.
    public static func chipIcon(name: String) -> String {
        switch normalizeToolName(name) {
        case "edit": return "pencil"
        case "write": return "square.and.pencil"
        case "read": return "doc.text"
        case "bash", "shell", "command": return "terminal"
        default: return "wrench.and.screwdriver"
        }
    }

    /// Same one-switch pattern as `chipIcon`, extended to a run of chips: one
    /// shared icon when they're all the same tool type, a "mixed" icon otherwise.
    public static func groupedChipIcon(_ chips: [ToolChipItem]) -> String {
        guard let first = chips.first else { return "wrench.and.screwdriver" }
        let normalized = Set(chips.map { normalizeToolName($0.name) })
        return normalized.count == 1 ? chipIcon(name: first.name) : "square.stack"
    }

    /// Collapsed group label: "Read 3 files" or "Read a file, edited a file".
    public static func groupedChipTitle(_ chips: [ToolChipItem]) -> String {
        guard !chips.isEmpty else { return "Tools" }
        if chips.count == 1 {
            return chipTitle(name: chips[0].name, inputJSON: chips[0].inputJSON)
        }
        let normalized = chips.map { normalizeToolName($0.name) }
        if normalized.allSatisfy({ $0 == "read" }) {
            return "Read \(chips.count) files"
        }
        var parts: [String] = []
        for (index, chip) in chips.enumerated() {
            let phrase = groupMemberPhrase(name: chip.name)
            if index == 0 {
                parts.append(phrase.prefix(1).uppercased() + phrase.dropFirst())
            } else {
                parts.append(phrase)
            }
        }
        return parts.joined(separator: ", ")
    }

    public static func aggregatedDiff(chips: [ToolChipItem]) -> (added: Int, removed: Int)? {
        let added = chips.compactMap(\.added).reduce(0, +)
        let removed = chips.compactMap(\.removed).reduce(0, +)
        let hasAny = chips.contains { $0.added != nil || $0.removed != nil }
        guard hasAny else { return nil }
        return (added, removed)
    }

    public static func cappedDetail(_ text: String) -> String {
        let utf8 = Array(text.utf8)
        guard utf8.count > detailByteCap else { return text }
        var end = detailByteCap
        while end > 0 && (utf8[end] & 0b1100_0000) == 0b1000_0000 {
            end -= 1
        }
        return String(decoding: utf8[..<end], as: UTF8.self) + "…"
    }

    /// Post-turn compact activity line (Cursor-style "Worked 59s · Edited N…").
    public static func activitySummary(
        from items: [TurnTranscriptItem],
        startedAt: Date,
        completedAt: Date
    ) -> TurnActivitySummary {
        let chips = items.compactMap { item -> ToolChipItem? in
            if case .toolChip(let chip) = item { return chip }
            return nil
        }
        var edited = 0
        var explored = 0
        var searches = 0
        for chip in chips {
            switch toolActivityKind(chip.name) {
            case .edit: edited += 1
            case .explore: explored += 1
            case .search: searches += 1
            case .other: break
            }
        }
        let diff = aggregatedDiff(chips: chips)
        let seconds = max(0, Int(completedAt.timeIntervalSince(startedAt)))
        return TurnActivitySummary(
            durationSeconds: seconds,
            editedFileCount: edited,
            exploredCount: explored,
            searchCount: searches,
            added: diff?.added,
            removed: diff?.removed
        )
    }

    /// Latest TodoWrite/todo checklist in the turn, if a parseable payload exists.
    public static func latestTodoChecklist(from items: [TurnTranscriptItem]) -> TodoChecklistState? {
        TodoPayloadParser.latestChecklist(from: items)
    }

    /// Whether a tool chip should render as the todo card instead of a fold chip.
    public static func isTodoToolChip(_ chip: ToolChipItem) -> Bool {
        TodoPayloadParser.isTodoTool(name: chip.name)
    }

    // MARK: - Private helpers

    private enum ToolActivityKind {
        case edit, explore, search, other
    }

    private static func toolActivityKind(_ name: String) -> ToolActivityKind {
        switch normalizeToolName(name) {
        case "edit", "write", "strreplace", "applypatch", "apply_patch":
            return .edit
        case "read", "readfile", "read_file":
            return .explore
        case "grep", "glob", "search", "semanticsearch", "semantic_search", "rg", "findall":
            return .search
        default:
            return .other
        }
    }

    private struct ToolResultBits {
        var text: String?
        var isError: Bool
        var added: Int?
        var removed: Int?
    }

    static func normalizeToolName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func groupMemberPhrase(name: String) -> String {
        switch normalizeToolName(name) {
        case "edit": return "edited a file"
        case "write": return "wrote a file"
        case "read": return "read a file"
        case "bash", "shell", "command": return "ran a command"
        default:
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "used a tool" : trimmed.lowercased()
        }
    }

    static func briefTarget(from inputJSON: String?) -> String? {
        guard let inputJSON, let data = inputJSON.data(using: .utf8) else { return nil }
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let path = obj["file_path"] as? String ?? obj["path"] as? String
                ?? obj["notebook_path"] as? String, !path.isEmpty
            {
                return ChatFileNameDisplay.displayName(for: path)
            }
            if let files = obj["files"] as? [Any], files.count > 1 {
                return "\(files.count) files"
            }
            return nil
        }
        // Bare path string
        let trimmed = inputJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("/") || trimmed.hasSuffix(".swift") {
            return ChatFileNameDisplay.displayName(for: trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "\"")))
        }
        return nil
    }

    private static func parsePayload(_ json: String?) -> [String: Any]? {
        guard let json, let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return obj
    }

    private static func stringValue(_ obj: [String: Any]?, _ key: String) -> String? {
        guard let obj else { return nil }
        if let s = obj[key] as? String { return s }
        return nil
    }

    private static func intValue(_ obj: [String: Any]?, _ key: String) -> Int? {
        guard let obj else { return nil }
        if let i = obj[key] as? Int { return i }
        if let n = obj[key] as? NSNumber { return n.intValue }
        return nil
    }

    private static func boolValue(_ obj: [String: Any]?, _ key: String) -> Bool? {
        guard let obj else { return nil }
        if let b = obj[key] as? Bool { return b }
        return nil
    }
}

private extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

#if os(iOS)
import PersistenceKit
import SSHTransport

/// Transport-agnostic view of the `agent.conversations.*` RPCs, constructed
/// by the caller from whichever channel actually reaches the host right now
/// (a connected SSH slot's `DaemonChannel`, or a paired machine's
/// `E2ERelayBridge`) — mirrors the existing `RelayRunControl` pattern
/// (AppRoot.swift) that already unifies SSH/relay for run control instead of
/// making this coordinator aware of either transport concretely.
public struct ConversationTransport: Sendable {
    public let append: @Sendable (ConversationAppendRequest) async throws -> ConversationAppendResponse
    public let fetch: @Sendable (ConversationFetchRequest) async throws -> ConversationFetchResponse
    public let archive: @Sendable (ConversationArchiveRequest) async throws -> ConversationArchiveResponse

    public init(
        append: @escaping @Sendable (ConversationAppendRequest) async throws -> ConversationAppendResponse,
        fetch: @escaping @Sendable (ConversationFetchRequest) async throws -> ConversationFetchResponse,
        archive: @escaping @Sendable (ConversationArchiveRequest) async throws -> ConversationArchiveResponse
    ) {
        self.append = append
        self.fetch = fetch
        self.archive = archive
    }
}

/// Where a conversation stands for the sync status banner (ChatHistoryView /
/// NewChatTabView / sidebar rows) — a superset of `ChatConversation.SyncState`
/// that also covers states the UI cares about but the mirror row doesn't
/// persist (host offline, stale mirror, etc.).
public enum ConversationSyncUIState: Sendable, Equatable {
    /// No banner — mirror matches the host's last known state.
    case synced
    /// An append/fetch is in flight.
    case syncing
    /// The host could not be reached; cached history is shown, sending is
    /// disabled or kept as an explicit local draft (never auto-sent).
    case hostOffline
    /// The mirror hasn't been refreshed from the host in a while and may be
    /// behind another device's writes — a pull-to-refresh hint, not a hard error.
    case cloudStale
    /// The host rejected an append because `baseSeq` was stale — another
    /// device (or turn) moved the conversation first. Resolved by refetching.
    case conflict
    /// The last turn started without an exact vendor-session match (fell
    /// back to "continue latest in cwd") — still usable, but the UI should
    /// disclose that resume may not be exact.
    case degradedResume
    /// Another device's turn is currently running on this conversation.
    case streamingElsewhere
}

/// Orchestrates host-mediated conversation turns (`agent.conversations.append`)
/// and keeps the local GRDB mirror (Task 6) consistent with the host ledger's
/// responses, so UI code never has to hand-roll the append→mirror→publish
/// sequence itself. One instance is shared for the app's lifetime; sync state
/// is tracked per conversation ID.
///
/// This is the ONLY place that should call `ConversationTransport.append`/
/// `.fetch` for UI-driven turns — see the build handoff's non-negotiable #3
/// ("host mediates all appends") and #5 ("no silent offline execution").
public actor ConversationSyncCoordinator {
    private let chatRepo: ChatConversationRepository
    private var syncStates: [String: ConversationSyncUIState] = [:]
    private var continuations: [String: [UUID: AsyncStream<ConversationSyncUIState>.Continuation]] = [:]

    public init(chatRepo: ChatConversationRepository) {
        self.chatRepo = chatRepo
    }

    /// The outcome of a single append call — deliberately mirrors
    /// `ChatDispatchOutcome`'s started/blocked shape so AppRoot's existing
    /// call sites need minimal changes to adopt this.
    public enum TurnOutcome: Sendable {
        case started(TurnStarted)
        case blocked(String)
    }

    public struct TurnStarted: Sendable {
        public let conversationID: String
        public let turnID: String?
        public let runID: String
        public let cwd: String
        public let baseSeqForNextTurn: Int
        public let resumeMode: String?
        public let vendorSessionID: String?
        public let worktreePath: String?
        public let isolated: Bool
    }

    // MARK: - Public API

    /// Starts a brand-new conversation. On success, creates the local mirror
    /// row (`syncState: .synced`) so History/sidebar immediately show it
    /// without waiting for a separate fetch.
    public func startConversation(
        agent: String, cwd: String, prompt: String, model: String?, budgetUSD: Double?,
        contract: ProofReceipt.Contract? = nil,
        fullTools: Bool = false,
        hostName: String, hostID: String?, clientTurnID: String,
        transport: ConversationTransport,
        attachments: [ConversationAttachmentReference] = []
    ) async -> TurnOutcome {
        // `agent` may be a full routing id (`relay|<machineID>|<vendor>` or
        // `<slotUUID>|<vendor>`) from the composer — the daemon wire only wants
        // the vendor token, but the local mirror must keep the routing id so
        // follow-ups can resolve a transport without "Unknown agent."
        let vendor = agent.split(separator: "|").last.map(String.init) ?? agent
        return await append(
            ConversationAppendRequest(
                conversationId: nil, baseSeq: 0, clientTurnId: clientTurnID,
                agent: vendor, cwd: cwd, prompt: prompt, model: model, budgetUSD: budgetUSD,
                contract: contract,
                attachments: attachments.isEmpty ? nil : attachments,
                fullTools: fullTools
            ),
            hostName: hostName, hostID: hostID, transport: transport,
            routingAgentID: agent.contains("|") ? agent : nil
        )
    }

    /// Appends a follow-up turn to an existing conversation. `baseSeq` must be
    /// the caller's last-known `nextSeq`. A stale value produces a host-reported
    /// conflict; this method refetches once and retries before surfacing `.conflict`.
    public func continueConversation(
        conversationID: String, baseSeq: Int, prompt: String, clientTurnID: String,
        agent: String? = nil, model: String? = nil, budgetUSD: Double? = nil,
        contract: ProofReceipt.Contract? = nil,
        fullTools: Bool = false,
        hostName: String, hostID: String?,
        transport: ConversationTransport,
        attachments: [ConversationAttachmentReference] = []
    ) async -> TurnOutcome {
        await append(
            ConversationAppendRequest(
                conversationId: conversationID, baseSeq: baseSeq, clientTurnId: clientTurnID,
                agent: agent, cwd: nil, prompt: prompt, model: model, budgetUSD: budgetUSD,
                contract: contract,
                attachments: attachments.isEmpty ? nil : attachments,
                fullTools: fullTools
            ),
            hostName: hostName, hostID: hostID, transport: transport
        )
    }

    /// Pulls everything after the mirror's last known seq and merges it in —
    /// used on thread-open, pull-to-refresh, and conflict recovery ("Refresh"
    /// in the conflict banner). Returns the merged conversation's fresh
    /// `lastHostSeq` so the caller can use it as the next `baseSeq`.
    ///
    /// End-to-end wall budget defaults to `refreshWallBudget` (60s) across all
    /// pages and at most one transient retry — not a per-page multiplication of
    /// the 30s RPC timeout. `now` is injectable for deterministic budget tests.
    @discardableResult
    public func refreshConversation(
        conversationID: String,
        transport: ConversationTransport,
        wallBudget: Duration = ConversationSyncCoordinator.refreshWallBudget,
        now: @escaping @Sendable () -> ContinuousClock.Instant = { ContinuousClock.now }
    ) async throws -> Int {
        publish(.syncing, for: conversationID)
        let hydratedSeq = try await chatRepo.hydratedEventCursor(conversationID: conversationID)
        let deadline = now().advanced(by: wallBudget)
        do {
            let nextSeq = try await fetchAndMergeAllPages(
                conversationID: conversationID,
                sinceSeq: hydratedSeq,
                transport: transport,
                deadline: deadline,
                now: now
            )
            publish(.synced, for: conversationID)
            return nextSeq
        } catch let partial as ConversationSyncPartialError {
            // Page cap hit — everything fetched so far is merged and
            // lastHostSeq advanced; honest hint instead of claiming synced.
            publish(.cloudStale, for: conversationID)
            return partial.nextSeq
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if let e2e = error as? E2EError, case .notPaired = e2e {
                // Pairing loss is a real connectivity/auth failure — not a refresh timeout.
                publish(.hostOffline, for: conversationID)
                try? await chatRepo.updateSyncState(conversationID: conversationID, state: .hostOffline)
                throw error
            }
            // Fetch timeout / large-payload / budget exhaustion: cached transcript
            // stays usable. Never persist `.hostOffline` — that banner means the
            // machine is unreachable, which is not true for a timed-out refresh.
            publish(.cloudStale, for: conversationID)
            throw error
        }
    }

    /// Thrown by `fetchAndMergeAllPages` when `maxFetchPages` was reached with
    /// `hasMore` still true. All fetched pages are already merged; `nextSeq`
    /// is the resume cursor for the next refresh.
    public struct ConversationSyncPartialError: Error, Sendable {
        public let nextSeq: Int
    }

    /// Thrown when the shared refresh wall budget cannot start another RPC
    /// (remaining time below `fetchRPCTimeout`). Surfaces as stale + retryable
    /// in the UI — not as host-offline.
    public struct ConversationSyncRefreshTimeoutError: Error, LocalizedError, Sendable, Equatable {
        public let nextSeq: Int
        public var errorDescription: String? {
            "Transcript refresh timed out before all host pages arrived (cursor \(nextSeq))."
        }
    }

    /// Bound on how many `agent.conversations.fetch` pages a single refresh will pull.
    public static let maxFetchPages = 20
    /// Page size for host event fetch during refresh / conflict recovery.
    /// Kept below a full ~1MB observed-import payload so each relay round-trip
    /// fits the conversation-fetch budget; paging is already supported.
    public static let fetchPageLimit = 500
    /// Page size when reading mirrored events back for assistant-text assembly.
    public static let localEventsPageLimit = 5000
    /// Hard wall for one `refreshConversation` across all pages + one retry.
    /// Designed maximum: 60s (not 3×45s / 135s).
    public static let refreshWallBudget: Duration = .seconds(60)
    /// Max duration of a single fetch RPC (matches `E2ERelayBridge.conversationFetchRPCTimeout`).
    public static let fetchRPCTimeout: Duration = .seconds(30)
    /// Initial attempt + at most one transient retry while wall budget remains.
    public static let fetchRetryAttempts = 2

    /// A live stream of sync-state changes for one conversation, for the
    /// banner view to observe. The current state (or `.synced` if never
    /// touched) is emitted immediately so a late subscriber isn't stuck on
    /// stale UI until the next transition.
    public func observeSyncState(conversationID: String) -> AsyncStream<ConversationSyncUIState> {
        AsyncStream { continuation in
            let token = UUID()
            continuations[conversationID, default: [:]][token] = continuation
            continuation.yield(syncStates[conversationID] ?? .synced)
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeContinuation(token, for: conversationID) }
            }
        }
    }

    public func currentSyncState(_ conversationID: String) -> ConversationSyncUIState {
        syncStates[conversationID] ?? .synced
    }

    // MARK: - Internals

    private func append(
        _ request: ConversationAppendRequest, hostName: String, hostID: String?, transport: ConversationTransport,
        routingAgentID: String? = nil
    ) async -> TurnOutcome {
        let conversationIDForBanner = request.conversationId
        if let id = conversationIDForBanner { publish(.syncing, for: id) }

        let response: ConversationAppendResponse
        do {
            response = try await Self.appendWithRetry(request, transport: transport)
        } catch {
            if let id = conversationIDForBanner { publish(.hostOffline, for: id) }
            return .blocked(Self.transportErrorMessage(error))
        }

        if response.status == "conflict" {
            return await recoverFromConflict(
                request: request, response: response, hostName: hostName, hostID: hostID,
                transport: transport, routingAgentID: routingAgentID
            )
        }

        return await finishAppendResponse(
            request: request, response: response, hostName: hostName, hostID: hostID,
            routingAgentID: routingAgentID
        )
    }

    private func recoverFromConflict(
        request: ConversationAppendRequest, response: ConversationAppendResponse,
        hostName: String, hostID: String?, transport: ConversationTransport,
        routingAgentID: String?
    ) async -> TurnOutcome {
        let conversationID = response.conversationId
        let refreshedSeq: Int
        do {
            refreshedSeq = try await refetchConversationForRecovery(
                conversationID: conversationID, transport: transport
            )
        } catch {
            return await blockConflict(conversationID: conversationID, message: response.message)
        }

        let retryRequest = AttachmentSendPipeline.retryPreserving(request, baseSeq: refreshedSeq)

        let retryResponse: ConversationAppendResponse
        do {
            retryResponse = try await transport.append(retryRequest)
        } catch {
            if !conversationID.isEmpty { publish(.hostOffline, for: conversationID) }
            return .blocked(Self.transportErrorMessage(error))
        }

        if retryResponse.status == "conflict" {
            return await blockConflict(
                conversationID: conversationID,
                message: "This conversation changed on another device. Refresh to catch up."
            )
        }

        return await finishAppendResponse(
            request: retryRequest, response: retryResponse, hostName: hostName, hostID: hostID,
            routingAgentID: routingAgentID
        )
    }

    private func refetchConversationForRecovery(
        conversationID: String, transport: ConversationTransport
    ) async throws -> Int {
        let hydratedSeq = try await chatRepo.hydratedEventCursor(conversationID: conversationID)
        let deadline = ContinuousClock.now.advanced(by: Self.refreshWallBudget)
        do {
            return try await fetchAndMergeAllPages(
                conversationID: conversationID,
                sinceSeq: hydratedSeq,
                transport: transport,
                deadline: deadline,
                now: { ContinuousClock.now }
            )
        } catch let partial as ConversationSyncPartialError {
            // Recovery proceeds from what merged; remainder syncs next refresh.
            return partial.nextSeq
        }
    }

    /// Pulls host fetch pages until `hasMore` is false, merging page-by-page;
    /// throws `ConversationSyncPartialError` when `maxFetchPages` is reached
    /// with more remaining (already-fetched pages stay merged).
    ///
    /// Shared `deadline` caps the whole refresh — pagination of 501+ events is
    /// still allowed when pages return quickly, but a page/retry is not started
    /// unless remaining wall time covers another `fetchRPCTimeout` slot.
    private func fetchAndMergeAllPages(
        conversationID: String,
        sinceSeq: Int,
        transport: ConversationTransport,
        deadline: ContinuousClock.Instant,
        now: @escaping @Sendable () -> ContinuousClock.Instant
    ) async throws -> Int {
        // Each page merges immediately: a transport failure or the page cap
        // keeps everything already fetched (lastHostSeq advances per page), so
        // the next refresh resumes from the last good page instead of
        // re-pulling — and never discards partial progress. A mid-pagination
        // failure leaves UI `.cloudStale` (caller) rather than claiming a
        // complete authoritative sync.
        var cursor = sinceSeq
        var pages = 0

        while pages < Self.maxFetchPages {
            try Self.throwIfInsufficientRefreshBudget(
                deadline: deadline, now: now(), nextSeq: cursor
            )
            pages += 1
            let response = try await Self.fetchPageWithRetry(
                ConversationFetchRequest(
                    conversationId: conversationID,
                    sinceSeq: cursor,
                    limit: Self.fetchPageLimit
                ),
                transport: transport,
                deadline: deadline,
                now: now,
                nextSeq: cursor
            )
            try await mergeFetchResponse(response)
            cursor = response.nextSeq
            if !response.hasMore { return cursor }
        }
        // Page cap hit with more remaining: surface partial sync instead of
        // claiming .synced — the next refresh continues from cursor.
        throw ConversationSyncPartialError(nextSeq: cursor)
    }

    /// Retries a single fetch page once on transient relay failures (`timedOut`
    /// / temporary `notConnected`) while the shared wall budget remains.
    /// Never retries cancellation, pairing, crypto, or superseded errors.
    private static func fetchPageWithRetry(
        _ request: ConversationFetchRequest,
        transport: ConversationTransport,
        deadline: ContinuousClock.Instant,
        now: @escaping @Sendable () -> ContinuousClock.Instant,
        nextSeq: Int,
        attempts: Int = ConversationSyncCoordinator.fetchRetryAttempts
    ) async throws -> ConversationFetchResponse {
        var lastError: Error?
        for attempt in 0..<attempts {
            try throwIfInsufficientRefreshBudget(
                deadline: deadline, now: now(), nextSeq: nextSeq
            )
            do {
                return try await transport.fetch(request)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                let canRetry = attempt < attempts - 1 && isTransientFetchFailure(error)
                guard canRetry else { throw error }
                // Re-check budget before sleeping; remaining must cover another RPC.
                try throwIfInsufficientRefreshBudget(
                    deadline: deadline, now: now(), nextSeq: nextSeq
                )
                try await Task.sleep(nanoseconds: 400_000_000)
            }
        }
        throw lastError ?? CancellationError()
    }

    private static func throwIfInsufficientRefreshBudget(
        deadline: ContinuousClock.Instant,
        now: ContinuousClock.Instant,
        nextSeq: Int
    ) throws {
        let remaining = now.duration(to: deadline)
        if remaining < fetchRPCTimeout {
            throw ConversationSyncRefreshTimeoutError(nextSeq: nextSeq)
        }
    }

    /// Transient transport failures safe to retry once under the refresh budget.
    private static func isTransientFetchFailure(_ error: Error) -> Bool {
        guard let e2e = error as? E2EError else { return false }
        switch e2e {
        case .timedOut, .notConnected:
            return true
        case .notPaired, .superseded, .encryptFailed, .decryptFailed:
            return false
        }
    }

    private func blockConflict(conversationID: String, message: String?) async -> TurnOutcome {
        if !conversationID.isEmpty {
            publish(.conflict, for: conversationID)
            try? await chatRepo.updateSyncState(conversationID: conversationID, state: .conflict)
        }
        return .blocked(message ?? "This conversation changed on another device. Refresh to catch up.")
    }

    private func finishAppendResponse(
        request: ConversationAppendRequest, response: ConversationAppendResponse,
        hostName: String, hostID: String?, routingAgentID: String?
    ) async -> TurnOutcome {
        switch response.status {
        case "started":
            await persistStartedTurn(
                request: request, response: response, hostName: hostName, hostID: hostID,
                routingAgentID: routingAgentID
            )
            let uiState: ConversationSyncUIState = response.resumeMode == "latestInCwdFallback" ? .degradedResume : .synced
            publish(uiState, for: response.conversationId)
            return .started(TurnStarted(
                conversationID: response.conversationId,
                turnID: response.turnId,
                runID: response.runId ?? "",
                cwd: response.cwd ?? request.cwd ?? "",
                baseSeqForNextTurn: response.nextSeq,
                resumeMode: response.resumeMode,
                vendorSessionID: response.vendorSessionId,
                worktreePath: response.worktreePath,
                isolated: response.isolated ?? false
            ))
        case "denied":
            publish(.synced, for: response.conversationId)
            return .blocked("Blocked by policy\(response.rule.map { " (\($0))" } ?? "").")
        case "needsApproval":
            publish(.synced, for: response.conversationId)
            return .blocked("Awaiting your approval — check the Inbox.")
        case "budgetExceeded":
            publish(.synced, for: response.conversationId)
            return .blocked(response.message ?? "Daily budget cap reached.")
        default:
            publish(.synced, for: response.conversationId)
            return .blocked(response.message ?? "Couldn't start the run.")
        }
    }

    private func persistStartedTurn(
        request: ConversationAppendRequest, response: ConversationAppendResponse, hostName: String, hostID: String?,
        routingAgentID: String? = nil
    ) async {
        let isNew = request.conversationId == nil
        let existing = isNew ? nil : try? await chatRepo.conversation(id: response.conversationId)
        // Prefer the composer routing id (`relay|<uuid>|<vendor>`) so follow-ups
        // can resolve a transport. Fall back to an existing routing id, then the
        // wire vendor token. Never overwrite a stored routing id with bare vendor.
        let wireVendor = request.agent ?? existing?.vendor ?? ""
        let agentID: String = {
            if let routingAgentID, routingAgentID.contains("|") { return routingAgentID }
            if let existingID = existing?.agentID, existingID.contains("|") { return existingID }
            if let hostID, UUID(uuidString: hostID) != nil, !wireVendor.isEmpty, !wireVendor.contains("|") {
                // Relay machines use the machine UUID as hostID — reconstruct.
                return "relay|\(hostID)|\(wireVendor)"
            }
            return wireVendor.isEmpty ? (existing?.agentID ?? "") : wireVendor
        }()
        let vendor = agentID.split(separator: "|").last.map(String.init) ?? agentID
        let conversation = ChatConversation(
            id: response.conversationId,
            title: existing?.title ?? Self.titleFromPrompt(request.prompt),
            agentID: agentID,
            vendor: vendor,
            hostName: hostName,
            hostID: hostID,
            cwd: response.cwd ?? request.cwd ?? existing?.cwd ?? "",
            model: request.model ?? existing?.model,
            budgetUSD: request.budgetUSD ?? existing?.budgetUSD,
            status: .active,
            sourceHostID: hostID,
            sourceHostName: hostName
        )
        _ = try? await chatRepo.upsertConversationMirror(conversation, lastHostSeq: response.nextSeq, syncState: .synced)

        guard let runID = response.runId else { return }
        let turnID = response.turnId ?? runID
        let existingTurns = (try? await chatRepo.turns(conversationID: response.conversationId)) ?? []
        let ordinal = existingTurns.count
        let turn = LancerCore.ChatTurn(
            id: turnID, conversationID: response.conversationId, ordinal: ordinal,
            prompt: request.prompt, runID: runID, transportKind: "sync",
            clientTurnID: request.clientTurnId,
            attachments: request.attachments ?? []
        )
        _ = try? await chatRepo.upsertTurnMirror(
            turn, vendorSessionID: response.vendorSessionId, hostSeqStart: response.baseSeq, hostSeqEnd: nil
        )
    }

    /// Best-effort discovery merge for `agent.conversations.list` results —
    /// lets `AppRoot.refreshCursorLiveBridge` surface a conversation started
    /// on another device without waiting on CloudKit. Upserts summary fields
    /// (title/state/hostName/timestamps). When the host sends additive
    /// `lastTurnID` + `lastTurnStatus`, also advances a locally-`.running`
    /// mirror turn to that status — never inventing a status when fields are
    /// absent, and never regressing a locally terminal turn.
    ///
    /// Two invariants a bulk list merge must not violate (unlike a single
    /// authoritative fetch, a list summary can be stale relative to what this
    /// device already mirrored from a live turn):
    /// - never advance the event hydration cursor from summary metadata. A
    ///   list response carries no events, so new mirrors start at zero and an
    ///   existing mirror keeps its current cursor;
    /// - never clobber a stored relay routing agentID (`relay|<id>|<vendor>`)
    ///   with a bare provider token — `mapSummary` preserves it via
    ///   `fallback`, and the repository's UPDATE clause never touches
    ///   `agent_id`/`vendor` on conflict regardless.
    public func mergeConversationSummaries(
        _ summaries: [ConversationSummary], hostName: String, hostID: String?
    ) async {
        for summary in summaries {
            let existing = try? await chatRepo.conversation(id: summary.id)
            var conversation = Self.mapSummary(summary, fallback: existing)
            if conversation.hostName.isEmpty { conversation.hostName = hostName }
            if conversation.hostID == nil { conversation.hostID = hostID }
            let mergedSeq = existing?.lastHostSeq ?? 0
            _ = try? await chatRepo.upsertConversationMirror(
                conversation, lastHostSeq: mergedSeq, syncState: existing?.syncState ?? .synced
            )
            await applyLastTurnStatusFromSummary(summary)
        }
    }

    /// Applies host `lastTurnID`/`lastTurnStatus` onto a matching local mirror
    /// turn when that turn is still `.running`. Fail-closed: missing fields,
    /// unknown turn id, or a locally terminal status → no-op.
    private func applyLastTurnStatusFromSummary(_ summary: ConversationSummary) async {
        guard let turnID = summary.lastTurnID, !turnID.isEmpty,
              let hostStatus = summary.lastTurnStatus, !hostStatus.isEmpty
        else { return }
        let mapped = LancerCore.ChatTurn.Status.fromHostStatus(hostStatus)
        let turns = (try? await chatRepo.turns(conversationID: summary.id)) ?? []
        guard var local = turns.first(where: { $0.id == turnID }) else { return }
        // Never regress a locally terminal status (completed/failed).
        guard local.status == .running else { return }
        guard mapped != .running else { return }
        local.status = mapped
        local.completedAt = local.completedAt ?? .now
        _ = try? await chatRepo.upsertTurnMirror(
            local,
            vendorSessionID: local.vendorSessionID,
            hostSeqStart: local.hostSeqStart,
            hostSeqEnd: local.hostSeqEnd
        )
    }

    private func mergeFetchResponse(_ response: ConversationFetchResponse) async throws {
        let existing = try await chatRepo.conversation(id: response.conversation.id)
        let conversation = Self.mapSummary(response.conversation, fallback: existing)
        _ = try await chatRepo.upsertConversationMirror(conversation, lastHostSeq: response.nextSeq, syncState: .synced)

        let events = response.events.map(Self.mapEvent)
        try await chatRepo.appendEventsMirror(conversationID: response.conversation.id, events: events)

        // `ConversationTurnEnvelope` carries no rolled-up reply text (only the
        // ledger's raw per-seq events do — see appendRunOutput in
        // conversation_store.go) — assemble each turn's `assistantText` from
        // ITS OWN mirrored events (this fetch's plus whatever was already
        // stored) before writing the turn row, so a device that never
        // streamed a turn live still renders its content in ChatHistoryView.
        let allEvents: [ChatEvent]
        do {
            allEvents = try await loadAllMirroredEvents(conversationID: response.conversation.id)
        } catch {
            // Fail closed on wipe: prefer this page's events over inventing
            // empty transcripts that would clobber already-hydrated text.
            allEvents = events
        }
        let existingTurns = Dictionary(
            uniqueKeysWithValues: ((try? await chatRepo.turns(conversationID: response.conversation.id)) ?? [])
                .map { ($0.id, $0) }
        )
        let eventsByTurn = Dictionary(grouping: allEvents, by: { $0.turnID })
        for turnEnvelope in response.turns {
            var turn = Self.mapTurn(turnEnvelope, conversationID: response.conversation.id)
            let turnEvents = eventsByTurn[turn.id] ?? []
            let assembled = Self.assistantText(from: turnEvents)
            if assembled.isEmpty,
               turnEvents.isEmpty,
               let prior = existingTurns[turn.id]?.assistantText,
               !prior.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // Preserve only when the authoritative event list for this turn
                // is truly empty — eventful-but-empty assembly must win so a
                // tool/thinking-only host page does not keep a stale body.
                turn.assistantText = prior
            } else {
                turn.assistantText = assembled
            }
            if turn.attachments.isEmpty,
               let priorAttachments = existingTurns[turn.id]?.attachments,
               !priorAttachments.isEmpty {
                turn.attachments = priorAttachments
            }
            _ = try await chatRepo.upsertTurnMirror(
                turn, vendorSessionID: turnEnvelope.vendorSessionId, hostSeqStart: nil, hostSeqEnd: nil
            )
        }

        // A terminal `lancer.proof/v0` receipt is stored on the host ONLY as a
        // `conversation_events` row (kind "receipt" — see appendRunReceipt in
        // conversation_store.go); it is never itself a conversation_artifacts
        // row there. Live delivery (AppRoot's lancerE2ERunReceipt notification
        // handler) materializes it into a `chat_artifacts` row via
        // `upsertReceipt` the moment it arrives — but a receipt that lands
        // while this device is disconnected only ever reaches it as one of
        // `response.events` here, and ReceiptCardView reads exclusively from
        // `chat_artifacts`. Without this, a reconnect-and-refresh would mirror
        // the event into `chat_events` (above) but the receipt card would
        // never appear. Mirror the live path: materialize any receipt-kind
        // event into the SAME `chat_artifacts` row `upsertReceipt` would have
        // written live. Runs after the turns loop above so the `chat_turns`
        // row `upsertReceipt` keys off of (by run_id) already exists.
        // `upsertReceipt` upserts by the stable id `"receipt:\(runID)"`, so
        // re-running this merge for the same receipt (e.g. a re-fetch that
        // re-delivers already-seen events) is idempotent — no duplicate rows.
        var materializedReceipt = false
        for event in response.events where event.kind == "receipt" {
            guard let runID = event.runId, let payloadJSON = event.payloadJson else { continue }
            if (try? await chatRepo.upsertReceipt(runID: runID, payloadJSON: payloadJSON)) != nil {
                materializedReceipt = true
            }
        }
        // Same notification the live path posts after `upsertReceipt`
        // (AppRoot's lancerE2ERunReceipt handler) — lets an already-open
        // thread's artifact list pick up a receipt that arrived while this
        // device was disconnected, without requiring a manual re-open.
        if materializedReceipt {
            NotificationCenter.default.post(
                name: .lancerChatArtifactPersisted,
                object: nil,
                userInfo: ["conversationID": response.conversation.id]
            )
        }
    }

    /// Concatenates a turn's `kind == "output"` events (the ledger's mirror of
    /// the run's raw stdout/stderr stream — see `appendRunOutput`) in seq
    /// order, the same text `RunOutputStore` accumulates live for an active run.
    /// Tool/thinking kinds are excluded — see `TurnTranscriptAssembler.items`.
    private static func assistantText(from events: [ChatEvent]) -> String {
        TurnTranscriptAssembler.assistantText(from: events)
    }

    /// Pages through the local event mirror so long turns aren't truncated at
    /// `localEventsPageLimit` when assembling `assistantText`.
    private func loadAllMirroredEvents(conversationID: String) async throws -> [ChatEvent] {
        var all: [ChatEvent] = []
        var sinceSeq = 0
        while true {
            let page = try await chatRepo.events(
                conversationID: conversationID,
                sinceSeq: sinceSeq,
                limit: Self.localEventsPageLimit
            )
            if page.isEmpty { break }
            all.append(contentsOf: page)
            sinceSeq = page[page.count - 1].seq
            if page.count < Self.localEventsPageLimit { break }
        }
        return all
    }

    private func publish(_ state: ConversationSyncUIState, for conversationID: String) {
        syncStates[conversationID] = state
        for continuation in continuations[conversationID, default: [:]].values {
            continuation.yield(state)
        }
    }

    private func removeContinuation(_ token: UUID, for conversationID: String) {
        continuations[conversationID]?.removeValue(forKey: token)
        if continuations[conversationID]?.isEmpty == true {
            continuations.removeValue(forKey: conversationID)
        }
    }

    private static func transportErrorMessage(_ error: Error) -> String {
        "Couldn't reach the host: \(error.localizedDescription)"
    }

    /// A single failed `append` used to be treated as "host offline" outright,
    /// which turned a momentary relay hiccup (reconnect in progress, a dropped
    /// frame) into a hard "couldn't continue, open from a connected host"
    /// dead end — even while the machine was actively streaming the previous
    /// turn's output (found live 2026-07-03: a follow-up on a "WORKING" run
    /// failed this way). Retry a couple of times with a short backoff before
    /// concluding the host is actually unreachable.
    private static func appendWithRetry(
        _ request: ConversationAppendRequest, transport: ConversationTransport, attempts: Int = 3
    ) async throws -> ConversationAppendResponse {
        var lastError: Error?
        for attempt in 0..<attempts {
            do {
                return try await transport.append(request)
            } catch {
                lastError = error
                if attempt < attempts - 1 {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                }
            }
        }
        throw lastError ?? CancellationError()
    }

    private static func titleFromPrompt(_ prompt: String) -> String {
        let trimmed = AttachmentDisplayText.cleanPrompt(prompt)
        let firstLine = trimmed.split(separator: "\n").first.map(String.init) ?? trimmed
        return firstLine.count > 60 ? String(firstLine.prefix(60)) + "…" : (firstLine.isEmpty ? "New Chat" : firstLine)
    }

    // MARK: - Wire → local mapping (ConversationSummary/Turn/Event use Go's
    // RFC3339 string dates; the mirror repository deals only in Foundation
    // types, so this coordinator — not PersistenceKit — owns the conversion.)

    // `ISO8601DateFormatter` predates `Sendable`; it's only ever read here
    // (never mutated after creation), matching the pattern in AccountClient.swift.
    // Try fractional seconds first — host RFC3339 often includes them; a plain
    // formatter alone returns nil and the `?? .now` callers corrupt recency.
    nonisolated(unsafe) private static let dateFormatterWithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) private static let dateFormatterPlain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Parses host wire timestamps (RFC3339 / ISO8601), with or without fractional seconds.
    static func parseDate(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        if let date = dateFormatterWithFractionalSeconds.date(from: s) { return date }
        return dateFormatterPlain.date(from: s)
    }

    private static func mapSummary(_ summary: ConversationSummary, fallback: ChatConversation?) -> ChatConversation {
        // Host summaries only carry the vendor/provider token. Preserve a local
        // routing agentID (`relay|…|…`) across refresh so follow-ups keep working.
        let provider = summary.provider
        let preservedRouting = fallback?.agentID
        let agentID: String = {
            if let preservedRouting, preservedRouting.contains("|") { return preservedRouting }
            if let hostID = summary.hostID ?? fallback?.hostID ?? fallback?.sourceHostID,
               UUID(uuidString: hostID) != nil, !provider.contains("|") {
                return "relay|\(hostID)|\(provider)"
            }
            return provider
        }()
        let vendor = agentID.split(separator: "|").last.map(String.init) ?? provider
        return ChatConversation(
            id: summary.id,
            title: summary.title,
            agentID: agentID,
            vendor: vendor,
            hostName: summary.hostName,
            hostID: summary.hostID,
            cwd: summary.cwd,
            model: summary.model,
            budgetUSD: summary.budgetUSD,
            status: {
                let base = ChatConversation.Status(rawValue: summary.state) ?? .active
                // Backfilled conversations have no local turn rows, so the list
                // fell back to "No runs yet" for threads the host knows are
                // finished. Trust the host's last-turn status for the label.
                guard base == .active, let last = summary.lastTurnStatus else { return base }
                switch last {
                case "completed", "exited": return .completed
                case "failed": return .failed
                default: return base
                }
            }(),
            createdAt: parseDate(summary.createdAt) ?? fallback?.createdAt ?? .now,
            updatedAt: parseDate(summary.updatedAt) ?? .now,
            lastActivityAt: parseDate(summary.lastActivityAt) ?? .now,
            sourceHostID: summary.hostID,
            sourceHostName: summary.hostName,
            archivedAt: parseDate(summary.archivedAt)
        )
    }

    private static func mapTurn(_ turn: ConversationTurnEnvelope, conversationID: String) -> LancerCore.ChatTurn {
        LancerCore.ChatTurn(
            id: turn.id, conversationID: conversationID, ordinal: turn.ordinal,
            prompt: turn.prompt, runID: turn.runId, transportKind: "sync",
            status: LancerCore.ChatTurn.Status.fromHostStatus(turn.status),
            errorMessage: turn.errorMessage,
            createdAt: parseDate(turn.startedAt) ?? .now,
            completedAt: parseDate(turn.completedAt),
            clientTurnID: turn.clientTurnId,
            vendorSessionID: turn.vendorSessionId,
            attachments: turn.attachments
        )
    }

    private static func mapEvent(_ event: ConversationEvent) -> ChatEvent {
        ChatEvent(
            conversationID: event.conversationId, seq: event.seq,
            turnID: event.turnId, runID: event.runId, kind: event.kind,
            role: event.role, stream: event.stream, text: event.text,
            payloadJSON: event.payloadJson, createdAt: parseDate(event.createdAt) ?? .now
        )
    }
}
#endif
