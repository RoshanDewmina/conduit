package main

import (
	"encoding/json"
	"strings"
	"testing"
)

// conversation_persist_test.go covers Task 4 of the cross-device sync build
// handoff: emitNotification's persistConversationEvent hook, which mirrors
// live agent.run.output / agent.run.status / agent.artifact notifications
// into the host conversation ledger (conversation_store.go) for
// conversation-ledger-backed runs (launchConversationTurn), while remaining a
// silent, non-crashing no-op for every ordinary non-ledger-backed run.

// newLedgerBackedTestServer returns a server with a real (t.TempDir()-backed)
// conversationStore already opened by newServer, plus a ledger turn for runID
// beginTurn's returned conversationID/turnID/runID triple, mirroring how
// launchConversationTurn's runID always has a ledger row before the process
// launches (see beginTurn's doc comment in conversation_store.go).
func newLedgerBackedTestServer(t *testing.T) (s *server, conversationID, runID string) {
	t.Helper()
	s = newServer(t.TempDir())
	t.Cleanup(func() { s.poller.stopForTest() })

	res, err := s.conversations.beginTurn(conversationAppendRequest{
		ClientTurnID: "device-1:1",
		Agent:        "claudeCode",
		Prompt:       "fix the failing test",
	}, "/proj", "run-ledger-1")
	if err != nil {
		t.Fatalf("beginTurn: %v", err)
	}
	return s, res.ConversationID, res.RunID
}

// TestPersistConversationEventOutputAppendsLedgerRow proves an
// agent.run.output notification for a ledger-backed run gets persisted as a
// conversation_events row, retrievable via fetch — including that the seq
// value used is exactly the one already present in the notification's
// "seq" param (the same per-run atomic counter streamOutput/streamJSONOutput
// thread through dispatch.go's realLauncher; see dispatch.go:308's `var seq
// int64` and streamOutput/streamJSONOutput's atomic.AddInt64(seq, 1)).
func TestPersistConversationEventOutputAppendsLedgerRow(t *testing.T) {
	s, conversationID, runID := newLedgerBackedTestServer(t)

	s.emitNotification("agent.run.output", map[string]any{
		"runId":  runID,
		"stream": "stdout",
		"chunk":  "hello from the agent",
		"seq":    2,
	})

	fetchRes, err := s.conversations.fetch(conversationID, 0, 500)
	if err != nil {
		t.Fatalf("fetch: %v", err)
	}
	var found bool
	for _, e := range fetchRes.Events {
		if e.Kind == "output" && e.Seq == 2 {
			found = true
			if e.Text != "hello from the agent" {
				t.Errorf("event text = %q, want %q", e.Text, "hello from the agent")
			}
			if e.Stream != "stdout" {
				t.Errorf("event stream = %q, want stdout", e.Stream)
			}
		}
	}
	if !found {
		t.Fatalf("expected an output event at seq 2, got events: %+v", fetchRes.Events)
	}
}

// TestPersistConversationEventStatusUpdatesTurn proves an agent.run.status
// notification updates the owning turn's status (and appends a status event)
// via appendRunStatus.
func TestPersistConversationEventStatusUpdatesTurn(t *testing.T) {
	s, conversationID, runID := newLedgerBackedTestServer(t)

	s.emitNotification("agent.run.status", map[string]any{
		"runId":    runID,
		"status":   "completed",
		"exitCode": 0,
	})

	fetchRes, err := s.conversations.fetch(conversationID, 0, 500)
	if err != nil {
		t.Fatalf("fetch: %v", err)
	}
	if len(fetchRes.Turns) != 1 {
		t.Fatalf("turns = %d, want 1", len(fetchRes.Turns))
	}
	if fetchRes.Turns[0].Status != "completed" {
		t.Errorf("turn status = %q, want completed", fetchRes.Turns[0].Status)
	}
	if fetchRes.Turns[0].CompletedAt == "" {
		t.Error("expected completedAt to be set for a completed turn")
	}
	var sawStatusEvent bool
	for _, e := range fetchRes.Events {
		if e.Kind == "status" {
			sawStatusEvent = true
		}
	}
	if !sawStatusEvent {
		t.Errorf("expected a status event in the log, got %+v", fetchRes.Events)
	}
}

