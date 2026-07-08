package main

import (
	"encoding/json"
	"strconv"
	"strings"
	"sync"
	"time"
)

const (
	receiptSchema        = "lancer.proof/v0"
	receiptMaxCommands   = 50
	receiptMaxSerialized = 32 * 1024
)

type receiptContract struct {
	Goal               string   `json:"goal,omitempty"`
	DoneCriteria       []string `json:"doneCriteria,omitempty"`
	ValidationCommands []string `json:"validationCommands,omitempty"`
}

type receiptCommand struct {
	Command   string `json:"command"`
	ExitCode  *int   `json:"exitCode,omitempty"`
	Kind      string `json:"kind"`
	StartedAt string `json:"startedAt"`
}

type receiptFileTouched struct {
	Path      string `json:"path"`
	Additions int    `json:"additions"`
	Deletions int    `json:"deletions"`
}

type receiptTests struct {
	Ran    bool `json:"ran"`
	Passed int  `json:"passed"`
	Failed int  `json:"failed"`
}

type receiptCriterion struct {
	Text     string `json:"text"`
	Status   string `json:"status"`
	Evidence string `json:"evidence,omitempty"`
}

type receiptGit struct {
	StartRef     string `json:"startRef,omitempty"`
	EndRef       string `json:"endRef,omitempty"`
	DirtyAtStart bool   `json:"dirtyAtStart"`
	WorktreePath string `json:"worktreePath,omitempty"`
}

type receiptConfidence struct {
	Commands string `json:"commands"`
	Files    string `json:"files"`
	Tests    string `json:"tests"`
}

type receiptResume struct {
	Agent           string `json:"agent"`
	VendorSessionID string `json:"vendorSessionId,omitempty"`
}

type runReceipt struct {
	Schema          string               `json:"schema"`
	RunID           string               `json:"runId"`
	ConversationID  string               `json:"conversationId,omitempty"`
	Agent           string               `json:"agent"`
	Model           string               `json:"model,omitempty"`
	StartedAt       string               `json:"startedAt"`
	EndedAt         string               `json:"endedAt"`
	ExitCode        int                  `json:"exitCode"`
	Status          string               `json:"status"`
	Contract        *receiptContract     `json:"contract,omitempty"`
	Commands        []receiptCommand     `json:"commands"`
	FilesTouched    []receiptFileTouched `json:"filesTouched"`
	Tests           receiptTests         `json:"tests"`
	Criteria        []receiptCriterion   `json:"criteria"`
	Git             receiptGit           `json:"git"`
	Confidence      receiptConfidence    `json:"confidence"`
	Resume          *receiptResume       `json:"resume,omitempty"`
	AnswersReserved any                  `json:"answersReserved"`
	Truncated       bool                 `json:"truncated,omitempty"`
}

type receiptStartParams struct {
	agent          string
	model          string
	cwd            string
	worktreePath   string
	conversationID string
	contract       *receiptContract
}

type receiptAccumulator struct {
	mu sync.Mutex

	runID          string
	agent          string
	model          string
	cwd            string
	worktreePath   string
	conversationID string
	contract       *receiptContract
	startedAt      time.Time

	gitStartRef     string
	gitDirtyAtStart bool
	gitAvailable    bool

	commands         []receiptCommand
	vendorSessionID  string
	finalizedReceipt *runReceipt
}

func newReceiptAccumulator(runID string, p receiptStartParams, gitRun gitRunner) *receiptAccumulator {
	acc := &receiptAccumulator{
		runID:          runID,
		agent:          p.agent,
		model:          p.model,
		cwd:            expandHome(p.cwd),
		worktreePath:   p.worktreePath,
		conversationID: p.conversationID,
		contract:       p.contract,
		startedAt:      time.Now().UTC(),
	}
	if gitRun == nil {
		gitRun = realGitRunner
	}
	ref, dirty, ok := gitStartSnapshot(acc.cwd, gitRun)
	acc.gitStartRef = ref
	acc.gitDirtyAtStart = dirty
	acc.gitAvailable = ok
	return acc
}

