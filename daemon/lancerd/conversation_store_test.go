package main

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"

	_ "modernc.org/sqlite"
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

// --- attachment metadata persistence (Task 1) -----------------------------

func sampleImageAttachment() conversationAttachmentReference {
	return conversationAttachmentReference{
		ID:              "a1",
		Name:            "photo.jpg",
		MimeType:        "image/jpeg",
		ByteCount:       310992,
		Kind:            "image",
		HostPath:        "/Users/me/.lancer/attachments/photo.jpg",
		PreviewCacheKey: "a1",
	}
}

func sampleFileAttachment() conversationAttachmentReference {
	return conversationAttachmentReference{
		ID:              "a2",
		Name:            "notes.txt",
		ByteCount:       42,
		Kind:            "file",
		HostPath:        "/Users/me/.lancer/attachments/notes.txt",
		PreviewCacheKey: "a2",
	}
}

func assertAttachmentEqual(t *testing.T, got, want conversationAttachmentReference) {
	t.Helper()
	if got.ID != want.ID {
		t.Errorf("id = %q, want %q", got.ID, want.ID)
	}
	if got.Name != want.Name {
		t.Errorf("name = %q, want %q", got.Name, want.Name)
	}
	if got.MimeType != want.MimeType {
		t.Errorf("mimeType = %q, want %q", got.MimeType, want.MimeType)
	}
	if got.ByteCount != want.ByteCount {
		t.Errorf("byteCount = %d, want %d", got.ByteCount, want.ByteCount)
	}
	if got.Kind != want.Kind {
		t.Errorf("kind = %q, want %q", got.Kind, want.Kind)
	}
	if got.HostPath != want.HostPath {
		t.Errorf("hostPath = %q, want %q", got.HostPath, want.HostPath)
	}
	if got.PreviewCacheKey != want.PreviewCacheKey {
		t.Errorf("previewCacheKey = %q, want %q", got.PreviewCacheKey, want.PreviewCacheKey)
	}
}

// TestConversationAttachmentAppendFetchReopenRoundTrip appends a turn with
// attachment metadata, reopens the SQLite store, fetches the turn, and
// compares every attachment field.
func TestConversationAttachmentAppendFetchReopenRoundTrip(t *testing.T) {
	home := t.TempDir()
	s1, err := openConversationStore(home)
	if err != nil {
		t.Fatalf("openConversationStore: %v", err)
	}

	want := []conversationAttachmentReference{sampleImageAttachment(), sampleFileAttachment()}
	res, err := s1.beginTurn(conversationAppendRequest{
		ClientTurnID: "device-1:att-1",
		Agent:        "claudeCode",
		Prompt:       "look at these",
		Attachments:  want,
	}, "/proj", "run_att_1")
	if err != nil {
		t.Fatalf("beginTurn: %v", err)
	}
	if err := s1.close(); err != nil {
		t.Fatalf("close: %v", err)
	}

	s2, err := openConversationStore(home)
	if err != nil {
		t.Fatalf("reopen: %v", err)
	}
	defer s2.close()

	fetchRes, err := s2.fetch(res.ConversationID, 0, 500)
	if err != nil {
		t.Fatalf("fetch after reopen: %v", err)
	}
	if len(fetchRes.Turns) != 1 {
		t.Fatalf("turns = %d, want 1", len(fetchRes.Turns))
	}
	got := fetchRes.Turns[0].Attachments
	if len(got) != len(want) {
		t.Fatalf("attachments = %d, want %d: %+v", len(got), len(want), got)
	}
	for i := range want {
		assertAttachmentEqual(t, got[i], want[i])
	}
}

