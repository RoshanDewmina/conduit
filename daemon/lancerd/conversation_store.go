package main

import (
	"database/sql"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	_ "modernc.org/sqlite"
)

// errNoLedgerTurn is the sentinel turnByRunID wraps its "no rows" case around.
// It lets a caller (server.persistConversationEvent, Task 4 of the cross-device
// sync build handoff) distinguish "this runID simply has no conversation-ledger
// turn" — the expected, silent-no-op case for every non-conversation-ledger-
// backed run (plain dispatch/continueRun/resumeObservedSession) — from a
// genuine lookup failure (e.g. the store's connection is closed/unavailable),
// which should still be logged. errors.Is(err, errNoLedgerTurn) is how callers
// tell the two apart; the wrapped message text is unchanged from before this
// sentinel was added.
var errNoLedgerTurn = errors.New("conversation_store: no turn found for run")

// conversation_store.go — the daemon's host-owned conversation ledger.
//
// The host is authoritative for execution truth: cwd, provider, policy context,
// run history, and the exact vendor session ID a follow-up must resume. This
// store persists that ledger to a host-local SQLite database so it survives
// daemon restarts. A later phase mirrors summaries/turns/events to CloudKit for
// cross-Apple-device continuity, but that mirror is read-mostly — this store
// remains the single writer for executable turns (see the append-first /
// host-mediated-append rules in the cross-device sync build handoff doc).
//
// Concurrency: the *sql.DB connection pool is capped at one connection, so every
// statement — including the multi-statement read-then-write sequence inside
// beginTurn — is naturally serialized. That gives us the equivalent of an
// in-process lock without a separate sync.Mutex, and it's what makes the
// baseSeq conflict check safe against concurrent callers.

const conversationsDBFileName = "conversations.sqlite"
const daemonHostIDFileName = "host-id"

type conversationStore struct {
	db     *sql.DB
	hostID string
}

// openConversationStore opens (creating if needed) the host conversation ledger
// at <home>/.lancer/conversations.sqlite using the pure-Go modernc.org/sqlite
// driver, so the daemon never depends on an external sqlite3 binary or cgo for
// its own canonical store.
func openConversationStore(home string) (*conversationStore, error) {
	dir := filepath.Join(home, ".lancer")
	if err := os.MkdirAll(dir, 0700); err != nil {
		return nil, fmt.Errorf("conversation_store: mkdir %s: %w", dir, err)
	}
	dbPath := filepath.Join(dir, conversationsDBFileName)

	dsn := dbPath + "?_pragma=foreign_keys(1)&_pragma=busy_timeout(5000)&_pragma=journal_mode(WAL)"
	db, err := sql.Open("sqlite", dsn)
	if err != nil {
		return nil, fmt.Errorf("conversation_store: open %s: %w", dbPath, err)
	}
	// modernc.org/sqlite is not safe for unbounded concurrent connections against
	// a single file the way a client/server DB is; capping the pool at one
	// connection serializes all access through the stdlib's connection borrow/
	// return, which is exactly the semantics this ledger needs.
	db.SetMaxOpenConns(1)

	s := &conversationStore{db: db}
	hostID, err := loadOrCreateDaemonHostID(dir)
	if err != nil {
		_ = db.Close()
		return nil, fmt.Errorf("conversation_store: host id: %w", err)
	}
	s.hostID = hostID
	if err := s.migrate(); err != nil {
		_ = db.Close()
		return nil, fmt.Errorf("conversation_store: migrate: %w", err)
	}
	if err := s.failOrphanedRunningTurns(); err != nil {
		// Non-fatal: a reconciliation failure must not stop the daemon, but it
		// is loud — orphans left 'running' spin phones forever.
		log.Printf("conversation_store: orphan reconciliation failed: %v", err)
	}
	return s, nil
}

// failOrphanedRunningTurns marks every turn still 'running' at daemon startup
// as failed. A turn can only be running while THIS daemon process supervises
// its agent subprocess; after a restart no such process exists, so a
// 'running' row is always a lie — and the phone polls it forever ("Working…"
// with no way out; live incident 2026-07-11: a daemon restart killed an
// in-flight run and the owner's thread spun indefinitely). The honest
// terminal state is failed-with-reason; the phone renders the message and
// offers follow-up/retry.
func (s *conversationStore) failOrphanedRunningTurns() error {
	now := time.Now().UTC().Format(time.RFC3339)
	res, err := s.db.Exec(
		`UPDATE conversation_turns SET status='failed',
			error_message='Interrupted: the daemon restarted while this run was in flight.',
			completed_at=? WHERE status='running'`, now)
	if err != nil {
		return err
	}
	if n, _ := res.RowsAffected(); n > 0 {
		log.Printf("conversation_store: marked %d orphaned running turn(s) failed after restart", n)
	}
	return nil
}

// loadOrCreateDaemonHostID returns a stable UUID persisted under ~/.lancer/host-id
// so every conversation row on this daemon shares the same host_id for cross-device identity.
func loadOrCreateDaemonHostID(lancerDir string) (string, error) {
	path := filepath.Join(lancerDir, daemonHostIDFileName)
	if data, err := os.ReadFile(path); err == nil {
		if id := strings.TrimSpace(string(data)); id != "" {
			return id, nil
		}
	}
	id := newUUID()
	if err := os.WriteFile(path, []byte(id+"\n"), 0600); err != nil {
		return "", err
	}
	return id, nil
}

func (s *conversationStore) close() error {
	return s.db.Close()
}