func (d *dispatcher) startReceiptAccum(runID string, p receiptStartParams) {
	if d == nil || runID == "" {
		return
	}
	gitRun := d.receiptGit
	if gitRun == nil {
		gitRun = realGitRunner
	}
	acc := newReceiptAccumulator(runID, p, gitRun)
	d.receiptMu.Lock()
	if d.receiptAccum == nil {
		d.receiptAccum = map[string]*receiptAccumulator{}
	}
	d.receiptAccum[runID] = acc
	d.receiptMu.Unlock()
}

func (d *dispatcher) observeReceiptEmit(runID, method string, params any) {
	acc := d.receiptAccumFor(runID)
	if acc == nil {
		return
	}
	m, ok := params.(map[string]any)
	if !ok {
		return
	}
	switch method {
	case "agent.tool.start":
		acc.recordToolStart(m)
	case "agent.run.vendorSession":
		if sid, _ := m["vendorSessionId"].(string); sid != "" {
			acc.setVendorSessionID(sid)
		}
	}
}

func (d *dispatcher) finalizeReceipt(runID, terminalStatus string, exitCode int) *runReceipt {
	acc := d.receiptAccumFor(runID)
	if acc == nil {
		return nil
	}
	gitRun := d.receiptGit
	if gitRun == nil {
		gitRun = realGitRunner
	}
	runStatus := ""
	d.mu.Lock()
	if run := d.runs[runID]; run != nil {
		runStatus = run.Status
		if run.SessionID != "" {
			acc.setVendorSessionID(run.SessionID)
		}
	}
	d.mu.Unlock()

	receipt := acc.build(runStatus, terminalStatus, exitCode, gitRun)

	d.receiptMu.Lock()
	if d.receipts == nil {
		d.receipts = map[string]*runReceipt{}
	}
	d.receipts[runID] = receipt
	delete(d.receiptAccum, runID)
	d.receiptMu.Unlock()
	return receipt
}

func (d *dispatcher) receiptAccumFor(runID string) *receiptAccumulator {
	if d == nil || runID == "" {
		return nil
	}
	d.receiptMu.Lock()
	defer d.receiptMu.Unlock()
	return d.receiptAccum[runID]
}

func (d *dispatcher) getReceipt(runID string) *runReceipt {
	if d == nil || runID == "" {
		return nil
	}
	d.receiptMu.Lock()
	defer d.receiptMu.Unlock()
	return d.receipts[runID]
}

func (acc *receiptAccumulator) recordToolStart(params map[string]any) {
	cmd := extractCommandFromToolStart(params)
	if cmd == "" {
		return
	}
	acc.mu.Lock()
	defer acc.mu.Unlock()
	acc.commands = append(acc.commands, receiptCommand{
		Command:   cmd,
		Kind:      classifyCommandKind(cmd),
		StartedAt: time.Now().UTC().Format(time.RFC3339),
	})
}

func (acc *receiptAccumulator) setVendorSessionID(id string) {
	acc.mu.Lock()
	defer acc.mu.Unlock()
	acc.vendorSessionID = id
}