// TestConversationAttachmentNilOrMissingJSONYieldsEmpty proves turns without
// attachment metadata (nil slice on append, and JSON without an attachments
// key) decode as an empty slice — not nil-panicking and not fabricating refs.
func TestConversationAttachmentNilOrMissingJSONYieldsEmpty(t *testing.T) {
	s := openTestConversationStore(t)

	res, err := s.beginTurn(conversationAppendRequest{
		ClientTurnID: "device-1:no-att",
		Agent:        "claudeCode",
		Prompt:       "plain prompt",
		// Attachments intentionally omitted (nil).
	}, "/proj", "run_no_att")
	if err != nil {
		t.Fatalf("beginTurn: %v", err)
	}

	fetchRes, err := s.fetch(res.ConversationID, 0, 500)
	if err != nil {
		t.Fatalf("fetch: %v", err)
	}
	if len(fetchRes.Turns) != 1 {
		t.Fatalf("turns = %d, want 1", len(fetchRes.Turns))
	}
	if fetchRes.Turns[0].Attachments == nil {
		t.Fatal("Attachments must be non-nil empty slice after load, got nil")
	}
	if len(fetchRes.Turns[0].Attachments) != 0 {
		t.Fatalf("Attachments = %+v, want empty", fetchRes.Turns[0].Attachments)
	}

	// Wire decode: missing attachments key → empty.
	raw := []byte(`{"id":"t1","conversationId":"c1","ordinal":1,"clientTurnId":"ct1","prompt":"hello","runId":"r1","provider":"claudeCode","status":"completed","startedAt":"2026-07-14T00:00:00Z"}`)
	var turn conversationTurn
	if err := json.Unmarshal(raw, &turn); err != nil {
		t.Fatalf("unmarshal turn without attachments: %v", err)
	}
	if len(turn.Attachments) != 0 {
		t.Fatalf("decoded Attachments = %+v, want empty", turn.Attachments)
	}
}

// TestConversationAttachmentFollowUpPersists proves follow-up turns also
// persist attachment metadata (not only the first-turn insert path).
func TestConversationAttachmentFollowUpPersists(t *testing.T) {
	s := openTestConversationStore(t)

	first, err := s.beginTurn(conversationAppendRequest{
		ClientTurnID: "device-1:fu-1",
		Agent:        "claudeCode",
		Prompt:       "first",
	}, "/proj", "run_fu_1")
	if err != nil {
		t.Fatalf("beginTurn first: %v", err)
	}

	want := []conversationAttachmentReference{sampleImageAttachment()}
	second, err := s.beginTurn(conversationAppendRequest{
		ConversationID: first.ConversationID,
		BaseSeq:        first.NextSeq,
		ClientTurnID:   "device-1:fu-2",
		Prompt:         "follow-up with image",
		Attachments:    want,
	}, "/proj", "run_fu_2")
	if err != nil {
		t.Fatalf("beginTurn follow-up: %v", err)
	}
	if second.Status != "started" {
		t.Fatalf("status = %q, want started", second.Status)
	}

	fetchRes, err := s.fetch(first.ConversationID, 0, 500)
	if err != nil {
		t.Fatalf("fetch: %v", err)
	}
	if len(fetchRes.Turns) != 2 {
		t.Fatalf("turns = %d, want 2", len(fetchRes.Turns))
	}
	if len(fetchRes.Turns[0].Attachments) != 0 {
		t.Errorf("first turn attachments = %+v, want empty", fetchRes.Turns[0].Attachments)
	}
	if len(fetchRes.Turns[1].Attachments) != 1 {
		t.Fatalf("second turn attachments = %d, want 1", len(fetchRes.Turns[1].Attachments))
	}
	assertAttachmentEqual(t, fetchRes.Turns[1].Attachments[0], want[0])
}

// TestConversationAttachmentObservedImportDefaultsEmpty proves observed-import
// inserts remain compatible and surface empty attachments (never null).
func TestConversationAttachmentObservedImportDefaultsEmpty(t *testing.T) {
	s := openTestConversationStore(t)

	res, err := s.attachObservedSession("claudeCode", "vendor-att-obs", "/proj", "", []SessionMessage{
		{Role: "user", Text: "imported prompt"},
		{Role: "assistant", Text: "imported reply"},
	})
	if err != nil {
		t.Fatalf("attachObservedSession: %v", err)
	}

	fetchRes, err := s.fetch(res.ConversationID, 0, 500)
	if err != nil {
		t.Fatalf("fetch: %v", err)
	}
	if len(fetchRes.Turns) == 0 {
		t.Fatal("expected at least one imported turn")
	}
	for i, turn := range fetchRes.Turns {
		if turn.Attachments == nil {
			t.Fatalf("turn[%d].Attachments is nil, want empty slice", i)
		}
		if len(turn.Attachments) != 0 {
			t.Fatalf("turn[%d].Attachments = %+v, want empty", i, turn.Attachments)
		}
	}
}