func (s *conversationStore) migrate() error {
	stmts := []string{
		`CREATE TABLE IF NOT EXISTS conversations (
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
		`CREATE TABLE IF NOT EXISTS conversation_turns (
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
			attachments_json TEXT NOT NULL DEFAULT '[]',
			UNIQUE(conversation_id, ordinal),
			UNIQUE(conversation_id, client_turn_id),
			UNIQUE(run_id)
		)`,
		`CREATE TABLE IF NOT EXISTS conversation_events (
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
		`CREATE TABLE IF NOT EXISTS conversation_artifacts (
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
		`CREATE INDEX IF NOT EXISTS idx_conversations_last_activity
			ON conversations(last_activity_at DESC)`,
		`CREATE INDEX IF NOT EXISTS idx_turns_conversation_ordinal
			ON conversation_turns(conversation_id, ordinal)`,
		`CREATE INDEX IF NOT EXISTS idx_events_conversation_seq
			ON conversation_events(conversation_id, seq)`,
		`CREATE INDEX IF NOT EXISTS idx_turns_vendor_session
			ON conversation_turns(provider, vendor_session_id)`,
	}
	for _, stmt := range stmts {
		if _, err := s.db.Exec(stmt); err != nil {
			return fmt.Errorf("exec %q: %w", firstLine(stmt), err)
		}
	}
	// Additive columns for DBs created before G1 turn-diff baselines / attachment metadata.
	for _, alter := range []string{
		`ALTER TABLE conversation_turns ADD COLUMN baseline_start_oid TEXT`,
		`ALTER TABLE conversation_turns ADD COLUMN baseline_end_oid TEXT`,
		`ALTER TABLE conversation_turns ADD COLUMN attachments_json TEXT NOT NULL DEFAULT '[]'`,
	} {
		if _, err := s.db.Exec(alter); err != nil && !isSQLiteDuplicateColumn(err) {
			return fmt.Errorf("exec %q: %w", firstLine(alter), err)
		}
	}
	return nil
}

func isSQLiteDuplicateColumn(err error) bool {
	if err == nil {
		return false
	}
	msg := strings.ToLower(err.Error())
	return strings.Contains(msg, "duplicate column")
}

func firstLine(s string) string {
	if i := strings.IndexByte(s, '\n'); i >= 0 {
		return strings.TrimSpace(s[:i])
	}
	return s
}

func conversationNow() string {
	return time.Now().UTC().Format(time.RFC3339)
}

// --- Request/result types -----------------------------------------------

// conversationAppendRequest mirrors the agent.conversations.append RPC request
// (see the cross-device sync build handoff's RPC Contract section). ConversationID
// empty means "start a new conversation"; otherwise this is a follow-up and BaseSeq
// must match the conversation's current last_seq or the append is rejected as a
// conflict.
type conversationAppendRequest struct {
	ConversationID string  `json:"conversationId,omitempty"`
	BaseSeq        int64   `json:"baseSeq"`
	ClientTurnID   string  `json:"clientTurnId"`
	Agent          string  `json:"agent,omitempty"`
	CWD            string  `json:"cwd,omitempty"`
	Prompt         string  `json:"prompt"`
	Model          string  `json:"model,omitempty"`
	BudgetUSD      float64 `json:"budgetUSD,omitempty"`
	UseWorktree    bool    `json:"useWorktree,omitempty"`
	// Contract mirrors dispatchParams.Contract (dispatch.go) — the iOS
	// composer sends the same `contract` key on agent.conversations.append
	// as it does on a plain agent.dispatch (see ConversationAppendRequest.contract,
	// LancerDProtocol.swift), so a live-composer-started or -continued turn's
	// goal/doneCriteria/validationCommands reach the terminal receipt the same
	// way a direct dispatch's do. Validated/cloned by launchConversationTurn
	// via the SAME contractTooLarge/cloneRunContract helpers dispatch() uses.
	Contract *runContract `json:"contract,omitempty"`
	// Attachments is optional structured metadata for files/images sent with
	// this turn. hostPath is transport-only and must not appear in UI copy.
	Attachments []conversationAttachmentReference `json:"attachments,omitempty"`
}

// conversationAttachmentReference is the shared Swift↔Go wire contract for a
// single attachment on a conversation turn / append request. Validated for
// bounded structural invariants at persist time; the store never opens hostPath.
//
// contentDigest (camelCase, locked) is the lowercase hex SHA-256 of the exact
// uploaded bytes, issued by attachment.put. New outgoing attachments MUST
// carry a valid 64-hex digest (encodeAttachmentsJSON). Historical
// attachments_json rows may omit it — decodeAttachmentsJSON allows empty
// digest for backward read compatibility, but launchConversationTurn fails
// closed on missing digest (actionable re-upload error).
type conversationAttachmentReference struct {
	ID              string `json:"id"`
	Name            string `json:"name"`
	MimeType        string `json:"mimeType,omitempty"`
	ByteCount       int    `json:"byteCount"`
	Kind            string `json:"kind"` // "image" | "file"
	HostPath        string `json:"hostPath"`
	PreviewCacheKey string `json:"previewCacheKey"`
	ContentDigest   string `json:"contentDigest,omitempty"`
}

// conversationAppendResult mirrors the subset of the agent.conversations.append
// response this store layer can determine. Fields that depend on dispatch/vendor
// CLI behavior (vendorSessionId, resumeMode, rule) are intentionally absent here —
// they belong to later tasks that call bindVendorSession / know the policy
// decision — and are filled in by the RPC layer built on top of this store.
type conversationAppendResult struct {
	Status         string `json:"status"`
	ConversationID string `json:"conversationId"`
	TurnID         string `json:"turnId,omitempty"`
	RunID          string `json:"runId,omitempty"`
	CWD            string `json:"cwd,omitempty"`
	BaseSeq        int64  `json:"baseSeq"`
	NextSeq        int64  `json:"nextSeq"`
	Message        string `json:"message,omitempty"`
}

type conversationSummary struct {
	ID             string  `json:"id"`
	Title          string  `json:"title"`
	Provider       string  `json:"provider"`
	AgentID        string  `json:"agentID"`
	HostID         string  `json:"hostID,omitempty"`
	HostName       string  `json:"hostName"`
	CWD            string  `json:"cwd"`
	Model          string  `json:"model,omitempty"`
	BudgetUSD      float64 `json:"budgetUSD,omitempty"`
	State          string  `json:"state"`
	Source         string  `json:"source"`
	CreatedAt      string  `json:"createdAt"`
	UpdatedAt      string  `json:"updatedAt"`
	LastActivityAt string  `json:"lastActivityAt"`
	LastSeq        int64   `json:"lastSeq"`
	ArchivedAt     string  `json:"archivedAt,omitempty"`
	// LastTurnID / LastTurnStatus are additive list-only fields so the phone
	// thread list can clear a stale "Working" badge after the daemon marks
	// an orphaned turn failed (or a turn completes) without opening the
	// thread. Omitted when the conversation has no turns yet.
	LastTurnID     string `json:"lastTurnID,omitempty"`
	LastTurnStatus string `json:"lastTurnStatus,omitempty"`
}

type conversationTurn struct {
	ID              string `json:"id"`
	ConversationID  string `json:"conversationId"`
	Ordinal         int    `json:"ordinal"`
	ClientTurnID    string `json:"clientTurnId"`
	Prompt          string `json:"prompt"`
	RunID           string `json:"runId"`
	Provider        string `json:"provider"`
	VendorSessionID string `json:"vendorSessionId,omitempty"`
	Status          string `json:"status"`
	StartedAt       string `json:"startedAt"`
	CompletedAt     string `json:"completedAt,omitempty"`
	ErrorMessage    string `json:"errorMessage,omitempty"`
	// BaselineStartOID / BaselineEndOID are shadow git tree OIDs stamped at
	// turn start/end (turn_baseline.go). Empty when cwd is not a git repo.
	BaselineStartOID string `json:"baselineStartOid,omitempty"`
	BaselineEndOID   string `json:"baselineEndOid,omitempty"`
	// Attachments is persisted as conversation_turns.attachments_json.
	// Missing/empty JSON decodes as a non-nil empty slice.
	Attachments []conversationAttachmentReference `json:"attachments,omitempty"`
}

type conversationEvent struct {
	ConversationID string `json:"conversationId"`
	Seq            int64  `json:"seq"`
	TurnID         string `json:"turnId,omitempty"`
	RunID          string `json:"runId,omitempty"`
	Kind           string `json:"kind"`
	Role           string `json:"role,omitempty"`
	Stream         string `json:"stream,omitempty"`
	Text           string `json:"text,omitempty"`
	PayloadJSON    string `json:"payloadJson,omitempty"`
	CreatedAt      string `json:"createdAt"`
}

type conversationArtifact struct {
	ID             string `json:"id"`
	ConversationID string `json:"conversationId"`
	TurnID         string `json:"turnId,omitempty"`
	RunID          string `json:"runId"`
	Kind           string `json:"kind"`
	Title          string `json:"title"`
	Summary        string `json:"summary,omitempty"`
	PayloadJSON    string `json:"payloadJson"`
	Status         string `json:"status"`
	CreatedAt      string `json:"createdAt"`
	UpdatedAt      string `json:"updatedAt"`
}

type conversationListResult struct {
	Conversations []conversationSummary `json:"conversations"`
	NextCursor    string                `json:"nextCursor"`
}

type conversationFetchResult struct {
	Conversation conversationSummary    `json:"conversation"`
	Turns        []conversationTurn     `json:"turns"`
	Events       []conversationEvent    `json:"events"`
	Artifacts    []conversationArtifact `json:"artifacts"`
	NextSeq      int64                  `json:"nextSeq"`
	HasMore      bool                   `json:"hasMore"`
}

// --- list -----------------------------------------------------------------

const defaultListLimit = 50

// list returns conversations ordered most-recently-active first. cursor is an
// opaque token from a previous call's NextCursor; pass "" to start from the
// beginning. includeArchived controls whether archived (not deleted) conversations
// are included.
func (s *conversationStore) list(limit int, cursor string, includeArchived bool) (conversationListResult, error) {
	if limit <= 0 {
		limit = defaultListLimit
	}

	var (
		cursorActivity string
		cursorRowID    int64
		hasCursor      bool
	)
	if cursor != "" {
		var err error
		cursorActivity, cursorRowID, err = decodeListCursor(cursor)
		if err != nil {
			return conversationListResult{}, fmt.Errorf("conversation_store: invalid cursor: %w", err)
		}
		hasCursor = true
	}

	// Correlated subqueries attach the latest turn (max ordinal) so list
	// callers can refresh per-turn status without a full fetch. Additive —
	// existing columns/order of conversations are unchanged.
	query := `SELECT rowid, id, title, provider, agent_id, host_id, host_name, cwd, model,
		budget_usd, state, source, created_at, updated_at, last_activity_at, last_seq, archived_at,
		(SELECT id FROM conversation_turns WHERE conversation_id = conversations.id ORDER BY ordinal DESC LIMIT 1),
		(SELECT status FROM conversation_turns WHERE conversation_id = conversations.id ORDER BY ordinal DESC LIMIT 1)
		FROM conversations WHERE deleted_at IS NULL`
	args := []any{}
	if !includeArchived {
		query += " AND archived_at IS NULL"
	}
	if hasCursor {
		query += " AND (last_activity_at, rowid) < (?, ?)"
		args = append(args, cursorActivity, cursorRowID)
	}
	query += " ORDER BY last_activity_at DESC, rowid DESC LIMIT ?"
	args = append(args, limit+1)

	rows, err := s.db.Query(query, args...)
	if err != nil {
		return conversationListResult{}, err
	}
	defer rows.Close()

	type row struct {
		rowid int64
		conv  conversationSummary
	}
	var out []row
	for rows.Next() {
		var (
			r              row
			hostID         sql.NullString
			model          sql.NullString
			budget         sql.NullFloat64
			archived       sql.NullString
			lastTurnID     sql.NullString
			lastTurnStatus sql.NullString
		)
		if err := rows.Scan(&r.rowid, &r.conv.ID, &r.conv.Title, &r.conv.Provider, &r.conv.AgentID,
			&hostID, &r.conv.HostName, &r.conv.CWD, &model, &budget, &r.conv.State, &r.conv.Source,
			&r.conv.CreatedAt, &r.conv.UpdatedAt, &r.conv.LastActivityAt, &r.conv.LastSeq, &archived,
			&lastTurnID, &lastTurnStatus); err != nil {
			return conversationListResult{}, err
		}
		r.conv.HostID = hostID.String
		r.conv.Model = model.String
		r.conv.BudgetUSD = budget.Float64
		r.conv.ArchivedAt = archived.String
		r.conv.LastTurnID = lastTurnID.String
		r.conv.LastTurnStatus = lastTurnStatus.String
		out = append(out, r)
	}
	if err := rows.Err(); err != nil {
		return conversationListResult{}, err
	}

	res := conversationListResult{}
	n := len(out)
	if n > limit {
		n = limit
	}
	res.Conversations = make([]conversationSummary, 0, n)
	for i := 0; i < n; i++ {
		res.Conversations = append(res.Conversations, out[i].conv)
	}
	if len(out) > limit {
		last := out[limit-1]
		res.NextCursor = encodeListCursor(last.conv.LastActivityAt, last.rowid)
	}
	return res, nil
}

func encodeListCursor(lastActivityAt string, rowid int64) string {
	raw := lastActivityAt + "|" + strconv.FormatInt(rowid, 10)
	return base64.RawURLEncoding.EncodeToString([]byte(raw))
}

func decodeListCursor(cursor string) (string, int64, error) {
	raw, err := base64.RawURLEncoding.DecodeString(cursor)
	if err != nil {
		return "", 0, err
	}
	parts := strings.SplitN(string(raw), "|", 2)
	if len(parts) != 2 {
		return "", 0, fmt.Errorf("malformed cursor")
	}
	rowid, err := strconv.ParseInt(parts[1], 10, 64)
	if err != nil {
		return "", 0, fmt.Errorf("malformed cursor rowid: %w", err)
	}
	return parts[0], rowid, nil
}

// --- fetch ------------------------------------------------------------------

const defaultFetchLimit = 500

// fetch returns a conversation with its full turn/artifact list plus events
// strictly after sinceSeq (up to limit), so the caller can incrementally page
// through the append-only event log.
func (s *conversationStore) fetch(conversationID string, sinceSeq int64, limit int) (conversationFetchResult, error) {
	if limit <= 0 {
		limit = defaultFetchLimit
	}

	conv, err := scanConversationRow(s.db.QueryRow(conversationSelectByID, conversationID))
	if err != nil {
		if err == sql.ErrNoRows {
			return conversationFetchResult{}, fmt.Errorf("conversation_store: conversation %q not found", conversationID)
		}
		return conversationFetchResult{}, err
	}

	turns, err := s.loadTurns(conversationID)
	if err != nil {
		return conversationFetchResult{}, err
	}
	artifacts, err := s.loadArtifacts(conversationID)
	if err != nil {
		return conversationFetchResult{}, err
	}
	events, hasMore, err := s.loadEvents(conversationID, sinceSeq, limit)
	if err != nil {
		return conversationFetchResult{}, err
	}

	nextSeq := sinceSeq
	if len(events) > 0 {
		nextSeq = events[len(events)-1].Seq
	} else if !hasMore {
		nextSeq = conv.LastSeq
	}

	return conversationFetchResult{
		Conversation: conv,
		Turns:        turns,
		Events:       events,
		Artifacts:    artifacts,
		NextSeq:      nextSeq,
		HasMore:      hasMore,
	}, nil
}

const conversationSelectByID = `SELECT id, title, provider, agent_id, host_id, host_name, cwd, model,
	budget_usd, state, source, created_at, updated_at, last_activity_at, last_seq, archived_at
	FROM conversations WHERE id = ? AND deleted_at IS NULL`

type rowScanner interface {
	Scan(dest ...any) error
}

func scanConversationRow(row rowScanner) (conversationSummary, error) {
	var (
		conv     conversationSummary
		hostID   sql.NullString
		model    sql.NullString
		budget   sql.NullFloat64
		archived sql.NullString
	)
	err := row.Scan(&conv.ID, &conv.Title, &conv.Provider, &conv.AgentID, &hostID, &conv.HostName,
		&conv.CWD, &model, &budget, &conv.State, &conv.Source, &conv.CreatedAt, &conv.UpdatedAt,
		&conv.LastActivityAt, &conv.LastSeq, &archived)
	if err != nil {
		return conversationSummary{}, err
	}
	conv.HostID = hostID.String
	conv.Model = model.String
	conv.BudgetUSD = budget.Float64
	conv.ArchivedAt = archived.String
	return conv, nil
}

func (s *conversationStore) loadTurns(conversationID string) ([]conversationTurn, error) {
	rows, err := s.db.Query(`SELECT id, conversation_id, ordinal, client_turn_id, prompt, run_id,
		provider, vendor_session_id, status, started_at, completed_at, error_message,
		baseline_start_oid, baseline_end_oid, attachments_json
		FROM conversation_turns WHERE conversation_id = ? ORDER BY ordinal ASC`, conversationID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var turns []conversationTurn
	for rows.Next() {
		var (
			t               conversationTurn
			vendorSessionID sql.NullString
			completedAt     sql.NullString
			errorMessage    sql.NullString
			startOID        sql.NullString
			endOID          sql.NullString
			attachmentsJSON string
		)
		if err := rows.Scan(&t.ID, &t.ConversationID, &t.Ordinal, &t.ClientTurnID, &t.Prompt, &t.RunID,
			&t.Provider, &vendorSessionID, &t.Status, &t.StartedAt, &completedAt, &errorMessage,
			&startOID, &endOID, &attachmentsJSON); err != nil {
			return nil, err
		}
		t.VendorSessionID = vendorSessionID.String
		t.CompletedAt = completedAt.String
		t.ErrorMessage = errorMessage.String
		t.BaselineStartOID = startOID.String
		t.BaselineEndOID = endOID.String
		atts, err := decodeAttachmentsJSON(attachmentsJSON)
		if err != nil {
			return nil, fmt.Errorf("conversation_store: turn %q attachments_json: %w", t.ID, err)
		}
		t.Attachments = atts
		turns = append(turns, t)
	}
	return turns, rows.Err()
}

func (s *conversationStore) loadArtifacts(conversationID string) ([]conversationArtifact, error) {
	rows, err := s.db.Query(`SELECT id, conversation_id, turn_id, run_id, kind, title, summary,
		payload_json, status, created_at, updated_at
		FROM conversation_artifacts WHERE conversation_id = ? ORDER BY created_at ASC, id ASC`, conversationID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var artifacts []conversationArtifact
	for rows.Next() {
		var (
			a       conversationArtifact
			turnID  sql.NullString
			summary sql.NullString
		)
		if err := rows.Scan(&a.ID, &a.ConversationID, &turnID, &a.RunID, &a.Kind, &a.Title, &summary,
			&a.PayloadJSON, &a.Status, &a.CreatedAt, &a.UpdatedAt); err != nil {
			return nil, err
		}
		a.TurnID = turnID.String
		a.Summary = summary.String
		artifacts = append(artifacts, a)
	}
	return artifacts, rows.Err()
}

func (s *conversationStore) loadEvents(conversationID string, sinceSeq int64, limit int) ([]conversationEvent, bool, error) {
	rows, err := s.db.Query(`SELECT conversation_id, seq, turn_id, run_id, kind, role, stream, text,
		payload_json, created_at
		FROM conversation_events WHERE conversation_id = ? AND seq > ?
		ORDER BY seq ASC LIMIT ?`, conversationID, sinceSeq, limit+1)
	if err != nil {
		return nil, false, err
	}
	defer rows.Close()

	var events []conversationEvent
	for rows.Next() {
		var (
			e           conversationEvent
			turnID      sql.NullString
			runID       sql.NullString
			role        sql.NullString
			stream      sql.NullString
			text        sql.NullString
			payloadJSON sql.NullString
		)
		if err := rows.Scan(&e.ConversationID, &e.Seq, &turnID, &runID, &e.Kind, &role, &stream, &text,
			&payloadJSON, &e.CreatedAt); err != nil {
			return nil, false, err
		}
		e.TurnID = turnID.String
		e.RunID = runID.String
		e.Role = role.String
		e.Stream = stream.String
		e.Text = text.String
		e.PayloadJSON = payloadJSON.String
		events = append(events, e)
	}
	if err := rows.Err(); err != nil {
		return nil, false, err
	}

	hasMore := len(events) > limit
	if hasMore {
		events = events[:limit]
	}
	return events, hasMore, nil
}

// --- beginTurn ----------------------------------------------------------

// beginTurn is the store-layer half of agent.conversations.append: it either
// creates a new conversation with its first turn (ConversationID == "") or
// appends a follow-up turn to an existing one. Two safety properties matter:
//
//   - Idempotent clientTurnId: a retried append with the same ClientTurnID
//     returns the already-persisted turn/run rather than creating a duplicate.
//   - baseSeq conflict detection: a follow-up whose BaseSeq no longer matches
//     the conversation's current last_seq is rejected with status "conflict"
//     rather than silently applied, per the append-first ledger semantics.
func (s *conversationStore) beginTurn(req conversationAppendRequest, resolvedCWD string, runID string) (conversationAppendResult, error) {
	if strings.TrimSpace(req.Prompt) == "" {
		return conversationAppendResult{}, fmt.Errorf("conversation_store: prompt is required")
	}
	if req.ClientTurnID == "" {
		return conversationAppendResult{}, fmt.Errorf("conversation_store: clientTurnId is required")
	}
	if runID == "" {
		return conversationAppendResult{}, fmt.Errorf("conversation_store: runID is required")
	}

	tx, err := s.db.Begin()
	if err != nil {
		return conversationAppendResult{}, err
	}
	defer func() { _ = tx.Rollback() }()

	if existing, ok, err := existingTurnByClientTurnID(tx, req.ClientTurnID); err != nil {
		return conversationAppendResult{}, err
	} else if ok {
		conv, err := scanConversationRow(tx.QueryRow(conversationSelectByID, existing.conversationID))
		if err != nil {
			return conversationAppendResult{}, err
		}
		return conversationAppendResult{
			Status:         "started",
			ConversationID: existing.conversationID,
			TurnID:         existing.id,
			RunID:          existing.runID,
			CWD:            conv.CWD,
			BaseSeq:        req.BaseSeq,
			NextSeq:        conv.LastSeq,
		}, nil
	}

	attachmentsJSON, err := encodeAttachmentsJSON(req.Attachments)
	if err != nil {
		return conversationAppendResult{}, err
	}

	now := conversationNow()

	if req.ConversationID == "" {
		res, err := s.createConversationAndFirstTurn(tx, req, resolvedCWD, runID, now, attachmentsJSON)
		if err != nil {
			return conversationAppendResult{}, err
		}
		if err := tx.Commit(); err != nil {
			return conversationAppendResult{}, err
		}
		return res, nil
	}

	conv, err := scanConversationRow(tx.QueryRow(conversationSelectByID, req.ConversationID))
	if err != nil {
		if err == sql.ErrNoRows {
			return conversationAppendResult{}, fmt.Errorf("conversation_store: conversation %q not found", req.ConversationID)
		}
		return conversationAppendResult{}, err
	}

	if req.BaseSeq != conv.LastSeq {
		return conversationAppendResult{
			Status:         "conflict",
			ConversationID: req.ConversationID,
			BaseSeq:        req.BaseSeq,
			NextSeq:        conv.LastSeq,
			Message:        "Conversation changed. Refetch before appending.",
		}, nil
	}

	res, err := s.appendFollowUpTurn(tx, req, conv, runID, now, attachmentsJSON)
	if err != nil {
		return conversationAppendResult{}, err
	}
	if err := tx.Commit(); err != nil {
		return conversationAppendResult{}, err
	}
	return res, nil
}

type existingTurnRef struct {
	id             string
	conversationID string
	runID          string
}

func existingTurnByClientTurnID(tx *sql.Tx, clientTurnID string) (existingTurnRef, bool, error) {
	var ref existingTurnRef
	err := tx.QueryRow(`SELECT id, conversation_id, run_id FROM conversation_turns
		WHERE client_turn_id = ? LIMIT 1`, clientTurnID).Scan(&ref.id, &ref.conversationID, &ref.runID)
	if err == sql.ErrNoRows {
		return existingTurnRef{}, false, nil
	}
	if err != nil {
		return existingTurnRef{}, false, err
	}
	return ref, true, nil
}

func (s *conversationStore) createConversationAndFirstTurn(tx *sql.Tx, req conversationAppendRequest, resolvedCWD, runID, now, attachmentsJSON string) (conversationAppendResult, error) {
	convID := "conv_" + newUUID()
	provider := req.Agent
	hostName, _ := os.Hostname()

	_, err := tx.Exec(`INSERT INTO conversations
		(id, title, provider, agent_id, host_id, host_name, cwd, model, budget_usd, state, source,
		 created_at, updated_at, last_activity_at, last_seq)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'active', 'phone', ?, ?, ?, 0)`,
		convID, deriveTitle(req.Prompt), provider, provider, s.hostID, hostName, resolvedCWD,
		nullIfEmpty(req.Model), nullIfZero(req.BudgetUSD), now, now, now)
	if err != nil {
		return conversationAppendResult{}, err
	}

	var newSeq int64
	if err := tx.QueryRow(`UPDATE conversations SET last_seq = last_seq + 1, updated_at = ?, last_activity_at = ?
		WHERE id = ? RETURNING last_seq`, now, now, convID).Scan(&newSeq); err != nil {
		return conversationAppendResult{}, err
	}

	turnID := "turn_" + newUUID()
	if _, err := tx.Exec(`INSERT INTO conversation_turns
		(id, conversation_id, ordinal, client_turn_id, prompt, run_id, provider, status, started_at, attachments_json)
		VALUES (?, ?, 1, ?, ?, ?, ?, 'running', ?, ?)`,
		turnID, convID, req.ClientTurnID, req.Prompt, runID, provider, now, attachmentsJSON); err != nil {
		return conversationAppendResult{}, err
	}

	if _, err := tx.Exec(`INSERT INTO conversation_events
		(conversation_id, seq, turn_id, run_id, kind, created_at)
		VALUES (?, ?, ?, ?, 'turn_started', ?)`,
		convID, newSeq, turnID, runID, now); err != nil {
		return conversationAppendResult{}, err
	}

	return conversationAppendResult{
		Status:         "started",
		ConversationID: convID,
		TurnID:         turnID,
		RunID:          runID,
		CWD:            resolvedCWD,
		BaseSeq:        0,
		NextSeq:        newSeq,
	}, nil
}

func (s *conversationStore) appendFollowUpTurn(tx *sql.Tx, req conversationAppendRequest, conv conversationSummary, runID, now, attachmentsJSON string) (conversationAppendResult, error) {
	var ordinal int
	if err := tx.QueryRow(`SELECT COALESCE(MAX(ordinal), 0) + 1 FROM conversation_turns
		WHERE conversation_id = ?`, conv.ID).Scan(&ordinal); err != nil {
		return conversationAppendResult{}, err
	}

	provider := req.Agent
	if provider == "" {
		provider = conv.Provider
	}
	cwd := req.CWD
	if cwd == "" {
		cwd = conv.CWD
	}

	var newSeq int64
	if err := tx.QueryRow(`UPDATE conversations SET last_seq = last_seq + 1, updated_at = ?, last_activity_at = ?
		WHERE id = ? RETURNING last_seq`, now, now, conv.ID).Scan(&newSeq); err != nil {
		return conversationAppendResult{}, err
	}

	turnID := "turn_" + newUUID()
	if _, err := tx.Exec(`INSERT INTO conversation_turns
		(id, conversation_id, ordinal, client_turn_id, prompt, run_id, provider, status, started_at, attachments_json)
		VALUES (?, ?, ?, ?, ?, ?, ?, 'running', ?, ?)`,
		turnID, conv.ID, ordinal, req.ClientTurnID, req.Prompt, runID, provider, now, attachmentsJSON); err != nil {
		return conversationAppendResult{}, err
	}

	if _, err := tx.Exec(`INSERT INTO conversation_events
		(conversation_id, seq, turn_id, run_id, kind, created_at)
		VALUES (?, ?, ?, ?, 'turn_started', ?)`,
		conv.ID, newSeq, turnID, runID, now); err != nil {
		return conversationAppendResult{}, err
	}

	return conversationAppendResult{
		Status:         "started",
		ConversationID: conv.ID,
		TurnID:         turnID,
		RunID:          runID,
		CWD:            cwd,
		BaseSeq:        req.BaseSeq,
		NextSeq:        newSeq,
	}, nil
}

func deriveTitle(prompt string) string {
	title := strings.Join(strings.Fields(prompt), " ")
	const maxRunes = 80
	runes := []rune(title)
	if len(runes) > maxRunes {
		title = string(runes[:maxRunes])
	}
	if title == "" {
		title = "New conversation"
	}
	return title
}

func nullIfEmpty(s string) any {
	if s == "" {
		return nil
	}
	return s
}

func nullIfZero(f float64) any {
	if f == 0 {
		return nil
	}
	return f
}

// Storage-layer string bounds for attachment metadata JSON. Count and per-file
// byte limits reuse attachmentMaxFiles / attachmentMaxBytes from attachment_rpc.go.
const (
	attachmentMetaMaxIDLen              = 1024 // stable UUIDs / client ids
	attachmentMetaMaxNameLen            = 4096 // display filenames
	attachmentMetaMaxHostPathLen        = 4096 // daemon attachment paths
	attachmentMetaMaxPreviewCacheKeyLen = 1024 // phone preview cache keys
	attachmentMetaMaxMimeTypeLen        = 256  // MIME type strings
)

// encodeAttachmentsJSON validates attachment metadata for safe storage and
// returns the JSON blob for conversation_turns.attachments_json. nil/empty
// input becomes "[]". Does not open hostPath or log paths. New outgoing
// attachments require a valid contentDigest (server-issued at attachment.put).
func encodeAttachmentsJSON(atts []conversationAttachmentReference) (string, error) {
	if len(atts) == 0 {
		return "[]", nil
	}
	if len(atts) > attachmentMaxFiles {
		return "", fmt.Errorf("conversation_store: at most %d attachments per turn", attachmentMaxFiles)
	}
	for i, a := range atts {
		if err := validateAttachmentReference(a, true); err != nil {
			return "", fmt.Errorf("conversation_store: attachments[%d]: %w", i, err)
		}
	}
	b, err := json.Marshal(atts)
	if err != nil {
		return "", fmt.Errorf("conversation_store: marshal attachments: %w", err)
	}
	return string(b), nil
}

// validateAttachmentReference checks structural bounds. When requireDigest is
// true (new outgoing / encode path), contentDigest must be a lowercase 64-hex
// SHA-256. When false (decode of historical rows), empty digest is allowed.
func validateAttachmentReference(a conversationAttachmentReference, requireDigest bool) error {
	if strings.TrimSpace(a.ID) == "" {
		return fmt.Errorf("id is required")
	}
	if len(a.ID) > attachmentMetaMaxIDLen {
		return fmt.Errorf("id exceeds maximum length")
	}
	if strings.TrimSpace(a.Name) == "" {
		return fmt.Errorf("name is required")
	}
	if len(a.Name) > attachmentMetaMaxNameLen {
		return fmt.Errorf("name exceeds maximum length")
	}
	if len(a.MimeType) > attachmentMetaMaxMimeTypeLen {
		return fmt.Errorf("mimeType exceeds maximum length")
	}
	if strings.TrimSpace(a.HostPath) == "" {
		return fmt.Errorf("hostPath is required")
	}
	if len(a.HostPath) > attachmentMetaMaxHostPathLen {
		return fmt.Errorf("hostPath exceeds maximum length")
	}
	if strings.TrimSpace(a.PreviewCacheKey) == "" {
		return fmt.Errorf("previewCacheKey is required")
	}
	if len(a.PreviewCacheKey) > attachmentMetaMaxPreviewCacheKeyLen {
		return fmt.Errorf("previewCacheKey exceeds maximum length")
	}
	if a.ByteCount < 0 {
		return fmt.Errorf("byteCount must be nonnegative")
	}
	if a.ByteCount > attachmentMaxBytes {
		return fmt.Errorf("byteCount exceeds %d byte limit", attachmentMaxBytes)
	}
	switch a.Kind {
	case "image", "file":
	default:
		return fmt.Errorf("kind must be \"image\" or \"file\"")
	}
	digest := strings.TrimSpace(a.ContentDigest)
	if requireDigest {
		if !isValidContentDigest(digest) {
			return fmt.Errorf("contentDigest is required (64-char lowercase hex SHA-256 from attachment.put)")
		}
	} else if digest != "" && !isValidContentDigest(digest) {
		return fmt.Errorf("contentDigest is invalid")
	}
	return nil
}

// decodeAttachmentsJSON parses a persisted attachments_json column. Missing,
// empty, or JSON-null payloads yield a non-nil empty slice so fetch callers
// never see nil Attachments. Historical rows without contentDigest decode
// successfully (backward read compatibility); dispatch fails closed later.
// Semantically invalid elements fail with a generic error that does not echo
// host paths or other secrets.
func decodeAttachmentsJSON(raw string) ([]conversationAttachmentReference, error) {
	trimmed := strings.TrimSpace(raw)
	if trimmed == "" || trimmed == "null" {
		return []conversationAttachmentReference{}, nil
	}
	var atts []conversationAttachmentReference
	if err := json.Unmarshal([]byte(trimmed), &atts); err != nil {
		return nil, fmt.Errorf("invalid attachment metadata")
	}
	if atts == nil {
		return []conversationAttachmentReference{}, nil
	}
	for i, a := range atts {
		if err := validateAttachmentReference(a, false); err != nil {
			return nil, fmt.Errorf("attachments[%d]: invalid attachment metadata", i)
		}
	}
	return atts, nil
}

// --- appendRunOutput / appendRunStatus / bindVendorSession / upsertArtifact --

// appendRunOutput records one chunk of a run's stdout/stderr as an immutable
// conversation_events row. seq is the caller-assigned position in the RUN's
// own chunk sequence (streamJSONOutput's per-run counter, used by the phone
// for live in-run ordering only) — it plays no part in ledger placement.
// The ledger seq is allocated here from the conversation's own sequence
// space (conversations.last_seq), the same idiom appendRunStatus uses,
// because the conversation ledger had already spent low seqs on
// turn_started/status events before any output chunk arrives; reusing the
// run-local chunk seq as the ledger seq collided with those rows and
// silently dropped early chunks via ON CONFLICT DO NOTHING (2026-07-09).
// persistConversationEvent (server.go) calls this exactly once per emitted
// notification, in-process, off a single per-run goroutine with no replay/
// redelivery path, so no dedupe is needed at this layer.
func (s *conversationStore) appendRunOutput(runID, stream, chunk string, seq int) error {
	convID, turnID, err := s.turnByRunID(runID)
	if err != nil {
		return err
	}
	now := conversationNow()

	tx, err := s.db.Begin()
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback() }()

	var newSeq int64
	if err := tx.QueryRow(`UPDATE conversations SET last_seq = last_seq + 1, updated_at = ?, last_activity_at = ?
		WHERE id = ? RETURNING last_seq`, now, now, convID).Scan(&newSeq); err != nil {
		return err
	}

	if _, err := tx.Exec(`INSERT INTO conversation_events
		(conversation_id, seq, turn_id, run_id, kind, stream, text, created_at)
		VALUES (?, ?, ?, ?, 'output', ?, ?, ?)`,
		convID, newSeq, turnID, runID, stream, chunk, now); err != nil {
		return err
	}

	return tx.Commit()
}

// appendRunStatus updates the owning turn's status (and completed_at/
// error_message for terminal states) and appends a status event allocated at
// the next conversation-level sequence number.
func (s *conversationStore) appendRunStatus(runID, status string, exitCode *int, errorMessage string) error {
	convID, turnID, err := s.turnByRunID(runID)
	if err != nil {
		return err
	}
	now := conversationNow()

	tx, err := s.db.Begin()
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback() }()

	if isTerminalRunStatus(status) {
		msg := truncateRunErrorMessage(errorMessage)
		if msg == "" && status == "failed" && exitCode != nil && *exitCode != 0 {
			msg = fmt.Sprintf("Run failed with exit code %d", *exitCode)
		}
		if msg != "" {
			if _, err := tx.Exec(`UPDATE conversation_turns SET status = ?, completed_at = ?, error_message = ? WHERE run_id = ?`,
				status, now, msg, runID); err != nil {
				return err
			}
		} else if _, err := tx.Exec(`UPDATE conversation_turns SET status = ?, completed_at = ? WHERE run_id = ?`,
			status, now, runID); err != nil {
			return err
		}
	} else {
		if _, err := tx.Exec(`UPDATE conversation_turns SET status = ? WHERE run_id = ?`, status, runID); err != nil {
			return err
		}
	}

	payload := map[string]any{"status": status}
	if exitCode != nil {
		payload["exitCode"] = *exitCode
	}
	payloadJSON, err := json.Marshal(payload)
	if err != nil {
		return err
	}

	var newSeq int64
	if err := tx.QueryRow(`UPDATE conversations SET last_seq = last_seq + 1, updated_at = ?, last_activity_at = ?
		WHERE id = ? RETURNING last_seq`, now, now, convID).Scan(&newSeq); err != nil {
		return err
	}

	if _, err := tx.Exec(`INSERT INTO conversation_events
		(conversation_id, seq, turn_id, run_id, kind, payload_json, created_at)
		VALUES (?, ?, ?, ?, 'status', ?, ?)`,
		convID, newSeq, turnID, runID, string(payloadJSON), now); err != nil {
		return err
	}

	return tx.Commit()
}

// appendRunReceipt records the finalized lancer.proof/v0 payload for a
// terminal run so agent.conversations.fetch can replay it after reconnect.
func (s *conversationStore) appendRunReceipt(runID, receiptJSON string) error {
	convID, turnID, err := s.turnByRunID(runID)
	if err != nil {
		return err
	}
	now := conversationNow()

	tx, err := s.db.Begin()
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback() }()

	var newSeq int64
	if err := tx.QueryRow(`UPDATE conversations SET last_seq = last_seq + 1, updated_at = ?, last_activity_at = ?
		WHERE id = ? RETURNING last_seq`, now, now, convID).Scan(&newSeq); err != nil {
		return err
	}

	if _, err := tx.Exec(`INSERT INTO conversation_events
		(conversation_id, seq, turn_id, run_id, kind, payload_json, created_at)
		VALUES (?, ?, ?, ?, 'receipt', ?, ?)`,
		convID, newSeq, turnID, runID, receiptJSON, now); err != nil {
		return err
	}

	return tx.Commit()
}

func isTerminalRunStatus(status string) bool {
	switch status {
	// "exited" is the process-lifecycle terminal status emitRunStatus writes
	// on success (dispatch.go). Omitting it left successful turns without
	// completed_at and made phone poll-sync treat them as still running.
	case "completed", "exited", "failed", "cancelled", "error", "denied", "budgetExceeded":
		return true
	default:
		return false
	}
}

const maxRunErrorMessageLen = 500

func truncateRunErrorMessage(msg string) string {
	msg = strings.TrimSpace(msg)
	if len(msg) <= maxRunErrorMessageLen {
		return msg
	}
	return msg[len(msg)-maxRunErrorMessageLen:]
}

// bindVendorSession records the exact vendor CLI session/thread ID for a run's
// turn, once the daemon has extracted it from the CLI's structured output. This
// is what lets a later follow-up use resumeArgv (exact resume) instead of
// falling back to "continue latest in cwd".
func (s *conversationStore) bindVendorSession(runID, vendorSessionID string) error {
	res, err := s.db.Exec(`UPDATE conversation_turns SET vendor_session_id = ? WHERE run_id = ?`,
		vendorSessionID, runID)
	if err != nil {
		return err
	}
	n, err := res.RowsAffected()
	if err != nil {
		return err
	}
	if n == 0 {
		return fmt.Errorf("conversation_store: no turn found for run %q", runID)
	}
	return nil
}

// setArchived toggles a conversation's archived_at timestamp and appends an
// "archived"/"unarchived" event at the next conversation-level sequence
// number, so the state change itself is visible in the event log like any
// other conversation-level change. Added for the agent.conversations.archive
// RPC (Task 2 of the cross-device sync build handoff) — Task 1's interface
// list didn't include an archive method, and a store-less stub would have
// meant either faking success without persisting anything or silently no-op
// RPCs, so this is a small additive method rather than a change to any
// existing behavior.
func (s *conversationStore) setArchived(conversationID string, archived bool) (int64, error) {
	tx, err := s.db.Begin()
	if err != nil {
		return 0, err
	}
	defer func() { _ = tx.Rollback() }()

	if _, err := scanConversationRow(tx.QueryRow(conversationSelectByID, conversationID)); err != nil {
		if err == sql.ErrNoRows {
			return 0, fmt.Errorf("conversation_store: conversation %q not found", conversationID)
		}
		return 0, err
	}

	now := conversationNow()
	var archivedAt any
	kind := "unarchived"
	if archived {
		archivedAt = now
		kind = "archived"
	}

	var newSeq int64
	if err := tx.QueryRow(`UPDATE conversations SET archived_at = ?, updated_at = ?, last_activity_at = ?,
		last_seq = last_seq + 1 WHERE id = ? RETURNING last_seq`,
		archivedAt, now, now, conversationID).Scan(&newSeq); err != nil {
		return 0, err
	}

	if _, err := tx.Exec(`INSERT INTO conversation_events (conversation_id, seq, kind, created_at)
		VALUES (?, ?, ?, ?)`, conversationID, newSeq, kind, now); err != nil {
		return 0, err
	}

	if err := tx.Commit(); err != nil {
		return 0, err
	}
	return newSeq, nil
}

// upsertArtifact inserts or updates a conversation_artifacts row from a loosely
// typed event map (the shape emitted by the "agent.artifact" notification).
// Recognized keys accept both camelCase (wire) and snake_case spellings. Events
// missing an "id" get a generated one, so accidental repeated calls without an
// id do not collide with each other on conflict.
func (s *conversationStore) upsertArtifact(event map[string]any) error {
	id := stringFromMap(event, "id", "artifactId", "artifact_id")
	if id == "" {
		id = "artifact_" + newUUID()
	}
	conversationID := stringFromMap(event, "conversationId", "conversation_id")
	if conversationID == "" {
		return fmt.Errorf("conversation_store: upsertArtifact requires conversationId")
	}
	turnID := stringFromMap(event, "turnId", "turn_id")
	runID := stringFromMap(event, "runId", "run_id")
	kind := stringFromMap(event, "kind")
	title := stringFromMap(event, "title")
	summary := stringFromMap(event, "summary")
	status := stringFromMap(event, "status")
	if status == "" {
		status = "ready"
	}
	payloadJSON := stringFromMap(event, "payloadJson", "payload_json")
	if payloadJSON == "" {
		if raw, ok := event["payload"]; ok {
			b, err := json.Marshal(raw)
			if err != nil {
				return err
			}
			payloadJSON = string(b)
		}
	}

	now := conversationNow()
	_, err := s.db.Exec(`INSERT INTO conversation_artifacts
		(id, conversation_id, turn_id, run_id, kind, title, summary, payload_json, status, created_at, updated_at)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
		ON CONFLICT(id) DO UPDATE SET
			turn_id = excluded.turn_id,
			run_id = excluded.run_id,
			kind = excluded.kind,
			title = excluded.title,
			summary = excluded.summary,
			payload_json = excluded.payload_json,
			status = excluded.status,
			updated_at = excluded.updated_at`,
		id, conversationID, nullIfEmpty(turnID), runID, kind, title, nullIfEmpty(summary), payloadJSON, status, now, now)
	return err
}

func stringFromMap(m map[string]any, keys ...string) string {
	for _, k := range keys {
		if v, ok := m[k]; ok && v != nil {
			if s, ok := v.(string); ok {
				return s
			}
			return fmt.Sprintf("%v", v)
		}
	}
	return ""
}

// conversationByID returns the conversation summary row only (no turns/
// events/artifacts) — a lighter read than fetch for callers (like Task 3's
// dispatch integration in conversation_rpc.go) that only need agent/cwd/
// model/budget defaults for a follow-up.
func (s *conversationStore) conversationByID(conversationID string) (conversationSummary, error) {
	return scanConversationRow(s.db.QueryRow(conversationSelectByID, conversationID))
}

// setTurnBaselineStart stores the shadow tree OID stamped at turn start.
func (s *conversationStore) setTurnBaselineStart(turnID, oid string) error {
	_, err := s.db.Exec(`UPDATE conversation_turns SET baseline_start_oid = ? WHERE id = ?`, oid, turnID)
	return err
}

// setTurnBaselineEnd stores the shadow tree OID stamped at turn end.
func (s *conversationStore) setTurnBaselineEnd(turnID, oid string) error {
	_, err := s.db.Exec(`UPDATE conversation_turns SET baseline_end_oid = ? WHERE id = ?`, oid, turnID)
	return err
}

// turnBaselineOIDs returns start/end shadow tree OIDs for a turn belonging to
// conversationID. sql.ErrNoRows when the turn is missing or mismatched.
func (s *conversationStore) turnBaselineOIDs(conversationID, turnID string) (startOID, endOID string, err error) {
	var start, end sql.NullString
	err = s.db.QueryRow(`SELECT baseline_start_oid, baseline_end_oid FROM conversation_turns
		WHERE id = ? AND conversation_id = ?`, turnID, conversationID).Scan(&start, &end)
	if err != nil {
		return "", "", err
	}
	return start.String, end.String, nil
}

// firstTurnBaselineStart returns the earliest turn's baseline_start_oid for a
// conversation (session-diff baseline), or "" when none is stamped.
func (s *conversationStore) firstTurnBaselineStart(conversationID string) (string, error) {
	var oid sql.NullString
	err := s.db.QueryRow(`SELECT baseline_start_oid FROM conversation_turns
		WHERE conversation_id = ? ORDER BY ordinal ASC LIMIT 1`, conversationID).Scan(&oid)
	if err == sql.ErrNoRows {
		return "", nil
	}
	if err != nil {
		return "", err
	}
	return oid.String, nil
}

// latestVendorSessionID returns the most recently bound vendor session id
// across a conversation's turns (most recent ordinal first), or "" if no turn
// has one yet. This is what lets agent.conversations.append choose resumeArgv
// (exact resume, resumeMode "exact") over continueArgv (resumeMode
// "latestInCwdFallback") — see the cross-device sync build handoff's Task 3.
func (s *conversationStore) latestVendorSessionID(conversationID string) (string, error) {
	var vendorSessionID sql.NullString
	err := s.db.QueryRow(`SELECT vendor_session_id FROM conversation_turns
		WHERE conversation_id = ? AND vendor_session_id IS NOT NULL AND vendor_session_id != ''
		ORDER BY ordinal DESC LIMIT 1`, conversationID).Scan(&vendorSessionID)
	if err == sql.ErrNoRows {
		return "", nil
	}
	if err != nil {
		return "", err
	}
	return vendorSessionID.String, nil
}

func (s *conversationStore) turnByRunID(runID string) (conversationID, turnID string, err error) {
	err = s.db.QueryRow(`SELECT conversation_id, id FROM conversation_turns WHERE run_id = ?`, runID).
		Scan(&conversationID, &turnID)
	if err == sql.ErrNoRows {
		return "", "", fmt.Errorf("%w %q", errNoLedgerTurn, runID)
	}
	return conversationID, turnID, err
}

// latestRunningRunID returns the run_id of the most recent turn still marked
// 'running' whose conversation matches cwd+agent. Used to correlate hook-
// originated approvals when no in-memory dispatch is registered. Returns ""
// when none match — never invents an ID.
func (s *conversationStore) latestRunningRunID(cwd, agent string) string {
	if s == nil {
		return ""
	}
	wantCWD := expandHome(cwd)
	wantAgent := normalizeAgentSource(agent)
	if wantCWD == "" || wantAgent == "" {
		return ""
	}
	var runID string
	err := s.db.QueryRow(`
		SELECT t.run_id FROM conversation_turns t
		JOIN conversations c ON c.id = t.conversation_id
		WHERE t.status = 'running'
		  AND c.cwd = ?
		  AND (c.agent_id = ? OR c.provider = ?)
		ORDER BY t.started_at DESC, t.ordinal DESC
		LIMIT 1`, wantCWD, wantAgent, wantAgent).Scan(&runID)
	if err != nil {
		return ""
	}
	return runID
}

// --- attachObservedSession (Task 9) -----------------------------------------

// conversationImportResult mirrors what attachObservedSession can determine at
// the store layer — conversation_rpc.go maps this onto the
// agent.conversations.attachObservedSession wire response.
type conversationImportResult struct {
	ConversationID  string
	TurnID          string
	RunID           string
	ImportedEvents  int
	LastSeq         int64
	AlreadyAttached bool
}

// attachObservedSession imports an already-observed CLI session's transcript
// (e.g. a Claude Code session the user ran directly in a terminal, never
// dispatched through agent.conversations.append) into the host ledger as one
// or more already-completed turns (segmented at each real user prompt), so it
// shows up and can be continued like any other host-mediated conversation —
// importantly, binding vendorSessionID means a follow-up append on the
// resulting conversation gets exact resume (resumeArgv), not just "latest in cwd".
//
// Idempotent: re-attaching the same provider+sessionID returns the
// conversation the FIRST call created rather than importing a second copy.
// This reuses beginTurn's exact replay mechanism — a deterministic
// clientTurnId ("observed:<provider>:<sessionId>") looked up via
// existingTurnByClientTurnID — rather than a parallel one, since both are
// "has this exact external event already been recorded?" checks.
func (s *conversationStore) attachObservedSession(provider, sessionID, cwd, title string, messages []SessionMessage) (conversationImportResult, error) {
	if provider == "" || sessionID == "" {
		return conversationImportResult{}, fmt.Errorf("conversation_store: provider and sessionId are required")
	}
	clientTurnID := "observed:" + provider + ":" + sessionID

	tx, err := s.db.Begin()
	if err != nil {
		return conversationImportResult{}, err
	}
	defer func() { _ = tx.Rollback() }()

	if existing, ok, err := existingTurnByClientTurnID(tx, clientTurnID); err != nil {
		return conversationImportResult{}, err
	} else if ok {
		conv, err := scanConversationRow(tx.QueryRow(conversationSelectByID, existing.conversationID))
		if err != nil {
			return conversationImportResult{}, err
		}
		return conversationImportResult{
			ConversationID:  existing.conversationID,
			TurnID:          existing.id,
			RunID:           existing.runID,
			LastSeq:         conv.LastSeq,
			AlreadyAttached: true,
		}, nil
	}

	now := conversationNow()
	convID := "conv_" + newUUID()
	hostName, _ := os.Hostname()

	convTitle := title
	if convTitle != "" {
		convTitle = deriveTitle(convTitle)
	} else {
		convTitle = firstUserMessagePreview(messages)
	}
	if convTitle == "" {
		convTitle = "Imported session"
	}

	if _, err := tx.Exec(`INSERT INTO conversations
		(id, title, provider, agent_id, host_id, host_name, cwd, state, source,
		 created_at, updated_at, last_activity_at, last_seq)
		VALUES (?, ?, ?, ?, ?, ?, ?, 'active', 'observedImport', ?, ?, ?, 0)`,
		convID, convTitle, provider, provider, s.hostID, hostName, cwd, now, now, now); err != nil {
		return conversationImportResult{}, err
	}

	segments := segmentObservedMessages(messages, convTitle)
	var seq int64
	var importedEvents int
	var firstTurnID, firstRunID, lastTurnID, lastRunID string

	for _, seg := range segments {
		turnID := "turn_" + newUUID()
		runID := "observed_" + newUUID()
		ctID := clientTurnID
		if seg.Ordinal > 1 {
			ctID = fmt.Sprintf("%s:%d", clientTurnID, seg.Ordinal)
		}
		if _, err := tx.Exec(`INSERT INTO conversation_turns
			(id, conversation_id, ordinal, client_turn_id, prompt, run_id, provider,
			 vendor_session_id, status, started_at, completed_at, attachments_json)
			VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'exited', ?, ?, '[]')`,
			turnID, convID, seg.Ordinal, ctID, seg.Prompt, runID, provider, sessionID, now, now); err != nil {
			return conversationImportResult{}, err
		}
		if firstTurnID == "" {
			firstTurnID = turnID
			firstRunID = runID
		}
		lastTurnID = turnID
		lastRunID = runID

		for _, msg := range seg.Outputs {
			seq++
			importedEvents++
			kind, role, text, payload := observedEventFields(msg)
			if _, err := tx.Exec(`INSERT INTO conversation_events
				(conversation_id, seq, turn_id, run_id, kind, role, text, payload_json, created_at)
				VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
				convID, seq, turnID, runID, kind, nullIfEmpty(role), text, nullIfEmpty(payload), now); err != nil {
				return conversationImportResult{}, err
			}
		}
	}

	if _, err := tx.Exec(`UPDATE conversations SET last_seq = ? WHERE id = ?`, seq, convID); err != nil {
		return conversationImportResult{}, err
	}

	if err := tx.Commit(); err != nil {
		return conversationImportResult{}, err
	}

	// Prefer the first turn for the idempotent clientTurnId binding surface;
	// fall back to last if somehow empty (shouldn't happen — segments always
	// yields ≥1 turn).
	outTurn, outRun := firstTurnID, firstRunID
	if outTurn == "" {
		outTurn, outRun = lastTurnID, lastRunID
	}
	return conversationImportResult{
		ConversationID: convID,
		TurnID:         outTurn,
		RunID:          outRun,
		ImportedEvents: importedEvents,
		LastSeq:        seq,
	}, nil
}

