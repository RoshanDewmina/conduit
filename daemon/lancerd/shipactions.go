package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"
)

// shipactions.go — phone-initiated git/PR "ship actions" (branch, stage+commit,
// open a PR), gated behind the approval pipeline.
//
// PERMANENT SCOPE BOUNDARY: merge-from-phone is out of scope, deliberately and
// permanently (see docs/plans/2026-07-08-lancer-layer-4-6-lane-proposal.md,
// "Owner decisions" §3). Do not add one here, not even behind a flag — merge
// needs its own gate design that doesn't exist yet. Nothing in this file calls
// `git merge`, `gh pr merge`, or any equivalent.
//
// Every ship action:
//   - is scored at the fixed "high" risk tier (shipActionRisk = 2), never a
//     value derived from caller input, so it can't be silently downgraded;
//   - is staged as a pending ApprovalEvent through the SAME approvalStore used
//     for hook-originated tool-call approvals (approval.go) — no bypass path,
//     no policy-engine auto-allow shortcut, regardless of the host's configured
//     autonomy preset. An explicit phone decision is required unconditionally;
//   - is content-hash bound (computeContentHash) over exactly the fields the
//     phone is shown (command summary, working-tree diff, workdir, and the
//     marshaled action params) — a decision echoing a stale/mismatched hash is
//     rejected by approvalStore.resolve, so what executes is cryptographically
//     tied to what was reviewed;
//   - only executes git/gh via explicit argv through the existing s.gitRun /
//     s.gitShip machinery (git.go) — no new subprocess-execution idiom, no
//     shell interpolation.

// shipActionRisk is the fixed risk tier for every ship action: 2 == "high" per
// policy.RiskLabel/riskOrder. This is a constant, not derived from any
// caller-supplied field, so a ship action can never be tagged at a lower tier.
const shipActionRisk = 2

// shipActionParams describes one staged branch/commit/PR action. Workdir and
// Message are required; Branch/OpenPR/PR fields are optional depending on
// which of the in-scope steps the phone is requesting.
type shipActionParams struct {
	Workdir string `json:"workdir"`
	// Branch, when set, is created (git checkout -b) before staging/committing.
	// Empty means "commit/PR on the current branch" (no new branch step).
	Branch string `json:"branch,omitempty"`
	// BaseBranch, when set, is the ref the new Branch is created from. Empty
	// means "from the current HEAD" (git's own default for checkout -b).
	BaseBranch string `json:"baseBranch,omitempty"`
	Message    string `json:"message"`
	OpenPR     bool   `json:"openPR,omitempty"`
	// PRBase is the PR's target base branch (gh pr create --base). Empty lets
	// gh fall back to the repo's configured default branch.
	PRBase string `json:"prBase,omitempty"`
	Title  string `json:"title,omitempty"`
	Body   string `json:"body,omitempty"`
}

// shipActionResult is returned synchronously from agent.ship.propose: the
// action is now staged and pending, not yet executed.
type shipActionResult struct {
	ApprovalID  string `json:"approvalId"`
	ContentHash string `json:"contentHash"`
	Risk        int    `json:"risk"`
}

// shipActionOutcome is emitted asynchronously (agent.ship.result) once a
// staged ship action's approval decision resolves and, if approved, execution
// finishes.
type shipActionOutcome struct {
	ApprovalID string         `json:"approvalId"`
	Status     string         `json:"status"` // "denied" | "completed" | "failed"
	Result     *gitShipResult `json:"result,omitempty"`
	Error      string         `json:"error,omitempty"`
}

// shipPreflightResult surfaces host readiness BEFORE an action is offered, so
// a phone-initiated ship action doesn't fail destructively mid-execution on an
// unprepared host (no gh, no auth, unreachable remote, mid-conflict tree).
type shipPreflightResult struct {
	Ready           bool     `json:"ready"`
	GHInstalled     bool     `json:"ghInstalled"`
	GHAuthenticated bool     `json:"ghAuthenticated"`
	HasRemote       bool     `json:"hasRemote"`
	RemoteReachable bool     `json:"remoteReachable"`
	Branch          string   `json:"branch,omitempty"`
	HasChanges      bool     `json:"hasChanges"`
	HasConflicts    bool     `json:"hasConflicts"`
	Reasons         []string `json:"reasons,omitempty"`
}

// isConflictCode reports whether a git short-status code (parseGitStatus)
// marks an unresolved merge conflict, per `git status --porcelain` §"Unmerged".
func isConflictCode(code string) bool {
	switch code {
	case "UU", "AA", "DD", "AU", "UA", "UD", "DU":
		return true
	default:
		return false
	}
}