// TestConversationAttachmentMalformedRejectedWithoutPartialTurn rejects
// bounded structural violations and leaves no conversation/turn row behind.
func TestConversationAttachmentMalformedRejectedWithoutPartialTurn(t *testing.T) {
	cases := []struct {
		name string
		att  conversationAttachmentReference
	}{
		{name: "empty id", att: conversationAttachmentReference{
			ID: "", Name: "a.jpg", ByteCount: 1, Kind: "image",
			HostPath: "/tmp/a.jpg", PreviewCacheKey: "k",
		}},
		{name: "empty name", att: conversationAttachmentReference{
			ID: "id", Name: "", ByteCount: 1, Kind: "image",
			HostPath: "/tmp/a.jpg", PreviewCacheKey: "k",
		}},
		{name: "empty hostPath", att: conversationAttachmentReference{
			ID: "id", Name: "a.jpg", ByteCount: 1, Kind: "image",
			HostPath: "", PreviewCacheKey: "k",
		}},
		{name: "negative byteCount", att: conversationAttachmentReference{
			ID: "id", Name: "a.jpg", ByteCount: -1, Kind: "image",
			HostPath: "/tmp/a.jpg", PreviewCacheKey: "k",
		}},
		{name: "unknown kind", att: conversationAttachmentReference{
			ID: "id", Name: "a.jpg", ByteCount: 1, Kind: "video",
			HostPath: "/tmp/a.jpg", PreviewCacheKey: "k",
		}},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			s := openTestConversationStore(t)
			_, err := s.beginTurn(conversationAppendRequest{
				ClientTurnID: "device-1:bad-" + tc.name,
				Agent:        "claudeCode",
				Prompt:       "should not persist",
				Attachments:  []conversationAttachmentReference{tc.att},
			}, "/proj", "run_bad_"+tc.name)
			if err == nil {
				t.Fatal("expected validation error, got nil")
			}

			listRes, err := s.list(50, "", false)
			if err != nil {
				t.Fatalf("list: %v", err)
			}
			if len(listRes.Conversations) != 0 {
				t.Fatalf("partial conversation persisted after rejection: %+v", listRes.Conversations)
			}
		})
	}
}

