package main

import (
	"encoding/json"
	"fmt"
	"strings"
	"sync"
	"time"
)

// QuestionOption is one typed, orderable choice in a question's Ladder — the
// vendor-agnostic analog of Claude's AskUserQuestion option shape
// ({label, description}). Order is significant: it is the order the Ladder
// is presented in.
type QuestionOption struct {
	Label       string `json:"label"`
	Description string `json:"description,omitempty"`
}

// QuestionItem is one question within a QuestionEvent. A single vendor tool
// call (e.g. Claude's AskUserQuestion) can bundle 1-4 of these; all items in
// an event are answered together (see QuestionAnswer.Items) since that is
// exactly how the vendor tool call itself expects its result.
type QuestionItem struct {
	Header      string           `json:"header,omitempty"`
	Question    string           `json:"question"`
	Options     []QuestionOption `json:"options,omitempty"` // the Ladder; empty ⇒ free-text-only (degraded vendor)
	MultiSelect bool             `json:"multiSelect,omitempty"`
}

// QuestionEvent mirrors ApprovalEvent's shape (see approval.go) for the
// question pipeline: a first-class, typed event the phone renders as a
// question card and eventually answers via the agent.question.answer RPC.
//
// Unlike ApprovalEvent, a QuestionEvent carries no risk/decision gate — an
// unanswered or wrongly-answered question cannot itself cause a dangerous
// action, so there is no ContentHash-style tamper binding and no
// allow/ask/deny policy evaluation. It is a pure relay: an agent asked
// something, a human answers it, the answer round-trips back.
type QuestionEvent struct {
	QuestionID string `json:"id"`
	Agent      string `json:"agent"`
	RunID      string `json:"runId,omitempty"`
	CWD        string `json:"cwd,omitempty"`
	ToolUseID  string `json:"toolUseID,omitempty"`
	Timestamp  string `json:"timestamp"`

	Questions []QuestionItem `json:"questions"`

	// AllowFreeText mirrors Claude's implicit "Other" option: true whenever a
	// human should be able to answer outside the Ladder's typed options —
	// always true for a degraded (bestEffort) event, since free text is then
	// the ONLY way to answer at all.
	AllowFreeText bool `json:"allowFreeText"`

	// Confidence records whether the Ladder came from the vendor's own
	// verified structured question schema ("complete") or was synthesized
	// best-effort because the vendor doesn't support structured questions, or
	// its tool call didn't match the known schema ("bestEffort") — same
	// two-tier vocabulary as receipt.go's commandsConfidence/testsConfidence.
	// Only Claude Code is ever eligible for "complete" (see
	// questionVendorSupportsStructured); every other vendor's question always
	// degrades visibly to "bestEffort" rather than being silently dropped or
	// faked as a capability it doesn't have.
	Confidence string `json:"confidence"`
}

// QuestionItemAnswer answers one QuestionItem: a set of selected option
// labels (single- or multi-select) and/or free text (Claude's "Other" — also
// the only field ever populated for a bestEffort, options-less item).
type QuestionItemAnswer struct {
	SelectedLabels []string `json:"selectedLabels,omitempty"`
	FreeText       string   `json:"freeText,omitempty"`
}

// QuestionAnswer resolves a pending QuestionEvent. Items must align 1:1 with
// the event's Questions by index — questionStore.resolve rejects a length
// mismatch rather than guessing, so a partially-answered multi-question event
// never silently resolves with missing answers.
type QuestionAnswer struct {
	QuestionID string               `json:"questionId"`
	Items      []QuestionItemAnswer `json:"items"`
}

type pendingQuestion struct {
	event  QuestionEvent
	answer chan QuestionAnswer
}

// questionStore is the question-pipeline analog of approvalStore (approval.go)
// — same add/resolve/remove/pendingEvents shape, same normID case-insensitive
// keying (a phone-supplied UUID and a daemon-generated one can differ only in
// case). It deliberately does NOT reuse approvalStore itself (see the E1 task
// write-set: approval.go is not to be touched) even though the shapes match,
// because a question's resolve() has different validation (item-count match,
// not a content-hash) and no policy/audit coupling belongs inside this type.
type questionStore struct {
	mu      sync.Mutex
	pending map[string]*pendingQuestion
}

