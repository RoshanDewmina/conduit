package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"syscall"
	"time"
)

// Claude auth preflight + status probe (2026-07-14).
//
// Live CLI audit (claude 2.1.209): `claude auth status --json` returns
// {"loggedIn":bool,...}. We only ever read loggedIn — never persist/log email,
// org, or token material.
//
// Fail-closed for launch:
//   - loggedIn:false → errClaudeNotLoggedIn
//   - probe timeout / invalid JSON / exec error → errClaudeAuthUnavailable
//     ("auth status unavailable — retry") — do not degrade into a long vendor
//     launch. Status RPC never blocks on the probe timeout.
const (
	claudeAuthTrueCacheTTL     = 45 * time.Second // within 30–60s band
	claudeAuthFalseCacheTTL    = 5 * time.Second  // short TTL: fast fail, quick recovery
	claudeAuthProbeStdoutLimit = 64 * 1024        // bound probe stdout; overflow → unavailable
	claudeNotLoggedInMessage   = "Not logged in — run claude /login on the host"
	claudeColdStartTimeoutMsg  = "Claude cold-start timeout — no vendor output before deadline (retryable)"
	claudeAuthUnavailableMsg   = "auth status unavailable — retry"
)

// claudeAuthProbeTimeout covers measured ~15s cold `claude auth status`.
// Var so tests can shorten; production default is 20s.
var claudeAuthProbeTimeout = 20 * time.Second

var (
	errClaudeNotLoggedIn     = errors.New(claudeNotLoggedInMessage)
	errClaudeAuthUnavailable = errors.New(claudeAuthUnavailableMsg)
)

// claudeAuthCommandRunner runs an explicit argv under env and returns stdout.
// Injectable for tests. Never use sh -c in production.
type claudeAuthCommandRunner func(ctx context.Context, bin string, args []string, env []string) ([]byte, error)

var defaultClaudeAuthRunner claudeAuthCommandRunner = runClaudeAuthCommand

// prepareClaudeAuthCmd applies process-group isolation (Setpgid) so a timed-out
// probe can kill the whole group, and discards stderr so probe PII never
// inherits into the daemon log. Test seam — production always uses this.
func prepareClaudeAuthCmd(cmd *exec.Cmd, env []string) {
	if env != nil {
		cmd.Env = env
	}
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	cmd.Stderr = io.Discard
}

// cappedWriter accepts up to lim bytes then marks overflow; further writes are
// drained (so the child pipe does not block) but discarded. Never logs content.
type cappedWriter struct {
	buf      bytes.Buffer
	n        int
	lim      int
	overflow bool
}

func (c *cappedWriter) Write(p []byte) (int, error) {
	if c.overflow {
		return len(p), nil
	}
	remain := c.lim - c.n
	if remain <= 0 {
		c.overflow = true
		return len(p), nil
	}
	if len(p) > remain {
		_, _ = c.buf.Write(p[:remain])
		c.n = c.lim
		c.overflow = true
		return len(p), nil
	}
	_, _ = c.buf.Write(p)
	c.n += len(p)
	return len(p), nil
}

// runClaudeAuthCommand executes bin+args with Setpgid, kills the process group
// on context cancel/timeout, and reaps Wait. Explicit argv only — no shell.
// Stderr is discarded; stdout is bounded to claudeAuthProbeStdoutLimit.
func runClaudeAuthCommand(ctx context.Context, bin string, args []string, env []string) ([]byte, error) {
	cmd := exec.Command(bin, args...)
	prepareClaudeAuthCmd(cmd, env)
	stdout := &cappedWriter{lim: claudeAuthProbeStdoutLimit}
	cmd.Stdout = stdout
	if err := cmd.Start(); err != nil {
		return nil, err
	}
	done := make(chan error, 1)
	go func() { done <- cmd.Wait() }()
	select {
	case err := <-done:
		if stdout.overflow {
			// Generic unavailable — never include probe content/PII.
			return nil, errClaudeAuthUnavailable
		}
		return stdout.buf.Bytes(), err
	case <-ctx.Done():
		if cmd.Process != nil {
			_ = syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL)
			_ = cmd.Process.Kill()
		}
		<-done // reap
		if stdout.overflow {
			return nil, errClaudeAuthUnavailable
		}
		return stdout.buf.Bytes(), ctx.Err()
	}
}