// TestConversationAttachmentMigratesPreColumnDB opens a ledger created before
// attachments_json existed, runs migrate via openConversationStore, and proves
// legacy turns load with empty attachments while new turns can persist refs.
func TestConversationAttachmentMigratesPreColumnDB(t *testing.T) {
	home := t.TempDir()
	dir := filepath.Join(home, ".lancer")
	if err := os.MkdirAll(dir, 0700); err != nil {
		t.Fatalf("mkdir: %v", err)
	}
	dbPath := filepath.Join(dir, conversationsDBFileName)

	db, err := sql.Open("sqlite", dbPath+"?_pragma=foreign_keys(1)")
	if err != nil {
		t.Fatalf("open raw sqlite: %v", err)
	}
	stmts := []string{
		`CREATE TABLE conversations (
			id TEXT PRIMARY KEY,
			title TEXT NOT NULL,
			provider TEXT NOT NULL,
			agent_id TEXT NOT NULL,
			host_id TEXT,
			host_name TEXT NOT NULL,
			cwd TEXT NOT NULL,
			model TEXT,
			budget_usd REAL,
			state TEXT NOT NULL,
			source TEXT NOT NULL,
			created_at TEXT NOT NULL,
			updated_at TEXT NOT NULL,
			last_activity_at TEXT NOT NULL,
			last_seq INTEGER NOT NULL DEFAULT 0,
			archived_at TEXT,
			deleted_at TEXT
		)`,
		`CREATE TABLE conversation_turns (
			id TEXT PRIMARY KEY,
			conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
			ordinal INTEGER NOT NULL,
			client_turn_id TEXT NOT NULL,
			prompt TEXT NOT NULL,
			run_id TEXT NOT NULL,
			provider TEXT NOT NULL,
			vendor_session_id TEXT,
			status TEXT NOT NULL,
			started_at TEXT NOT NULL,
			completed_at TEXT,
			error_message TEXT,
			baseline_start_oid TEXT,
			baseline_end_oid TEXT,
			UNIQUE(conversation_id, ordinal),
			UNIQUE(conversation_id, client_turn_id),
			UNIQUE(run_id)
		)`,
		`CREATE TABLE conversation_events (
			conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
			seq INTEGER NOT NULL,
			turn_id TEXT,
			run_id TEXT,
			kind TEXT NOT NULL,
			role TEXT,
			stream TEXT,
			text TEXT,
			payload_json TEXT,
			created_at TEXT NOT NULL,
			PRIMARY KEY(conversation_id, seq)
		)`,
		`CREATE TABLE conversation_artifacts (
			id TEXT PRIMARY KEY,
			conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
			turn_id TEXT,
			run_id TEXT NOT NULL,
			kind TEXT NOT NULL,
			title TEXT NOT NULL,
			summary TEXT,
			payload_json TEXT NOT NULL,
			status TEXT NOT NULL,
			created_at TEXT NOT NULL,
			updated_at TEXT NOT NULL
		)`,
		`INSERT INTO conversations
			(id, title, provider, agent_id, host_name, cwd, state, source,
			 created_at, updated_at, last_activity_at, last_seq)
			VALUES ('conv_legacy', 'legacy', 'claudeCode', 'claudeCode', 'host',
			 '/proj', 'active', 'phone', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z',
			 '2026-01-01T00:00:00Z', 1)`,
		`INSERT INTO conversation_turns
			(id, conversation_id, ordinal, client_turn_id, prompt, run_id, provider, status, started_at)
			VALUES ('turn_legacy', 'conv_legacy', 1, 'legacy-ct', 'old prompt', 'run_legacy',
			 'claudeCode', 'exited', '2026-01-01T00:00:00Z')`,
	}
	for _, stmt := range stmts {
		if _, err := db.Exec(stmt); err != nil {
			_ = db.Close()
			t.Fatalf("seed pre-column schema: %v\nstmt: %s", err, stmt)
		}
	}
	// Confirm the column is absent before migrate.
	var colCount int
	if err := db.QueryRow(`SELECT COUNT(*) FROM pragma_table_info('conversation_turns') WHERE name = 'attachments_json'`).Scan(&colCount); err != nil {
		_ = db.Close()
		t.Fatalf("pragma_table_info: %v", err)
	}
	if colCount != 0 {
		_ = db.Close()
		t.Fatalf("precondition: attachments_json already present")
	}
	if err := db.Close(); err != nil {
		t.Fatalf("close seed db: %v", err)
	}

	s, err := openConversationStore(home)
	if err != nil {
		t.Fatalf("openConversationStore (migrate): %v", err)
	}
	defer s.close()

	var migratedCount int
	if err := s.db.QueryRow(`SELECT COUNT(*) FROM pragma_table_info('conversation_turns') WHERE name = 'attachments_json'`).Scan(&migratedCount); err != nil {
		t.Fatalf("pragma after migrate: %v", err)
	}
	if migratedCount != 1 {
		t.Fatalf("attachments_json column count = %d, want 1 after migrate", migratedCount)
	}

	fetchRes, err := s.fetch("conv_legacy", 0, 500)
	if err != nil {
		t.Fatalf("fetch legacy: %v", err)
	}
	if len(fetchRes.Turns) != 1 {
		t.Fatalf("legacy turns = %d, want 1", len(fetchRes.Turns))
	}
	if len(fetchRes.Turns[0].Attachments) != 0 {
		t.Fatalf("legacy Attachments = %+v, want empty", fetchRes.Turns[0].Attachments)
	}

	want := []conversationAttachmentReference{sampleFileAttachment()}
	res, err := s.beginTurn(conversationAppendRequest{
		ConversationID: "conv_legacy",
		BaseSeq:        1,
		ClientTurnID:   "device-1:post-migrate",
		Prompt:         "new with file",
		Attachments:    want,
	}, "/proj", "run_post_migrate")
	if err != nil {
		t.Fatalf("beginTurn after migrate: %v", err)
	}
	if res.Status != "started" {
		t.Fatalf("status = %q, want started", res.Status)
	}

	fetch2, err := s.fetch("conv_legacy", 0, 500)
	if err != nil {
		t.Fatalf("fetch after append: %v", err)
	}
	if len(fetch2.Turns) != 2 {
		t.Fatalf("turns = %d, want 2", len(fetch2.Turns))
	}
	if len(fetch2.Turns[1].Attachments) != 1 {
		t.Fatalf("new turn attachments = %d, want 1", len(fetch2.Turns[1].Attachments))
	}
	assertAttachmentEqual(t, fetch2.Turns[1].Attachments[0], want[0])
}