func newQuestionStore() *questionStore {
	return &questionStore{pending: make(map[string]*pendingQuestion)}
}

func (s *questionStore) add(event QuestionEvent) <-chan QuestionAnswer {
	ch := make(chan QuestionAnswer, 1)
	s.mu.Lock()
	s.pending[normID(event.QuestionID)] = &pendingQuestion{event: event, answer: ch}
	s.mu.Unlock()
	return ch
}

func (s *questionStore) pendingEvents() []QuestionEvent {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := make([]QuestionEvent, 0, len(s.pending))
	for _, p := range s.pending {
		out = append(out, p.event)
	}
	return out
}

// resolve is the single delete-under-lock chokepoint for a pending question —
// same shape as approvalStore.resolve. A question answer carries no
// content-hash tamper binding (see QuestionEvent's doc comment), so the only
// validation is a length match between the answer's Items and the event's
// Questions: a mismatched count means the client answered a stale/different
// version of the question, not a security event, but it is still rejected
// rather than partially applied.
func (s *questionStore) resolve(id string, answer QuestionAnswer) (QuestionEvent, bool) {
	key := normID(id)
	s.mu.Lock()
	p, ok := s.pending[key]
	if ok && len(answer.Items) != len(p.event.Questions) {
		s.mu.Unlock()
		return QuestionEvent{}, false
	}
	if ok {
		delete(s.pending, key)
	}
	s.mu.Unlock()
	if !ok {
		return QuestionEvent{}, false
	}
	select {
	case p.answer <- answer:
	default:
	}
	return p.event, true
}

// remove drops a pending question without delivering an answer. Unlike
// approvalStore.remove (used by the hook-wait timeout path to retire an
// orphaned approval so a late decision can't mis-audit it), this is NOT called
// by waitForAnswer's timeout path — see its doc comment for why a question
// holds instead of resolving away on timeout. It exists only for explicit
// cleanup (e.g. the owning run being cancelled outright), matching
// approvalStore's shape for symmetry.
func (s *questionStore) remove(id string) {
	s.mu.Lock()
	delete(s.pending, normID(id))
	s.mu.Unlock()
}

// waitForAnswer blocks for an answer on ch. The bool reports whether an
// answer was received (true) versus the timeout firing (false).
//
// This deliberately does NOT mirror approval.go's waitWithTimeout all the way:
// that function's false path synthesizes a fail-closed "deny" — a load-bearing
// decision its caller immediately acts on and that caller then evicts the
// pending approval (approvalStore.remove) so a late decision can't re-resolve
// it. A question has no analog to "deny" — there is nothing unsafe about an
// agent run continuing to wait — so the false path here returns a zero-value
// QuestionAnswer that callers MUST NOT treat as a real answer; it only means
// "not yet". The pending question is left exactly as it was (see
// questionStore.remove's doc comment: this function never calls it), so an
// answer arriving after this particular wait gave up can still resolve it.
// This is the fail-closed **hold** the task spec calls for, as distinct from
// approval.go's fail-closed **deny**.
func waitForAnswer(ch <-chan QuestionAnswer, timeout time.Duration) (QuestionAnswer, bool) {
	select {
	case a := <-ch:
		return a, true
	case <-time.After(timeout):
		return QuestionAnswer{}, false
	}
}

func marshalPendingQuestionNotification(event QuestionEvent) ([]byte, error) {
	msg := map[string]interface{}{
		"jsonrpc": "2.0",
		"method":  "agent.question.pending",
		"params":  event,
	}
	return json.Marshal(msg)
}

