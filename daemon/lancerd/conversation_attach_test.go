package main

import (
	"encoding/json"
	"strings"
	"testing"
)

// conversation_attach_test.go covers Task 9 of the cross-device sync build
// handoff: conversationStore.attachObservedSession, the create-from-import
// path that turns an already-observed CLI session's transcript into ledger
// turns (segmented at each real user prompt). Exercised directly against the
// store (not through the RPC layer) so it doesn't depend on a real on-disk
// ~/.claude/projects transcript — see conversation_rpc_test.go's
// TestConversationsAttachObservedSessionUnknownSessionErrorsIdentically for
// the RPC-layer error-shape coverage.

func newObservedTestStore(t *testing.T) *conversationStore {
	t.Helper()
	s, err := openConversationStore(t.TempDir())
	if err != nil {
		t.Fatalf("openConversationStore: %v", err)
	}
	t.Cleanup(func() { _ = s.close() })
	return s
}

func TestAttachObservedSessionImportsMessagesAsOneCompletedTurn(t *testing.T) {
	s := newObservedTestStore(t)

	messages := []SessionMessage{
		{Role: "user", Text: "fix the flaky test"},
		{Role: "assistant", Text: "Looking into it now."},
		{Role: "toolCall", Text: "Bash: go test ./...", ToolName: "Bash"},
		{Role: "toolResult", Text: "PASS"},
		{Role: "assistant", Text: "Fixed — the test now passes."},
	}

	res, err := s.attachObservedSession("claudeCode", "vendor-session-1", "/Users/roshan/project", "", messages)
	if err != nil {
		t.Fatalf("attachObservedSession: %v", err)
	}
	if res.AlreadyAttached {
		t.Fatal("expected AlreadyAttached=false on first attach")
	}
	// User prompt becomes the turn prompt, not an output event.
	wantEvents := len(messages) - 1
	if res.ImportedEvents != wantEvents {
		t.Fatalf("ImportedEvents = %d, want %d", res.ImportedEvents, wantEvents)
	}
	if res.LastSeq != int64(wantEvents) {
		t.Fatalf("LastSeq = %d, want %d", res.LastSeq, wantEvents)
	}

	fetched, err := s.fetch(res.ConversationID, 0, 100)
	if err != nil {
		t.Fatalf("fetch: %v", err)
	}
	if fetched.Conversation.Source != "observedImport" {
		t.Fatalf("Conversation.Source = %q, want observedImport", fetched.Conversation.Source)
	}
	if fetched.Conversation.Title == "" || fetched.Conversation.Title == "Imported session" {
		t.Fatalf("expected title derived from first user message, got %q", fetched.Conversation.Title)
	}
	if len(fetched.Turns) != 1 {
		t.Fatalf("expected exactly one imported turn, got %d", len(fetched.Turns))
	}
	turn := fetched.Turns[0]
	if turn.Status != "exited" {
		t.Fatalf("turn.Status = %q, want exited", turn.Status)
	}
	if turn.Prompt != "fix the flaky test" {
		t.Fatalf("turn.Prompt = %q, want the user message", turn.Prompt)
	}
	// Binding the observed session id as vendorSessionId is what lets a later
	// agent.conversations.append follow-up on this conversation use exact
	// resume instead of "latest in cwd" — the whole point of importing.
	if turn.VendorSessionID != "vendor-session-1" {
		t.Fatalf("turn.VendorSessionID = %q, want vendor-session-1", turn.VendorSessionID)
	}
	if len(fetched.Events) != wantEvents {
		t.Fatalf("len(Events) = %d, want %d", len(fetched.Events), wantEvents)
	}
	outputs := messages[1:]
	for i, ev := range fetched.Events {
		if ev.Text != outputs[i].Text {
			t.Fatalf("event[%d].Text = %q, want %q", i, ev.Text, outputs[i].Text)
		}
		if ev.Role != outputs[i].Role {
			t.Fatalf("event[%d].Role = %q, want %q", i, ev.Role, outputs[i].Role)
		}
	}

	sid, err := s.latestVendorSessionID(res.ConversationID)
	if err != nil {
		t.Fatalf("latestVendorSessionID: %v", err)
	}
	if sid != "vendor-session-1" {
		t.Fatalf("latestVendorSessionID = %q, want vendor-session-1", sid)
	}
}

