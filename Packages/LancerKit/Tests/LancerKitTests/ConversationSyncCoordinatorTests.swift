#if os(iOS)
import Foundation
import Testing
import LancerCore
import PersistenceKit
import SSHTransport
@testable import AppFeature

@Suite("ConversationSyncCoordinator")
struct ConversationSyncCoordinatorTests {

    private func makeTransport(
        append: @escaping @Sendable (ConversationAppendRequest) async throws -> ConversationAppendResponse = { _ in
            ConversationAppendResponse(status: "started", conversationId: "unused")
        },
        fetch: @escaping @Sendable (ConversationFetchRequest) async throws -> ConversationFetchResponse = { req in
            ConversationFetchResponse(conversation: ConversationSummary(
                id: req.conversationId, title: "T", provider: "claudeCode", agentID: "claudeCode",
                hostName: "h", cwd: "/proj", state: "active", source: "app",
                createdAt: "2026-07-02T00:00:00Z", updatedAt: "2026-07-02T00:00:00Z",
                lastActivityAt: "2026-07-02T00:00:00Z", lastSeq: 0
            ))
        },
        archive: @escaping @Sendable (ConversationArchiveRequest) async throws -> ConversationArchiveResponse = { req in
            ConversationArchiveResponse(ok: true, conversationId: req.conversationId)
        }
    ) -> ConversationTransport {
        ConversationTransport(append: append, fetch: fetch, archive: archive)
    }

    @Test("startConversation persists a synced mirror row and returns runID")
    func startConversationSuccess() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let coordinator = ConversationSyncCoordinator(chatRepo: repo)
        let transport = makeTransport(append: { request in
            #expect(request.conversationId == nil)
            #expect(request.prompt == "hello")
            return ConversationAppendResponse(
                status: "started", conversationId: "conv-1", turnId: "turn-1", runId: "run-1",
                cwd: "/proj", baseSeq: 0, nextSeq: 2, resumeMode: "new"
            )
        })

        let outcome = await coordinator.startConversation(
            agent: "claudeCode", cwd: "/proj", prompt: "hello", model: nil, budgetUSD: nil,
            hostName: "MacBook Pro", hostID: "host-1", clientTurnID: "device-1:1", transport: transport
        )

        guard case .started(let started) = outcome else {
            Issue.record("expected .started, got \(outcome)")
            return
        }
        #expect(started.conversationID == "conv-1")
        #expect(started.runID == "run-1")
        #expect(started.baseSeqForNextTurn == 2)
        #expect(started.resumeMode == "new")

        let mirrored = try await repo.conversation(id: "conv-1")
        #expect(mirrored?.syncState == .synced)
        #expect(mirrored?.lastHostSeq == 2)
        #expect(mirrored?.hostID == "host-1")
        #expect(mirrored?.agentID == "claudeCode")

        let turns = try await repo.turns(conversationID: "conv-1")
        #expect(turns.count == 1)
        #expect(turns.first?.runID == "run-1")
        #expect(turns.first?.clientTurnID == "device-1:1")