// observedTurnSegment is one imported turn: a prompt plus the assistant/tool
// output events that followed until the next real user message.
type observedTurnSegment struct {
	Ordinal int
	Prompt  string
	Outputs []SessionMessage
}

// segmentObservedMessages splits an observed transcript into turns. A new turn
// starts at each real user message (role=="user", non-empty text, not a
// Claude wrapper injection). Messages before the first real user prompt go
// under an initial turn whose prompt is fallbackPrompt (typically the derived
// conversation title). Always returns at least one turn so empty imports still
// bind vendorSessionID for exact resume.
func segmentObservedMessages(messages []SessionMessage, fallbackPrompt string) []observedTurnSegment {
	if fallbackPrompt == "" {
		fallbackPrompt = "Imported session"
	}

	var segments []observedTurnSegment
	var current *observedTurnSegment

	startTurn := func(prompt string) {
		segments = append(segments, observedTurnSegment{
			Ordinal: len(segments) + 1,
			Prompt:  prompt,
		})
		current = &segments[len(segments)-1]
	}

	for _, msg := range messages {
		if msg.Role == "user" && isObservedWrapperUserText(msg.Text) {
			continue
		}
		if isRealObservedUserPrompt(msg) {
			startTurn(msg.Text)
			continue
		}
		if current == nil {
			startTurn(fallbackPrompt)
		}
		current.Outputs = append(current.Outputs, msg)
	}

	if len(segments) == 0 {
		startTurn(fallbackPrompt)
	}
	return segments
}

