package main

import (
	"fmt"
	"path/filepath"
)

// conversation_rpc.go — wire-level request/response glue between the
// agent.conversations.* JSON-RPC methods (SSH transport, server.go's
// handleMessage switch) and the mirrored agentConversations* relay messages
// (e2e_router.go's handleMessage switch). Both transports call the exact same
// server methods defined below, so the payload shape is identical by
// construction rather than by convention — see conversation_rpc_test.go for
// tests that drive both paths and assert matching output.
//
// NOTE on agent.conversations.append (Task 3, cross-device sync build
// handoff): this handler persists a ledger row via conversationStore.beginTurn
// and dispatches the vendor CLI process via dispatcher.launchConversationTurn,
// choosing new/exact-resume/latest-in-cwd-fallback argv per
// buildConversationArgv (dispatch.go). A clientTurnId replay (beginTurn
// returns an existing turn rather than creating one) is detected by comparing
// the runID beginTurn returns against the one we minted for this call — if
// they differ, the original call already dispatched this turn, so we report
// its state without launching a second process.
//
// NOTE on agent.conversations.attachObservedSession (Task 9): imports an
// already-observed terminal session's transcript into the ledger as completed
// turns (segmented at each real user prompt) via
// conversationStore.attachObservedSession — a create-from-import path
// distinct from beginTurn's prompt/turn semantics. The transcript itself is
// read fresh from disk here (loadFullObservedTranscript, session_index.go)
// rather than accepting caller-supplied messages, so a phone can't inject
// arbitrary ledger content through this RPC.

// conversationListRequest mirrors the agent.conversations.list RPC request.
type conversationListRequest struct {
	Limit           int    `json:"limit"`
	Cursor          string `json:"cursor"`
	IncludeArchived bool   `json:"includeArchived"`
}

// conversationFetchRequest mirrors the agent.conversations.fetch RPC request.
type conversationFetchRequest struct {
	ConversationID string `json:"conversationId"`
	SinceSeq       int64  `json:"sinceSeq"`
	Limit          int    `json:"limit"`
}

// conversationAppendResponse is the full agent.conversations.append wire
// response — a superset of conversationAppendResult (conversation_store.go)
// with the fields that depend on vendor-dispatch knowledge the store layer
// intentionally doesn't have (see that type's doc comment).
//
// ClientTurnID is echoed from the request on every started/conflict/idempotent
// (and error-status) response so the phone can correlate append results to the
// waiter that owns that logical turn — without it, a late result for turn A
// can resolve an in-flight wait for turn B.
type conversationAppendResponse struct {
	Status          string `json:"status"`
	ConversationID  string `json:"conversationId"`
	TurnID          string `json:"turnId,omitempty"`
	RunID           string `json:"runId,omitempty"`
	VendorSessionID string `json:"vendorSessionId,omitempty"`
	CWD             string `json:"cwd,omitempty"`
	BaseSeq         int64  `json:"baseSeq"`
	NextSeq         int64  `json:"nextSeq"`
	ResumeMode      string `json:"resumeMode,omitempty"`
	Message         string `json:"message,omitempty"`
	Rule            string `json:"rule,omitempty"`
	WorktreePath    string `json:"worktreePath,omitempty"`
	Isolated        bool   `json:"isolated,omitempty"`
	ClientTurnID    string `json:"clientTurnId,omitempty"`
}

// conversationArchiveRequest mirrors the agent.conversations.archive RPC request.
type conversationArchiveRequest struct {
	ConversationID string `json:"conversationId"`
	Archived       bool   `json:"archived"`
}

// conversationArchiveResponse mirrors the agent.conversations.archive RPC response.
type conversationArchiveResponse struct {
	OK             bool   `json:"ok"`
	ConversationID string `json:"conversationId"`
	LastSeq        int64  `json:"lastSeq"`
}

// conversationAttachObservedSessionRequest mirrors the
// agent.conversations.attachObservedSession RPC request.
type conversationAttachObservedSessionRequest struct {
	Provider  string `json:"provider"`
	SessionID string `json:"sessionId"`
	CWD       string `json:"cwd"`
}

// conversationAttachObservedSessionResponse mirrors the
// agent.conversations.attachObservedSession RPC response.
type conversationAttachObservedSessionResponse struct {
	ConversationID  string `json:"conversationId"`
	ImportedEvents  int    `json:"importedEvents"`
	LastSeq         int64  `json:"lastSeq"`
	AlreadyAttached bool   `json:"alreadyAttached"`
}

// --- server methods shared by the SSH JSON-RPC switch (server.go) and the
// E2E relay switch (e2e_router.go). Keeping the logic here (not duplicated in
// each transport) is what guarantees the two paths return the same shape. ---

func (s *server) conversationsList(req conversationListRequest) (conversationListResult, error) {
	if s.conversations == nil {
		return conversationListResult{}, fmt.Errorf("conversation store unavailable")
	}
	return s.conversations.list(req.Limit, req.Cursor, req.IncludeArchived)
}