// TestConversationAttachmentJSONWireShape locks the camelCase wire keys and
// omitempty behavior for append requests and turn envelopes.
func TestConversationAttachmentJSONWireShape(t *testing.T) {
	att := sampleImageAttachment()
	raw, err := json.Marshal(att)
	if err != nil {
		t.Fatalf("marshal attachment: %v", err)
	}
	var asMap map[string]any
	if err := json.Unmarshal(raw, &asMap); err != nil {
		t.Fatalf("unmarshal map: %v", err)
	}
	for _, key := range []string{"id", "name", "mimeType", "byteCount", "kind", "hostPath", "previewCacheKey"} {
		if _, ok := asMap[key]; !ok {
			t.Errorf("missing wire key %q in %s", key, raw)
		}
	}

	reqRaw, err := json.Marshal(conversationAppendRequest{
		ClientTurnID: "ct",
		Prompt:       "p",
		Attachments:  []conversationAttachmentReference{att},
	})
	if err != nil {
		t.Fatalf("marshal append request: %v", err)
	}
	if !strings.Contains(string(reqRaw), `"attachments"`) {
		t.Fatalf("append request JSON missing attachments: %s", reqRaw)
	}

	var decodedReq conversationAppendRequest
	if err := json.Unmarshal(reqRaw, &decodedReq); err != nil {
		t.Fatalf("unmarshal append request: %v", err)
	}
	if len(decodedReq.Attachments) != 1 {
		t.Fatalf("decoded attachments = %d, want 1", len(decodedReq.Attachments))
	}
	assertAttachmentEqual(t, decodedReq.Attachments[0], att)

	turnRaw, err := json.Marshal(conversationTurn{
		ID: "t1", ConversationID: "c1", Ordinal: 1, ClientTurnID: "ct",
		Prompt: "p", RunID: "r1", Provider: "claudeCode", Status: "completed",
		StartedAt: "2026-07-14T00:00:00Z", Attachments: []conversationAttachmentReference{att},
	})
	if err != nil {
		t.Fatalf("marshal turn: %v", err)
	}
	var decodedTurn conversationTurn
	if err := json.Unmarshal(turnRaw, &decodedTurn); err != nil {
		t.Fatalf("unmarshal turn: %v", err)
	}
	if len(decodedTurn.Attachments) != 1 {
		t.Fatalf("decoded turn attachments = %d, want 1", len(decodedTurn.Attachments))
	}
	assertAttachmentEqual(t, decodedTurn.Attachments[0], att)
}

func bytesOfLen(n int) string {
	if n <= 0 {
		return ""
	}
	return strings.Repeat("a", n)
}

func validAttachmentForBounds() conversationAttachmentReference {
	return conversationAttachmentReference{
		ID:              "id-ok",
		Name:            "file.bin",
		MimeType:        "application/octet-stream",
		ByteCount:       1,
		Kind:            "file",
		HostPath:        "/tmp/file.bin",
		PreviewCacheKey: "cache-key",
	}
}