// isObservedWrapperUserText reports Claude-injected user-role wrappers that
// must not become turn prompts or conversation titles.
func isObservedWrapperUserText(text string) bool {
	trimmed := strings.TrimSpace(text)
	return strings.HasPrefix(trimmed, "<local-command-caveat>") ||
		strings.HasPrefix(trimmed, "<command-name>") ||
		strings.HasPrefix(trimmed, "<command-message>") ||
		strings.HasPrefix(trimmed, "<system-reminder>") ||
		// Background-task completion envelopes (owner phone 2026-07-13: raw XML
		// bubbles + "(no reply text)" in long imported threads).
		strings.HasPrefix(trimmed, "<task-notification>")
}

func isRealObservedUserPrompt(m SessionMessage) bool {
	return m.Role == "user" && strings.TrimSpace(m.Text) != "" && !isObservedWrapperUserText(m.Text)
}

// observedEventFields maps a neutral SessionMessage onto a conversation_events
// row: structured tool/thinking kinds with payload_json, prose as kind=output.
func observedEventFields(msg SessionMessage) (kind, role, text, payloadJSON string) {
	switch msg.Role {
	case "toolCall":
		added, removed := computeEditStats(msg.ToolName, msg.InputJSON)
		var input any
		if msg.InputJSON != "" {
			_ = json.Unmarshal([]byte(msg.InputJSON), &input)
		}
		b, _ := json.Marshal(map[string]any{
			"name":      msg.ToolName,
			"toolUseId": msg.ToolUseID,
			"input":     input,
			"added":     added,
			"removed":   removed,
		})
		return "tool_call", msg.Role, clampText(msg.Text), string(b)
	case "toolResult":
		b, _ := json.Marshal(map[string]any{
			"toolUseId": msg.ToolUseID,
			"isError":   msg.IsError,
		})
		return "tool_result", msg.Role, clampText(msg.Text), string(b)
	case "thinking":
		return "thinking", msg.Role, clampText(msg.Text), ""
	default:
		return "output", msg.Role, msg.Text, ""
	}
}

// firstUserMessagePreview derives a short title/prompt-preview from the first
// real user-role message in an imported transcript (skipping Claude wrapper
// injections), falling back to "" (callers each have their own default for
// that case) when there is none.
func firstUserMessagePreview(messages []SessionMessage) string {
	for _, m := range messages {
		if isRealObservedUserPrompt(m) {
			return deriveTitle(m.Text)
		}
	}
	return ""
}

// runStatus returns a turn's current status column by its run id — used by
// agent.conversations.append's clientTurnId-replay path (conversation_rpc.go)
// to report the SAME outcome (started/needsApproval/denied/budgetExceeded/
// error) the original dispatch attempt actually had, rather than assuming
// "started" just because a ledger row exists. Read-only additive accessor;
// no schema change.
func (s *conversationStore) runStatus(runID string) (string, error) {
	var status string
	err := s.db.QueryRow(`SELECT status FROM conversation_turns WHERE run_id = ?`, runID).Scan(&status)
	if err == sql.ErrNoRows {
		return "", fmt.Errorf("conversation_store: no turn found for run %q", runID)
	}
	return status, err
}