// TestPersistConversationEventArtifactUpsertsArtifact proves an agent.artifact
// notification upserts a conversation_artifacts row. The live event shape
// (dispatch.go's emitToolArtifact) uses "artifactID"/"runID" (capital ID) and
// carries no conversationId/turnId at all — persistConversationEvent must
// resolve those itself via turnByRunID rather than expect them on the wire.
func TestPersistConversationEventArtifactUpsertsArtifact(t *testing.T) {
	s, conversationID, runID := newLedgerBackedTestServer(t)

	s.emitNotification("agent.artifact", map[string]any{
		"artifactID":  "art-1",
		"runID":       runID,
		"kind":        "tool",
		"title":       "Bash",
		"payloadJSON": `{"command":"ls"}`,
		"status":      "running",
	})

	fetchRes, err := s.conversations.fetch(conversationID, 0, 500)
	if err != nil {
		t.Fatalf("fetch: %v", err)
	}
	if len(fetchRes.Artifacts) != 1 {
		t.Fatalf("artifacts = %d, want 1: %+v", len(fetchRes.Artifacts), fetchRes.Artifacts)
	}
	a := fetchRes.Artifacts[0]
	if a.ID != "art-1" {
		t.Errorf("artifact id = %q, want art-1", a.ID)
	}
	if a.Title != "Bash" {
		t.Errorf("artifact title = %q, want Bash", a.Title)
	}
	if a.Kind != "tool" {
		t.Errorf("artifact kind = %q, want tool", a.Kind)
	}
	if a.RunID != runID {
		t.Errorf("artifact runID = %q, want %q", a.RunID, runID)
	}

	// Upsert again with an updated title — must update in place, not duplicate
	// (upsertArtifact's ON CONFLICT(id) DO UPDATE semantics).
	s.emitNotification("agent.artifact", map[string]any{
		"artifactID":  "art-1",
		"runID":       runID,
		"kind":        "tool",
		"title":       "Bash (updated)",
		"payloadJSON": `{"command":"ls -la"}`,
		"status":      "done",
	})
	fetchRes2, err := s.conversations.fetch(conversationID, 0, 500)
	if err != nil {
		t.Fatalf("fetch (after update): %v", err)
	}
	if len(fetchRes2.Artifacts) != 1 {
		t.Fatalf("artifacts after update = %d, want 1 (upsert must not duplicate)", len(fetchRes2.Artifacts))
	}
	if fetchRes2.Artifacts[0].Title != "Bash (updated)" {
		t.Errorf("artifact title after update = %q, want updated title", fetchRes2.Artifacts[0].Title)
	}
}

// TestPersistConversationEventNonLedgerRunIsSilentNoop proves a notification
// for a runID with NO conversation-ledger turn (every ordinary
// agent.dispatch/agent.run.continue/agent.observedSession.continue run) is a
// silent no-op at the ledger level: it must not error, panic, or create any
// ledger row, since calling appendRunOutput for a plain dispatch run would
// otherwise fail "no turn found for run" on every single ordinary message.
func TestPersistConversationEventNonLedgerRunIsSilentNoop(t *testing.T) {
	s := newServer(t.TempDir())
	t.Cleanup(func() { s.poller.stopForTest() })

	// No beginTurn call was made for "plain-dispatch-run" — it has no ledger
	// turn, exactly like a plain agent.dispatch/agent.run.continue run.
	didPanic := false
	func() {
		defer func() {
			if r := recover(); r != nil {
				didPanic = true
			}
		}()
		s.emitNotification("agent.run.output", map[string]any{
			"runId":  "plain-dispatch-run",
			"stream": "stdout",
			"chunk":  "ordinary chat output",
			"seq":    1,
		})
		s.emitNotification("agent.run.status", map[string]any{
			"runId":  "plain-dispatch-run",
			"status": "exited",
		})
		s.emitNotification("agent.artifact", map[string]any{
			"artifactID": "art-x",
			"runID":      "plain-dispatch-run",
			"kind":       "tool",
			"title":      "Bash",
			"status":     "running",
		})
	}()
	if didPanic {
		t.Fatal("emitNotification for a non-ledger-backed run must not panic")
	}

	// No conversation should have been created as a side effect.
	listRes, err := s.conversations.list(50, "", true)
	if err != nil {
		t.Fatalf("list: %v", err)
	}
	if len(listRes.Conversations) != 0 {
		t.Fatalf("expected no conversations created for a non-ledger run, got %+v", listRes.Conversations)
	}
}