// TestConversationAttachmentIdempotentReplayMalformedMetadata proves clientTurnId
// first-write-wins: a retry with invalid attachment metadata must return the
// original turn without error and must not create a duplicate row.
func TestConversationAttachmentIdempotentReplayMalformedMetadata(t *testing.T) {
	s := openTestConversationStore(t)
	want := []conversationAttachmentReference{sampleImageAttachment()}
	clientTurnID := "device-1:idempotent-malformed"

	first, err := s.beginTurn(conversationAppendRequest{
		ClientTurnID: clientTurnID,
		Agent:        "claudeCode",
		Prompt:       "with image",
		Attachments:  want,
	}, "/proj", "run_idem_1")
	if err != nil {
		t.Fatalf("beginTurn (first): %v", err)
	}

	replay, err := s.beginTurn(conversationAppendRequest{
		ClientTurnID: clientTurnID,
		Agent:        "claudeCode",
		Prompt:       "with image",
		Attachments: []conversationAttachmentReference{{
			ID: "", Name: "bad.jpg", ByteCount: 1, Kind: "image",
			HostPath: "/tmp/bad.jpg", PreviewCacheKey: "bad",
		}},
	}, "/proj", "run_idem_2_should_be_ignored")
	if err != nil {
		t.Fatalf("beginTurn (malformed replay): %v", err)
	}
	if replay.TurnID != first.TurnID || replay.RunID != first.RunID {
		t.Fatalf("replay = %+v, want same turn/run as first %+v", replay, first)
	}

	fetchRes, err := s.fetch(first.ConversationID, 0, 500)
	if err != nil {
		t.Fatalf("fetch: %v", err)
	}
	if len(fetchRes.Turns) != 1 {
		t.Fatalf("turns = %d, want 1 (no duplicate from replay)", len(fetchRes.Turns))
	}
	got := fetchRes.Turns[0].Attachments
	if len(got) != 1 {
		t.Fatalf("attachments = %d, want 1", len(got))
	}
	assertAttachmentEqual(t, got[0], want[0])
}

// TestConversationAttachmentIdempotentReplayDifferentMetadata proves a retry
// with different but valid attachment metadata still returns the first-write
// persisted attachments unchanged.
func TestConversationAttachmentIdempotentReplayDifferentMetadata(t *testing.T) {
	s := openTestConversationStore(t)
	want := []conversationAttachmentReference{sampleImageAttachment()}
	clientTurnID := "device-1:idempotent-diff"

	first, err := s.beginTurn(conversationAppendRequest{
		ClientTurnID: clientTurnID,
		Agent:        "claudeCode",
		Prompt:       "first write",
		Attachments:  want,
	}, "/proj", "run_diff_1")
	if err != nil {
		t.Fatalf("beginTurn (first): %v", err)
	}

	alt := []conversationAttachmentReference{sampleFileAttachment()}
	replay, err := s.beginTurn(conversationAppendRequest{
		ClientTurnID: clientTurnID,
		Agent:        "claudeCode",
		Prompt:       "different metadata retry",
		Attachments:  alt,
	}, "/proj", "run_diff_2_should_be_ignored")
	if err != nil {
		t.Fatalf("beginTurn (different replay): %v", err)
	}
	if replay.TurnID != first.TurnID || replay.RunID != first.RunID {
		t.Fatalf("replay = %+v, want same turn/run as first %+v", replay, first)
	}

	fetchRes, err := s.fetch(first.ConversationID, 0, 500)
	if err != nil {
		t.Fatalf("fetch: %v", err)
	}
	if len(fetchRes.Turns) != 1 {
		t.Fatalf("turns = %d, want 1", len(fetchRes.Turns))
	}
	got := fetchRes.Turns[0].Attachments
	if len(got) != 1 {
		t.Fatalf("attachments = %d, want 1 (original persisted)", len(got))
	}
	assertAttachmentEqual(t, got[0], want[0])
}

