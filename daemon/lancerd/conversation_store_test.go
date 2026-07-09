package main

import (
	"fmt"
	"os"
	"path/filepath"
	"testing"
)

func openTestConversationStore(t *testing.T) *conversationStore {
	t.Helper()
	home := t.TempDir()
	s, err := openConversationStore(home)
	if err != nil {
		t.Fatalf("openConversationStore: %v", err)
	}
	t.Cleanup(func() { s.close() })
	return s
}

func TestOpenConversationStoreCreatesDBUnderLancerDir(t *testing.T) {
	home := t.TempDir()
	s, err := openConversationStore(home)
	if err != nil {
		t.Fatalf("openConversationStore: %v", err)
	}
	defer s.close()

	want := filepath.Join(home, ".lancer", "conversations.sqlite")
	if _, err := os.Stat(want); err != nil {
		t.Errorf("expected sqlite file at %s: %v", want, err)
	}
}

func TestBeginTurnCreatesConversationAndListFetch(t *testing.T) {
	s := openTestConversationStore(t)

	req := conversationAppendRequest{
		ClientTurnID: "device-1:1",
		Agent:        "claudeCode",
		Prompt:       "Fix the failing auth test",
		Model:        "sonnet",
		BudgetUSD:    5.0,
	}
	res, err := s.beginTurn(req, "/Users/roshan/project", "run_1")
	if err != nil {
		t.Fatalf("beginTurn: %v", err)
	}
	if res.Status != "started" {
		t.Fatalf("status = %q, want started", res.Status)
	}
	if res.ConversationID == "" || res.TurnID == "" {
		t.Fatalf("expected non-empty conversationID/turnID, got %+v", res)
	}
	if res.RunID != "run_1" {
		t.Errorf("runID = %q, want run_1", res.RunID)
	}
	if res.NextSeq != 1 {
		t.Errorf("nextSeq = %d, want 1", res.NextSeq)
	}

	listRes, err := s.list(50, "", false)
	if err != nil {
		t.Fatalf("list: %v", err)
	}
	if len(listRes.Conversations) != 1 {
		t.Fatalf("conversations = %d, want 1", len(listRes.Conversations))
	}
	if listRes.Conversations[0].ID != res.ConversationID {
		t.Errorf("listed id = %q, want %q", listRes.Conversations[0].ID, res.ConversationID)
	}
	if listRes.Conversations[0].CWD != "/Users/roshan/project" {
		t.Errorf("cwd = %q, want /Users/roshan/project", listRes.Conversations[0].CWD)
	}

	fetchRes, err := s.fetch(res.ConversationID, 0, 500)
	if err != nil {
		t.Fatalf("fetch: %v", err)
	}
	if len(fetchRes.Turns) != 1 {
		t.Fatalf("turns = %d, want 1", len(fetchRes.Turns))
	}
	if fetchRes.Turns[0].Prompt != "Fix the failing auth test" {
		t.Errorf("prompt = %q, want %q", fetchRes.Turns[0].Prompt, "Fix the failing auth test")
	}
	if fetchRes.Turns[0].RunID != "run_1" {
		t.Errorf("turn runID = %q, want run_1", fetchRes.Turns[0].RunID)
	}
}