// shipPreflight never hard-errors: an unready host is a valid, expected answer
// (Ready=false + Reasons), not a failure of the check itself.
func (s *server) shipPreflight(workdir string) shipPreflightResult {
	var res shipPreflightResult

	if _, err := s.repoRoot(workdir); err != nil {
		res.Reasons = append(res.Reasons, fmt.Sprintf("not a git repository: %v", err))
		return res
	}

	if status, err := s.gitStatus(workdir); err != nil {
		res.Reasons = append(res.Reasons, fmt.Sprintf("git status failed: %v", err))
	} else {
		res.Branch = status.Branch
		res.HasChanges = len(status.Changes) > 0
		for _, c := range status.Changes {
			if isConflictCode(c.Code) {
				res.HasConflicts = true
				break
			}
		}
		if res.HasConflicts {
			res.Reasons = append(res.Reasons, "unresolved merge conflicts in the working tree")
		}
	}

	if _, err := s.gitRun(workdir, "git", "remote", "get-url", "origin"); err != nil {
		res.Reasons = append(res.Reasons, "no 'origin' remote configured")
	} else {
		res.HasRemote = true
		// No ref pattern, no --exit-code: this only proves the transport can be
		// reached (auth + connectivity), not that the remote has any commits —
		// an empty-but-reachable remote must not be reported as unreachable.
		if _, err := s.gitRun(workdir, "git", "ls-remote", "origin"); err != nil {
			res.Reasons = append(res.Reasons, fmt.Sprintf("origin remote is not reachable: %v", err))
		} else {
			res.RemoteReachable = true
		}
	}

	if _, err := s.gitRun(workdir, "gh", "--version"); err != nil {
		res.Reasons = append(res.Reasons, "GitHub CLI (gh) is not installed on the host")
	} else {
		res.GHInstalled = true
		if _, err := s.gitRun(workdir, "gh", "auth", "status"); err != nil {
			res.Reasons = append(res.Reasons, "GitHub CLI (gh) is not authenticated on the host — run `gh auth login`")
		} else {
			res.GHAuthenticated = true
		}
	}

	res.Ready = res.HasRemote && res.RemoteReachable && res.GHInstalled && res.GHAuthenticated && !res.HasConflicts
	return res
}

// describeShipAction renders a one-line, human-reviewable summary of a staged
// action for the approval card and audit log.
func describeShipAction(p shipActionParams) string {
	var parts []string
	if p.Branch != "" {
		if p.BaseBranch != "" {
			parts = append(parts, fmt.Sprintf("create branch %s from %s", p.Branch, p.BaseBranch))
		} else {
			parts = append(parts, fmt.Sprintf("create branch %s", p.Branch))
		}
	}
	parts = append(parts, fmt.Sprintf("commit %q", p.Message))
	if p.OpenPR {
		if p.Title != "" {
			parts = append(parts, fmt.Sprintf("open PR %q", p.Title))
		} else {
			parts = append(parts, "open PR")
		}
	}
	return "ship: " + strings.Join(parts, "; ")
}

// proposeShipAction stages a ship action as a pending approval. It never
// executes git/gh itself — execution only happens from awaitShipDecision,
// after an explicit "approve" decision resolves the approval this creates.
func (s *server) proposeShipAction(p shipActionParams) (shipActionResult, error) {
	pre := s.shipPreflight(p.Workdir)
	if !pre.Ready {
		return shipActionResult{}, fmt.Errorf("host not ready to ship: %s", strings.Join(pre.Reasons, "; "))
	}

	toolInput, err := json.Marshal(p)
	if err != nil {
		return shipActionResult{}, fmt.Errorf("encode ship action: %w", err)
	}
	// The working-tree diff is exactly what `git add -A && git commit` (via
	// gitShip, in executeShipAction) will capture — binding it into the content
	// hash means the phone's review and the eventual commit can never diverge.
	patch, _ := s.gitRun(p.Workdir, "git", "diff", "HEAD")

	event := ApprovalEvent{
		ApprovalID: newUUID(),
		Agent:      "lancer-phone",
		Kind:       "shipAction",
		Command:    describeShipAction(p),
		Patch:      patch,
		CWD:        p.Workdir,
		Risk:       shipActionRisk,
		Timestamp:  time.Now().UTC().Format(time.RFC3339),
		ToolInput:  string(toolInput),
	}
	event.ContentHash = computeContentHash(event.Command, event.Patch, event.CWD, event.ToolInput)

	// Unconditional staging: no policy.Evaluate call here, by design. A ship
	// action must always ask, even under the "bypass" autonomy preset that
	// auto-allows other high-risk commands — see the package doc comment.
	decisionCh := s.approvals.add(event)

	s.auditEntry(AuditEntry{
		Action:     "ship-propose",
		Kind:       "git",
		Command:    event.Command,
		ApprovalID: event.ApprovalID,
	})
	s.notifyApprovalPending(event)

	go s.awaitShipDecision(event, p, decisionCh)

	return shipActionResult{
		ApprovalID:  event.ApprovalID,
		ContentHash: event.ContentHash,
		Risk:        event.Risk,
	}, nil
}