// TestConversationAttachmentBoundsAcceptsAtLimitAndRejectsOver proves storage-layer
// metadata bounds aligned with upload constants and named string limits.
func TestConversationAttachmentBoundsAcceptsAtLimitAndRejectsOver(t *testing.T) {
	atLimit := validAttachmentForBounds()
	atLimit.ID = bytesOfLen(attachmentMetaMaxIDLen)
	atLimit.Name = bytesOfLen(attachmentMetaMaxNameLen)
	atLimit.MimeType = bytesOfLen(attachmentMetaMaxMimeTypeLen)
	atLimit.HostPath = "/" + bytesOfLen(attachmentMetaMaxHostPathLen-1)
	atLimit.PreviewCacheKey = bytesOfLen(attachmentMetaMaxPreviewCacheKeyLen)
	atLimit.ByteCount = attachmentMaxBytes

	t.Run("at limit accepted", func(t *testing.T) {
		s := openTestConversationStore(t)
		_, err := s.beginTurn(conversationAppendRequest{
			ClientTurnID: "device-1:bound-ok",
			Agent:        "claudeCode",
			Prompt:       "max bounds",
			Attachments:  []conversationAttachmentReference{atLimit},
		}, "/proj", "run_bound_ok")
		if err != nil {
			t.Fatalf("beginTurn at limit: %v", err)
		}
	})

	overCases := []struct {
		name string
		mut  func(*conversationAttachmentReference)
	}{
		{name: "too many attachments", mut: func(_ *conversationAttachmentReference) {}},
		{name: "byteCount over max", mut: func(a *conversationAttachmentReference) {
			a.ByteCount = attachmentMaxBytes + 1
		}},
		{name: "id over max", mut: func(a *conversationAttachmentReference) {
			a.ID = bytesOfLen(attachmentMetaMaxIDLen + 1)
		}},
		{name: "name over max", mut: func(a *conversationAttachmentReference) {
			a.Name = bytesOfLen(attachmentMetaMaxNameLen + 1)
		}},
		{name: "mimeType over max", mut: func(a *conversationAttachmentReference) {
			a.MimeType = bytesOfLen(attachmentMetaMaxMimeTypeLen + 1)
		}},
		{name: "hostPath over max", mut: func(a *conversationAttachmentReference) {
			a.HostPath = "/" + bytesOfLen(attachmentMetaMaxHostPathLen)
		}},
		{name: "previewCacheKey over max", mut: func(a *conversationAttachmentReference) {
			a.PreviewCacheKey = bytesOfLen(attachmentMetaMaxPreviewCacheKeyLen + 1)
		}},
		{name: "empty previewCacheKey", mut: func(a *conversationAttachmentReference) {
			a.PreviewCacheKey = ""
		}},
		{name: "whitespace previewCacheKey", mut: func(a *conversationAttachmentReference) {
			a.PreviewCacheKey = "   "
		}},
	}

	for _, tc := range overCases {
		t.Run(tc.name, func(t *testing.T) {
			s := openTestConversationStore(t)
			var atts []conversationAttachmentReference
			if tc.name == "too many attachments" {
				for i := 0; i < attachmentMaxFiles+1; i++ {
					a := validAttachmentForBounds()
					a.ID = fmt.Sprintf("att-%d", i)
					a.PreviewCacheKey = fmt.Sprintf("key-%d", i)
					atts = append(atts, a)
				}
			} else {
				a := validAttachmentForBounds()
				tc.mut(&a)
				atts = []conversationAttachmentReference{a}
			}
			_, err := s.beginTurn(conversationAppendRequest{
				ClientTurnID: "device-1:bound-bad-" + tc.name,
				Agent:        "claudeCode",
				Prompt:       "should not persist",
				Attachments:  atts,
			}, "/proj", "run_bound_bad")
			if err == nil {
				t.Fatal("expected validation error, got nil")
			}
			listRes, err := s.list(50, "", false)
			if err != nil {
				t.Fatalf("list: %v", err)
			}
			if len(listRes.Conversations) != 0 {
				t.Fatalf("partial conversation persisted: %+v", listRes.Conversations)
			}
		})
	}

	t.Run("max file count accepted", func(t *testing.T) {
		s := openTestConversationStore(t)
		var atts []conversationAttachmentReference
		for i := 0; i < attachmentMaxFiles; i++ {
			a := validAttachmentForBounds()
			a.ID = fmt.Sprintf("att-%d", i)
			a.PreviewCacheKey = fmt.Sprintf("key-%d", i)
			atts = append(atts, a)
		}
		_, err := s.beginTurn(conversationAppendRequest{
			ClientTurnID: "device-1:max-files-ok",
			Agent:        "claudeCode",
			Prompt:       "max files",
			Attachments:  atts,
		}, "/proj", "run_max_files")
		if err != nil {
			t.Fatalf("beginTurn max files: %v", err)
		}
	})
}