func TestAppendRunOutputAndStatusOrderingViaFetch(t *testing.T) {
	s := openTestConversationStore(t)

	res, err := s.beginTurn(conversationAppendRequest{
		ClientTurnID: "device-1:1",
		Agent:        "claudeCode",
		Prompt:       "first prompt",
	}, "/proj", "run_1")
	if err != nil {
		t.Fatalf("beginTurn: %v", err)
	}

	if err := s.appendRunOutput("run_1", "stdout", "chunk-a", 2); err != nil {
		t.Fatalf("appendRunOutput chunk-a: %v", err)
	}
	if err := s.appendRunOutput("run_1", "stdout", "chunk-b", 3); err != nil {
		t.Fatalf("appendRunOutput chunk-b: %v", err)
	}
	exitCode := 0
	if err := s.appendRunStatus("run_1", "completed", &exitCode, ""); err != nil {
		t.Fatalf("appendRunStatus: %v", err)
	}

	fetchRes, err := s.fetch(res.ConversationID, 0, 500)
	if err != nil {
		t.Fatalf("fetch: %v", err)
	}
	// turn_started (seq 1), output chunk-a (seq 2), output chunk-b (seq 3), status (seq 4).
	if len(fetchRes.Events) != 4 {
		t.Fatalf("events = %d, want 4: %+v", len(fetchRes.Events), fetchRes.Events)
	}
	for i := 1; i < len(fetchRes.Events); i++ {
		if fetchRes.Events[i].Seq <= fetchRes.Events[i-1].Seq {
			t.Fatalf("events not strictly increasing by seq: %+v", fetchRes.Events)
		}
	}
	if fetchRes.Events[1].Text != "chunk-a" {
		t.Errorf("events[1].Text = %q, want chunk-a", fetchRes.Events[1].Text)
	}
	if fetchRes.Events[2].Text != "chunk-b" {
		t.Errorf("events[2].Text = %q, want chunk-b", fetchRes.Events[2].Text)
	}
	if fetchRes.Events[3].Kind != "status" {
		t.Errorf("events[3].Kind = %q, want status", fetchRes.Events[3].Kind)
	}

	if fetchRes.Turns[0].Status != "completed" {
		t.Errorf("turn status = %q, want completed", fetchRes.Turns[0].Status)
	}
	if fetchRes.Turns[0].CompletedAt == "" {
		t.Error("expected completedAt to be set for a completed turn")
	}

	// sinceSeq pagination: only events strictly after seq 2 should return.
	sinceRes, err := s.fetch(res.ConversationID, 2, 500)
	if err != nil {
		t.Fatalf("fetch sinceSeq=2: %v", err)
	}
	if len(sinceRes.Events) != 2 {
		t.Fatalf("events since seq 2 = %d, want 2: %+v", len(sinceRes.Events), sinceRes.Events)
	}
	if sinceRes.Events[0].Text != "chunk-b" {
		t.Errorf("first event after seq 2 = %q, want chunk-b", sinceRes.Events[0].Text)
	}

	// limit + hasMore.
	limitedRes, err := s.fetch(res.ConversationID, 0, 1)
	if err != nil {
		t.Fatalf("fetch limit=1: %v", err)
	}
	if len(limitedRes.Events) != 1 {
		t.Fatalf("events with limit=1 = %d, want 1", len(limitedRes.Events))
	}
	if !limitedRes.HasMore {
		t.Error("hasMore = false, want true when more events remain beyond limit")
	}
}

// TestAppendRunOutputAllocatesFromConversationSeqSpace proves the 2026-07-09
// data-loss fix: appendRunOutput must NOT use its caller-supplied per-run
// chunk seq (streamJSONOutput's own counter, starting at 1 for every run) as
// the conversation_events primary-key seq. A short reply's first chunks
// collided with the turn_started/status rows the ledger had already
// allocated at those same low seqs and were silently dropped via the old
// ON CONFLICT(conversation_id, seq) DO NOTHING. This test starts a
// conversation already at last_seq 2 (turn_started + a first output chunk),
// then appends a run whose OWN chunk seq restarts at 1 and 2, and asserts
// both chunks persist at freshly allocated conversation seqs 3 and 4.
func TestAppendRunOutputAllocatesFromConversationSeqSpace(t *testing.T) {
	s := openTestConversationStore(t)

	res, err := s.beginTurn(conversationAppendRequest{
		ClientTurnID: "device-1:1",
		Agent:        "claudeCode",
		Prompt:       "first prompt",
	}, "/proj", "run_1")
	if err != nil {
		t.Fatalf("beginTurn: %v", err)
	}
	// Advances the conversation to last_seq 2 (turn_started=1, this
	// output=2), mirroring the state a conversation is already in by the
	// time a SECOND turn's run starts streaming its own chunk 1.
	if err := s.appendRunOutput("run_1", "stdout", "run_1 chunk", 1); err != nil {
		t.Fatalf("appendRunOutput run_1: %v", err)
	}

	followUp, err := s.beginTurn(conversationAppendRequest{
		ConversationID: res.ConversationID,
		BaseSeq:        2,
		ClientTurnID:   "device-1:2",
		Agent:          "claudeCode",
		Prompt:         "second prompt",
	}, "/proj", "run_2")
	if err != nil {
		t.Fatalf("beginTurn (follow-up): %v", err)
	}
	if followUp.RunID != "run_2" {
		t.Fatalf("follow-up runID = %q, want run_2", followUp.RunID)
	}

	// run_2's OWN chunk sequence restarts at 1, exactly like conv_e87ef148's
	// "pong" reply did live: chunk seq 1 and 2 land on top of conversation
	// seqs already spent by turn_started/status events.
	if err := s.appendRunOutput("run_2", "stdout", "run_2 chunk-a", 1); err != nil {
		t.Fatalf("appendRunOutput run_2 chunk-a: %v", err)
	}
	if err := s.appendRunOutput("run_2", "stdout", "run_2 chunk-b", 2); err != nil {
		t.Fatalf("appendRunOutput run_2 chunk-b: %v", err)
	}

	fetchRes, err := s.fetch(res.ConversationID, 0, 500)
	if err != nil {
		t.Fatalf("fetch: %v", err)
	}
	// turn_started(1), run_1 output(2), turn_started(3), run_2 chunk-a(4), run_2 chunk-b(5).
	if len(fetchRes.Events) != 5 {
		t.Fatalf("events = %d, want 5: %+v", len(fetchRes.Events), fetchRes.Events)
	}

	var run2Texts []string
	for i, ev := range fetchRes.Events {
		if i > 0 && ev.Seq <= fetchRes.Events[i-1].Seq {
			t.Fatalf("events not strictly increasing by seq: %+v", fetchRes.Events)
		}
		if ev.RunID == "run_2" && ev.Kind == "output" {
			run2Texts = append(run2Texts, ev.Text)
		}
	}
	if len(run2Texts) != 2 {
		t.Fatalf("run_2 output events = %d, want 2 (both chunks must survive, not just the last): %+v", len(run2Texts), fetchRes.Events)
	}
	if run2Texts[0] != "run_2 chunk-a" || run2Texts[1] != "run_2 chunk-b" {
		t.Fatalf("run_2 output texts = %v, want [run_2 chunk-a, run_2 chunk-b] in order", run2Texts)
	}

	lastSeq := fetchRes.Events[len(fetchRes.Events)-1].Seq
	if lastSeq != 5 {
		t.Fatalf("last event seq = %d, want 5", lastSeq)
	}
}