// claudeAuthProbe runs `claude auth status --json` under the given env.
// Returns (loggedIn, nil) on a parseable response; (_, err) on timeout/invalid/exec.
// Does not expose token/keychain/email fields to callers.
func claudeAuthProbe(runner claudeAuthCommandRunner, env []string, timeout time.Duration) (bool, error) {
	if runner == nil {
		runner = defaultClaudeAuthRunner
	}
	if timeout <= 0 {
		timeout = claudeAuthProbeTimeout
	}
	bin := "claude"
	if resolved := lookPathIn("claude", env); resolved != "" {
		bin = resolved
	}
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	out, err := runner(ctx, bin, []string{"auth", "status", "--json"}, env)
	if ctx.Err() == context.DeadlineExceeded {
		return false, errClaudeAuthUnavailable
	}
	loggedIn, parseErr := parseClaudeAuthStatusJSON(out)
	if parseErr != nil {
		return false, errClaudeAuthUnavailable
	}
	if err != nil && !loggedIn {
		// Non-zero exit with parseable loggedIn:false is still a valid probe.
		return loggedIn, nil
	}
	_ = err // successful parse wins over exit code
	return loggedIn, nil
}

// parseClaudeAuthStatusJSON defensively reads only the loggedIn boolean.
func parseClaudeAuthStatusJSON(raw []byte) (bool, error) {
	raw = bytes.TrimSpace(raw)
	if len(raw) == 0 {
		return false, errClaudeAuthUnavailable
	}
	var obj map[string]any
	if err := json.Unmarshal(raw, &obj); err != nil {
		return false, errClaudeAuthUnavailable
	}
	v, ok := obj["loggedIn"]
	if !ok {
		return false, errClaudeAuthUnavailable
	}
	switch b := v.(type) {
	case bool:
		return b, nil
	default:
		return false, errClaudeAuthUnavailable
	}
}

// claudeAuthCacheKey identities a probe by resolved binary + non-secret launch
// env (PATH, HOME, optional CLAUDE_CONFIG_DIR). Never includes API keys/tokens.
func claudeAuthCacheKey(bin string, env []string) string {
	var path, home, cfg string
	for _, e := range env {
		switch {
		case strings.HasPrefix(e, "PATH="):
			path = e
		case strings.HasPrefix(e, "HOME="):
			home = e
		case strings.HasPrefix(e, "CLAUDE_CONFIG_DIR="):
			cfg = e
		}
	}
	return bin + "\x00" + path + "\x00" + home + "\x00" + cfg
}

// claudeAuthCache holds last-known probe results with dual TTLs.
// generation is a monotonic epoch: invalidate increments it. Each singleflight
// stamps its creation generation under the cache lock; only the flight leader
// publishes on success when that generation still matches. Joiners may observe
// the in-flight result for their call but never republish under a newer epoch.
type claudeAuthCache struct {
	mu         sync.Mutex
	generation uint64
	loggedIn   bool
	ok         bool // true when a successful probe result is present
	at         time.Time
	trueTTL    time.Duration
	falseTTL   time.Duration

	// singleflight
	flights map[string]*claudeAuthFlight

	// status-path background refresh: at most one goroutine
	bgRefresh bool
}

type claudeAuthFlight struct {
	done       chan struct{}
	generation uint64 // cache epoch at flight creation; only leader may publish with this
	loggedIn   bool
	err        error
}

func newClaudeAuthCache(trueTTL, falseTTL time.Duration) *claudeAuthCache {
	if trueTTL <= 0 {
		trueTTL = claudeAuthTrueCacheTTL
	}
	if falseTTL <= 0 {
		falseTTL = claudeAuthFalseCacheTTL
	}
	return &claudeAuthCache{
		trueTTL:  trueTTL,
		falseTTL: falseTTL,
		flights:  make(map[string]*claudeAuthFlight),
	}
}

func (c *claudeAuthCache) ttlFor(loggedIn bool) time.Duration {
	if loggedIn {
		return c.trueTTL
	}
	return c.falseTTL
}

// snapshot returns (loggedIn, fresh, hasValue). hasValue may be true while
// fresh is false (stale last-known for status).
func (c *claudeAuthCache) snapshot() (loggedIn bool, fresh bool, has bool) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if !c.ok {
		return false, false, false
	}
	age := time.Since(c.at)
	fresh = age <= c.ttlFor(c.loggedIn)
	return c.loggedIn, fresh, true
}

func (c *claudeAuthCache) put(loggedIn bool) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.loggedIn = loggedIn
	c.ok = true
	c.at = time.Now()
}

// currentGeneration returns the cache epoch under lock.
func (c *claudeAuthCache) currentGeneration() uint64 {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.generation
}

// putIfGeneration publishes loggedIn only when generation still matches the
// value captured before the probe. Returns false when a mid-flight invalidate
// (or another epoch bump) raced ahead — callers must not treat that as a
// cache hit.
func (c *claudeAuthCache) putIfGeneration(loggedIn bool, gen uint64) bool {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.generation != gen {
		return false
	}
	c.loggedIn = loggedIn
	c.ok = true
	c.at = time.Now()
	return true
}