        let state = await coordinator.currentSyncState("conv-1")
        #expect(state == .synced)
    }

    @Test("startConversation with relay routing id persists it for follow-ups")
    func startConversationPersistsRelayRoutingID() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let coordinator = ConversationSyncCoordinator(chatRepo: repo)
        let machineID = "557A7877-F729-5031-9606-0E04F2B67822"
        let wireVendorCapture = WireVendorCapture()
        let transport = makeTransport(append: { request in
            await wireVendorCapture.set(request.agent)
            return ConversationAppendResponse(
                status: "started", conversationId: "conv-relay", turnId: "turn-1", runId: "run-1",
                cwd: "/proj", baseSeq: 0, nextSeq: 2, resumeMode: "new"
            )
        })

        let outcome = await coordinator.startConversation(
            agent: "relay|\(machineID)|claudeCode", cwd: "/proj", prompt: "hello", model: nil, budgetUSD: nil,
            hostName: "Mac", hostID: machineID, clientTurnID: "device-1:1", transport: transport
        )
        guard case .started = outcome else {
            Issue.record("expected .started, got \(outcome)")
            return
        }
        #expect(await wireVendorCapture.value == "claudeCode")
        let mirrored = try await repo.conversation(id: "conv-relay")
        #expect(mirrored?.agentID == "relay|\(machineID)|claudeCode")
        #expect(mirrored?.vendor == "claudeCode")
    }

    @Test("startConversation with latestInCwdFallback resumeMode publishes degradedResume")
    func startConversationDegradedResume() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let coordinator = ConversationSyncCoordinator(chatRepo: repo)
        let transport = makeTransport(append: { _ in
            ConversationAppendResponse(
                status: "started", conversationId: "conv-1", runId: "run-1",
                cwd: "/proj", nextSeq: 2, resumeMode: "latestInCwdFallback"
            )
        })
        _ = await coordinator.startConversation(
            agent: "claudeCode", cwd: "/proj", prompt: "hi", model: nil, budgetUSD: nil,
            hostName: "h", hostID: nil, clientTurnID: "d:1", transport: transport
        )
        #expect(await coordinator.currentSyncState("conv-1") == .degradedResume)
    }

    @Test("continueConversation preserves existing agentID when request omits agent")
    func continueConversationPreservesAgent() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let coordinator = ConversationSyncCoordinator(chatRepo: repo)
        let seed = ChatConversation(id: "conv-1", title: "T", agentID: "claudeCode", hostName: "h", hostID: nil, cwd: "/proj")
        _ = try await repo.upsertConversationMirror(seed, lastHostSeq: 2, syncState: .synced)
        _ = try await repo.upsertTurnMirror(
            ChatTurn(id: "turn-0", conversationID: "conv-1", ordinal: 0, prompt: "hi", runID: "run-0", clientTurnID: "d:1"),
            vendorSessionID: nil, hostSeqStart: nil, hostSeqEnd: nil
        )

        let transport = makeTransport(append: { request in
            #expect(request.conversationId == "conv-1")
            #expect(request.agent == nil)
            return ConversationAppendResponse(
                status: "started", conversationId: "conv-1", turnId: "turn-1", runId: "run-1",
                vendorSessionId: "sess-1", cwd: "/proj", baseSeq: 2, nextSeq: 4, resumeMode: "exact"
            )
        })

        let outcome = await coordinator.continueConversation(
            conversationID: "conv-1", baseSeq: 2, prompt: "follow up", clientTurnID: "d:2",
            hostName: "h", hostID: nil, transport: transport
        )
        guard case .started = outcome else {
            Issue.record("expected .started, got \(outcome)")
            return
        }
        let mirrored = try await repo.conversation(id: "conv-1")
        #expect(mirrored?.agentID == "claudeCode")
        let turns = try await repo.turns(conversationID: "conv-1")
        #expect(turns.count == 2)
        #expect(turns.last?.vendorSessionID == "sess-1")
    }

    @Test("startConversation threads fullTools into the append request")
    func startConversationThreadsFullTools() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let coordinator = ConversationSyncCoordinator(chatRepo: repo)
        let transport = makeTransport(append: { request in
            #expect(request.fullTools == true)
            return ConversationAppendResponse(
                status: "started", conversationId: "conv-1", turnId: "turn-1", runId: "run-1",
                cwd: "/proj", baseSeq: 0, nextSeq: 2, resumeMode: "new"
            )
        })

        _ = await coordinator.startConversation(
            agent: "claudeCode", cwd: "/proj", prompt: "hello", model: nil, budgetUSD: nil,
            fullTools: true,
            hostName: "MacBook Pro", hostID: "host-1", clientTurnID: "device-1:1", transport: transport
        )
    }

    @Test("startConversation omits fullTools from the request by default")
    func startConversationDefaultsFullToolsFalse() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let coordinator = ConversationSyncCoordinator(chatRepo: repo)
        let transport = makeTransport(append: { request in
            #expect(request.fullTools == false)
            return ConversationAppendResponse(
                status: "started", conversationId: "conv-1", turnId: "turn-1", runId: "run-1",
                cwd: "/proj", baseSeq: 0, nextSeq: 2, resumeMode: "new"
            )
        })

        _ = await coordinator.startConversation(
            agent: "claudeCode", cwd: "/proj", prompt: "hello", model: nil, budgetUSD: nil,
            hostName: "MacBook Pro", hostID: "host-1", clientTurnID: "device-1:1", transport: transport
        )
    }

    @Test("continueConversation threads fullTools into the append request")
    func continueConversationThreadsFullTools() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let coordinator = ConversationSyncCoordinator(chatRepo: repo)
        let seed = ChatConversation(id: "conv-1", title: "T", agentID: "claudeCode", hostName: "h", hostID: nil, cwd: "/proj")
        _ = try await repo.upsertConversationMirror(seed, lastHostSeq: 2, syncState: .synced)
        _ = try await repo.upsertTurnMirror(
            ChatTurn(id: "turn-0", conversationID: "conv-1", ordinal: 0, prompt: "hi", runID: "run-0", clientTurnID: "d:1"),
            vendorSessionID: nil, hostSeqStart: nil, hostSeqEnd: nil
        )

        let transport = makeTransport(append: { request in
            #expect(request.fullTools == true)
            return ConversationAppendResponse(
                status: "started", conversationId: "conv-1", turnId: "turn-1", runId: "run-1",
                vendorSessionId: "sess-1", cwd: "/proj", baseSeq: 2, nextSeq: 4, resumeMode: "exact"
            )
        })

        _ = await coordinator.continueConversation(
            conversationID: "conv-1", baseSeq: 2, prompt: "follow up", clientTurnID: "d:2",
            fullTools: true,
            hostName: "h", hostID: nil, transport: transport
        )
    }

    @Test("conflict auto-recovers: stale baseSeq refetches then retries with fresh nextSeq")
    func conflictAutoRecoversOnce() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let coordinator = ConversationSyncCoordinator(chatRepo: repo)
        let seed = ChatConversation(id: "conv-1", title: "T", agentID: "claudeCode", hostName: "h", hostID: nil, cwd: "/proj")
        _ = try await repo.upsertConversationMirror(seed, lastHostSeq: 2, syncState: .synced)

        let appendCount = Counter()
        let transport = makeTransport(
            append: { request in
                let n = await appendCount.increment()
                if n == 1 {
                    #expect(request.baseSeq == 1)
                    return ConversationAppendResponse(
                        status: "conflict", conversationId: "conv-1", baseSeq: 1, nextSeq: 7,
                        message: "Conversation changed. Refetch before appending."
                    )
                }
                #expect(request.baseSeq == 7)
                return ConversationAppendResponse(
                    status: "started", conversationId: "conv-1", turnId: "turn-2", runId: "run-2",
                    cwd: "/proj", baseSeq: 7, nextSeq: 9, resumeMode: "exact"
                )
            },
            fetch: { req in
                ConversationFetchResponse(
                    conversation: ConversationSummary(
                        id: req.conversationId, title: "T", provider: "claudeCode", agentID: "claudeCode",
                        hostName: "h", cwd: "/proj", state: "active", source: "app",
                        createdAt: "2026-07-02T00:00:00Z", updatedAt: "2026-07-02T01:00:00Z",
                        lastActivityAt: "2026-07-02T01:00:00Z", lastSeq: 7
                    ),
                    nextSeq: 7
                )
            }
        )

        let outcome = await coordinator.continueConversation(
            conversationID: "conv-1", baseSeq: 1, prompt: "Thank you", clientTurnID: "d:3",
            hostName: "h", hostID: nil, transport: transport
        )
        guard case .started(let started) = outcome else {
            Issue.record("expected .started after conflict recovery, got \(outcome)")
            return
        }
        #expect(started.runID == "run-2")
        #expect(started.baseSeqForNextTurn == 9)
        #expect(await appendCount.value == 2)
        let mirrored = try await repo.conversation(id: "conv-1")
        #expect(mirrored?.lastHostSeq == 9)
        #expect(mirrored?.syncState == .synced)
        #expect(await coordinator.currentSyncState("conv-1") == .synced)
    }

    @Test("conflict after refetch and retry still conflicts surfaces runbook blocked message")
    func conflictDoubleBlocked() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let coordinator = ConversationSyncCoordinator(chatRepo: repo)
        let seed = ChatConversation(id: "conv-1", title: "T", agentID: "claudeCode", hostName: "h", hostID: nil, cwd: "/proj")
        _ = try await repo.upsertConversationMirror(seed, lastHostSeq: 2, syncState: .synced)

        let transport = makeTransport(
            append: { _ in
                ConversationAppendResponse(
                    status: "conflict", conversationId: "conv-1", baseSeq: 1, nextSeq: 5,
                    message: "Conversation changed. Refetch before appending."
                )
            },
            fetch: { req in
                ConversationFetchResponse(
                    conversation: ConversationSummary(
                        id: req.conversationId, title: "T", provider: "claudeCode", agentID: "claudeCode",
                        hostName: "h", cwd: "/proj", state: "active", source: "app",
                        createdAt: "2026-07-02T00:00:00Z", updatedAt: "2026-07-02T01:00:00Z",
                        lastActivityAt: "2026-07-02T01:00:00Z", lastSeq: 5
                    ),
                    nextSeq: 5
                )
            }
        )

        let outcome = await coordinator.continueConversation(
            conversationID: "conv-1", baseSeq: 1, prompt: "stale", clientTurnID: "d:3",
            hostName: "h", hostID: nil, transport: transport
        )
        guard case .blocked(let message) = outcome else {
            Issue.record("expected .blocked, got \(outcome)")
            return
        }
        #expect(message == "This conversation changed on another device. Refresh to catch up.")
        let mirrored = try await repo.conversation(id: "conv-1")
        #expect(mirrored?.syncState == .conflict)
        #expect(mirrored?.lastHostSeq == 5, "refetch should advance mirror seq before the retry conflict")
        #expect(await coordinator.currentSyncState("conv-1") == .conflict)
    }

    @Test("conflict when refetch throws blocks without retrying append")
    func conflictRefetchThrows() async throws {
        struct Boom: Error {}
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let coordinator = ConversationSyncCoordinator(chatRepo: repo)
        let seed = ChatConversation(id: "conv-1", title: "T", agentID: "claudeCode", hostName: "h", hostID: nil, cwd: "/proj")
        _ = try await repo.upsertConversationMirror(seed, lastHostSeq: 2, syncState: .synced)

        let appendCount = Counter()
        let transport = makeTransport(
            append: { _ in
                await appendCount.increment()
                return ConversationAppendResponse(
                    status: "conflict", conversationId: "conv-1", baseSeq: 1, nextSeq: 5,
                    message: "stale baseSeq"
                )
            },
            fetch: { _ in throw Boom() }
        )

        let outcome = await coordinator.continueConversation(
            conversationID: "conv-1", baseSeq: 1, prompt: "stale", clientTurnID: "d:3",
            hostName: "h", hostID: nil, transport: transport
        )
        guard case .blocked(let message) = outcome else {
            Issue.record("expected .blocked, got \(outcome)")
            return
        }
        #expect(message == "stale baseSeq")
        #expect(await appendCount.value == 1, "must not retry append when refetch fails")
        let mirrored = try await repo.conversation(id: "conv-1")
        #expect(mirrored?.syncState == .conflict)
        #expect(mirrored?.lastHostSeq == 2)
        #expect(await coordinator.currentSyncState("conv-1") == .conflict)
    }

    @Test("needsApproval and denied statuses surface as blocked without changing sync state")
    func needsApprovalAndDenied() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let coordinator = ConversationSyncCoordinator(chatRepo: repo)

        let deniedTransport = makeTransport(append: { _ in
            ConversationAppendResponse(status: "denied", conversationId: "conv-1", rule: "no-network")
        })
        let deniedOutcome = await coordinator.startConversation(
            agent: "codex", cwd: "/proj", prompt: "curl evil.com", model: nil, budgetUSD: nil,
            hostName: "h", hostID: nil, clientTurnID: "d:1", transport: deniedTransport
        )
        guard case .blocked(let deniedMessage) = deniedOutcome else {
            Issue.record("expected .blocked")
            return
        }
        #expect(deniedMessage.contains("no-network"))

        let approvalTransport = makeTransport(append: { _ in
            ConversationAppendResponse(status: "needsApproval", conversationId: "conv-2")
        })
        let approvalOutcome = await coordinator.startConversation(
            agent: "codex", cwd: "/proj", prompt: "rm -rf /", model: nil, budgetUSD: nil,
            hostName: "h", hostID: nil, clientTurnID: "d:2", transport: approvalTransport
        )
        guard case .blocked(let approvalMessage) = approvalOutcome else {
            Issue.record("expected .blocked")
            return
        }
        #expect(approvalMessage.contains("approval"))
    }

    @Test("a transport failure marks the conversation hostOffline and returns blocked")
    func transportFailureMarksHostOffline() async throws {
        struct Boom: Error {}
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let coordinator = ConversationSyncCoordinator(chatRepo: repo)
        let seed = ChatConversation(id: "conv-1", title: "T", agentID: "claudeCode", hostName: "h", hostID: nil, cwd: "/proj")
        _ = try await repo.upsertConversationMirror(seed, lastHostSeq: 2, syncState: .synced)

        let transport = makeTransport(append: { _ in throw Boom() })
        let outcome = await coordinator.continueConversation(
            conversationID: "conv-1", baseSeq: 2, prompt: "hi", clientTurnID: "d:1",
            hostName: "h", hostID: nil, transport: transport
        )
        guard case .blocked = outcome else {
            Issue.record("expected .blocked")
            return
        }
        #expect(await coordinator.currentSyncState("conv-1") == .hostOffline)
    }

    @Test("a transient transport failure on append recovers via retry instead of going hostOffline")
    func appendRetriesTransientFailureBeforeGivingUp() async throws {
        struct Blip: Error {}
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let coordinator = ConversationSyncCoordinator(chatRepo: repo)
        let seed = ChatConversation(id: "conv-1", title: "T", agentID: "claudeCode", hostName: "h", hostID: nil, cwd: "/proj")
        _ = try await repo.upsertConversationMirror(seed, lastHostSeq: 2, syncState: .synced)

        let attemptCount = Counter()
        let transport = makeTransport(append: { _ in
            let n = await attemptCount.increment()
            if n < 2 { throw Blip() } // fails once, succeeds on the retry
            return ConversationAppendResponse(
                status: "started", conversationId: "conv-1", turnId: "turn-1", runId: "run-1",
                cwd: "/proj", baseSeq: 2, nextSeq: 4, resumeMode: "exact"
            )
        })

        let outcome = await coordinator.continueConversation(
            conversationID: "conv-1", baseSeq: 2, prompt: "follow up", clientTurnID: "d:2",
            hostName: "h", hostID: nil, transport: transport
        )
        guard case .started = outcome else {
            Issue.record("expected .started after the retry recovered, got \(outcome)")
            return
        }
        #expect(await attemptCount.value == 2, "should have retried exactly once before succeeding")
        #expect(await coordinator.currentSyncState("conv-1") == .synced, "a recovered append must not leave the conversation flagged hostOffline")
    }

    @Test("append retries keep the same clientTurnId so the host can dedupe")
    func appendRetriesPreserveClientTurnId() async throws {
        struct Blip: Error {}
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let coordinator = ConversationSyncCoordinator(chatRepo: repo)
        let seed = ChatConversation(id: "conv-1", title: "T", agentID: "claudeCode", hostName: "h", hostID: nil, cwd: "/proj")
        _ = try await repo.upsertConversationMirror(seed, lastHostSeq: 2, syncState: .synced)

        let seen = ClientTurnIDCapture()
        let transport = makeTransport(append: { request in
            await seen.append(request.clientTurnId)
            let n = await seen.count()
            if n < 2 { throw Blip() }
            return ConversationAppendResponse(
                status: "started", conversationId: "conv-1", turnId: "turn-1", runId: "run-1",
                cwd: "/proj", baseSeq: 2, nextSeq: 4, resumeMode: "exact",
                clientTurnId: request.clientTurnId
            )
        })

        let outcome = await coordinator.continueConversation(
            conversationID: "conv-1", baseSeq: 2, prompt: "follow up", clientTurnID: "device:idempotent-1",
            hostName: "h", hostID: nil, transport: transport
        )
        guard case .started = outcome else {
            Issue.record("expected .started, got \(outcome)")
            return
        }
        let ids = await seen.all()
        #expect(ids == ["device:idempotent-1", "device:idempotent-1"])
    }

    private actor ClientTurnIDCapture {
        private var values: [String] = []
        func append(_ id: String) { values.append(id) }
        func count() -> Int { values.count }
        func all() -> [String] { values }
    }

    private actor Counter {
        private(set) var value = 0
        @discardableResult
        func increment() -> Int { value += 1; return value }
    }

    private actor WireVendorCapture {
        private(set) var value: String?
        func set(_ vendor: String?) { value = vendor }
    }

    @Test("refreshConversation merges conversation, turns, and events into the mirror")
    func refreshMergesFetchResponse() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let coordinator = ConversationSyncCoordinator(chatRepo: repo)
        let seed = ChatConversation(id: "conv-1", title: "Old title", agentID: "claudeCode", hostName: "h", hostID: nil, cwd: "/proj")
        _ = try await repo.upsertConversationMirror(seed, lastHostSeq: 0, syncState: .syncing)

        let transport = makeTransport(fetch: { req in
            #expect(req.conversationId == "conv-1")
            #expect(req.sinceSeq == 0)
            return ConversationFetchResponse(
                conversation: ConversationSummary(
                    id: "conv-1", title: "Fresh title from another device", provider: "claudeCode",
                    agentID: "claudeCode", hostName: "MacBook Pro", cwd: "/proj", state: "active",
                    source: "app", createdAt: "2026-07-02T00:00:00Z", updatedAt: "2026-07-02T01:00:00Z",
                    lastActivityAt: "2026-07-02T01:00:00Z", lastSeq: 4
                ),
                turns: [
                    ConversationTurnEnvelope(
                        id: "turn-1", conversationId: "conv-1", ordinal: 0, clientTurnId: "device-2:1",
                        prompt: "hi from device 2", runId: "run-remote-1", provider: "claudeCode",
                        vendorSessionId: "sess-remote-1", status: "completed", startedAt: "2026-07-02T00:30:00Z"
                    ),
                ],
                events: [
                    ConversationEvent(conversationId: "conv-1", seq: 1, kind: "prompt", role: "user", text: "hi from device 2", createdAt: "2026-07-02T00:30:00Z"),
                    ConversationEvent(conversationId: "conv-1", seq: 2, kind: "output", role: "assistant", text: "hello!", createdAt: "2026-07-02T00:31:00Z"),
                ],
                nextSeq: 4
            )
        })

        let nextSeq = try await coordinator.refreshConversation(conversationID: "conv-1", transport: transport)
        #expect(nextSeq == 4)

        let mirrored = try await repo.conversation(id: "conv-1")
        #expect(mirrored?.title == "Fresh title from another device")
        #expect(mirrored?.lastHostSeq == 4)
        #expect(mirrored?.syncState == .synced)

        let turns = try await repo.turns(conversationID: "conv-1")
        #expect(turns.count == 1)
        #expect(turns.first?.vendorSessionID == "sess-remote-1")

        let events = try await repo.events(conversationID: "conv-1")
        #expect(events.map(\.seq) == [1, 2])
    }

    @Test("refreshConversation pages until hasMore is false and merges all events")
    func refreshConversationPagesUntilComplete() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let coordinator = ConversationSyncCoordinator(chatRepo: repo)
        let seed = ChatConversation(id: "conv-1", title: "T", agentID: "claudeCode", hostName: "h", hostID: nil, cwd: "/proj")
        _ = try await repo.upsertConversationMirror(seed, lastHostSeq: 0, syncState: .syncing)

        let fetchCount = Counter()
        let summary = ConversationSummary(
            id: "conv-1", title: "Long thread", provider: "claudeCode", agentID: "claudeCode",
            hostName: "h", cwd: "/proj", state: "active", source: "app",
            createdAt: "2026-07-02T00:00:00Z", updatedAt: "2026-07-02T03:00:00Z",
            lastActivityAt: "2026-07-02T03:00:00Z", lastSeq: 6
        )
        let turn = ConversationTurnEnvelope(
            id: "turn-1", conversationId: "conv-1", ordinal: 0, clientTurnId: "device-2:1",
            prompt: "long reply", runId: "run-long-1", provider: "claudeCode",
            vendorSessionId: "sess-1", status: "completed", startedAt: "2026-07-02T00:30:00Z"
        )

        let transport = makeTransport(fetch: { req in
            #expect(req.conversationId == "conv-1")
            #expect(req.limit == ConversationSyncCoordinator.fetchPageLimit)
            let n = await fetchCount.increment()
            switch n {
            case 1:
                #expect(req.sinceSeq == 0)
                return ConversationFetchResponse(
                    conversation: summary,
                    turns: [turn],
                    events: [
                        ConversationEvent(
                            conversationId: "conv-1", seq: 1, turnId: "turn-1", runId: "run-long-1",
                            kind: "prompt", role: "user", text: "long reply", createdAt: "2026-07-02T00:30:00Z"
                        ),
                        ConversationEvent(
                            conversationId: "conv-1", seq: 2, turnId: "turn-1", runId: "run-long-1",
                            kind: "output", role: "assistant", text: "part-a-", createdAt: "2026-07-02T00:31:00Z"
                        ),
                    ],
                    nextSeq: 2,
                    hasMore: true
                )
            case 2:
                #expect(req.sinceSeq == 2)
                return ConversationFetchResponse(
                    conversation: summary,
                    turns: [turn],
                    events: [
                        ConversationEvent(
                            conversationId: "conv-1", seq: 3, turnId: "turn-1", runId: "run-long-1",
                            kind: "output", role: "assistant", text: "part-b-", createdAt: "2026-07-02T00:32:00Z"
                        ),
                        ConversationEvent(
                            conversationId: "conv-1", seq: 4, turnId: "turn-1", runId: "run-long-1",
                            kind: "output", role: "assistant", text: "part-c-", createdAt: "2026-07-02T00:33:00Z"
                        ),
                    ],
                    nextSeq: 4,
                    hasMore: true
                )
            case 3:
                #expect(req.sinceSeq == 4)
                return ConversationFetchResponse(
                    conversation: summary,
                    turns: [turn],
                    events: [
                        ConversationEvent(
                            conversationId: "conv-1", seq: 5, turnId: "turn-1", runId: "run-long-1",
                            kind: "output", role: "assistant", text: "part-d", createdAt: "2026-07-02T00:34:00Z"
                        ),
                        ConversationEvent(
                            conversationId: "conv-1", seq: 6, turnId: "turn-1", runId: "run-long-1",
                            kind: "status", payloadJson: "{\"status\":\"exited\",\"exitCode\":0}",
                            createdAt: "2026-07-02T00:35:00Z"
                        ),
                    ],
                    nextSeq: 6,
                    hasMore: false
                )
            default:
                Issue.record("unexpected fetch #\(n) sinceSeq=\(req.sinceSeq)")
                return ConversationFetchResponse(conversation: summary, nextSeq: 6, hasMore: false)
            }
        })

        let nextSeq = try await coordinator.refreshConversation(conversationID: "conv-1", transport: transport)
        #expect(nextSeq == 6)
        #expect(await fetchCount.value == 3)

        let mirrored = try await repo.conversation(id: "conv-1")
        #expect(mirrored?.lastHostSeq == 6)
        #expect(mirrored?.title == "Long thread")

        let events = try await repo.events(conversationID: "conv-1")
        #expect(events.map(\.seq) == [1, 2, 3, 4, 5, 6])

        let turns = try await repo.turns(conversationID: "conv-1")
        #expect(turns.count == 1)
        #expect(turns.first?.assistantText == "part-a-part-b-part-c-part-d")
    }

    @Test("refreshConversation maps host 'exited' turn status to .completed (not .running)")
    func refreshMapsExitedHostStatusToCompleted() async throws {
        // Daemon persist uses process-lifecycle "exited" on success. Phone
        // ChatTurn.Status has no "exited" case — rawValue decode used to fall
        // through to .running, so onPollThread never cleared Working… after a
        // successful live run when run.status events were missed.
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let coordinator = ConversationSyncCoordinator(chatRepo: repo)
        let seed = ChatConversation(id: "conv-1", title: "hi", agentID: "claudeCode", hostName: "h", hostID: nil, cwd: "/Users/roshansilva")
        _ = try await repo.upsertConversationMirror(seed, lastHostSeq: 0, syncState: .syncing)

        let transport = makeTransport(fetch: { _ in
            ConversationFetchResponse(
                conversation: ConversationSummary(
                    id: "conv-1", title: "hi", provider: "claudeCode", agentID: "claudeCode",
                    hostName: "h", cwd: "/Users/roshansilva", state: "active", source: "phone",
                    createdAt: "2026-07-09T19:28:33Z", updatedAt: "2026-07-09T19:28:40Z",
                    lastActivityAt: "2026-07-09T19:28:40Z", lastSeq: 6
                ),
                turns: [
                    ConversationTurnEnvelope(
                        id: "turn-1", conversationId: "conv-1", ordinal: 0, clientTurnId: "device-1:1",
                        prompt: "hi", runId: "run-exited-1", provider: "claudeCode",
                        vendorSessionId: "sess-1", status: "exited",
                        startedAt: "2026-07-09T19:28:33Z", completedAt: "2026-07-09T19:28:40Z"
                    ),
                ],
                events: [
                    ConversationEvent(conversationId: "conv-1", seq: 1, kind: "turn_started", createdAt: "2026-07-09T19:28:33Z"),
                    ConversationEvent(
                        conversationId: "conv-1", seq: 3, turnId: "turn-1", runId: "run-exited-1",
                        kind: "output", role: "assistant", stream: "stdout",
                        text: "Hey! How can I help you today?", createdAt: "2026-07-09T19:28:38Z"
                    ),
                    ConversationEvent(
                        conversationId: "conv-1", seq: 6, turnId: "turn-1", runId: "run-exited-1",
                        kind: "status", payloadJson: "{\"status\":\"exited\",\"exitCode\":0}",
                        createdAt: "2026-07-09T19:28:40Z"
                    ),
                ],
                nextSeq: 6
            )
        })

        _ = try await coordinator.refreshConversation(conversationID: "conv-1", transport: transport)

        let turns = try await repo.turns(conversationID: "conv-1")
        #expect(turns.count == 1)
        #expect(turns.first?.status == .completed)
        #expect(turns.first?.assistantText.contains("How can I help") == true)
    }

    // --- receipt materialization on reconnect (PR #34 review finding P2) ---
    //
    // The host stores a terminal `lancer.proof/v0` receipt ONLY as a
    // `conversation_events` row (kind "receipt" — see appendRunReceipt in
    // conversation_store.go). Live delivery turns it into a `chat_artifacts`
    // row via `upsertReceipt` (AppRoot's lancerE2ERunReceipt handler), but
    // before this fix, `mergeFetchResponse` only mirrored fetched events into
    // `chat_events` — never converting a `kind == "receipt"` event into an
    // artifact — so a receipt that arrived while the phone was disconnected
    // never appeared in ReceiptCardView (which reads exclusively from
    // `chat_artifacts`) even after a refresh.

    @Test("refreshConversation materializes a receipt-kind event into a chat_artifacts .receipt row")
    func refreshConversationMaterializesReceiptArtifact() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let coordinator = ConversationSyncCoordinator(chatRepo: repo)
        let seed = ChatConversation(id: "conv-1", title: "T", agentID: "claudeCode", hostName: "h", hostID: nil, cwd: "/proj")
        _ = try await repo.upsertConversationMirror(seed, lastHostSeq: 0, syncState: .syncing)

        let receiptPayload = """
        {"schema":"lancer.proof/v0","runId":"run-remote-1","conversationId":"conv-1","agent":"claudeCode","status":"completed","exitCode":0}
        """
        let transport = makeTransport(fetch: { _ in
            ConversationFetchResponse(
                conversation: ConversationSummary(
                    id: "conv-1", title: "T", provider: "claudeCode", agentID: "claudeCode",
                    hostName: "h", cwd: "/proj", state: "active", source: "app",
                    createdAt: "2026-07-08T00:00:00Z", updatedAt: "2026-07-08T00:01:00Z",
                    lastActivityAt: "2026-07-08T00:01:00Z", lastSeq: 3
                ),
                turns: [
                    ConversationTurnEnvelope(
                        id: "turn-1", conversationId: "conv-1", ordinal: 0, clientTurnId: "device-2:1",
                        prompt: "hi while phone was offline", runId: "run-remote-1", provider: "claudeCode",
                        status: "completed", startedAt: "2026-07-08T00:00:00Z", completedAt: "2026-07-08T00:01:00Z"
                    ),
                ],
                events: [
                    ConversationEvent(conversationId: "conv-1", seq: 1, turnId: "turn-1", runId: "run-remote-1", kind: "prompt", role: "user", text: "hi while phone was offline", createdAt: "2026-07-08T00:00:00Z"),
                    ConversationEvent(conversationId: "conv-1", seq: 2, turnId: "turn-1", runId: "run-remote-1", kind: "output", role: "assistant", text: "done!", createdAt: "2026-07-08T00:00:30Z"),
                    ConversationEvent(conversationId: "conv-1", seq: 3, turnId: "turn-1", runId: "run-remote-1", kind: "receipt", payloadJson: receiptPayload, createdAt: "2026-07-08T00:01:00Z"),
                ],
                nextSeq: 3
            )
        })

        let nextSeq = try await coordinator.refreshConversation(conversationID: "conv-1", transport: transport)
        #expect(nextSeq == 3)

        let artifacts = try await repo.artifacts(runID: "run-remote-1")
        #expect(artifacts.count == 1, "expected exactly one artifact materialized from the fetched receipt event")
        #expect(artifacts.first?.kind == .receipt)
        #expect(artifacts.first?.status == .done)
        #expect(artifacts.first?.id == "receipt:run-remote-1")
        #expect(artifacts.first?.payloadJSON.contains("lancer.proof/v0") == true)

        // The receipt event itself must still be mirrored into chat_events
        // like any other fetched event — materializing the artifact is
        // additive, not a replacement for the existing event mirror.
        let events = try await repo.events(conversationID: "conv-1")
        #expect(events.map(\.seq) == [1, 2, 3])
        #expect(events.first(where: { $0.kind == "receipt" })?.runID == "run-remote-1")
    }

    @Test("refetching the same receipt event does not duplicate the materialized artifact")
    func refreshConversationReceiptMaterializationIsIdempotent() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let coordinator = ConversationSyncCoordinator(chatRepo: repo)
        let seed = ChatConversation(id: "conv-1", title: "T", agentID: "claudeCode", hostName: "h", hostID: nil, cwd: "/proj")
        _ = try await repo.upsertConversationMirror(seed, lastHostSeq: 0, syncState: .syncing)

        let receiptPayload = """
        {"schema":"lancer.proof/v0","runId":"run-remote-2","conversationId":"conv-1","agent":"claudeCode","status":"completed","exitCode":0}
        """
        @Sendable func fetchResponse() -> ConversationFetchResponse {
            ConversationFetchResponse(
                conversation: ConversationSummary(
                    id: "conv-1", title: "T", provider: "claudeCode", agentID: "claudeCode",
                    hostName: "h", cwd: "/proj", state: "active", source: "app",
                    createdAt: "2026-07-08T00:00:00Z", updatedAt: "2026-07-08T00:01:00Z",
                    lastActivityAt: "2026-07-08T00:01:00Z", lastSeq: 1
                ),
                turns: [
                    ConversationTurnEnvelope(
                        id: "turn-1", conversationId: "conv-1", ordinal: 0, clientTurnId: "device-2:1",
                        prompt: "hi", runId: "run-remote-2", provider: "claudeCode",
                        status: "completed", startedAt: "2026-07-08T00:00:00Z", completedAt: "2026-07-08T00:01:00Z"
                    ),
                ],
                events: [
                    ConversationEvent(conversationId: "conv-1", seq: 1, turnId: "turn-1", runId: "run-remote-2", kind: "receipt", payloadJson: receiptPayload, createdAt: "2026-07-08T00:01:00Z"),
                ],
                nextSeq: 1
            )
        }
        let transport = makeTransport(fetch: { _ in fetchResponse() })

        _ = try await coordinator.refreshConversation(conversationID: "conv-1", transport: transport)
        _ = try await coordinator.refreshConversation(conversationID: "conv-1", transport: transport)

        let artifacts = try await repo.artifacts(runID: "run-remote-2")
        #expect(artifacts.count == 1, "re-fetching the same receipt event twice must not duplicate the artifact row")
    }

    @Test("mergeConversationSummaries creates mirror rows for conversations discovered via list")
    func mergeConversationSummariesCreatesMirrorRows() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let coordinator = ConversationSyncCoordinator(chatRepo: repo)

        let summaries = [
            ConversationSummary(
                id: "conv-remote-1", title: "Started on Mac", provider: "claudeCode", agentID: "claudeCode",
                hostName: "MacBook Pro", cwd: "/proj", state: "active", source: "app",
                createdAt: "2026-07-08T00:00:00Z", updatedAt: "2026-07-08T00:05:00Z",
                lastActivityAt: "2026-07-08T00:05:00Z", lastSeq: 6
            ),
        ]
        await coordinator.mergeConversationSummaries(summaries, hostName: "MacBook Pro", hostID: "host-1")

        let mirrored = try await repo.conversation(id: "conv-remote-1")
        #expect(mirrored?.title == "Started on Mac")
        #expect(mirrored?.hostName == "MacBook Pro")
        #expect(mirrored?.lastHostSeq == 0, "a list summary is not a hydrated event cursor")
        #expect(mirrored?.syncState == .synced)
    }

    @Test("mergeConversationSummaries never regresses lastHostSeq below the existing mirror value")
    func mergeConversationSummariesDoesNotRegressSeq() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let coordinator = ConversationSyncCoordinator(chatRepo: repo)
        let seed = ChatConversation(id: "conv-1", title: "T", agentID: "claudeCode", hostName: "h", hostID: nil, cwd: "/proj")
        _ = try await repo.upsertConversationMirror(seed, lastHostSeq: 12, syncState: .synced)

        // A stale list summary reporting a lower lastSeq than what this
        // device already mirrored from a live turn (e.g. the daemon's list
        // cache hadn't caught up yet) must not roll the mirror backward.
        let staleSummary = ConversationSummary(
            id: "conv-1", title: "T (stale)", provider: "claudeCode", agentID: "claudeCode",
            hostName: "h", cwd: "/proj", state: "active", source: "app",
            createdAt: "2026-07-08T00:00:00Z", updatedAt: "2026-07-08T00:01:00Z",
            lastActivityAt: "2026-07-08T00:01:00Z", lastSeq: 3
        )
        await coordinator.mergeConversationSummaries([staleSummary], hostName: "h", hostID: nil)

        let mirrored = try await repo.conversation(id: "conv-1")
        #expect(mirrored?.lastHostSeq == 12, "list-based merge must never regress lastHostSeq")
    }

    @Test("mergeConversationSummaries never clobbers a stored relay routing agentID with a bare provider token")
    func mergeConversationSummariesPreservesRelayRoutingID() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let coordinator = ConversationSyncCoordinator(chatRepo: repo)
        let machineID = "557A7877-F729-5031-9606-0E04F2B67822"
        let seed = ChatConversation(
            id: "conv-relay", title: "T", agentID: "relay|\(machineID)|claudeCode",
            hostName: "Mac", hostID: machineID, cwd: "/proj"
        )
        _ = try await repo.upsertConversationMirror(seed, lastHostSeq: 2, syncState: .synced)

        let summary = ConversationSummary(
            id: "conv-relay", title: "T (from list)", provider: "claudeCode", agentID: "claudeCode",
            hostID: machineID, hostName: "Mac", cwd: "/proj", state: "active", source: "app",
            createdAt: "2026-07-08T00:00:00Z", updatedAt: "2026-07-08T00:01:00Z",
            lastActivityAt: "2026-07-08T00:01:00Z", lastSeq: 5
        )
        await coordinator.mergeConversationSummaries([summary], hostName: "Mac", hostID: machineID)

        let mirrored = try await repo.conversation(id: "conv-relay")
        #expect(mirrored?.agentID == "relay|\(machineID)|claudeCode", "must not clobber the stored routing id with the bare provider token")
        #expect(mirrored?.lastHostSeq == 2, "summary metadata must preserve the hydrated cursor")
    }

    @Test("refresh repairs a summary-poisoned cursor from locally hydrated events")
    func refreshRepairsSummaryPoisonedCursor() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let coordinator = ConversationSyncCoordinator(chatRepo: repo)
        let seed = ChatConversation(
            id: "conv-poisoned", title: "Imported", agentID: "claudeCode",
            hostName: "Mac", hostID: nil, cwd: "/proj"
        )
        _ = try await repo.upsertConversationMirror(seed, lastHostSeq: 1_036, syncState: .synced)

        let transport = makeTransport(fetch: { request in
            #expect(request.sinceSeq == 0)
            return ConversationFetchResponse(
                conversation: ConversationSummary(
                    id: "conv-poisoned", title: "Imported", provider: "claudeCode",
                    agentID: "claudeCode", hostName: "Mac", cwd: "/proj", state: "completed",
                    source: "observed", createdAt: "2026-07-13T00:00:00Z",
                    updatedAt: "2026-07-13T00:01:00Z", lastActivityAt: "2026-07-13T00:01:00Z",
                    lastSeq: 1_036
                ),
                turns: [
                    ConversationTurnEnvelope(
                        id: "turn-1", conversationId: "conv-poisoned", ordinal: 0,
                        clientTurnId: "observed:1", prompt: "hello", runId: "run-1",
                        provider: "claudeCode", status: "completed",
                        startedAt: "2026-07-13T00:00:00Z"
                    ),
                ],
                events: [
                    ConversationEvent(
                        conversationId: "conv-poisoned", seq: 1, turnId: "turn-1",
                        runId: "run-1", kind: "output", role: "assistant",
                        text: "hydrated reply", createdAt: "2026-07-13T00:00:01Z"
                    ),
                ],
                nextSeq: 1_036
            )
        })

        _ = try await coordinator.refreshConversation(conversationID: "conv-poisoned", transport: transport)
        let turns = try await repo.turns(conversationID: "conv-poisoned")
        #expect(turns.first?.assistantText == "hydrated reply")
    }

    @Test("refresh resumes from the highest contiguous locally hydrated event")
    func refreshUsesContiguousLocalEventCursor() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let coordinator = ConversationSyncCoordinator(chatRepo: repo)
        let seed = ChatConversation(
            id: "conv-partial", title: "Partial", agentID: "claudeCode",
            hostName: "Mac", hostID: nil, cwd: "/proj"
        )
        _ = try await repo.upsertConversationMirror(seed, lastHostSeq: 1_036, syncState: .synced)
        try await repo.appendEventsMirror(
            conversationID: "conv-partial",
            events: [
                ChatEvent(conversationID: "conv-partial", seq: 1, kind: "output", text: "first"),
                ChatEvent(conversationID: "conv-partial", seq: 30, kind: "output", text: "later chunk"),
            ]
        )

        let transport = makeTransport(fetch: { request in
            #expect(request.sinceSeq == 1)
            return ConversationFetchResponse(
                conversation: ConversationSummary(
                    id: "conv-partial", title: "Partial", provider: "claudeCode",
                    agentID: "claudeCode", hostName: "Mac", cwd: "/proj", state: "active",
                    source: "observed", createdAt: "2026-07-13T00:00:00Z",
                    updatedAt: "2026-07-13T00:01:00Z", lastActivityAt: "2026-07-13T00:01:00Z",
                    lastSeq: 30
                ),
                turns: [], events: [], nextSeq: 30
            )
        })

        _ = try await coordinator.refreshConversation(conversationID: "conv-partial", transport: transport)
    }

    @Test("mergeConversationSummaries applies running→failed from enriched list lastTurnStatus")
    func mergeConversationSummariesAppliesRunningToFailed() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let coordinator = ConversationSyncCoordinator(chatRepo: repo)
        let seed = ChatConversation(
            id: "conv-orphan", title: "Orphaned", agentID: "claudeCode",
            hostName: "Mac", hostID: nil, cwd: "/proj"
        )
        _ = try await repo.upsertConversationMirror(seed, lastHostSeq: 2, syncState: .synced)
        let running = ChatTurn(
            id: "turn-orphan", conversationID: "conv-orphan", ordinal: 0,
            prompt: "go", runID: "run-orphan", status: .running
        )
        _ = try await repo.upsertTurnMirror(
            running, vendorSessionID: nil, hostSeqStart: nil, hostSeqEnd: nil
        )

        let summary = ConversationSummary(
            id: "conv-orphan", title: "Orphaned", provider: "claudeCode", agentID: "claudeCode",
            hostName: "Mac", cwd: "/proj", state: "active", source: "app",
            createdAt: "2026-07-08T00:00:00Z", updatedAt: "2026-07-08T00:01:00Z",
            lastActivityAt: "2026-07-08T00:01:00Z", lastSeq: 2,
            lastTurnID: "turn-orphan", lastTurnStatus: "failed"
        )
        await coordinator.mergeConversationSummaries([summary], hostName: "Mac", hostID: nil)

        let turns = try await repo.turns(conversationID: "conv-orphan")
        #expect(turns.count == 1)
        #expect(turns[0].status == .failed)
        let kind = WorkspaceRepoCatalog.statusKind(conversation: seed, lastTurn: turns[0])
        #expect(kind == .failed)
        #expect(kind != .working)
    }

    @Test("mergeConversationSummaries does not overwrite a locally-completed turn")
    func mergeConversationSummariesDoesNotRegressCompleted() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let coordinator = ConversationSyncCoordinator(chatRepo: repo)
        let seed = ChatConversation(
            id: "conv-done", title: "Done", agentID: "claudeCode",
            hostName: "Mac", hostID: nil, cwd: "/proj"
        )
        _ = try await repo.upsertConversationMirror(seed, lastHostSeq: 4, syncState: .synced)
        let completed = ChatTurn(
            id: "turn-done", conversationID: "conv-done", ordinal: 0,
            prompt: "go", runID: "run-done", status: .completed
        )
        _ = try await repo.upsertTurnMirror(
            completed, vendorSessionID: nil, hostSeqStart: nil, hostSeqEnd: nil
        )

        // Stale/hostile host status must not regress a terminal local turn.
        let summary = ConversationSummary(
            id: "conv-done", title: "Done", provider: "claudeCode", agentID: "claudeCode",
            hostName: "Mac", cwd: "/proj", state: "active", source: "app",
            createdAt: "2026-07-08T00:00:00Z", updatedAt: "2026-07-08T00:01:00Z",
            lastActivityAt: "2026-07-08T00:01:00Z", lastSeq: 4,
            lastTurnID: "turn-done", lastTurnStatus: "running"
        )
        await coordinator.mergeConversationSummaries([summary], hostName: "Mac", hostID: nil)

        let turns = try await repo.turns(conversationID: "conv-done")
        #expect(turns[0].status == .completed)
        let kind = WorkspaceRepoCatalog.statusKind(conversation: seed, lastTurn: turns[0])
        #expect(kind == .completed)
        #expect(kind != .working)
    }

    @Test("mergeConversationSummaries ignores summaries without lastTurn fields")
    func mergeConversationSummariesIgnoresAbsentLastTurnFields() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let coordinator = ConversationSyncCoordinator(chatRepo: repo)
        let seed = ChatConversation(
            id: "conv-old", title: "Old daemon", agentID: "claudeCode",
            hostName: "Mac", hostID: nil, cwd: "/proj"
        )
        _ = try await repo.upsertConversationMirror(seed, lastHostSeq: 1, syncState: .synced)
        let running = ChatTurn(
            id: "turn-old", conversationID: "conv-old", ordinal: 0,
            prompt: "go", runID: "run-old", status: .running
        )
        _ = try await repo.upsertTurnMirror(
            running, vendorSessionID: nil, hostSeqStart: nil, hostSeqEnd: nil
        )

        let summary = ConversationSummary(
            id: "conv-old", title: "Old daemon", provider: "claudeCode", agentID: "claudeCode",
            hostName: "Mac", cwd: "/proj", state: "active", source: "app",
            createdAt: "2026-07-08T00:00:00Z", updatedAt: "2026-07-08T00:01:00Z",
            lastActivityAt: "2026-07-08T00:01:00Z", lastSeq: 1
        )
        await coordinator.mergeConversationSummaries([summary], hostName: "Mac", hostID: nil)

        let turns = try await repo.turns(conversationID: "conv-old")
        #expect(turns[0].status == .running, "absent lastTurn fields must not invent a status")
    }

    @Test("observeSyncState immediately yields the current state, then updates on transitions")
    func observeSyncStateStream() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let coordinator = ConversationSyncCoordinator(chatRepo: repo)
        let seed = ChatConversation(id: "conv-1", title: "T", agentID: "claudeCode", hostName: "h", hostID: nil, cwd: "/proj")
        _ = try await repo.upsertConversationMirror(seed, lastHostSeq: 2, syncState: .synced)

        let stream = await coordinator.observeSyncState(conversationID: "conv-1")
        var iterator = stream.makeAsyncIterator()
        let first = await iterator.next()
        #expect(first == .synced)

        let transport = makeTransport(
            append: { _ in
                ConversationAppendResponse(status: "conflict", conversationId: "conv-1", baseSeq: 1, nextSeq: 5)
            },
            fetch: { _ in throw NSError(domain: "test", code: 1) }
        )
        async let outcome: ConversationSyncCoordinator.TurnOutcome = coordinator.continueConversation(
            conversationID: "conv-1", baseSeq: 1, prompt: "x", clientTurnID: "d:1",
            hostName: "h", hostID: nil, transport: transport
        )
        // First transition is `.syncing` (published before the append call resolves).
        let syncing = await iterator.next()
        #expect(syncing == .syncing)
        let conflict = await iterator.next()
        #expect(conflict == .conflict)
        _ = await outcome
    }

    @Test("parseDate accepts fractional and plain ISO8601 host timestamps")
    func parseDateFractionalAndPlain() {
        let fractional = ConversationSyncCoordinator.parseDate("2026-07-12T08:30:00.123Z")
        let plain = ConversationSyncCoordinator.parseDate("2026-07-12T08:30:00Z")
        #expect(fractional != nil)
        #expect(plain != nil)
        // Same instant modulo fractional part — must not fall back to .now.
        #expect(abs((fractional?.timeIntervalSince1970 ?? 0) - (plain?.timeIntervalSince1970 ?? 0)) < 1)
        #expect(ConversationSyncCoordinator.parseDate(nil) == nil)
        #expect(ConversationSyncCoordinator.parseDate("") == nil)
        #expect(ConversationSyncCoordinator.parseDate("not-a-date") == nil)
    }

    // MARK: - P1 imported-transcript hydration

    @Test("event-less refresh preserves non-empty local assistantText")
    func eventLessRefreshPreservesAssistantText() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let coordinator = ConversationSyncCoordinator(chatRepo: repo)
        let seed = ChatConversation(
            id: "conv-keep", title: "Imported", agentID: "claudeCode",
            hostName: "Mac", hostID: nil, cwd: "/proj"
        )
        _ = try await repo.upsertConversationMirror(seed, lastHostSeq: 10, syncState: .synced)
        let hydrated = ChatTurn(
            id: "turn-1", conversationID: "conv-keep", ordinal: 0,
            prompt: "hello", runID: "run-1", status: .completed,
            assistantText: "already hydrated reply"
        )
        _ = try await repo.upsertTurnMirror(
            hydrated, vendorSessionID: nil, hostSeqStart: nil, hostSeqEnd: nil
        )

        let transport = makeTransport(fetch: { request in
            #expect(request.sinceSeq == 0 || request.sinceSeq == 10)
            return ConversationFetchResponse(
                conversation: ConversationSummary(
                    id: "conv-keep", title: "Imported", provider: "claudeCode",
                    agentID: "claudeCode", hostName: "Mac", cwd: "/proj", state: "completed",
                    source: "observed", createdAt: "2026-07-13T00:00:00Z",
                    updatedAt: "2026-07-13T00:01:00Z", lastActivityAt: "2026-07-13T00:01:00Z",
                    lastSeq: 10
                ),
                turns: [
                    ConversationTurnEnvelope(
                        id: "turn-1", conversationId: "conv-keep", ordinal: 0,
                        clientTurnId: "observed:1", prompt: "hello", runId: "run-1",
                        provider: "claudeCode", status: "completed",
                        startedAt: "2026-07-13T00:00:00Z"
                    ),
                ],
                events: [],
                nextSeq: 10
            )
        })

        _ = try await coordinator.refreshConversation(conversationID: "conv-keep", transport: transport)
        let turns = try await repo.turns(conversationID: "conv-keep")
        #expect(turns.first?.assistantText == "already hydrated reply")
    }

    @Test("eventful refresh that assembles empty replaces prior assistantText")
    func eventfulEmptyAssemblyReplacesPriorAssistantText() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let coordinator = ConversationSyncCoordinator(chatRepo: repo)
        let seed = ChatConversation(
            id: "conv-replace", title: "Imported", agentID: "claudeCode",
            hostName: "Mac", hostID: nil, cwd: "/proj"
        )
        _ = try await repo.upsertConversationMirror(seed, lastHostSeq: 0, syncState: .synced)
        let stale = ChatTurn(
            id: "turn-1", conversationID: "conv-replace", ordinal: 0,
            prompt: "hello", runID: "run-1", status: .completed,
            assistantText: "stale body that must not win"
        )
        _ = try await repo.upsertTurnMirror(
            stale, vendorSessionID: nil, hostSeqStart: nil, hostSeqEnd: nil
        )

        let transport = makeTransport(fetch: { _ in
            ConversationFetchResponse(
                conversation: ConversationSummary(
                    id: "conv-replace", title: "Imported", provider: "claudeCode",
                    agentID: "claudeCode", hostName: "Mac", cwd: "/proj", state: "completed",
                    source: "observed", createdAt: "2026-07-13T00:00:00Z",
                    updatedAt: "2026-07-13T00:01:00Z", lastActivityAt: "2026-07-13T00:01:00Z",
                    lastSeq: 2
                ),
                turns: [
                    ConversationTurnEnvelope(
                        id: "turn-1", conversationId: "conv-replace", ordinal: 0,
                        clientTurnId: "observed:1", prompt: "hello", runId: "run-1",
                        provider: "claudeCode", status: "completed",
                        startedAt: "2026-07-13T00:00:00Z"
                    ),
                ],
                events: [
                    ConversationEvent(
                        conversationId: "conv-replace", seq: 1, turnId: "turn-1",
                        runId: "run-1", kind: "tool_use", role: "assistant",
                        text: nil, payloadJson: #"{"name":"Read","toolUseId":"t1"}"#,
                        createdAt: "2026-07-13T00:00:01Z"
                    ),
                    ConversationEvent(
                        conversationId: "conv-replace", seq: 2, turnId: "turn-1",
                        runId: "run-1", kind: "thinking", role: "assistant",
                        text: "silent thoughts", createdAt: "2026-07-13T00:00:02Z"
                    ),
                ],
                nextSeq: 2
            )
        })

        _ = try await coordinator.refreshConversation(conversationID: "conv-replace", transport: transport)
        let turns = try await repo.turns(conversationID: "conv-replace")
        #expect(turns.first?.assistantText == "")
    }

    @Test("refresh retries a timed-out fetch then hydrates assistantText")
    func refreshRetriesTimedOutFetchThenHydrates() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let coordinator = ConversationSyncCoordinator(chatRepo: repo)
        let seed = ChatConversation(
            id: "conv-retry", title: "Large import", agentID: "claudeCode",
            hostName: "Mac", hostID: nil, cwd: "/proj"
        )
        _ = try await repo.upsertConversationMirror(seed, lastHostSeq: 0, syncState: .synced)

        let attempts = FetchAttemptCounter()
        let largeBody = String(repeating: "assistant chunk ", count: 2_000)
        let transport = makeTransport(fetch: { request in
            let n = await attempts.increment()
            if n == 1 {
                throw E2EError.timedOut
            }
            #expect(request.sinceSeq == 0)
            return ConversationFetchResponse(
                conversation: ConversationSummary(
                    id: "conv-retry", title: "Large import", provider: "claudeCode",
                    agentID: "claudeCode", hostName: "Mac", cwd: "/proj", state: "completed",
                    source: "observed", createdAt: "2026-07-13T00:00:00Z",
                    updatedAt: "2026-07-13T00:01:00Z", lastActivityAt: "2026-07-13T00:01:00Z",
                    lastSeq: 1_036
                ),
                turns: [
                    ConversationTurnEnvelope(
                        id: "turn-1", conversationId: "conv-retry", ordinal: 0,
                        clientTurnId: "observed:1", prompt: "fix rows", runId: "run-1",
                        provider: "claudeCode", status: "completed",
                        startedAt: "2026-07-13T00:00:00Z"
                    ),
                ],
                events: [
                    ConversationEvent(
                        conversationId: "conv-retry", seq: 1, turnId: "turn-1",
                        runId: "run-1", kind: "output", role: "assistant",
                        text: largeBody, createdAt: "2026-07-13T00:00:01Z"
                    ),
                ],
                nextSeq: 1_036
            )
        })

        _ = try await coordinator.refreshConversation(conversationID: "conv-retry", transport: transport)
        #expect(await attempts.value == 2)
        #expect(ConversationSyncCoordinator.fetchRetryAttempts == 2)
        let turns = try await repo.turns(conversationID: "conv-retry")
        #expect(turns.first?.assistantText == largeBody)
        #expect(await coordinator.currentSyncState("conv-retry") == .synced)
    }

    @Test("exhausted timed-out fetch throws cloudStale without persisting hostOffline")
    func exhaustedTimedOutFetchPublishesCloudStaleNotHostOffline() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let coordinator = ConversationSyncCoordinator(chatRepo: repo)
        let seed = ChatConversation(
            id: "conv-fail", title: "Import", agentID: "claudeCode",
            hostName: "Mac", hostID: nil, cwd: "/proj"
        )
        _ = try await repo.upsertConversationMirror(seed, lastHostSeq: 0, syncState: .synced)

        let attempts = FetchAttemptCounter()
        let transport = makeTransport(fetch: { _ in
            _ = await attempts.increment()
            throw E2EError.timedOut
        })

        await #expect(throws: E2EError.timedOut) {
            _ = try await coordinator.refreshConversation(conversationID: "conv-fail", transport: transport)
        }
        #expect(await attempts.value == 2, "initial + one transient retry only")
        #expect(await coordinator.currentSyncState("conv-fail") == .cloudStale)
        let mirrored = try await repo.conversation(id: "conv-fail")
        #expect(mirrored?.syncState == .synced, "timeout must not persist hostOffline")
    }

    @Test("refresh never retries non-transient transport errors")
    func refreshNeverRetriesNonTransientErrors() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let coordinator = ConversationSyncCoordinator(chatRepo: repo)
        let seed = ChatConversation(
            id: "conv-crypto", title: "Import", agentID: "claudeCode",
            hostName: "Mac", hostID: nil, cwd: "/proj"
        )
        _ = try await repo.upsertConversationMirror(seed, lastHostSeq: 0, syncState: .synced)

        let nonTransient: [E2EError] = [.decryptFailed, .notPaired, .superseded, .encryptFailed]
        for error in nonTransient {
            let attempts = FetchAttemptCounter()
            let transport = makeTransport(fetch: { _ in
                _ = await attempts.increment()
                throw error
            })
            do {
                _ = try await coordinator.refreshConversation(
                    conversationID: "conv-crypto", transport: transport
                )
                Issue.record("expected \(error) to throw")
            } catch let thrown as E2EError {
                #expect(thrown == error)
            } catch {
                Issue.record("expected E2EError \(error), got \(error)")
            }
            #expect(await attempts.value == 1, "non-transient \(error) must not retry")
        }
    }

    @Test("zero wall budget throws refresh timeout without calling fetch")
    func zeroWallBudgetThrowsRefreshTimeoutWithoutFetch() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let coordinator = ConversationSyncCoordinator(chatRepo: repo)
        let seed = ChatConversation(
            id: "conv-budget", title: "Import", agentID: "claudeCode",
            hostName: "Mac", hostID: nil, cwd: "/proj"
        )
        _ = try await repo.upsertConversationMirror(seed, lastHostSeq: 3, syncState: .synced)

        let attempts = FetchAttemptCounter()
        let transport = makeTransport(fetch: { _ in
            _ = await attempts.increment()
            Issue.record("fetch must not start when wall budget is already exhausted")
            throw E2EError.timedOut
        })
        let frozen = ContinuousClock.now

        await #expect(throws: ConversationSyncCoordinator.ConversationSyncRefreshTimeoutError.self) {
            _ = try await coordinator.refreshConversation(
                conversationID: "conv-budget",
                transport: transport,
                wallBudget: .seconds(0),
                now: { frozen }
            )
        }
        #expect(await attempts.value == 0)
        #expect(await coordinator.currentSyncState("conv-budget") == .cloudStale)
        let mirrored = try await repo.conversation(id: "conv-budget")
        #expect(mirrored?.syncState == .synced)
        #expect(ConversationSyncCoordinator.refreshWallBudget == .seconds(60))
        #expect(ConversationSyncCoordinator.fetchRPCTimeout == .seconds(30))
    }

    @Test("insufficient remaining budget skips retry and throws refresh timeout")
    func insufficientRemainingBudgetSkipsRetry() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let coordinator = ConversationSyncCoordinator(chatRepo: repo)
        let seed = ChatConversation(
            id: "conv-short", title: "Import", agentID: "claudeCode",
            hostName: "Mac", hostID: nil, cwd: "/proj"
        )
        _ = try await repo.upsertConversationMirror(seed, lastHostSeq: 0, syncState: .synced)

        let attempts = FetchAttemptCounter()
        let transport = makeTransport(fetch: { _ in
            _ = await attempts.increment()
            throw E2EError.timedOut
        })
        // One RPC-sized budget: first attempt may start; after it fails the
        // injected clock jumps so remaining < fetchRPCTimeout and retry is skipped.
        let clock = RefreshBudgetTestClock(
            exhaustAfterReads: 3,
            advanceBy: ConversationSyncCoordinator.fetchRPCTimeout
        )

        await #expect(throws: ConversationSyncCoordinator.ConversationSyncRefreshTimeoutError.self) {
            _ = try await coordinator.refreshConversation(
                conversationID: "conv-short",
                transport: transport,
                wallBudget: ConversationSyncCoordinator.fetchRPCTimeout,
                now: { clock.now() }
            )
        }
        #expect(await attempts.value == 1)
        #expect(await coordinator.currentSyncState("conv-short") == .cloudStale)
    }

    @Test("refresh pages past 500 events with cursor merge")
    func refreshPagesPastFiveHundredEvents() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let coordinator = ConversationSyncCoordinator(chatRepo: repo)
        let seed = ChatConversation(
            id: "conv-501", title: "Long import", agentID: "claudeCode",
            hostName: "Mac", hostID: nil, cwd: "/proj"
        )
        _ = try await repo.upsertConversationMirror(seed, lastHostSeq: 0, syncState: .synced)

        #expect(ConversationSyncCoordinator.fetchPageLimit == 500)
        let summary = ConversationSummary(
            id: "conv-501", title: "Long import", provider: "claudeCode",
            agentID: "claudeCode", hostName: "Mac", cwd: "/proj", state: "completed",
            source: "observed", createdAt: "2026-07-13T00:00:00Z",
            updatedAt: "2026-07-13T00:02:00Z", lastActivityAt: "2026-07-13T00:02:00Z",
            lastSeq: 501
        )
        let turn = ConversationTurnEnvelope(
            id: "turn-1", conversationId: "conv-501", ordinal: 0,
            clientTurnId: "observed:1", prompt: "long", runId: "run-1",
            provider: "claudeCode", status: "completed",
            startedAt: "2026-07-13T00:00:00Z"
        )
        let page1Events: [ConversationEvent] = (1...500).map { seq in
            ConversationEvent(
                conversationId: "conv-501", seq: seq, turnId: "turn-1",
                runId: "run-1", kind: "output", role: "assistant",
                text: "e\(seq)-", createdAt: "2026-07-13T00:00:01Z"
            )
        }
        let page2Events = [
            ConversationEvent(
                conversationId: "conv-501", seq: 501, turnId: "turn-1",
                runId: "run-1", kind: "output", role: "assistant",
                text: "tail", createdAt: "2026-07-13T00:00:02Z"
            )
        ]
        let attempts = FetchAttemptCounter()
        let transport = makeTransport(fetch: { request in
            #expect(request.limit == 500)
            let n = await attempts.increment()
            switch n {
            case 1:
                #expect(request.sinceSeq == 0)
                return ConversationFetchResponse(
                    conversation: summary, turns: [turn], events: page1Events,
                    nextSeq: 500, hasMore: true
                )
            case 2:
                #expect(request.sinceSeq == 500)
                return ConversationFetchResponse(
                    conversation: summary, turns: [turn], events: page2Events,
                    nextSeq: 501, hasMore: false
                )
            default:
                Issue.record("unexpected third fetch page")
                throw E2EError.timedOut
            }
        })

        let nextSeq = try await coordinator.refreshConversation(
            conversationID: "conv-501", transport: transport
        )
        #expect(nextSeq == 501)
        #expect(await attempts.value == 2)
        let events = try await repo.events(conversationID: "conv-501", limit: 1_000)
        #expect(events.count == 501)
        let turns = try await repo.turns(conversationID: "conv-501")
        #expect(turns.first?.assistantText.hasSuffix("tail") == true)
        #expect(await coordinator.currentSyncState("conv-501") == .synced)
    }

    @Test("mid-pagination timeout keeps partial merge stale without hostOffline")
    func midPaginationTimeoutKeepsCloudStale() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let coordinator = ConversationSyncCoordinator(chatRepo: repo)
        let seed = ChatConversation(
            id: "conv-partial", title: "Partial", agentID: "claudeCode",
            hostName: "Mac", hostID: nil, cwd: "/proj"
        )
        _ = try await repo.upsertConversationMirror(seed, lastHostSeq: 0, syncState: .synced)
        let prior = ChatTurn(
            id: "turn-1", conversationID: "conv-partial", ordinal: 0,
            prompt: "hello", runID: "run-1", status: .completed,
            assistantText: "prior cached prose"
        )
        _ = try await repo.upsertTurnMirror(
            prior, vendorSessionID: nil, hostSeqStart: nil, hostSeqEnd: nil
        )

        let summary = ConversationSummary(
            id: "conv-partial", title: "Partial", provider: "claudeCode",
            agentID: "claudeCode", hostName: "Mac", cwd: "/proj", state: "completed",
            source: "observed", createdAt: "2026-07-13T00:00:00Z",
            updatedAt: "2026-07-13T00:01:00Z", lastActivityAt: "2026-07-13T00:01:00Z",
            lastSeq: 20
        )
        let turn = ConversationTurnEnvelope(
            id: "turn-1", conversationId: "conv-partial", ordinal: 0,
            clientTurnId: "observed:1", prompt: "hello", runId: "run-1",
            provider: "claudeCode", status: "completed",
            startedAt: "2026-07-13T00:00:00Z"
        )
        let attempts = FetchAttemptCounter()
        let transport = makeTransport(fetch: { request in
            let n = await attempts.increment()
            if n == 1 {
                #expect(request.sinceSeq == 0)
                return ConversationFetchResponse(
                    conversation: summary,
                    turns: [turn],
                    events: [],
                    nextSeq: 10,
                    hasMore: true
                )
            }
            throw E2EError.timedOut
        })

        await #expect(throws: E2EError.timedOut) {
            _ = try await coordinator.refreshConversation(
                conversationID: "conv-partial", transport: transport
            )
        }
        #expect(await attempts.value == 3, "page1 + page2 initial + one retry")
        #expect(await coordinator.currentSyncState("conv-partial") == .cloudStale)
        let mirrored = try await repo.conversation(id: "conv-partial")
        #expect(mirrored?.syncState == .synced)
        #expect(mirrored?.lastHostSeq == 10)
        let turns = try await repo.turns(conversationID: "conv-partial")
        #expect(turns.first?.assistantText == "prior cached prose")
    }

    @Test("transcript refresh load gate only latest attempt mutates banner")
    func transcriptRefreshLoadGateOnlyLatestMutates() {
        let gate = TranscriptRefreshLoadGate()
        let first = gate.beginLoad()
        let second = gate.beginLoad()
        #expect(gate.allowsMutation(first) == false)
        #expect(gate.allowsMutation(second) == true)
        #expect(gate.clearBanner(onSuccessFor: first) == false)
        #expect(gate.clearBanner(onSuccessFor: second) == true)
        #expect(gate.setBanner(failedFor: first) == false)
        #expect(gate.setBanner(failedFor: second) == true)
    }

    @Test("host attachment envelopes map into local ChatTurn.attachments")
    func hostAttachmentsMapIntoLocalTurns() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let coordinator = ConversationSyncCoordinator(chatRepo: repo)
        let attachment = ConversationAttachmentReference(
            id: "a1", name: "photo.jpg", mimeType: "image/jpeg",
            byteCount: 310_992, kind: .image,
            hostPath: "/Users/me/.lancer/attachments/photo.jpg",
            previewCacheKey: "a1"
        )
        let transport = makeTransport(fetch: { req in
            ConversationFetchResponse(
                conversation: ConversationSummary(
                    id: req.conversationId, title: "Describe", provider: "claudeCode",
                    agentID: "claudeCode", hostName: "h", cwd: "/proj", state: "active",
                    source: "app", createdAt: "2026-07-14T00:00:00Z", updatedAt: "2026-07-14T00:00:00Z",
                    lastActivityAt: "2026-07-14T00:00:00Z", lastSeq: 2
                ),
                turns: [
                    ConversationTurnEnvelope(
                        id: "turn-att", conversationId: req.conversationId, ordinal: 0,
                        clientTurnId: "ios:1", prompt: "Describe this image",
                        runId: "run-att", provider: "claudeCode", status: "completed",
                        startedAt: "2026-07-14T00:00:00Z", attachments: [attachment]
                    ),
                ],
                events: [
                    ConversationEvent(
                        conversationId: req.conversationId, seq: 1, turnId: "turn-att",
                        kind: "prompt", role: "user", text: "Describe this image",
                        createdAt: "2026-07-14T00:00:00Z"
                    ),
                    ConversationEvent(
                        conversationId: req.conversationId, seq: 2, turnId: "turn-att",
                        kind: "output", role: "assistant", text: "A sunset.",
                        createdAt: "2026-07-14T00:00:01Z"
                    ),
                ],
                nextSeq: 2
            )
        })

        _ = try await coordinator.refreshConversation(conversationID: "conv-att", transport: transport)
        let turns = try await repo.turns(conversationID: "conv-att")
        #expect(turns.count == 1)
        #expect(turns.first?.attachments == [attachment])
        #expect(turns.first?.prompt == "Describe this image")
        #expect(turns.first?.assistantText == "A sunset.")
        #expect(!(turns.first?.prompt.contains("/Users/") ?? true))
    }

    @Test("startConversation forwards attachments and persists clean prompt")
    func startConversationForwardsAttachments() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let coordinator = ConversationSyncCoordinator(chatRepo: repo)
        let attachment = ConversationAttachmentReference(
            id: "a1", name: "photo.jpg", mimeType: "image/jpeg",
            byteCount: 100, kind: .image,
            hostPath: "/Users/me/.lancer/attachments/photo.jpg",
            previewCacheKey: "a1"
        )
        nonisolated(unsafe) var seenRequest: ConversationAppendRequest?
        let transport = makeTransport(append: { request in
            seenRequest = request
            return ConversationAppendResponse(
                status: "started", conversationId: "conv-att-2", turnId: "turn-2",
                runId: "run-2", cwd: "/proj", nextSeq: 1
            )
        })

        let outcome = await coordinator.startConversation(
            agent: "claudeCode", cwd: "/proj", prompt: "Describe this image",
            model: nil, budgetUSD: nil, hostName: "h", hostID: "h1",
            clientTurnID: "ios:att-1", transport: transport,
            attachments: [attachment]
        )
        guard case .started = outcome else {
            Issue.record("expected started")
            return
        }
        #expect(seenRequest?.prompt == "Describe this image")
        #expect(seenRequest?.attachments == [attachment])
        #expect(!(seenRequest?.prompt.contains("Attached files") ?? true))
        let turns = try await repo.turns(conversationID: "conv-att-2")
        #expect(turns.first?.attachments == [attachment])
        #expect(turns.first?.prompt == "Describe this image")
    }

    @Test("conflict retry preserves attachment metadata and clientTurnId")
    func conflictRetryPreservesAttachments() async throws {
        let db = try AppDatabase.inMemory()
        let repo = ChatConversationRepository(db)
        let coordinator = ConversationSyncCoordinator(chatRepo: repo)
        let attachment = ConversationAttachmentReference(
            id: "a1", name: "photo.jpg", mimeType: "image/jpeg",
            byteCount: 100, kind: .image,
            hostPath: "/Users/me/.lancer/attachments/photo.jpg",
            previewCacheKey: "a1"
        )
        let appendCount = FetchAttemptCounter()
        nonisolated(unsafe) var lastRequest: ConversationAppendRequest?
        let transport = makeTransport(
            append: { request in
                let count = await appendCount.increment()
                lastRequest = request
                if count == 1 {
                    return ConversationAppendResponse(
                        status: "conflict", conversationId: "conv-retry",
                        nextSeq: 3, message: "stale baseSeq"
                    )
                }
                return ConversationAppendResponse(
                    status: "started", conversationId: "conv-retry", turnId: "turn-r",
                    runId: "run-r", cwd: "/proj", nextSeq: 4
                )
            },
            fetch: { req in
                ConversationFetchResponse(
                    conversation: ConversationSummary(
                        id: req.conversationId, title: "T", provider: "claudeCode",
                        agentID: "claudeCode", hostName: "h", cwd: "/proj", state: "active",
                        source: "app", createdAt: "2026-07-14T00:00:00Z",
                        updatedAt: "2026-07-14T00:00:00Z",
                        lastActivityAt: "2026-07-14T00:00:00Z", lastSeq: 3
                    ),
                    turns: [], events: [], nextSeq: 3
                )
            }
        )

        _ = try await repo.upsertConversationMirror(
            ChatConversation(
                id: "conv-retry", title: "T", agentID: "claudeCode",
                hostName: "h", hostID: "h1", cwd: "/proj"
            ),
            lastHostSeq: 1,
            syncState: .synced
        )

        let outcome = await coordinator.continueConversation(
            conversationID: "conv-retry", baseSeq: 1, prompt: "Describe this image",
            clientTurnID: "ios:retry-1", hostName: "h", hostID: "h1",
            transport: transport, attachments: [attachment]
        )
        guard case .started = outcome else {
            Issue.record("expected started after retry")
            return
        }
        #expect(await appendCount.value == 2)
        #expect(lastRequest?.clientTurnId == "ios:retry-1")
        #expect(lastRequest?.attachments == [attachment])
        #expect(lastRequest?.prompt == "Describe this image")
        #expect(lastRequest?.baseSeq == 3)
    }
}

/// Actor counter for concurrent fetch-attempt assertions in refresh retry tests.
private actor FetchAttemptCounter {
    private(set) var value = 0
    @discardableResult
    func increment() -> Int {
        value += 1
        return value
    }
}

/// Deterministic clock for refresh-budget tests: returns `start` for the first
/// `exhaustAfterReads` reads, then jumps forward by `advanceBy` so remaining
/// budget drops below `fetchRPCTimeout`.
private final class RefreshBudgetTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private let start: ContinuousClock.Instant
    private let exhaustAfterReads: Int
    private let advanceBy: Duration
    private var reads = 0

    init(exhaustAfterReads: Int, advanceBy: Duration) {
        self.start = ContinuousClock.now
        self.exhaustAfterReads = exhaustAfterReads
        self.advanceBy = advanceBy
    }

    func now() -> ContinuousClock.Instant {
        lock.lock()
        defer { lock.unlock() }
        reads += 1
        if reads <= exhaustAfterReads {
            return start
        }
        return start.advanced(by: advanceBy)
    }
}

#endif