// TestPersistConversationEventSurvivesClosedStore proves the "must NEVER
// crash live streaming" requirement even when a ledger write for a
// PREVIOUSLY-valid ledger-backed run starts failing (simulating "store
// unavailable" — e.g. the sqlite connection is closed underneath it).
func TestPersistConversationEventSurvivesClosedStore(t *testing.T) {
	s, _, runID := newLedgerBackedTestServer(t)

	// Simulate the store becoming unavailable mid-run.
	if err := s.conversations.close(); err != nil {
		t.Fatalf("close: %v", err)
	}

	didPanic := false
	func() {
		defer func() {
			if r := recover(); r != nil {
				didPanic = true
			}
		}()
		s.emitNotification("agent.run.output", map[string]any{
			"runId":  runID,
			"stream": "stdout",
			"chunk":  "output after store closed",
			"seq":    99,
		})
	}()
	if didPanic {
		t.Fatal("emitNotification must not panic when the ledger store is unavailable")
	}
}

// TestEmitNotificationPhoneDeliveryUnaffectedByLedgerOutcome is the single
// most important behavior this task must protect: the existing relay/SSH
// phone-facing notification (the writeFramed path emitNotification already
// had) must fire with the EXACT SAME method/params regardless of whether
// ledger persistence succeeds, silently no-ops, or fails.
func TestEmitNotificationPhoneDeliveryUnaffectedByLedgerOutcome(t *testing.T) {
	type frame struct {
		Method string         `json:"method"`
		Params map[string]any `json:"params"`
	}

	captureOneFrame := func(s *server, method string, params map[string]any) frame {
		t.Helper()
		framesCh := make(chan frame, 1)
		s.setEmitter(func(data []byte) error {
			var f frame
			if err := json.Unmarshal(data, &f); err != nil {
				t.Fatalf("unmarshal emitted frame: %v", err)
			}
			select {
			case framesCh <- f:
			default:
			}
			return nil
		})
		s.emitNotification(method, params)
		select {
		case f := <-framesCh:
			return f
		default:
			t.Fatal("emitNotification did not deliver a phone-facing frame")
			return frame{}
		}
	}

	params := map[string]any{
		"runId":  "run-x",
		"stream": "stdout",
		"chunk":  "identical either way",
		"seq":    5,
	}

	// Case 1: ledger persistence SUCCEEDS (ledger-backed run).
	sSuccess, _, runID := newLedgerBackedTestServer(t)
	successParams := map[string]any{
		"runId":  runID,
		"stream": "stdout",
		"chunk":  "identical either way",
		"seq":    2,
	}
	f1 := captureOneFrame(sSuccess, "agent.run.output", successParams)
	if f1.Method != "agent.run.output" {
		t.Fatalf("case success: method = %q, want agent.run.output", f1.Method)
	}
	if f1.Params["chunk"] != "identical either way" {
		t.Fatalf("case success: chunk = %v, want unchanged", f1.Params["chunk"])
	}

	// Case 2: ledger persistence is a silent NO-OP (non-ledger-backed run —
	// the common case for every ordinary dispatched message).
	sNoop := newServer(t.TempDir())
	t.Cleanup(func() { sNoop.poller.stopForTest() })
	f2 := captureOneFrame(sNoop, "agent.run.output", params)
	if f2.Method != "agent.run.output" {
		t.Fatalf("case no-op: method = %q, want agent.run.output", f2.Method)
	}
	if f2.Params["chunk"] != "identical either way" {
		t.Fatalf("case no-op: chunk = %v, want unchanged", f2.Params["chunk"])
	}

	// Case 3: ledger persistence FAILS (store unavailable — closed underneath
	// a previously-valid ledger-backed run).
	sFail, _, failRunID := newLedgerBackedTestServer(t)
	if err := sFail.conversations.close(); err != nil {
		t.Fatalf("close: %v", err)
	}
	failParams := map[string]any{
		"runId":  failRunID,
		"stream": "stdout",
		"chunk":  "identical either way",
		"seq":    2,
	}
	f3 := captureOneFrame(sFail, "agent.run.output", failParams)
	if f3.Method != "agent.run.output" {
		t.Fatalf("case failure: method = %q, want agent.run.output", f3.Method)
	}
	if f3.Params["chunk"] != "identical either way" {
		t.Fatalf("case failure: chunk = %v, want unchanged", f3.Params["chunk"])
	}
}