func TestBeginTurnIdempotentClientTurnID(t *testing.T) {
	s := openTestConversationStore(t)

	req := conversationAppendRequest{
		ClientTurnID: "device-1:1",
		Agent:        "claudeCode",
		Prompt:       "same prompt",
	}
	res1, err := s.beginTurn(req, "/proj", "run_1")
	if err != nil {
		t.Fatalf("beginTurn (first): %v", err)
	}

	// Simulate a client retry: same clientTurnId, a different runID this time
	// (the phone may regenerate a runID on retry, but the store must still
	// return the original turn/conversation/run rather than creating a duplicate).
	res2, err := s.beginTurn(req, "/proj", "run_2_should_be_ignored")
	if err != nil {
		t.Fatalf("beginTurn (retry): %v", err)
	}

	if res2.ConversationID != res1.ConversationID {
		t.Errorf("retry conversationID = %q, want %q", res2.ConversationID, res1.ConversationID)
	}
	if res2.TurnID != res1.TurnID {
		t.Errorf("retry turnID = %q, want %q", res2.TurnID, res1.TurnID)
	}
	if res2.RunID != res1.RunID {
		t.Errorf("retry runID = %q, want original %q (idempotent replay)", res2.RunID, res1.RunID)
	}

	listRes, err := s.list(50, "", false)
	if err != nil {
		t.Fatalf("list: %v", err)
	}
	if len(listRes.Conversations) != 1 {
		t.Fatalf("conversations = %d, want 1 (no duplicate created)", len(listRes.Conversations))
	}

	fetchRes, err := s.fetch(res1.ConversationID, 0, 500)
	if err != nil {
		t.Fatalf("fetch: %v", err)
	}
	if len(fetchRes.Turns) != 1 {
		t.Fatalf("turns = %d, want 1 (no duplicate turn from retried clientTurnId)", len(fetchRes.Turns))
	}
}