// notifyApprovalPending pushes a newly staged approval to every channel a
// human could see it on: the local attach/stdout framed connection, the E2E
// relay (when paired), and APNs (when a push device is registered). Mirrors
// the notify/e2e/push sequence handleHookWithNotify uses for hook-originated
// approvals (server.go) — same delivery fan-out, different origin.
func (s *server) notifyApprovalPending(event ApprovalEvent) {
	if notification, err := marshalPendingNotification(event); err == nil {
		s.writeFramed(notification)
	}
	if s.e2e != nil {
		s.e2e.sendApproval(event)
	}
	s.deviceMu.RLock()
	dev := s.device
	s.deviceMu.RUnlock()
	if dev != nil && dev.PushBackendURL != "" {
		go s.postApprovalPush(dev, event)
	}
}

// awaitShipDecision blocks (no timeout — matches the reachable-client path in
// handleHookWithNotify: a pending approval must pause, never silently resolve,
// on a slow tap) until a human decision resolves the approval, then executes
// the staged action iff approved. "approveAlways" is treated identically to
// "approve" for execution purposes (matching handleHookWithNotify's own
// normalization) — the always-policy rule it may append is inert here anyway,
// since proposeShipAction never consults the policy engine, so it cannot
// later suppress a required ask for a future ship action.
func (s *server) awaitShipDecision(event ApprovalEvent, p shipActionParams, decisionCh <-chan hookDecision) {
	result := <-decisionCh
	if result.decision != "approve" && result.decision != "approveAlways" {
		s.emitNotification("agent.ship.result", shipActionOutcome{
			ApprovalID: event.ApprovalID,
			Status:     "denied",
		})
		return
	}

	res, err := s.executeShipAction(p)
	outcome := shipActionOutcome{ApprovalID: event.ApprovalID}
	if err != nil {
		outcome.Status = "failed"
		outcome.Error = err.Error()
		s.auditEntry(AuditEntry{
			Action:     "ship-failed",
			Kind:       "git",
			Command:    event.Command,
			ApprovalID: event.ApprovalID,
		})
	} else {
		outcome.Status = "completed"
		outcome.Result = &res
		s.auditEntry(AuditEntry{
			Action:     "ship-completed",
			Kind:       "git",
			Command:    event.Command,
			ApprovalID: event.ApprovalID,
		})
	}
	s.emitNotification("agent.ship.result", outcome)
}

// executeShipAction runs the approved steps against the host repo: an
// optional branch creation, then stage+commit+push+PR via the existing,
// already-tested gitShip (git.go) — no new subprocess-execution idiom.
//
// PERMANENT: no merge step exists here, on this path, or anywhere else in this
// file. Ship actions stop at "PR opened."
func (s *server) executeShipAction(p shipActionParams) (gitShipResult, error) {
	if p.Branch != "" {
		args := []string{"checkout", "-b", p.Branch}
		if p.BaseBranch != "" {
			args = append(args, p.BaseBranch)
		}
		if _, err := s.gitRun(p.Workdir, "git", args...); err != nil {
			if !isBranchAlreadyExists(err) {
				return gitShipResult{}, fmt.Errorf("branch create failed: %w", err)
			}
			// Retry-safe: the branch already exists (a prior partial attempt
			// created it) — switch onto it instead of failing.
			if _, err := s.gitRun(p.Workdir, "git", "checkout", p.Branch); err != nil {
				return gitShipResult{}, fmt.Errorf("checkout existing branch failed: %w", err)
			}
		}
	}

	return s.gitShip(shipParams{
		Workdir: p.Workdir,
		Message: p.Message,
		OpenPR:  p.OpenPR,
		Base:    p.PRBase,
		Title:   p.Title,
		Body:    p.Body,
	})
}

func isBranchAlreadyExists(err error) bool {
	var ce *gitCmdError
	if !errors.As(err, &ce) {
		return false
	}
	low := strings.ToLower(ce.output)
	return strings.Contains(low, "already exists")
}