func (s *server) conversationsFetch(req conversationFetchRequest) (conversationFetchResult, error) {
	if s.conversations == nil {
		return conversationFetchResult{}, fmt.Errorf("conversation store unavailable")
	}
	if req.ConversationID == "" {
		return conversationFetchResult{}, fmt.Errorf("conversationId is required")
	}
	return s.conversations.fetch(req.ConversationID, req.SinceSeq, req.Limit)
}

func (s *server) conversationsAppend(req conversationAppendRequest) (conversationAppendResponse, error) {
	if s.conversations == nil {
		return conversationAppendResponse{}, fmt.Errorf("conversation store unavailable")
	}

	isNew := req.ConversationID == ""
	resolvedCWD := expandHome(req.CWD)
	if isNew && resolvedCWD == "" {
		resolvedCWD = expandHome("~")
	}
	// Validate before beginTurn so a relative/missing cwd cannot leave a
	// garbage ledger row when the later launch fails the same check.
	// resolveDispatchCWD only Stats the path — a relative cwd that happens to
	// exist under the daemon process's own working directory would pass and
	// persist verbatim, so reject non-absolute paths explicitly first.
	if resolvedCWD != "" && !filepath.IsAbs(resolvedCWD) {
		return conversationAppendResponse{}, fmt.Errorf("cwd must be an absolute path")
	}
	var err error
	resolvedCWD, err = resolveDispatchCWD(resolvedCWD)
	if err != nil {
		return conversationAppendResponse{}, err
	}

	runID := newUUID()
	var wt worktreeCreateResult
	if req.UseWorktree && isNew && resolvedCWD != "" {
		wt, err = s.createManagedWorktree(resolvedCWD, "", runID)
		if err != nil {
			return conversationAppendResponse{
				Status:       "error",
				Message:      err.Error(),
				ClientTurnID: req.ClientTurnID,
			}, nil
		}
		resolvedCWD = wt.Path
	}

	res, err := s.conversations.beginTurn(req, resolvedCWD, runID)
	if err != nil {
		return conversationAppendResponse{}, err
	}

	resp := conversationAppendResponse{
		Status:         res.Status,
		ConversationID: res.ConversationID,
		TurnID:         res.TurnID,
		RunID:          res.RunID,
		CWD:            res.CWD,
		BaseSeq:        res.BaseSeq,
		NextSeq:        res.NextSeq,
		Message:        res.Message,
		ClientTurnID:   req.ClientTurnID,
	}

	if res.Status != "started" {
		// conflict — beginTurn already rejected a stale baseSeq; nothing to dispatch.
		return resp, nil
	}

	if res.RunID != runID {
		// clientTurnId replay: beginTurn returned an EXISTING turn/run rather
		// than creating one under the runID we just minted. That original
		// call already dispatched (or is dispatching) this turn — launching
		// again here would double-run the CLI for one logical append.
		// Report the SAME outcome the original dispatch attempt actually had.
		// The turn row's status column uses PROCESS-lifecycle values (running/
		// completed/failed/cancelled) once a launch succeeds, but the RPC
		// contract's status vocabulary is started/needsApproval/denied/
		// budgetExceeded/error — only the latter set was ever explicitly
		// persisted onto the row below (a successful launch never overwrites
		// "running"), so treat anything else as "started" rather than leaking
		// the ledger's internal lifecycle vocabulary onto the wire.
		if actual, err := s.conversations.runStatus(res.RunID); err == nil {
			switch actual {
			case "needsApproval", "denied", "budgetExceeded", "error":
				resp.Status = actual
			default:
				resp.Status = "started"
			}
		}
		resp.ResumeMode = "none"
		if isNew {
			resp.ResumeMode = "new"
		} else if sid, _ := s.conversations.latestVendorSessionID(res.ConversationID); sid != "" {
			resp.ResumeMode = "exact"
			resp.VendorSessionID = sid
		} else {
			resp.ResumeMode = "latestInCwdFallback"
		}
		return resp, nil
	}

	// Fresh turn — stamp shadow git baseline before launch (never touches user index).
	s.stampTurnBaselinesForAppend(res.CWD, res.TurnID)

	// Fresh turn — dispatch it. A vendor session id already bound to an
	// EARLIER turn on this conversation (from a prior reply's captured
	// session/thread id) is what lets THIS follow-up use resumeArgv (exact
	// resume) instead of continueArgv (latest-in-cwd fallback).
	vendorSessionID, err := s.conversations.latestVendorSessionID(res.ConversationID)
	if err != nil {
		vendorSessionID = ""
	}

	// A follow-up's request legitimately omits "agent" (per the RPC contract,
	// it's inherited from the conversation) — mirror
	// conversation_store.appendFollowUpTurn's own fallback so the dispatched
	// argv uses the conversation's actual provider instead of an empty string.
	agent := req.Agent
	if agent == "" {
		if conv, err := s.conversations.conversationByID(res.ConversationID); err == nil {
			agent = conv.Provider
		}
	}

	launchCWD := res.CWD
	launchParams := conversationLaunchParams{
		Agent:           agent,
		CWD:             launchCWD,
		Prompt:          req.Prompt,
		Model:           req.Model,
		BudgetUSD:       req.BudgetUSD,
		VendorSessionID: vendorSessionID,
		IsNew:           isNew,
		Contract:        req.Contract,
		FullTools:       req.FullTools,
	}
	if wt.Path != "" {
		// Set on the run record inside launchConversationTurn() itself,
		// before launch — not after it returns — so a fast-exiting
		// process's terminal-status event can't race past the run's own
		// creation. See dispatch.go's identical fix for runDispatch.
		launchParams.worktreePath = wt.Path
		launchParams.worktreeRepoRoot = wt.RepoRoot
	}
	launchResult := s.dispatcher.launchConversationTurn(runID, launchParams, s.policyEffect, s.auditEntry)

	if wt.Path != "" {
		if launchResult.Status == "started" {
			resp.WorktreePath = wt.Path
			resp.Isolated = true
		} else {
			_, _ = s.removeManagedWorktree(wt.RepoRoot, wt.Path)
		}
	}

	// Persist the REAL outcome onto the turn row (best-effort — a failed
	// write here would only degrade a future clientTurnId replay's reported
	// status, not this call's own response) so a replay of this exact append
	// reports the same status instead of the ledger-only "started" beginTurn
	// itself always returns. appendRunStatus also appends a 'status' event,
	// which bumps the conversation's last_seq PAST what beginTurn returned —
	// re-read the authoritative value so this response's NextSeq (and thus
	// what the caller uses as their next baseSeq) isn't stale by one.
	if launchResult.Status != "" && launchResult.Status != "started" {
		if err := s.conversations.appendRunStatus(runID, launchResult.Status, nil, launchResult.Message); err == nil {
			if conv, err := s.conversations.conversationByID(res.ConversationID); err == nil {
				resp.NextSeq = conv.LastSeq
			}
		}
		if isTerminalRunStatus(launchResult.Status) {
			s.stampTurnBaselineEndForRun(runID, res.TurnID)
		}
	}

	resp.Status = launchResult.Status
	resp.Message = launchResult.Message
	if launchResult.CWD != "" {
		resp.CWD = launchResult.CWD
	}
	switch {
	case isNew:
		resp.ResumeMode = "new"
	case vendorSessionID != "":
		resp.ResumeMode = "exact"
		resp.VendorSessionID = vendorSessionID
	default:
		resp.ResumeMode = "latestInCwdFallback"
	}
	return resp, nil
}