func (acc *receiptAccumulator) build(runStatus, terminalStatus string, exitCode int, gitRun gitRunner) *runReceipt {
	acc.mu.Lock()
	agent := acc.agent
	model := acc.model
	cwd := acc.cwd
	worktreePath := acc.worktreePath
	conversationID := acc.conversationID
	contract := acc.contract
	startedAt := acc.startedAt
	gitStartRef := acc.gitStartRef
	gitDirtyAtStart := acc.gitDirtyAtStart
	gitAvailable := acc.gitAvailable
	commands := append([]receiptCommand(nil), acc.commands...)
	vendorSessionID := acc.vendorSessionID
	acc.mu.Unlock()

	endedAt := time.Now().UTC()
	files, filesConfidence := gitFilesTouched(cwd, gitStartRef, gitAvailable, gitRun)
	endRef, _ := gitHEAD(cwd, gitRun)

	receipt := &runReceipt{
		Schema:         receiptSchema,
		RunID:          acc.runID,
		ConversationID: conversationID,
		Agent:          receiptAgentName(agent),
		Model:          model,
		StartedAt:      startedAt.Format(time.RFC3339),
		EndedAt:        endedAt.Format(time.RFC3339),
		ExitCode:       exitCode,
		Status:         mapReceiptStatus(terminalStatus, exitCode, runStatus),
		Contract:       contract,
		Commands:       commands,
		FilesTouched:   files,
		Tests:          summarizeReceiptTests(commands),
		Criteria:       evaluateReceiptCriteria(contract, commands),
		Git: receiptGit{
			StartRef:     gitStartRef,
			EndRef:       endRef,
			DirtyAtStart: gitDirtyAtStart,
			WorktreePath: worktreePath,
		},
		Confidence: receiptConfidence{
			Commands: commandsConfidence(agent),
			Files:    filesConfidence,
			Tests:    testsConfidence(commands),
		},
		AnswersReserved: nil,
	}
	if vendorSessionID != "" {
		receipt.Resume = &receiptResume{
			Agent:           receipt.Agent,
			VendorSessionID: vendorSessionID,
		}
	}
	applyReceiptLimits(receipt)
	return receipt
}

func extractCommandFromToolStart(params map[string]any) string {
	inputJSON, _ := params["inputJSON"].(string)
	if inputJSON == "" {
		return ""
	}
	var obj map[string]any
	if err := json.Unmarshal([]byte(inputJSON), &obj); err != nil {
		return ""
	}
	if cmd, ok := obj["command"].(string); ok && cmd != "" {
		return cmd
	}
	return ""
}

var receiptTestPrefixes = [][]string{
	{"go", "test"},
	{"swift", "test"},
	{"pytest"},
	{"npm", "test"},
	{"yarn", "test"},
	{"cargo", "test"},
	{"xcodebuild", "test"},
}

func classifyCommandKind(command string) string {
	tokens := strings.Fields(strings.TrimSpace(command))
	if len(tokens) == 0 {
		return "shell"
	}
	for _, prefix := range receiptTestPrefixes {
		if len(tokens) < len(prefix) {
			continue
		}
		match := true
		for i, p := range prefix {
			if !strings.EqualFold(tokens[i], p) {
				match = false
				break
			}
		}
		if match {
			return "test"
		}
	}
	return "shell"
}

func normalizeCommandWhitespace(command string) string {
	return strings.Join(strings.Fields(strings.TrimSpace(command)), " ")
}

func receiptAgentName(agent string) string {
	switch normalizeAgentSource(agent) {
	case "claudeCode":
		return "claude"
	case "codex":
		return "codex"
	case "kimi":
		return "kimi"
	case "opencode":
		return "opencode"
	default:
		return normalizeAgentSource(agent)
	}
}

func commandsConfidence(agent string) string {
	switch normalizeAgentSource(agent) {
	case "claudeCode":
		return "complete"
	case "codex", "kimi", "opencode":
		return "bestEffort"
	default:
		return "bestEffort"
	}
}

func testsConfidence(commands []receiptCommand) string {
	ranTest := false
	for _, cmd := range commands {
		if cmd.Kind != "test" {
			continue
		}
		ranTest = true
		if cmd.ExitCode == nil {
			return "bestEffort"
		}
	}
	if ranTest {
		return "complete"
	}
	return "bestEffort"
}

func mapReceiptStatus(terminalStatus string, exitCode int, runStatus string) string {
	if runStatus == "cancelled" {
		return "stopped"
	}
	switch terminalStatus {
	case "exited":
		if exitCode == 0 {
			return "completed"
		}
		return "failed"
	case "failed":
		return "failed"
	default:
		return "failed"
	}
}