func (c *claudeAuthCache) invalidate() {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.ok = false
	c.loggedIn = false
	c.at = time.Time{}
	c.generation++
}

func (c *claudeAuthCache) backgroundRefreshInFlight() bool {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.bgRefresh
}

// Package-level cache + runner for status UI and production preflight.
var (
	globalClaudeAuthCache  = newClaudeAuthCache(claudeAuthTrueCacheTTL, claudeAuthFalseCacheTTL)
	claudeAuthRunnerForPkg claudeAuthCommandRunner // nil ⇒ defaultClaudeAuthRunner
)

// Package-level test hook: when true (TestMain in unit tests), a nil
// dispatcher.claudeAuthPreflight skips the live CLI probe so ordinary dispatch
// tests do not shell out. Production leaves this false.
var claudeAuthPreflightDisabledForTest bool

// claudeFirstOutputTimeout is the production time-to-first-output bound for
// Claude Code processes. Zero disables. Tests override temporarily.
var claudeFirstOutputTimeout = 45 * time.Second

// ttfoAppliesTo reports whether the TTFO watchdog should arm for argv.
// Production: Claude only (bare name or absolute path). Tests may override.
var ttfoAppliesTo = func(argv []string) bool {
	if len(argv) == 0 {
		return false
	}
	return filepath.Base(argv[0]) == "claude"
}

func invalidateClaudeAuthCache() {
	globalClaudeAuthCache.invalidate()
}

func resolveClaudeAuthBin(env []string) string {
	bin := "claude"
	if resolved := lookPathIn("claude", env); resolved != "" {
		bin = resolved
	}
	return bin
}

// claudeAuthProbeSingleflight runs one probe per key; concurrent callers share.
func claudeAuthProbeSingleflight(env []string) (bool, error) {
	bin := resolveClaudeAuthBin(env)
	key := claudeAuthCacheKey(bin, env)
	return globalClaudeAuthCache.do(key, func() (bool, error) {
		runner := claudeAuthRunnerForPkg
		return claudeAuthProbe(runner, env, claudeAuthProbeTimeout)
	})
}

func (c *claudeAuthCache) do(key string, fn func() (bool, error)) (bool, error) {
	c.mu.Lock()
	if f, ok := c.flights[key]; ok {
		c.mu.Unlock()
		<-f.done
		// Joiners observe the in-flight result for this call but must never
		// publish it — only the leader publishes with the creation generation.
		return f.loggedIn, f.err
	}
	f := &claudeAuthFlight{
		done:       make(chan struct{}),
		generation: c.generation, // stamp under same lock as flight insert
	}
	c.flights[key] = f
	c.mu.Unlock()

	loggedIn, err := fn()
	f.loggedIn, f.err = loggedIn, err

	c.mu.Lock()
	delete(c.flights, key)
	// Leader-only publish: use creation generation so a mid-flight invalidate
	// (or a joiner that arrived after invalidate) cannot repopulate stale data.
	if err == nil && c.generation == f.generation {
		c.loggedIn = loggedIn
		c.ok = true
		c.at = time.Now()
	}
	c.mu.Unlock()
	close(f.done)
	return loggedIn, err
}

func (c *claudeAuthCache) triggerBackgroundRefresh(env []string) {
	c.mu.Lock()
	if c.bgRefresh {
		c.mu.Unlock()
		return
	}
	c.bgRefresh = true
	c.mu.Unlock()

	go func() {
		defer func() {
			c.mu.Lock()
			c.bgRefresh = false
			c.mu.Unlock()
		}()
		_, err := claudeAuthProbeSingleflight(env)
		if err != nil {
			// Keep last-known on transient probe failure; do not invent false.
			// Successful results are published only by the flight leader.
			return
		}
	}()
}

// probeClaudeLoggedInCached powers agent.status. Never waits on a live probe:
// returns last-known (possibly stale) or nil, and kicks at most one background
// refresh when missing/stale.
func probeClaudeLoggedInCached() *bool {
	loggedIn, fresh, has := globalClaudeAuthCache.snapshot()
	if !fresh {
		globalClaudeAuthCache.triggerBackgroundRefresh(agentLaunchEnvironment())
	}
	if !has {
		return nil
	}
	return ptrBool(loggedIn)
}