func TestBeginTurnConflictOnStaleBaseSeq(t *testing.T) {
	s := openTestConversationStore(t)

	first, err := s.beginTurn(conversationAppendRequest{
		ClientTurnID: "device-1:1",
		Agent:        "claudeCode",
		Prompt:       "first",
	}, "/proj", "run_1")
	if err != nil {
		t.Fatalf("beginTurn (first): %v", err)
	}
	if first.NextSeq != 1 {
		t.Fatalf("first.NextSeq = %d, want 1", first.NextSeq)
	}

	// A correct follow-up using the current baseSeq must succeed.
	second, err := s.beginTurn(conversationAppendRequest{
		ConversationID: first.ConversationID,
		BaseSeq:        first.NextSeq,
		ClientTurnID:   "device-1:2",
		Prompt:         "second",
	}, "/proj", "run_2")
	if err != nil {
		t.Fatalf("beginTurn (second, valid baseSeq): %v", err)
	}
	if second.Status != "started" {
		t.Fatalf("second.Status = %q, want started", second.Status)
	}
	if second.NextSeq != 2 {
		t.Fatalf("second.NextSeq = %d, want 2", second.NextSeq)
	}

	// A third append using the now-stale baseSeq (1, but the conversation is at 2)
	// must be rejected as a conflict, not silently applied.
	third, err := s.beginTurn(conversationAppendRequest{
		ConversationID: first.ConversationID,
		BaseSeq:        first.NextSeq, // stale: conversation has moved to seq 2
		ClientTurnID:   "device-2:1",
		Prompt:         "concurrent conflicting write",
	}, "/proj", "run_3")
	if err != nil {
		t.Fatalf("beginTurn (third, stale baseSeq): %v", err)
	}
	if third.Status != "conflict" {
		t.Fatalf("third.Status = %q, want conflict", third.Status)
	}
	if third.NextSeq != 2 {
		t.Errorf("third.NextSeq = %d, want 2 (current conversation seq)", third.NextSeq)
	}

	// The rejected append must not have created a turn or bumped the seq further.
	fetchRes, err := s.fetch(first.ConversationID, 0, 500)
	if err != nil {
		t.Fatalf("fetch: %v", err)
	}
	if len(fetchRes.Turns) != 2 {
		t.Fatalf("turns = %d, want 2 (conflicting append must not persist)", len(fetchRes.Turns))
	}
	if fetchRes.Conversation.LastSeq != 2 {
		t.Errorf("conversation.LastSeq = %d, want 2", fetchRes.Conversation.LastSeq)
	}
}

func TestBindVendorSession(t *testing.T) {
	s := openTestConversationStore(t)

	res, err := s.beginTurn(conversationAppendRequest{
		ClientTurnID: "device-1:1",
		Agent:        "claudeCode",
		Prompt:       "first",
	}, "/proj", "run_1")
	if err != nil {
		t.Fatalf("beginTurn: %v", err)
	}

	if err := s.bindVendorSession("run_1", "vendor-session-abc"); err != nil {
		t.Fatalf("bindVendorSession: %v", err)
	}

	fetchRes, err := s.fetch(res.ConversationID, 0, 500)
	if err != nil {
		t.Fatalf("fetch: %v", err)
	}
	if fetchRes.Turns[0].VendorSessionID != "vendor-session-abc" {
		t.Errorf("vendorSessionID = %q, want vendor-session-abc", fetchRes.Turns[0].VendorSessionID)
	}

	if err := s.bindVendorSession("no-such-run", "x"); err == nil {
		t.Error("expected error binding vendor session for unknown runID, got nil")
	}
}

func TestUpsertArtifact(t *testing.T) {
	s := openTestConversationStore(t)

	res, err := s.beginTurn(conversationAppendRequest{
		ClientTurnID: "device-1:1",
		Agent:        "claudeCode",
		Prompt:       "first",
	}, "/proj", "run_1")
	if err != nil {
		t.Fatalf("beginTurn: %v", err)
	}

	event := map[string]any{
		"id":             "artifact_1",
		"conversationId": res.ConversationID,
		"turnId":         res.TurnID,
		"runId":          "run_1",
		"kind":           "diff",
		"title":          "Fix auth redirect",
		"summary":        "Adjusted redirect URL",
		"payloadJson":    `{"path":"auth.go"}`,
		"status":         "ready",
	}
	if err := s.upsertArtifact(event); err != nil {
		t.Fatalf("upsertArtifact (create): %v", err)
	}

	// Upserting the same id again with an updated title must update, not duplicate.
	event["title"] = "Fix auth redirect (updated)"
	if err := s.upsertArtifact(event); err != nil {
		t.Fatalf("upsertArtifact (update): %v", err)
	}

	fetchRes, err := s.fetch(res.ConversationID, 0, 500)
	if err != nil {
		t.Fatalf("fetch: %v", err)
	}
	if len(fetchRes.Artifacts) != 1 {
		t.Fatalf("artifacts = %d, want 1 (upsert must not duplicate)", len(fetchRes.Artifacts))
	}
	if fetchRes.Artifacts[0].Title != "Fix auth redirect (updated)" {
		t.Errorf("title = %q, want updated title", fetchRes.Artifacts[0].Title)
	}
}