func (s *server) conversationsArchive(req conversationArchiveRequest) (conversationArchiveResponse, error) {
	if s.conversations == nil {
		return conversationArchiveResponse{}, fmt.Errorf("conversation store unavailable")
	}
	if req.ConversationID == "" {
		return conversationArchiveResponse{}, fmt.Errorf("conversationId is required")
	}
	lastSeq, err := s.conversations.setArchived(req.ConversationID, req.Archived)
	if err != nil {
		return conversationArchiveResponse{}, err
	}
	return conversationArchiveResponse{OK: true, ConversationID: req.ConversationID, LastSeq: lastSeq}, nil
}

// conversationsAttachObservedSession imports an observed session's full
// on-disk transcript into the host ledger as completed turns (one per real
// user prompt). See the package doc comment above and
// conversationStore.attachObservedSession for the idempotency/exact-resume-
// binding contract.
func (s *server) conversationsAttachObservedSession(req conversationAttachObservedSessionRequest) (conversationAttachObservedSessionResponse, error) {
	if req.Provider == "" || req.SessionID == "" {
		return conversationAttachObservedSessionResponse{}, fmt.Errorf("provider and sessionId are required")
	}
	if s.conversations == nil {
		return conversationAttachObservedSessionResponse{}, fmt.Errorf("conversation store unavailable")
	}

	// Observed attach only requires a well-formed absolute cwd — the session
	// may reference a removed worktree, so existence is not required here
	// (unlike conversationsAppend / resolveDispatchCWD).
	resolvedCWD := expandHome(req.CWD)
	if resolvedCWD == "" || !filepath.IsAbs(resolvedCWD) {
		return conversationAttachObservedSessionResponse{}, fmt.Errorf("cwd must be an absolute path")
	}

	transcript, err := loadFullObservedTranscript("", req.SessionID)
	if err != nil {
		return conversationAttachObservedSessionResponse{}, fmt.Errorf("attachObservedSession: %w", err)
	}

	// Prefer the transcript's ai-title (latest wins inside parseClaudeTranscript);
	// attachObservedSession falls back to firstUserMessagePreview when empty.
	res, err := s.conversations.attachObservedSession(req.Provider, req.SessionID, resolvedCWD, transcript.Title, transcript.Messages)
	if err != nil {
		return conversationAttachObservedSessionResponse{}, err
	}

	return conversationAttachObservedSessionResponse{
		ConversationID:  res.ConversationID,
		ImportedEvents:  res.ImportedEvents,
		LastSeq:         res.LastSeq,
		AlreadyAttached: res.AlreadyAttached,
	}, nil
}