// TestEmitNotificationIgnoresUnrelatedMethods proves persistConversationEvent
// only inspects the three method names it is documented to touch, leaving
// every other notification (e.g. agent.run.vendorSession, which must NEVER
// reach the phone at all — see wrapEmitForRun) completely unaffected by this
// hook: no ledger row is created, and delivery is unchanged.
func TestEmitNotificationIgnoresUnrelatedMethods(t *testing.T) {
	s, conversationID, _ := newLedgerBackedTestServer(t)

	var got map[string]any
	s.setEmitter(func(data []byte) error {
		var f struct {
			Method string         `json:"method"`
			Params map[string]any `json:"params"`
		}
		_ = json.Unmarshal(data, &f)
		got = f.Params
		return nil
	})

	s.emitNotification("agent.someOtherEvent", map[string]any{"runId": "run-ledger-1", "foo": "bar"})
	if got["foo"] != "bar" {
		t.Fatalf("unrelated method notification not delivered unchanged: %+v", got)
	}

	fetchRes, err := s.conversations.fetch(conversationID, 0, 500)
	if err != nil {
		t.Fatalf("fetch: %v", err)
	}
	// Only the initial turn_started event from beginTurn — nothing new.
	if len(fetchRes.Events) != 1 {
		t.Fatalf("expected no new ledger events from an unrelated method, got %+v", fetchRes.Events)
	}
}

func TestPersistConversationEventFailedRunCapturesStderrErrorMessage(t *testing.T) {
	s, conversationID, runID := newLedgerBackedTestServer(t)

	s.emitNotification("agent.run.output", map[string]any{
		"runId":  runID,
		"stream": "stderr",
		"chunk":  "API Error: model_not_found: anthropic/claude-haiku-4\n",
		"seq":    2,
	})
	s.emitNotification("agent.run.status", map[string]any{
		"runId":    runID,
		"status":   "failed",
		"exitCode": 1,
	})

	fetchRes, err := s.conversations.fetch(conversationID, 0, 500)
	if err != nil {
		t.Fatalf("fetch: %v", err)
	}
	if len(fetchRes.Turns) != 1 {
		t.Fatalf("turns = %d, want 1", len(fetchRes.Turns))
	}
	if fetchRes.Turns[0].Status != "failed" {
		t.Errorf("turn status = %q, want failed", fetchRes.Turns[0].Status)
	}
	if fetchRes.Turns[0].ErrorMessage == "" {
		t.Fatal("expected non-empty error_message on failed turn")
	}
	if !strings.Contains(fetchRes.Turns[0].ErrorMessage, "model_not_found") {
		t.Errorf("error_message = %q, want stderr tail containing model_not_found", fetchRes.Turns[0].ErrorMessage)
	}
}