func TestListOrdersByLastActivityDescending(t *testing.T) {
	s := openTestConversationStore(t)

	older, err := s.beginTurn(conversationAppendRequest{
		ClientTurnID: "device-1:1",
		Agent:        "claudeCode",
		Prompt:       "older conversation",
	}, "/proj-a", "run_1")
	if err != nil {
		t.Fatalf("beginTurn (older): %v", err)
	}
	newer, err := s.beginTurn(conversationAppendRequest{
		ClientTurnID: "device-1:2",
		Agent:        "claudeCode",
		Prompt:       "newer conversation",
	}, "/proj-b", "run_2")
	if err != nil {
		t.Fatalf("beginTurn (newer): %v", err)
	}

	listRes, err := s.list(50, "", false)
	if err != nil {
		t.Fatalf("list: %v", err)
	}
	if len(listRes.Conversations) != 2 {
		t.Fatalf("conversations = %d, want 2", len(listRes.Conversations))
	}
	if listRes.Conversations[0].ID != newer.ConversationID {
		t.Errorf("most recent conversation first: got %q, want %q", listRes.Conversations[0].ID, newer.ConversationID)
	}
	if listRes.Conversations[1].ID != older.ConversationID {
		t.Errorf("older conversation second: got %q, want %q", listRes.Conversations[1].ID, older.ConversationID)
	}
}

// TestListCursorPaginationCoversEveryConversationExactlyOnce pages through
// list() one small page at a time via NextCursor (the (last_activity_at,
// rowid) keyset from decodeListCursor/encodeListCursor) and checks the union
// of every page is every conversation, in the same order a single
// limit=len(all) call would return, with no duplicates or gaps at page
// boundaries and no NextCursor once exhausted.
func TestListCursorPaginationCoversEveryConversationExactlyOnce(t *testing.T) {
	s := openTestConversationStore(t)

	const total = 5
	var created []string
	for i := 0; i < total; i++ {
		res, err := s.beginTurn(conversationAppendRequest{
			ClientTurnID: fmt.Sprintf("device-1:%d", i),
			Agent:        "claudeCode",
			Prompt:       fmt.Sprintf("conversation %d", i),
		}, fmt.Sprintf("/proj-%d", i), fmt.Sprintf("run_%d", i))
		if err != nil {
			t.Fatalf("beginTurn(%d): %v", i, err)
		}
		created = append(created, res.ConversationID)
	}

	full, err := s.list(total, "", false)
	if err != nil {
		t.Fatalf("list(full page): %v", err)
	}
	if len(full.Conversations) != total || full.NextCursor != "" {
		t.Fatalf("full page = %d conversations, nextCursor=%q; want %d and empty cursor", len(full.Conversations), full.NextCursor, total)
	}

	var paged []conversationSummary
	cursor := ""
	for page := 0; ; page++ {
		if page > total {
			t.Fatalf("pagination did not terminate after %d pages", page)
		}
		res, err := s.list(2, cursor, false)
		if err != nil {
			t.Fatalf("list(page %d): %v", page, err)
		}
		paged = append(paged, res.Conversations...)
		if res.NextCursor == "" {
			break
		}
		cursor = res.NextCursor
	}

	if len(paged) != total {
		t.Fatalf("paged through %d conversations, want %d", len(paged), total)
	}
	seen := map[string]bool{}
	for i, conv := range paged {
		if seen[conv.ID] {
			t.Fatalf("conversation %q returned more than once across pages", conv.ID)
		}
		seen[conv.ID] = true
		if conv.ID != full.Conversations[i].ID {
			t.Fatalf("paged order diverges from full-page order at index %d: paged=%q full=%q", i, conv.ID, full.Conversations[i].ID)
		}
	}
	for _, id := range created {
		if !seen[id] {
			t.Fatalf("conversation %q created but never seen across pages", id)
		}
	}
}