// isQuestionToolName reports whether a completed tool_use's tool name is
// recognized as a question-ask. Only "AskUserQuestion" (Claude Code's
// documented tool, verified against the Claude Agent SDK's "Handle approvals
// and user input" docs) has a known structured schema today; the broader
// "contains question" match exists so an unknown/future vendor tool with an
// obviously question-shaped name still surfaces as a (bestEffort, free-text)
// QuestionEvent via extractQuestionEvent instead of being silently swallowed
// as an ordinary, uninspected tool artifact.
func isQuestionToolName(name string) bool {
	lower := strings.ToLower(strings.TrimSpace(name))
	if lower == "askuserquestion" {
		return true
	}
	return strings.Contains(lower, "question")
}

// questionVendorSupportsStructured reports whether agent's CLI is known (and
// verified) to emit AskUserQuestion's documented structured schema — same
// per-vendor trust axis as receipt.go's commandsConfidence, and deliberately
// keyed the same way (claudeCode only) so a vendor never gets "complete"
// confidence it hasn't earned, even if some other CLI happens to name a tool
// "AskUserQuestion" without implementing the same schema.
func questionVendorSupportsStructured(agent string) bool {
	return normalizeAgentSource(agent) == "claudeCode"
}

// claudeAskUserQuestionInput mirrors the Claude Agent SDK's documented
// AskUserQuestion tool_use input shape exactly (1-4 questions, 2-4 options
// each, an implicit "Other" free-text option always available) — see
// https://code.claude.com/docs/en/agent-sdk/user-input.
type claudeAskUserQuestionInput struct {
	Questions []struct {
		Question    string `json:"question"`
		Header      string `json:"header"`
		MultiSelect bool   `json:"multiSelect"`
		Options     []struct {
			Label       string `json:"label"`
			Description string `json:"description"`
		} `json:"options"`
	} `json:"questions"`
}

// extractQuestionEvent inspects one completed tool_use content block (the
// same {toolID, toolName, inputJSON} accumulator streamJSONOutput already
// builds for emitToolArtifact — see dispatch.go) and, if toolName names a
// recognized question tool, returns a QuestionEvent. Returns ok=false for any
// other tool name — the overwhelming majority of calls — so the ordinary
// artifact/chat pipeline is completely unaffected.
//
// A recognized question tool name whose input doesn't parse into the known
// structured schema (a truncated/malformed capture, or a vendor that only
// ever sends unstructured text) still produces a QuestionEvent — Confidence
// "bestEffort", no typed Ladder, free-text only — rather than being silently
// dropped. Only an unrecognized tool name produces no event at all.
func extractQuestionEvent(agent, runID, cwd, toolUseID, toolName, inputJSON string) (QuestionEvent, bool) {
	if !isQuestionToolName(toolName) {
		return QuestionEvent{}, false
	}

	base := QuestionEvent{
		QuestionID: newUUID(),
		Agent:      normalizeAgentSource(agent),
		RunID:      runID,
		CWD:        cwd,
		ToolUseID:  toolUseID,
		Timestamp:  time.Now().UTC().Format(time.RFC3339),
	}

	if questionVendorSupportsStructured(agent) && strings.EqualFold(toolName, "AskUserQuestion") {
		if items, complete, ok := parseClaudeAskUserQuestion(inputJSON); ok {
			base.Questions = items
			base.AllowFreeText = true // Claude's implicit "Other" option
			if complete {
				base.Confidence = "complete"
			} else {
				base.Confidence = "bestEffort"
			}
			return base, true
		}
	}

	// Recognized as a question tool, but either the vendor isn't trusted for
	// the structured schema (questionVendorSupportsStructured) or the input
	// didn't parse into it — degrade visibly rather than drop.
	base.Questions = []QuestionItem{{Question: bestEffortQuestionText(inputJSON)}}
	base.AllowFreeText = true
	base.Confidence = "bestEffort"
	return base, true
}