// claudeAuthPreflight is the launch gate for Claude Code only.
// loggedIn:false → errClaudeNotLoggedIn (fail-closed).
// probe failure → errClaudeAuthUnavailable (fail-closed; do not launch).
//
// Follow-up (low): singleflight waiters are not yet cancellation-aware —
// do()'s signature has no context. Leave until a caller needs ctx cancel.
func claudeAuthPreflight() error {
	env := agentLaunchEnvironment()

	// Fresh cache hit: avoid re-probe within TTL.
	if loggedIn, fresh, has := globalClaudeAuthCache.snapshot(); has && fresh {
		if !loggedIn {
			return errClaudeNotLoggedIn
		}
		return nil
	}

	loggedIn, err := claudeAuthProbeSingleflight(env)
	if err != nil {
		invalidateClaudeAuthCache()
		return errClaudeAuthUnavailable
	}
	// Cache publication is flight-leader-only (creation generation). Joiners
	// still observe the probe result for this call without republishing.
	if !loggedIn {
		return errClaudeNotLoggedIn
	}
	return nil
}

// isClaudeAuthenticationFailureText reports vendor auth-failure text markers.
// Used only with structured signals or is_error results — never alone on
// benign assistant prose.
func isClaudeAuthenticationFailureText(s string) bool {
	s = strings.ToLower(strings.TrimSpace(s))
	if s == "" {
		return false
	}
	if strings.Contains(s, "authentication_failed") {
		return true
	}
	if strings.Contains(s, "not logged in") {
		return true
	}
	if strings.Contains(s, "/login") {
		return true
	}
	return false
}

// normalizeClaudeAuthErrorMessage maps vendor auth text onto the actionable
// host-side message. Does not advise automating /login.
func normalizeClaudeAuthErrorMessage(raw string) string {
	if isClaudeAuthenticationFailureText(raw) || strings.TrimSpace(raw) == "" {
		return claudeNotLoggedInMessage
	}
	return strings.TrimSpace(raw)
}

// extractClaudeAssistantAuthError requires structured error==authentication_failed
// and/or trusted isApiErrorMessage whose error field itself is an auth marker.
// Arbitrary benign assistant mentions of /login in message content must not classify.
func extractClaudeAssistantAuthError(obj map[string]any) (string, bool) {
	errField, _ := obj["error"].(string)
	isAPI, _ := obj["isApiErrorMessage"].(bool)
	structured := errField == "authentication_failed"
	trustedAPI := isAPI && errField != "" && isClaudeAuthenticationFailureText(errField)
	if !structured && !trustedAPI {
		return "", false
	}
	text := claudeAssistantText(obj)
	if text == "" {
		text = errField
	}
	return normalizeClaudeAuthErrorMessage(text), true
}

// classifyClaudeResultAuthError applies auth classification to a stream-json
// result that extractStreamJSONResultError already accepted. Content heuristic
// only when is_error is set; structured authentication_failed always counts.
func classifyClaudeResultAuthError(obj map[string]any, errText string) bool {
	if e, _ := obj["error"].(string); e == "authentication_failed" {
		return true
	}
	if isAPI, _ := obj["isApiErrorMessage"].(bool); isAPI {
		if e, _ := obj["error"].(string); e != "" && isClaudeAuthenticationFailureText(e) {
			return true
		}
	}
	isError, _ := obj["is_error"].(bool)
	return isError && isClaudeAuthenticationFailureText(errText)
}

func claudeAssistantText(obj map[string]any) string {
	msg, _ := obj["message"].(map[string]any)
	if msg == nil {
		return ""
	}
	switch content := msg["content"].(type) {
	case string:
		return strings.TrimSpace(content)
	case []any:
		var b strings.Builder
		for _, part := range content {
			m, _ := part.(map[string]any)
			if m == nil {
				continue
			}
			if t, _ := m["type"].(string); t != "" && t != "text" {
				continue
			}
			if t, _ := m["text"].(string); t != "" {
				b.WriteString(t)
			}
		}
		return strings.TrimSpace(b.String())
	default:
		return ""
	}
}

// ttfoEventIsProgress reports whether an emitted RPC method represents real
// vendor progress that should cancel the Claude TTFO watchdog.
// Does NOT treat stderr, init-only vendorSession, thinking/starting liveStatus,
// or metadata/heartbeat as progress.
func ttfoEventIsProgress(method string, params any) bool {
	switch method {
	case "agent.run.resultError", "agent.control.request", "agent.tool.start",
		"agent.question.raw", "agent.control.close":
		return true
	case "agent.run.output":
		p, _ := params.(map[string]any)
		if p == nil {
			return false
		}
		if stream, _ := p["stream"].(string); stream == "stderr" {
			return false
		}
		chunk, _ := p["chunk"].(string)
		return strings.TrimSpace(chunk) != ""
	case "agent.run.liveStatus":
		p, _ := params.(map[string]any)
		if p == nil {
			return false
		}
		state, _ := p["state"].(string)
		// tool / streaming are actionable; thinking + starting are not.
		return state == liveStatusTool || state == liveStatusStreaming
	case "agent.run.vendorSession":
		return false
	default:
		return false
	}
}