// TestSetArchived covers setArchived, added alongside the Task 2
// agent.conversations.archive RPC (Task 1's interface list did not include an
// archive method). It must: default-exclude archived conversations from
// list(), include them when includeArchived=true, bump last_seq, and
// unarchive cleanly.
func TestSetArchived(t *testing.T) {
	s := openTestConversationStore(t)

	res, err := s.beginTurn(conversationAppendRequest{
		ClientTurnID: "device-1:1",
		Agent:        "claudeCode",
		Prompt:       "first",
	}, "/proj", "run_1")
	if err != nil {
		t.Fatalf("beginTurn: %v", err)
	}

	newSeq, err := s.setArchived(res.ConversationID, true)
	if err != nil {
		t.Fatalf("setArchived(true): %v", err)
	}
	if newSeq != 2 {
		t.Fatalf("setArchived returned lastSeq = %d, want 2", newSeq)
	}

	activeOnly, err := s.list(50, "", false)
	if err != nil {
		t.Fatalf("list(includeArchived=false): %v", err)
	}
	if len(activeOnly.Conversations) != 0 {
		t.Fatalf("expected archived conversation excluded from default list, got %d", len(activeOnly.Conversations))
	}

	withArchived, err := s.list(50, "", true)
	if err != nil {
		t.Fatalf("list(includeArchived=true): %v", err)
	}
	if len(withArchived.Conversations) != 1 || withArchived.Conversations[0].ArchivedAt == "" {
		t.Fatalf("expected 1 conversation with archivedAt set, got %+v", withArchived.Conversations)
	}

	fetchRes, err := s.fetch(res.ConversationID, 0, 500)
	if err != nil {
		t.Fatalf("fetch: %v", err)
	}
	if fetchRes.Conversation.LastSeq != 2 {
		t.Errorf("conversation.LastSeq = %d, want 2 after archive", fetchRes.Conversation.LastSeq)
	}
	var sawArchivedEvent bool
	for _, e := range fetchRes.Events {
		if e.Kind == "archived" {
			sawArchivedEvent = true
		}
	}
	if !sawArchivedEvent {
		t.Errorf("expected an 'archived' event in the event log, got %+v", fetchRes.Events)
	}

	// Unarchive: bumps seq again, clears archivedAt.
	newSeq2, err := s.setArchived(res.ConversationID, false)
	if err != nil {
		t.Fatalf("setArchived(false): %v", err)
	}
	if newSeq2 != 3 {
		t.Fatalf("setArchived(false) returned lastSeq = %d, want 3", newSeq2)
	}
	afterUnarchive, err := s.list(50, "", false)
	if err != nil {
		t.Fatalf("list after unarchive: %v", err)
	}
	if len(afterUnarchive.Conversations) != 1 || afterUnarchive.Conversations[0].ArchivedAt != "" {
		t.Fatalf("expected unarchived conversation back in default list with empty archivedAt, got %+v", afterUnarchive.Conversations)
	}

	if _, err := s.setArchived("conv_does_not_exist", true); err == nil {
		t.Error("expected error archiving an unknown conversationId, got nil")
	}
}

func TestDaemonHostIDStableAcrossConversationsAndReopen(t *testing.T) {
	home := t.TempDir()
	s1, err := openConversationStore(home)
	if err != nil {
		t.Fatalf("openConversationStore: %v", err)
	}

	res1, err := s1.beginTurn(conversationAppendRequest{
		ClientTurnID: "device-1:1", Agent: "claudeCode", Prompt: "first",
	}, "/proj", "run_a")
	if err != nil {
		t.Fatalf("beginTurn first: %v", err)
	}
	res2, err := s1.beginTurn(conversationAppendRequest{
		ClientTurnID: "device-1:2", Agent: "claudeCode", Prompt: "second",
	}, "/proj", "run_b")
	if err != nil {
		t.Fatalf("beginTurn second: %v", err)
	}

	fetch1, err := s1.fetch(res1.ConversationID, 0, 100)
	if err != nil {
		t.Fatalf("fetch first: %v", err)
	}
	fetch2, err := s1.fetch(res2.ConversationID, 0, 100)
	if err != nil {
		t.Fatalf("fetch second: %v", err)
	}
	if fetch1.Conversation.HostID == "" {
		t.Fatal("expected host_id on first conversation")
	}
	if fetch1.Conversation.HostID != fetch2.Conversation.HostID {
		t.Fatalf("host_id mismatch: %q vs %q", fetch1.Conversation.HostID, fetch2.Conversation.HostID)
	}
	if fetch1.Conversation.HostID != s1.hostID {
		t.Fatalf("listed host_id %q != store hostID %q", fetch1.Conversation.HostID, s1.hostID)
	}

	if err := s1.close(); err != nil {
		t.Fatalf("close: %v", err)
	}
	s2, err := openConversationStore(home)
	if err != nil {
		t.Fatalf("reopen: %v", err)
	}
	defer s2.close()
	if s2.hostID != fetch1.Conversation.HostID {
		t.Fatalf("host_id after reopen = %q, want %q", s2.hostID, fetch1.Conversation.HostID)
	}
}
