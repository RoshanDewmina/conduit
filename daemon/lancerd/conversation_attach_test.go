package main

import "testing"

// conversation_attach_test.go covers Task 9 of the cross-device sync build
// handoff: conversationStore.attachObservedSession, the create-from-import
// path that turns an already-observed CLI session's transcript into a
// single completed ledger turn. Exercised directly against the store (not
// through the RPC layer) so it doesn't depend on a real on-disk
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
	if res.ImportedEvents != len(messages) {
		t.Fatalf("ImportedEvents = %d, want %d", res.ImportedEvents, len(messages))
	}
	if res.LastSeq != int64(len(messages)) {
		t.Fatalf("LastSeq = %d, want %d", res.LastSeq, len(messages))
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
	if turn.Status != "completed" {
		t.Fatalf("turn.Status = %q, want completed", turn.Status)
	}
	// Binding the observed session id as vendorSessionId is what lets a later
	// agent.conversations.append follow-up on this conversation use exact
	// resume instead of "latest in cwd" — the whole point of importing.
	if turn.VendorSessionID != "vendor-session-1" {
		t.Fatalf("turn.VendorSessionID = %q, want vendor-session-1", turn.VendorSessionID)
	}
	if len(fetched.Events) != len(messages) {
		t.Fatalf("len(Events) = %d, want %d", len(fetched.Events), len(messages))
	}
	for i, ev := range fetched.Events {
		if ev.Text != messages[i].Text {
			t.Fatalf("event[%d].Text = %q, want %q", i, ev.Text, messages[i].Text)
		}
		if ev.Role != messages[i].Role {
			t.Fatalf("event[%d].Role = %q, want %q", i, ev.Role, messages[i].Role)
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