// TestAttachObservedSessionSegmentsIntoRealTurns proves three user prompts
// become three turns with correct ordinals/prompts, and assistant replies land
// as that turn's output events.
func TestAttachObservedSessionSegmentsIntoRealTurns(t *testing.T) {
	s := newObservedTestStore(t)
	messages := []SessionMessage{
		{Role: "user", Text: "first prompt"},
		{Role: "assistant", Text: "first reply"},
		{Role: "user", Text: "second prompt"},
		{Role: "assistant", Text: "second reply"},
		{Role: "toolCall", Text: "Bash: ls", ToolName: "Bash"},
		{Role: "user", Text: "third prompt"},
		{Role: "assistant", Text: "third reply"},
	}

	res, err := s.attachObservedSession("claudeCode", "vendor-multi-turn", "/tmp/proj", "Session Title", messages)
	if err != nil {
		t.Fatalf("attachObservedSession: %v", err)
	}

	fetched, err := s.fetch(res.ConversationID, 0, 100)
	if err != nil {
		t.Fatalf("fetch: %v", err)
	}
	if len(fetched.Turns) != 3 {
		t.Fatalf("got %d turns, want 3", len(fetched.Turns))
	}
	wantPrompts := []string{"first prompt", "second prompt", "third prompt"}
	for i, turn := range fetched.Turns {
		if turn.Ordinal != i+1 {
			t.Fatalf("turn[%d].Ordinal = %d, want %d", i, turn.Ordinal, i+1)
		}
		if turn.Prompt != wantPrompts[i] {
			t.Fatalf("turn[%d].Prompt = %q, want %q", i, turn.Prompt, wantPrompts[i])
		}
		if turn.Status != "exited" {
			t.Fatalf("turn[%d].Status = %q, want exited", i, turn.Status)
		}
		if turn.VendorSessionID != "vendor-multi-turn" {
			t.Fatalf("turn[%d].VendorSessionID = %q", i, turn.VendorSessionID)
		}
	}

	eventsByTurn := map[string][]conversationEvent{}
	for _, ev := range fetched.Events {
		eventsByTurn[ev.TurnID] = append(eventsByTurn[ev.TurnID], ev)
	}
	if got := eventsByTurn[fetched.Turns[0].ID]; len(got) != 1 || got[0].Text != "first reply" {
		t.Fatalf("turn 1 events = %+v, want [first reply]", got)
	}
	if got := eventsByTurn[fetched.Turns[1].ID]; len(got) != 2 {
		t.Fatalf("turn 2 events = %+v, want 2 (reply + toolCall)", got)
	}
	if got := eventsByTurn[fetched.Turns[2].ID]; len(got) != 1 || got[0].Text != "third reply" {
		t.Fatalf("turn 3 events = %+v, want [third reply]", got)
	}
}