// parseClaudeAskUserQuestion parses inputJSON against the documented
// AskUserQuestion schema. ok is false only when the JSON doesn't parse at all
// or contains zero usable questions — the caller falls back to a best-effort
// free-text event in that case. complete is false when parsing succeeded but
// at least one question or option had to be dropped for missing required
// fields (empty question text, or an option with no label) — a partial
// structured result that should not claim full "complete" confidence.
func parseClaudeAskUserQuestion(inputJSON string) (items []QuestionItem, complete bool, ok bool) {
	var parsed claudeAskUserQuestionInput
	if err := json.Unmarshal([]byte(inputJSON), &parsed); err != nil || len(parsed.Questions) == 0 {
		return nil, false, false
	}

	complete = true
	for _, q := range parsed.Questions {
		if q.Question == "" || len(q.Options) == 0 {
			complete = false
			continue
		}
		opts := make([]QuestionOption, 0, len(q.Options))
		for _, o := range q.Options {
			if o.Label == "" {
				continue
			}
			opts = append(opts, QuestionOption{Label: o.Label, Description: o.Description})
		}
		if len(opts) == 0 {
			complete = false
			continue
		}
		items = append(items, QuestionItem{
			Header:      q.Header,
			Question:    q.Question,
			Options:     opts,
			MultiSelect: q.MultiSelect,
		})
	}
	if len(items) == 0 {
		return nil, false, false
	}
	return items, complete, true
}

// bestEffortQuestionText recovers whatever human-readable question text a
// degraded (non-structured) question tool call carries, so a human still sees
// SOMETHING instead of raw JSON whenever a recognizable field is present.
func bestEffortQuestionText(inputJSON string) string {
	var obj map[string]any
	if err := json.Unmarshal([]byte(inputJSON), &obj); err == nil {
		for _, key := range []string{"question", "prompt", "text", "message"} {
			if s, ok := obj[key].(string); ok && s != "" {
				return s
			}
		}
	}
	if inputJSON == "" {
		return "(agent asked a question with no readable text)"
	}
	return inputJSON
}

// questionAnswerHoldTimeout bounds how long registerAndWaitForQuestion blocks
// a run's stream-scanning goroutine per question before giving up on THIS
// wait and letting that run's output resume — not a deadline on the question
// itself, which (per waitForAnswer/questionStore.resolve) can still be
// answered indefinitely afterward. Long enough to comfortably cover a human
// noticing and answering a push/relay notification; unlike approvals there is
// no noClientGrace fast-path because a question has no safe default to fall
// back to.
// var, not const: TestRegisterAndWaitForQuestionStashesDenyOnTimeout
// temporarily lowers this to make the timeout path testable in milliseconds
// instead of genuinely waiting 10 minutes (save/restore around the test).
var questionAnswerHoldTimeout = 10 * time.Minute

