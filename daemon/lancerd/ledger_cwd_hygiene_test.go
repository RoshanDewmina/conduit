package main

import (
	"encoding/json"
	"net"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func conversationCount(t *testing.T, s *conversationStore) int {
	t.Helper()
	var n int
	if err := s.db.QueryRow(`SELECT COUNT(*) FROM conversations`).Scan(&n); err != nil {
		t.Fatalf("COUNT conversations: %v", err)
	}
	return n
}

func TestConversationsAppendRejectsRelativeCWDWithoutPersisting(t *testing.T) {
	home := t.TempDir()
	s := newServer(home)
	defer s.poller.stopForTest()

	// Make the relative path really exist under the process cwd: a Stat-only
	// check would pass it and persist the relative string verbatim, so this
	// proves the explicit IsAbs guard does the rejecting.
	procCWD := t.TempDir()
	if err := os.Mkdir(filepath.Join(procCWD, "command-center"), 0o755); err != nil {
		t.Fatalf("mkdir: %v", err)
	}
	t.Chdir(procCWD)

	before := conversationCount(t, s.conversations)
	_, err := s.conversationsAppend(conversationAppendRequest{
		ClientTurnID: "rel-cwd-1",
		Agent:        "claudeCode",
		Prompt:       "should not persist",
		CWD:          "command-center",
	})
	if err == nil {
		t.Fatal("expected RPC error for relative cwd")
	}
	if got := conversationCount(t, s.conversations); got != before {
		t.Fatalf("conversation rows = %d, want %d (nothing persisted)", got, before)
	}
}

func TestConversationsAppendEmptyCWDDefaultsToAbsoluteHome(t *testing.T) {
	home := t.TempDir()
	s := newServer(home)
	defer s.poller.stopForTest()

	userHome, err := os.UserHomeDir()
	if err != nil {
		t.Fatalf("UserHomeDir: %v", err)
	}

	resp, err := s.conversationsAppend(conversationAppendRequest{
		ClientTurnID: "empty-cwd-1",
		Agent:        "claudeCode",
		Prompt:       "default cwd",
		CWD:          "",
	})
	if err != nil {
		t.Fatalf("conversationsAppend: %v", err)
	}
	if !filepath.IsAbs(resp.CWD) {
		t.Fatalf("CWD = %q, want absolute home path", resp.CWD)
	}
	if resp.CWD != userHome {
		t.Fatalf("CWD = %q, want %q", resp.CWD, userHome)
	}
	fetched, err := s.conversations.fetch(resp.ConversationID, 0, 10)
	if err != nil {
		t.Fatalf("fetch: %v", err)
	}
	if fetched.Conversation.CWD != userHome {
		t.Fatalf("persisted CWD = %q, want %q", fetched.Conversation.CWD, userHome)
	}
}

func TestAttachObservedSessionRPCRejectsRelativeAndEmptyCWD(t *testing.T) {
	home := t.TempDir()
	s := newServer(home)
	defer s.poller.stopForTest()

	before := conversationCount(t, s.conversations)

	relErr, err := s.conversationsAttachObservedSession(conversationAttachObservedSessionRequest{
		Provider:  "claudeCode",
		SessionID: "sess-rel",
		CWD:       "command-center",
	})
	_ = relErr
	if err == nil {
		t.Fatal("expected error for relative cwd")
	}
	if !strings.Contains(strings.ToLower(err.Error()), "cwd") {
		t.Fatalf("relative cwd error should mention cwd, got %q", err)
	}

	emptyErr, err := s.conversationsAttachObservedSession(conversationAttachObservedSessionRequest{
		Provider:  "claudeCode",
		SessionID: "sess-empty",
		CWD:       "",
	})
	_ = emptyErr
	if err == nil {
		t.Fatal("expected error for empty cwd")
	}
	if !strings.Contains(strings.ToLower(err.Error()), "cwd") {
		t.Fatalf("empty cwd error should mention cwd, got %q", err)
	}
	if got := conversationCount(t, s.conversations); got != before {
		t.Fatalf("conversation rows = %d, want %d", got, before)
	}
}

func TestAttachObservedSessionAcceptsAbsoluteNonexistentCWD(t *testing.T) {
	s := newObservedTestStore(t)
	missing := filepath.Join(t.TempDir(), "removed-worktree")
	res, err := s.attachObservedSession("claudeCode", "sess-missing-cwd", missing, "", []SessionMessage{
		{Role: "user", Text: "from a gone worktree"},
	})
	if err != nil {
		t.Fatalf("attachObservedSession: %v", err)
	}
	fetched, err := s.fetch(res.ConversationID, 0, 10)
	if err != nil {
		t.Fatalf("fetch: %v", err)
	}
	if fetched.Conversation.CWD != missing {
		t.Fatalf("CWD = %q, want %q", fetched.Conversation.CWD, missing)
	}
}

func TestAttachObservedSessionTruncatesOversizedTitle(t *testing.T) {
	s := newObservedTestStore(t)
	long := strings.Repeat("字", 100) // 100 runes > 80
	res, err := s.attachObservedSession("claudeCode", "sess-long-title", "/tmp/proj", long, nil)
	if err != nil {
		t.Fatalf("attachObservedSession: %v", err)
	}
	fetched, err := s.fetch(res.ConversationID, 0, 10)
	if err != nil {
		t.Fatalf("fetch: %v", err)
	}
	if got := len([]rune(fetched.Conversation.Title)); got != 80 {
		t.Fatalf("title rune length = %d, want 80 (got %q)", got, fetched.Conversation.Title)
	}
}

func TestHookRunIDBackfillFromLedgerRunningTurnThenRestoreQueuePrunes(t *testing.T) {
	dir := withStateDir(t)
	installTestPolicy(t)

	core := newServer(serverHome())
	defer core.poller.stopForTest()

	turn, err := core.conversations.beginTurn(conversationAppendRequest{
		ClientTurnID: "hook-backfill-1",
		Agent:        "claudeCode",
		Prompt:       "live ledger turn",
	}, dir, "run-ledger-backfill")
	if err != nil {
		t.Fatalf("beginTurn: %v", err)
	}
	if core.dispatcher.runForCWD(dir, "claudeCode") != "" {
		t.Fatal("expected no in-memory dispatch run for this cwd")
	}

	srv, cli := net.Pipe()
	defer cli.Close()
	event := ApprovalEvent{
		ApprovalID: "hook-backfill-appr",
		Agent:      "claudeCode",
		Kind:       "command",
		Command:    "ls",
		CWD:        dir,
		Timestamp:  time.Now().UTC().Format(time.RFC3339),
	}
	first, _ := json.Marshal(event)

	go core.handleHookWithNotify(srv, first, nil, func() bool { return true })

	deadline := time.Now().Add(2 * time.Second)
	var pending []ApprovalEvent
	for time.Now().Before(deadline) {
		pending = core.approvals.pendingEvents()
		if len(pending) == 1 {
			break
		}
		time.Sleep(10 * time.Millisecond)
	}
	if len(pending) != 1 {
		t.Fatalf("pending = %+v, want one escalated approval", pending)
	}
	if pending[0].RunID != turn.RunID {
		t.Fatalf("RunID = %q, want ledger run %q", pending[0].RunID, turn.RunID)
	}

	if _, err := core.conversations.db.Exec(
		`UPDATE conversation_turns SET status='failed' WHERE run_id=?`, turn.RunID); err != nil {
		t.Fatalf("mark failed: %v", err)
	}

	q := newDiskQueue(filepath.Join(dir, queueFileName))
	if err := q.replace(pending); err != nil {
		t.Fatalf("queue replace: %v", err)
	}
	// Fresh approvals map so restoreQueue is the sole source of pending.
	core2 := newServer(serverHome())
	defer core2.poller.stopForTest()
	core2.conversations = core.conversations
	r := &resident{core: core2, queue: q}
	if err := r.restoreQueue(); err != nil {
		t.Fatalf("restoreQueue: %v", err)
	}
	if got := r.core.approvals.pendingEvents(); len(got) != 0 {
		t.Fatalf("pending after restore = %+v, want pruned (empty)", got)
	}
}