// seedTurnAttachmentsJSON overwrites attachments_json on an existing turn for read-path tests.
func seedTurnAttachmentsJSON(t *testing.T, s *conversationStore, turnID, raw string) {
	t.Helper()
	if _, err := s.db.Exec(`UPDATE conversation_turns SET attachments_json = ? WHERE id = ?`, raw, turnID); err != nil {
		t.Fatalf("seed attachments_json: %v", err)
	}
}

// TestConversationAttachmentFetchRejectsCorruptJSON fails fetch on syntactically
// invalid attachments_json without leaking host paths from the payload.
func TestConversationAttachmentFetchRejectsCorruptJSON(t *testing.T) {
	s := openTestConversationStore(t)
	secretPath := "/Users/secret/.lancer/attachments/leaked.jpg"
	res, err := s.beginTurn(conversationAppendRequest{
		ClientTurnID: "device-1:corrupt-json",
		Agent:        "claudeCode",
		Prompt:       "seed turn",
	}, "/proj", "run_corrupt")
	if err != nil {
		t.Fatalf("beginTurn: %v", err)
	}
	seedTurnAttachmentsJSON(t, s, res.TurnID, `{"id":"x","hostPath":"`+secretPath+`" not-json`)

	_, err = s.fetch(res.ConversationID, 0, 500)
	if err == nil {
		t.Fatal("expected fetch error for corrupt attachments_json, got nil")
	}
	if strings.Contains(err.Error(), secretPath) {
		t.Fatalf("fetch error leaked host path: %v", err)
	}
}

// TestConversationAttachmentFetchRejectsSemanticallyInvalidJSON fails fetch when
// decoded JSON violates attachment invariants, with generic errors only.
func TestConversationAttachmentFetchRejectsSemanticallyInvalidJSON(t *testing.T) {
	s := openTestConversationStore(t)
	secretPath := "/Users/secret/.lancer/attachments/leaked.bin"
	res, err := s.beginTurn(conversationAppendRequest{
		ClientTurnID: "device-1:semantic-bad",
		Agent:        "claudeCode",
		Prompt:       "seed turn",
	}, "/proj", "run_semantic")
	if err != nil {
		t.Fatalf("beginTurn: %v", err)
	}
	payload, err := json.Marshal([]conversationAttachmentReference{{
		ID: "x", Name: "y", ByteCount: 1, Kind: "video",
		HostPath: secretPath, PreviewCacheKey: "k",
	}})
	if err != nil {
		t.Fatalf("marshal seed payload: %v", err)
	}
	seedTurnAttachmentsJSON(t, s, res.TurnID, string(payload))

	_, err = s.fetch(res.ConversationID, 0, 500)
	if err == nil {
		t.Fatal("expected fetch error for semantically invalid attachments_json, got nil")
	}
	if strings.Contains(err.Error(), secretPath) {
		t.Fatalf("fetch error leaked host path: %v", err)
	}
}

// TestConversationAttachmentFetchNullEmptyJSONYieldsEmpty proves missing, null,
// and empty attachments_json still decode as a non-nil empty slice on fetch.
func TestConversationAttachmentFetchNullEmptyJSONYieldsEmpty(t *testing.T) {
	cases := []struct {
		name string
		raw  string
	}{
		{name: "empty string", raw: ""},
		{name: "whitespace", raw: "  "},
		{name: "json null", raw: "null"},
		{name: "empty array", raw: "[]"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			s := openTestConversationStore(t)
			res, err := s.beginTurn(conversationAppendRequest{
				ClientTurnID: "device-1:null-" + tc.name,
				Agent:        "claudeCode",
				Prompt:       "seed",
			}, "/proj", "run_"+tc.name)
			if err != nil {
				t.Fatalf("beginTurn: %v", err)
			}
			seedTurnAttachmentsJSON(t, s, res.TurnID, tc.raw)

			fetchRes, err := s.fetch(res.ConversationID, 0, 500)
			if err != nil {
				t.Fatalf("fetch: %v", err)
			}
			if fetchRes.Turns[0].Attachments == nil {
				t.Fatal("Attachments is nil, want non-nil empty slice")
			}
			if len(fetchRes.Turns[0].Attachments) != 0 {
				t.Fatalf("Attachments = %+v, want empty", fetchRes.Turns[0].Attachments)
			}
		})
	}
}