// registerAndWaitForQuestion is the dispatcher's onQuestion hook (wired in
// newServer, server.go): it registers a freshly extracted question, relays it
// (attach + E2E), and then BLOCKS the calling goroutine — the same one
// scanning the run's stdout in streamJSONOutput — until a human answers or
// questionAnswerHoldTimeout elapses.
//
// Blocking the stream-scanning goroutine is the deliberate "hold" mechanism,
// and — as of M3 (2026-07-10) — it is also what makes the SAME-TURN
// injection below race-free: this call resolves (answered or timed out)
// strictly BEFORE the scanner can reach the "control_request" line that
// corresponds to this exact tool_use_id, because that line always arrives
// later in the same stdout stream this very goroutine is blocked reading.
// So by the time the scanner gets there, stashControlAnswer below has always
// already run — dispatcher.handleControlRequest never has to wait for it.
//
// Historical note (superseded by M3, kept for context): before M3, there was
// no stdin/tool-result injection path into an already-launched claudeCode
// process (dispatch() launched it fully non-interactively), so the daemon
// could only pause this run's own event stream — output, artifacts, and
// receipt accumulation all paused here, while the CLI itself had already
// auto-denied the tool call and moved on internally. M3 (see agentArgv's doc
// comment: --input-format stream-json + --permission-prompt-tool stdio with
// a live stdin pipe) replaced that: the CLI itself now genuinely blocks
// waiting for a control_response, so this hold is a REAL pause of the
// agent's own reasoning, not just a cosmetic delay of already-raced-ahead
// output. On questionAnswerHoldTimeout, per waitForAnswer's contract, the
// pending question is left exactly as it was in questionStore (never
// auto-removed) — but the control_request IS resolved (denied) below, since
// unlike before M3 the CLI is now actually waiting on it and would otherwise
// hang indefinitely (the Agent SDK's own documented behavior: "The callback
// can stay pending indefinitely"). A later answer arriving after the timeout
// can still be recorded via questionStore.resolve for audit purposes, but by
// then the CLI has already moved on past its own deny — same accepted gap as
// before M3, now scoped to "after the 10-minute hold, not after every turn".
func (s *server) registerAndWaitForQuestion(event QuestionEvent) {
	ch := s.questions.add(event)
	s.notifyQuestionPending(event)
	_ = s.audit.append(AuditEntry{
		Action:     "question-pending",
		Agent:      event.Agent,
		Kind:       "question",
		Command:    bestEffortQuestionSummary(event),
		Effect:     event.Confidence,
		ApprovalID: event.QuestionID,
	})
	answer, answered := waitForAnswer(ch, questionAnswerHoldTimeout)
	if !answered {
		_ = s.audit.append(AuditEntry{
			Action:     "question-hold-timeout",
			Agent:      event.Agent,
			Kind:       "question",
			Command:    bestEffortQuestionSummary(event),
			ApprovalID: event.QuestionID,
		})
		if event.ToolUseID != "" {
			s.dispatcher.stashControlAnswer(event.RunID, event.ToolUseID, controlAnswer{
				allow:   false,
				message: "No human answer arrived within the wait window.",
			})
		}
		return
	}
	if event.ToolUseID != "" {
		s.dispatcher.stashControlAnswer(event.RunID, event.ToolUseID, controlAnswer{
			allow:   true,
			answers: buildControlAnswers(event, answer),
		})
	}
}

// notifyQuestionPending relays a newly-registered question to every channel
// an approval-pending event already uses: the attach client (if connected,
// via the same writeFramed path as marshalPendingNotification), the E2E
// relay (if paired, via e2eRouter.sendQuestion), and — mirroring
// handleHookWithNotify's postApprovalPush call (server.go) — the
// push-backend APNs alert, so a backgrounded/killed app still learns the
// agent is waiting on input instead of only the live-attached client ever
// finding out.
func (s *server) notifyQuestionPending(event QuestionEvent) {
	if notification, err := marshalPendingQuestionNotification(event); err == nil {
		s.writeFramed(notification)
	}
	if s.e2e != nil {
		s.e2e.sendQuestion(event)
	}
	s.deviceMu.RLock()
	dev := s.device
	s.deviceMu.RUnlock()
	if dev != nil && dev.PushBackendURL != "" {
		go s.postQuestionPush(dev, event)
	}
}

// applyQuestionAnswer resolves a pending question — the RPC-layer entry point
// for agent.question.answer (server.go), mirroring applyDecision's role for
// agent.approval.response. Unlike applyDecision there is no "human decision"
// audit write keyed off an allow/deny outcome and no approveAlways-style
// policy persistence: a question answer carries no risk decision to record.
func (s *server) applyQuestionAnswer(answer QuestionAnswer) (QuestionEvent, bool) {
	event, ok := s.questions.resolve(answer.QuestionID, answer)
	if !ok {
		return QuestionEvent{}, false
	}
	_ = s.audit.append(AuditEntry{
		Action:     "question-answered",
		Agent:      event.Agent,
		Kind:       "question",
		Command:    bestEffortQuestionSummary(event),
		ApprovalID: event.QuestionID,
	})
	return event, true
}

// bestEffortQuestionSummary renders a short, human-readable audit summary for
// a QuestionEvent — the first question's text, or a count when there is more
// than one (Claude's AskUserQuestion allows up to 4 per call).
func bestEffortQuestionSummary(event QuestionEvent) string {
	if len(event.Questions) == 0 {
		return ""
	}
	if len(event.Questions) == 1 {
		return event.Questions[0].Question
	}
	return event.Questions[0].Question + fmt.Sprintf(" (+%d more)", len(event.Questions)-1)
}