func TestAttachObservedSessionTitleFromAITitleOrRealUser(t *testing.T) {
	s := newObservedTestStore(t)

	withTitle, err := s.attachObservedSession("claudeCode", "vendor-ai-title", "/tmp/proj", "fix-dead-buttons", []SessionMessage{
		{Role: "user", Text: "<local-command-caveat>Caveat: The messages below were generated by the user."},
		{Role: "user", Text: "please fix the dead button"},
		{Role: "assistant", Text: "Sure."},
	})
	if err != nil {
		t.Fatalf("attach with ai-title: %v", err)
	}
	fetched, err := s.fetch(withTitle.ConversationID, 0, 10)
	if err != nil {
		t.Fatalf("fetch: %v", err)
	}
	if fetched.Conversation.Title != "fix-dead-buttons" {
		t.Fatalf("Title = %q, want ai-title value", fetched.Conversation.Title)
	}

	s2 := newObservedTestStore(t)
	withoutTitle, err := s2.attachObservedSession("claudeCode", "vendor-no-ai-title", "/tmp/proj", "", []SessionMessage{
		{Role: "user", Text: "<local-command-caveat>Caveat: The messages below were generated by the user."},
		{Role: "user", Text: "<command-name>/compact</command-name>"},
		{Role: "user", Text: "<system-reminder>do not cite</system-reminder>"},
		{Role: "user", Text: "<task-notification><task-id>bg</task-id><summary>done</summary></task-notification>"},
		{Role: "user", Text: "real user question about the bug"},
		{Role: "assistant", Text: "Looking."},
	})
	if err != nil {
		t.Fatalf("attach without ai-title: %v", err)
	}
	fetched2, err := s2.fetch(withoutTitle.ConversationID, 0, 10)
	if err != nil {
		t.Fatalf("fetch: %v", err)
	}
	if fetched2.Conversation.Title != "real user question about the bug" {
		t.Fatalf("Title = %q, want first real user message (wrappers skipped)", fetched2.Conversation.Title)
	}
	if len(fetched2.Turns) != 1 {
		t.Fatalf("expected 1 turn (wrappers skipped as turn starters), got %d", len(fetched2.Turns))
	}
	if fetched2.Turns[0].Prompt != "real user question about the bug" {
		t.Fatalf("Prompt = %q, want real user question", fetched2.Turns[0].Prompt)
	}
}

// TestAttachObservedSessionIsIdempotent proves re-attaching the exact same
// provider+sessionId returns the FIRST call's conversation rather than
// importing a second copy — the acceptance criterion the build handoff calls
// out explicitly for Task 9.
func TestAttachObservedSessionIsIdempotent(t *testing.T) {
	s := newObservedTestStore(t)
	messages := []SessionMessage{{Role: "user", Text: "hello"}, {Role: "assistant", Text: "hi"}}

	first, err := s.attachObservedSession("codex", "vendor-session-2", "/tmp/proj", "", messages)
	if err != nil {
		t.Fatalf("first attachObservedSession: %v", err)
	}

	second, err := s.attachObservedSession("codex", "vendor-session-2", "/tmp/proj", "", messages)
	if err != nil {
		t.Fatalf("second attachObservedSession: %v", err)
	}
	if !second.AlreadyAttached {
		t.Fatal("expected AlreadyAttached=true on re-attach")
	}
	if second.ConversationID != first.ConversationID {
		t.Fatalf("re-attach returned a different conversationId: first=%q second=%q", first.ConversationID, second.ConversationID)
	}

	list, err := s.list(50, "", false)
	if err != nil {
		t.Fatalf("list: %v", err)
	}
	count := 0
	for _, c := range list.Conversations {
		if c.ID == first.ConversationID {
			count++
		}
	}
	if count != 1 {
		t.Fatalf("expected exactly one conversation for the imported session, found %d", count)
	}
}

func TestAttachObservedSessionRequiresProviderAndSessionID(t *testing.T) {
	s := newObservedTestStore(t)
	if _, err := s.attachObservedSession("", "vendor-session-3", "/tmp", "", nil); err == nil {
		t.Fatal("expected an error for empty provider")
	}
	if _, err := s.attachObservedSession("claudeCode", "", "/tmp", "", nil); err == nil {
		t.Fatal("expected an error for empty sessionId")
	}
}

func TestAttachObservedSessionWithNoMessagesImportsZeroEvents(t *testing.T) {
	s := newObservedTestStore(t)
	res, err := s.attachObservedSession("kimi", "vendor-session-4", "/tmp", "Empty session", nil)
	if err != nil {
		t.Fatalf("attachObservedSession: %v", err)
	}
	if res.ImportedEvents != 0 || res.LastSeq != 0 {
		t.Fatalf("expected zero imported events/lastSeq, got %d/%d", res.ImportedEvents, res.LastSeq)
	}

	fetched, err := s.fetch(res.ConversationID, 0, 10)
	if err != nil {
		t.Fatalf("fetch: %v", err)
	}
	if fetched.Conversation.Title != "Empty session" {
		t.Fatalf("Title = %q, want the explicit title passed in", fetched.Conversation.Title)
	}
}