func gitStartSnapshot(cwd string, run gitRunner) (ref string, dirty bool, ok bool) {
	if cwd == "" {
		return "", false, false
	}
	if _, err := run(cwd, "git", "rev-parse", "--git-dir"); err != nil {
		return "", false, false
	}
	head, err := run(cwd, "git", "rev-parse", "HEAD")
	if err != nil {
		return "", false, false
	}
	status, _ := run(cwd, "git", "status", "--porcelain")
	return strings.TrimSpace(head), strings.TrimSpace(status) != "", true
}

func gitHEAD(cwd string, run gitRunner) (string, bool) {
	if cwd == "" {
		return "", false
	}
	out, err := run(cwd, "git", "rev-parse", "HEAD")
	if err != nil {
		return "", false
	}
	return strings.TrimSpace(out), true
}

func gitFilesTouched(cwd, startRef string, gitAvailable bool, run gitRunner) ([]receiptFileTouched, string) {
	if !gitAvailable || cwd == "" {
		return nil, "unavailable"
	}
	args := []string{"diff", "--numstat"}
	if startRef != "" {
		args = append(args, startRef)
	}
	out, err := run(cwd, "git", args...)
	if err != nil {
		return nil, "unavailable"
	}
	files := parseGitNumstat(out)
	if len(files) == 0 && strings.TrimSpace(out) == "" {
		return files, "complete"
	}
	if len(files) == 0 {
		return files, "complete"
	}
	return files, "complete"
}

func parseGitNumstat(output string) []receiptFileTouched {
	var files []receiptFileTouched
	for _, line := range strings.Split(output, "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		parts := strings.Split(line, "\t")
		if len(parts) < 3 {
			continue
		}
		additions := 0
		deletions := 0
		if parts[0] != "-" {
			additions, _ = strconv.Atoi(parts[0])
		}
		if parts[1] != "-" {
			deletions, _ = strconv.Atoi(parts[1])
		}
		files = append(files, receiptFileTouched{
			Path:      parts[2],
			Additions: additions,
			Deletions: deletions,
		})
	}
	return files
}

func summarizeReceiptTests(commands []receiptCommand) receiptTests {
	tests := receiptTests{}
	for _, cmd := range commands {
		if cmd.Kind != "test" {
			continue
		}
		tests.Ran = true
		if cmd.ExitCode == nil {
			continue
		}
		if *cmd.ExitCode == 0 {
			tests.Passed++
		} else {
			tests.Failed++
		}
	}
	return tests
}

func evaluateReceiptCriteria(contract *receiptContract, commands []receiptCommand) []receiptCriterion {
	if contract == nil || len(contract.DoneCriteria) == 0 {
		return nil
	}
	validationByNorm := map[string]int{}
	for _, cmd := range commands {
		if cmd.ExitCode == nil {
			continue
		}
		validationByNorm[normalizeCommandWhitespace(cmd.Command)] = *cmd.ExitCode
	}
	var criteria []receiptCriterion
	for _, text := range contract.DoneCriteria {
		criterion := receiptCriterion{Text: text, Status: "unknown"}
		matched := false
		for _, validation := range contract.ValidationCommands {
			norm := normalizeCommandWhitespace(validation)
			exitCode, ok := validationByNorm[norm]
			if !ok {
				continue
			}
			matched = true
			if exitCode == 0 {
				criterion.Status = "met"
				criterion.Evidence = validation
			} else {
				criterion.Status = "unmet"
				criterion.Evidence = validation
			}
			break
		}
		if !matched && len(contract.ValidationCommands) == 0 {
			criterion.Status = "unknown"
		}
		criteria = append(criteria, criterion)
	}
	return criteria
}

func applyReceiptLimits(receipt *runReceipt) {
	if len(receipt.Commands) > receiptMaxCommands {
		receipt.Commands = receipt.Commands[:receiptMaxCommands]
		receipt.Truncated = true
	}
	for {
		data, err := json.Marshal(receipt)
		if err != nil || len(data) <= receiptMaxSerialized {
			return
		}
		if len(receipt.Commands) == 0 {
			return
		}
		receipt.Truncated = true
		receipt.Commands = receipt.Commands[:len(receipt.Commands)-1]
	}
}