// TestAttachObservedSessionStructuredKindsRoundTrip proves toolCall / toolResult /
// thinking persist as distinct event kinds with payload_json, and fetch returns
// them verbatim (no flattening to kind=output).
func TestAttachObservedSessionStructuredKindsRoundTrip(t *testing.T) {
	s := newObservedTestStore(t)
	messages := []SessionMessage{
		{Role: "user", Text: "please edit"},
		{Role: "thinking", Text: "planning the edit"},
		{
			Role: "toolCall", Text: "Edit: /a.go", ToolName: "Edit", ToolUseID: "toolu_1",
			InputJSON: `{"file_path":"/a.go","old_string":"x","new_string":"x\ny"}`,
		},
		{Role: "toolResult", Text: "ok", ToolUseID: "toolu_1", IsError: false},
		{Role: "assistant", Text: "done"},
	}

	res, err := s.attachObservedSession("claudeCode", "vendor-structured", "/tmp/proj", "", messages)
	if err != nil {
		t.Fatalf("attachObservedSession: %v", err)
	}
	fetched, err := s.fetch(res.ConversationID, 0, 100)
	if err != nil {
		t.Fatalf("fetch: %v", err)
	}
	if len(fetched.Events) != 4 {
		t.Fatalf("len(Events) = %d, want 4", len(fetched.Events))
	}

	wantKinds := []string{"thinking", "tool_call", "tool_result", "output"}
	for i, kind := range wantKinds {
		if fetched.Events[i].Kind != kind {
			t.Fatalf("event[%d].Kind = %q, want %q", i, fetched.Events[i].Kind, kind)
		}
	}
	if fetched.Events[0].Text != "planning the edit" || fetched.Events[0].PayloadJSON != "" {
		t.Fatalf("thinking event = %+v", fetched.Events[0])
	}

	var toolPayload map[string]any
	if err := json.Unmarshal([]byte(fetched.Events[1].PayloadJSON), &toolPayload); err != nil {
		t.Fatalf("tool_call payload: %v (%q)", err, fetched.Events[1].PayloadJSON)
	}
	if toolPayload["name"] != "Edit" || toolPayload["toolUseId"] != "toolu_1" {
		t.Fatalf("tool_call payload = %#v", toolPayload)
	}
	if toolPayload["added"] != float64(2) || toolPayload["removed"] != float64(1) {
		t.Fatalf("diff stats in payload = %#v", toolPayload)
	}
	input, _ := toolPayload["input"].(map[string]any)
	if input["file_path"] != "/a.go" {
		t.Fatalf("payload input = %#v", toolPayload["input"])
	}
	if fetched.Events[1].Text != "Edit: /a.go" {
		t.Fatalf("tool_call text = %q", fetched.Events[1].Text)
	}

	var resultPayload map[string]any
	if err := json.Unmarshal([]byte(fetched.Events[2].PayloadJSON), &resultPayload); err != nil {
		t.Fatalf("tool_result payload: %v", err)
	}
	if resultPayload["toolUseId"] != "toolu_1" || resultPayload["isError"] != false {
		t.Fatalf("tool_result payload = %#v", resultPayload)
	}
	if fetched.Events[2].Text != "ok" {
		t.Fatalf("tool_result text = %q", fetched.Events[2].Text)
	}
	if fetched.Events[3].Kind != "output" || fetched.Events[3].Role != "assistant" || fetched.Events[3].Text != "done" {
		t.Fatalf("assistant output = %+v", fetched.Events[3])
	}
	if !strings.Contains(fetched.Events[1].PayloadJSON, `"input"`) {
		t.Fatal("tool_call payload missing input key")
	}
}
