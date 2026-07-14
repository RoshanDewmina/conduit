package main

import (
	"context"
	"errors"
	"io"
	"os/exec"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"testing"
	"time"
)

func TestParseClaudeAuthStatusJSON(t *testing.T) {
	t.Parallel()
	cases := []struct {
		name    string
		raw     string
		want    bool
		wantErr bool
	}{
		{"logged_in", `{"loggedIn":true,"email":"x@y.z"}`, true, false},
		{"logged_out", `{"loggedIn":false}`, false, false},
		{"mcp_oauth_shape_no_loggedIn", `{"mcpOAuth":{"token":"secret"}}`, false, true},
		{"empty", ``, false, true},
		{"invalid", `not-json`, false, true},
		{"loggedIn_wrong_type", `{"loggedIn":"yes"}`, false, true},
	}
	for _, tc := range cases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			got, err := parseClaudeAuthStatusJSON([]byte(tc.raw))
			if tc.wantErr {
				if err == nil {
					t.Fatalf("want error, got loggedIn=%v", got)
				}
				return
			}
			if err != nil {
				t.Fatalf("unexpected err: %v", err)
			}
			if got != tc.want {
				t.Fatalf("loggedIn=%v want %v", got, tc.want)
			}
		})
	}
}

func TestClaudeAuthProductionTimeouts(t *testing.T) {
	t.Parallel()
	if claudeAuthProbeTimeout != 20*time.Second {
		t.Fatalf("probe timeout=%v want 20s (covers ~15s cold claude auth status)", claudeAuthProbeTimeout)
	}
	if claudeFirstOutputTimeout != 45*time.Second {
		t.Fatalf("TTFO=%v want 45s", claudeFirstOutputTimeout)
	}
	if claudeAuthTrueCacheTTL < 30*time.Second || claudeAuthTrueCacheTTL > 60*time.Second {
		t.Fatalf("true cache TTL=%v want 30–60s", claudeAuthTrueCacheTTL)
	}
	if claudeAuthFalseCacheTTL <= 0 || claudeAuthFalseCacheTTL >= claudeAuthTrueCacheTTL {
		t.Fatalf("false cache TTL=%v must be short and < true TTL", claudeAuthFalseCacheTTL)
	}
}

func TestClaudeAuthProbeUsesExplicitArgvAndEnv(t *testing.T) {
	t.Parallel()
	var sawBin string
	var sawArgs []string
	var sawEnv []string
	runner := func(ctx context.Context, bin string, args []string, env []string) ([]byte, error) {
		sawBin, sawArgs, sawEnv = bin, append([]string{}, args...), append([]string{}, env...)
		return []byte(`{"loggedIn":true}`), nil
	}
	env := []string{"PATH=/opt/homebrew/bin:/bin", "HOME=/tmp/no-secrets"}
	ok, err := claudeAuthProbe(runner, env, time.Second)
	if err != nil || !ok {
		t.Fatalf("probe: ok=%v err=%v", ok, err)
	}
	if sawBin == "" || strings.Contains(sawBin, " ") {
		t.Fatalf("bin must be explicit path/name, got %q", sawBin)
	}
	wantArgs := []string{"auth", "status", "--json"}
	if len(sawArgs) != len(wantArgs) {
		t.Fatalf("args=%v want %v", sawArgs, wantArgs)
	}
	for i := range wantArgs {
		if sawArgs[i] != wantArgs[i] {
			t.Fatalf("args=%v want %v", sawArgs, wantArgs)
		}
	}
	if len(sawEnv) == 0 || sawEnv[0] != env[0] {
		t.Fatalf("env not forwarded: %v", sawEnv)
	}
}

func TestClaudeAuthProbeTimeout(t *testing.T) {
	t.Parallel()
	runner := func(ctx context.Context, bin string, args []string, env []string) ([]byte, error) {
		<-ctx.Done()
		return nil, ctx.Err()
	}
	_, err := claudeAuthProbe(runner, nil, 30*time.Millisecond)
	if err == nil || !strings.Contains(err.Error(), "auth status unavailable") {
		t.Fatalf("want unavailable timeout error, got %v", err)
	}
}

func TestClaudeAuthCacheKeyOmitsSecrets(t *testing.T) {
	t.Parallel()
	env := []string{
		"PATH=/bin",
		"HOME=/tmp/home",
		"ANTHROPIC_API_KEY=sk-secret-do-not-leak",
		"CLAUDE_API_KEY=also-secret",
	}
	key := claudeAuthCacheKey("/usr/bin/claude", env)
	if strings.Contains(key, "sk-secret") || strings.Contains(key, "also-secret") || strings.Contains(key, "ANTHROPIC") {
		t.Fatalf("cache key must not include secrets: %q", key)
	}
	if !strings.Contains(key, "/usr/bin/claude") || !strings.Contains(key, "PATH=/bin") {
		t.Fatalf("key should include bin+PATH identity: %q", key)
	}
}

func TestClaudeAuthCacheTTLAndInvalidate(t *testing.T) {
	c := newClaudeAuthCache(40*time.Millisecond, 20*time.Millisecond)
	c.put(true)
	if v, fresh, has := c.snapshot(); !has || !fresh || !v {
		t.Fatalf("want fresh true hit")
	}
	c.invalidate()
	if _, _, has := c.snapshot(); has {
		t.Fatalf("invalidate must drop cache")
	}
	c.put(true)
	time.Sleep(50 * time.Millisecond)
	if v, fresh, has := c.snapshot(); !has || fresh || !v {
		t.Fatalf("want stale true after true-TTL: has=%v fresh=%v v=%v", has, fresh, v)
	}
	c.put(false)
	if v, fresh, has := c.snapshot(); !has || !fresh || v {
		t.Fatalf("want fresh false")
	}
	time.Sleep(30 * time.Millisecond)
	if _, fresh, has := c.snapshot(); !has || fresh {
		t.Fatalf("false TTL must expire sooner: has=%v fresh=%v", has, fresh)
	}
}

func TestClaudeAuthSingleflightOneRunner(t *testing.T) {
	resetClaudeAuthCoordinatorForTest(t)
	var calls atomic.Int64
	var release sync.WaitGroup
	release.Add(1)
	claudeAuthRunnerForPkg = func(ctx context.Context, bin string, args []string, env []string) ([]byte, error) {
		calls.Add(1)
		release.Wait()
		return []byte(`{"loggedIn":true}`), nil
	}

	const n = 8
	var started sync.WaitGroup
	var done sync.WaitGroup
	started.Add(n)
	done.Add(n)
	errs := make([]error, n)
	vals := make([]bool, n)
	for i := 0; i < n; i++ {
		go func(i int) {
			started.Done()
			vals[i], errs[i] = claudeAuthProbeSingleflight(agentLaunchEnvironment())
			done.Done()
		}(i)
	}
	started.Wait()
	time.Sleep(30 * time.Millisecond)
	if calls.Load() != 1 {
		release.Done()
		t.Fatalf("want exactly 1 runner during stampede, got %d", calls.Load())
	}
	release.Done()
	done.Wait()
	for i := 0; i < n; i++ {
		if errs[i] != nil || !vals[i] {
			t.Fatalf("[%d] val=%v err=%v", i, vals[i], errs[i])
		}
	}
	if calls.Load() != 1 {
		t.Fatalf("want 1 total runner call, got %d", calls.Load())
	}
}

func TestClaudeAuthSingleflightInvalidateAndExpiry(t *testing.T) {
	resetClaudeAuthCoordinatorForTest(t)
	var calls atomic.Int64
	claudeAuthRunnerForPkg = func(ctx context.Context, bin string, args []string, env []string) ([]byte, error) {
		calls.Add(1)
		return []byte(`{"loggedIn":true}`), nil
	}
	globalClaudeAuthCache.trueTTL = 40 * time.Millisecond
	globalClaudeAuthCache.falseTTL = 15 * time.Millisecond

	if err := claudeAuthPreflight(); err != nil {
		t.Fatalf("preflight: %v", err)
	}
	if err := claudeAuthPreflight(); err != nil {
		t.Fatalf("cached preflight: %v", err)
	}
	if calls.Load() != 1 {
		t.Fatalf("want 1 call via true cache, got %d", calls.Load())
	}

	invalidateClaudeAuthCache()
	if err := claudeAuthPreflight(); err != nil {
		t.Fatalf("after invalidate: %v", err)
	}
	if calls.Load() != 2 {
		t.Fatalf("invalidate must force re-probe, got %d", calls.Load())
	}

	time.Sleep(50 * time.Millisecond)
	if err := claudeAuthPreflight(); err != nil {
		t.Fatalf("after true TTL: %v", err)
	}
	if calls.Load() != 3 {
		t.Fatalf("true TTL expiry must re-probe, got %d", calls.Load())
	}

	invalidateClaudeAuthCache()
	claudeAuthRunnerForPkg = func(ctx context.Context, bin string, args []string, env []string) ([]byte, error) {
		calls.Add(1)
		return []byte(`{"loggedIn":false}`), nil
	}
	if err := claudeAuthPreflight(); !errors.Is(err, errClaudeNotLoggedIn) {
		t.Fatalf("want not-logged-in, got %v", err)
	}
	n := calls.Load()
	if err := claudeAuthPreflight(); !errors.Is(err, errClaudeNotLoggedIn) {
		t.Fatalf("false cache fast-fail: %v", err)
	}
	if calls.Load() != n {
		t.Fatalf("stale false must fast-fail without re-probe during false TTL")
	}
}

func TestClaudeAuthPreflightFailClosedWhenLoggedOut(t *testing.T) {
	resetClaudeAuthCoordinatorForTest(t)
	claudeAuthRunnerForPkg = func(ctx context.Context, bin string, args []string, env []string) ([]byte, error) {
		return []byte(`{"loggedIn":false}`), nil
	}
	err := claudeAuthPreflight()
	if !errors.Is(err, errClaudeNotLoggedIn) {
		t.Fatalf("want errClaudeNotLoggedIn, got %v", err)
	}
	if !strings.Contains(err.Error(), "claude /login on the host") {
		t.Fatalf("message=%q", err.Error())
	}
}

func TestClaudeAuthPreflightFailClosedOnProbeErrors(t *testing.T) {
	cases := []struct {
		name string
		run  claudeAuthCommandRunner
	}{
		{
			name: "invalid_json",
			run: func(ctx context.Context, bin string, args []string, env []string) ([]byte, error) {
				return []byte(`{`), nil
			},
		},
		{
			name: "timeout",
			run: func(ctx context.Context, bin string, args []string, env []string) ([]byte, error) {
				<-ctx.Done()
				return nil, ctx.Err()
			},
		},
		{
			name: "exec_error",
			run: func(ctx context.Context, bin string, args []string, env []string) ([]byte, error) {
				return nil, errors.New("executable file not found")
			},
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			resetClaudeAuthCoordinatorForTest(t)
			globalClaudeAuthCache.put(true) // prior true must not survive a failed re-probe
			globalClaudeAuthCache.trueTTL = time.Nanosecond
			time.Sleep(time.Millisecond) // expire → force live probe
			claudeAuthRunnerForPkg = tc.run
			prevTimeout := claudeAuthProbeTimeout
			if tc.name == "timeout" {
				claudeAuthProbeTimeout = 40 * time.Millisecond
				t.Cleanup(func() { claudeAuthProbeTimeout = prevTimeout })
			}
			err := claudeAuthPreflight()
			if !errors.Is(err, errClaudeAuthUnavailable) {
				t.Fatalf("want errClaudeAuthUnavailable, got %v", err)
			}
			if !strings.Contains(err.Error(), "auth status unavailable — retry") {
				t.Fatalf("message=%q", err.Error())
			}
			if _, _, has := globalClaudeAuthCache.snapshot(); has {
				t.Fatalf("probe failure must invalidate stale logged-in cache")
			}
		})
	}
}

func TestClaudeAuthPreflightAllowsLoggedIn(t *testing.T) {
	resetClaudeAuthCoordinatorForTest(t)
	claudeAuthRunnerForPkg = func(ctx context.Context, bin string, args []string, env []string) ([]byte, error) {
		return []byte(`{"loggedIn":true}`), nil
	}
	if err := claudeAuthPreflight(); err != nil {
		t.Fatalf("loggedIn true must allow: %v", err)
	}
}

func TestProbeClaudeLoggedInCachedNeverBlocks(t *testing.T) {
	resetClaudeAuthCoordinatorForTest(t)
	var release sync.WaitGroup
	release.Add(1)
	claudeAuthRunnerForPkg = func(ctx context.Context, bin string, args []string, env []string) ([]byte, error) {
		release.Wait()
		return []byte(`{"loggedIn":true}`), nil
	}

	start := time.Now()
	got := probeClaudeLoggedInCached()
	elapsed := time.Since(start)
	release.Done()
	if got != nil {
		t.Fatalf("cache miss must omit loggedIn (nil), got %v", *got)
	}
	if elapsed > 100*time.Millisecond {
		t.Fatalf("status path blocked %v waiting on probe", elapsed)
	}

	// Wait for background refresh to populate.
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		if v, _, has := globalClaudeAuthCache.snapshot(); has && v {
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatal("background refresh did not populate cache")
}

func TestProbeClaudeLoggedInCachedReturnsLastKnownAndSingleflightRefresh(t *testing.T) {
	resetClaudeAuthCoordinatorForTest(t)
	globalClaudeAuthCache.trueTTL = 30 * time.Millisecond
	globalClaudeAuthCache.put(true)

	var calls atomic.Int64
	var release sync.WaitGroup
	release.Add(1)
	claudeAuthRunnerForPkg = func(ctx context.Context, bin string, args []string, env []string) ([]byte, error) {
		calls.Add(1)
		release.Wait()
		return []byte(`{"loggedIn":true}`), nil
	}

	time.Sleep(40 * time.Millisecond) // expire → stale last-known
	start := time.Now()
	var wg sync.WaitGroup
	for i := 0; i < 6; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			v := probeClaudeLoggedInCached()
			if v == nil || !*v {
				t.Errorf("want last-known true while refresh blocks")
			}
		}()
	}
	wg.Wait()
	if time.Since(start) > 100*time.Millisecond {
		release.Done()
		t.Fatalf("status path blocked on refresh")
	}
	time.Sleep(30 * time.Millisecond)
	if calls.Load() != 1 {
		release.Done()
		t.Fatalf("concurrent status refresh must singleflight, calls=%d", calls.Load())
	}
	release.Done()
	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		if !globalClaudeAuthCache.backgroundRefreshInFlight() && calls.Load() == 1 {
			return
		}
		time.Sleep(5 * time.Millisecond)
	}
}

func TestClaudeAuthRunnerKillsProcessGroupOnTimeout(t *testing.T) {
	t.Parallel()
	// Test-only shell grandchild: production probe never uses sh -c.
	script := `sleep 60 & exec sleep 60`
	ctx, cancel := context.WithTimeout(context.Background(), 80*time.Millisecond)
	defer cancel()
	start := time.Now()
	_, err := runClaudeAuthCommand(ctx, "/bin/sh", []string{"-c", script}, nil)
	elapsed := time.Since(start)
	if err == nil {
		t.Fatal("want context deadline error")
	}
	if elapsed > 2*time.Second {
		t.Fatalf("runner did not return promptly after kill: %v", elapsed)
	}
	// Best-effort: no sleep orphans with our pgid should remain. We prove the
	// seam (Setpgid + group kill + Wait reap) via the helper returning promptly.
}

func TestClaudeAuthRunnerSetsProcessGroup(t *testing.T) {
	t.Parallel()
	cmd := exec.Command("/bin/sleep", "30")
	prepareClaudeAuthCmd(cmd, nil)
	if cmd.SysProcAttr == nil || !cmd.SysProcAttr.Setpgid {
		t.Fatal("probe command must Setpgid for group kill")
	}
	if err := cmd.Start(); err != nil {
		t.Fatal(err)
	}
	pid := cmd.Process.Pid
	pgid, err := syscall.Getpgid(pid)
	if err != nil {
		_ = cmd.Process.Kill()
		_, _ = cmd.Process.Wait()
		t.Fatal(err)
	}
	if pgid != pid {
		_ = cmd.Process.Kill()
		_, _ = cmd.Process.Wait()
		t.Fatalf("pgid=%d want leader pid=%d", pgid, pid)
	}
	_ = syscall.Kill(-pid, syscall.SIGKILL)
	_, _ = cmd.Process.Wait()
}

func TestMcpOAuthOnlyCredentialsNoLongerPassFileHeuristic(t *testing.T) {
	_, err := parseClaudeAuthStatusJSON([]byte(`{"mcpOAuth":{"accessToken":"x"}}`))
	if err == nil {
		t.Fatal("mcpOAuth-only must not parse as auth status loggedIn")
	}
}

func TestNormalizeClaudeAuthErrorMessage(t *testing.T) {
	t.Parallel()
	got := normalizeClaudeAuthErrorMessage("Not logged in · Please run /login")
	if got != claudeNotLoggedInMessage {
		t.Fatalf("got %q", got)
	}
	got = normalizeClaudeAuthErrorMessage("authentication_failed")
	if got != claudeNotLoggedInMessage {
		t.Fatalf("got %q", got)
	}
}

func TestExtractClaudeAssistantAuthErrorRequiresStructuredSignal(t *testing.T) {
	t.Parallel()
	obj := map[string]any{
		"type":  "assistant",
		"error": "authentication_failed",
		"message": map[string]any{
			"content": []any{
				map[string]any{"type": "text", "text": "Not logged in · Please run /login"},
			},
		},
		"isApiErrorMessage": true,
	}
	msg, ok := extractClaudeAssistantAuthError(obj)
	if !ok {
		t.Fatal("expected auth error")
	}
	if msg != claudeNotLoggedInMessage {
		t.Fatalf("msg=%q", msg)
	}

	// Benign assistant mention of /login must NOT classify.
	benign := map[string]any{
		"type": "assistant",
		"message": map[string]any{
			"content": "See docs: run /login on the host if needed",
		},
	}
	if _, ok := extractClaudeAssistantAuthError(benign); ok {
		t.Fatal("benign /login mention must not classify as auth error")
	}

	// Content-only with wrong error field must not classify on assistant path.
	wrong := map[string]any{
		"type":  "assistant",
		"error": "rate_limit",
		"message": map[string]any{
			"content": "Please run /login",
		},
	}
	if _, ok := extractClaudeAssistantAuthError(wrong); ok {
		t.Fatal("non-auth structured error must not classify via content")
	}

	normal := map[string]any{"type": "assistant", "message": map[string]any{"content": "hello"}}
	if _, ok := extractClaudeAssistantAuthError(normal); ok {
		t.Fatal("normal assistant must not classify as auth error")
	}
}

func TestIsClaudeAuthenticationFailureText(t *testing.T) {
	t.Parallel()
	if !isClaudeAuthenticationFailureText("authentication_failed") {
		t.Fatal()
	}
	if isClaudeAuthenticationFailureText("Credit balance is too low") {
		t.Fatal()
	}
}

func TestTTFOAppliesToAbsoluteClaudeArgv(t *testing.T) {
	t.Parallel()
	if !ttfoAppliesTo([]string{"claude", "-p", "hi"}) {
		t.Fatal("bare claude")
	}
	if !ttfoAppliesTo([]string{"/opt/homebrew/bin/claude", "-p", "hi"}) {
		t.Fatal("absolute claude path must arm TTFO")
	}
	if ttfoAppliesTo([]string{"codex", "exec"}) {
		t.Fatal("codex must not arm Claude TTFO")
	}
	if ttfoAppliesTo([]string{"/bin/sleep", "1"}) {
		t.Fatal("sleep must not arm Claude TTFO")
	}
}

func resetClaudeAuthCoordinatorForTest(t *testing.T) {
	t.Helper()
	prevRunner := claudeAuthRunnerForPkg
	prevTimeout := claudeAuthProbeTimeout
	t.Cleanup(func() {
		claudeAuthRunnerForPkg = prevRunner
		claudeAuthProbeTimeout = prevTimeout
		invalidateClaudeAuthCache()
		globalClaudeAuthCache.trueTTL = claudeAuthTrueCacheTTL
		globalClaudeAuthCache.falseTTL = claudeAuthFalseCacheTTL
	})
	invalidateClaudeAuthCache()
	globalClaudeAuthCache.trueTTL = claudeAuthTrueCacheTTL
	globalClaudeAuthCache.falseTTL = claudeAuthFalseCacheTTL
}

func TestClaudeAuthCacheKeyUsesResolvedBin(t *testing.T) {
	t.Parallel()
	a := claudeAuthCacheKey("/a/claude", []string{"PATH=/bin", "HOME=/tmp"})
	b := claudeAuthCacheKey("/b/claude", []string{"PATH=/bin", "HOME=/tmp"})
	if a == b {
		t.Fatal("different resolved bins must key differently")
	}
}

// --- Generation-safe cache (invalidate mid-flight must not be overwritten) ---

func TestClaudeAuthPutIfGenerationRejectsStale(t *testing.T) {
	c := newClaudeAuthCache(time.Minute, time.Second)
	gen := c.currentGeneration()
	if !c.putIfGeneration(true, gen) {
		t.Fatal("matching generation must publish")
	}
	if v, fresh, has := c.snapshot(); !has || !fresh || !v {
		t.Fatalf("want fresh true after putIfGeneration")
	}
	c.invalidate()
	if c.putIfGeneration(true, gen) {
		t.Fatal("stale generation must not publish after invalidate")
	}
	if _, _, has := c.snapshot(); has {
		t.Fatal("cache must remain unknown after rejected stale put")
	}
	// Fresh capture after invalidate can populate.
	gen2 := c.currentGeneration()
	if !c.putIfGeneration(false, gen2) {
		t.Fatal("post-invalidate generation must publish")
	}
	if v, fresh, has := c.snapshot(); !has || !fresh || v {
		t.Fatalf("want fresh false: has=%v fresh=%v v=%v", has, fresh, v)
	}
}

func TestClaudeAuthInvalidateWhileBlockedProbeLeavesCacheUnknown(t *testing.T) {
	resetClaudeAuthCoordinatorForTest(t)
	var release sync.WaitGroup
	release.Add(1)
	var entered sync.WaitGroup
	entered.Add(1)
	claudeAuthRunnerForPkg = func(ctx context.Context, bin string, args []string, env []string) ([]byte, error) {
		entered.Done()
		release.Wait()
		return []byte(`{"loggedIn":true}`), nil
	}

	var preflightErr error
	var done sync.WaitGroup
	done.Add(1)
	go func() {
		defer done.Done()
		preflightErr = claudeAuthPreflight()
	}()
	entered.Wait()
	invalidateClaudeAuthCache()
	release.Done()
	done.Wait()

	// Waiters may observe the live probe result (true → nil), but cache must
	// stay unknown so a mid-flight invalidate is not overwritten by late success.
	if preflightErr != nil {
		t.Fatalf("waiter may still see probe success without caching; err=%v", preflightErr)
	}
	if _, _, has := globalClaudeAuthCache.snapshot(); has {
		t.Fatal("late true after invalidate must not populate cache")
	}

	// New post-invalidate probe can populate.
	claudeAuthRunnerForPkg = func(ctx context.Context, bin string, args []string, env []string) ([]byte, error) {
		return []byte(`{"loggedIn":true}`), nil
	}
	if err := claudeAuthPreflight(); err != nil {
		t.Fatalf("fresh probe: %v", err)
	}
	if v, fresh, has := globalClaudeAuthCache.snapshot(); !has || !fresh || !v {
		t.Fatalf("post-invalidate probe must populate: has=%v fresh=%v v=%v", has, fresh, v)
	}
}

func TestClaudeAuthInvalidateWhileBlockedBackgroundRefreshLeavesCacheUnknown(t *testing.T) {
	resetClaudeAuthCoordinatorForTest(t)
	var release sync.WaitGroup
	release.Add(1)
	var entered sync.WaitGroup
	entered.Add(1)
	claudeAuthRunnerForPkg = func(ctx context.Context, bin string, args []string, env []string) ([]byte, error) {
		entered.Done()
		release.Wait()
		return []byte(`{"loggedIn":true}`), nil
	}

	_ = probeClaudeLoggedInCached() // miss → kicks background refresh
	entered.Wait()
	invalidateClaudeAuthCache()
	release.Done()

	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		if !globalClaudeAuthCache.backgroundRefreshInFlight() {
			break
		}
		time.Sleep(5 * time.Millisecond)
	}
	if globalClaudeAuthCache.backgroundRefreshInFlight() {
		t.Fatal("background refresh did not finish")
	}
	if _, _, has := globalClaudeAuthCache.snapshot(); has {
		t.Fatal("late background true after invalidate must not populate cache")
	}
}

func TestClaudeAuthInvalidateWhileBlockedProbeFalseLeavesCacheUnknown(t *testing.T) {
	resetClaudeAuthCoordinatorForTest(t)
	var release sync.WaitGroup
	release.Add(1)
	var entered sync.WaitGroup
	entered.Add(1)
	claudeAuthRunnerForPkg = func(ctx context.Context, bin string, args []string, env []string) ([]byte, error) {
		entered.Done()
		release.Wait()
		return []byte(`{"loggedIn":false}`), nil
	}

	var preflightErr error
	var done sync.WaitGroup
	done.Add(1)
	go func() {
		defer done.Done()
		preflightErr = claudeAuthPreflight()
	}()
	entered.Wait()
	invalidateClaudeAuthCache()
	release.Done()
	done.Wait()

	if !errors.Is(preflightErr, errClaudeNotLoggedIn) {
		t.Fatalf("waiter still sees probe false: %v", preflightErr)
	}
	if _, _, has := globalClaudeAuthCache.snapshot(); has {
		t.Fatal("late false after invalidate must not populate cache")
	}
}

func TestClaudeAuthGenerationRaceClean(t *testing.T) {
	c := newClaudeAuthCache(time.Minute, time.Second)
	var wg sync.WaitGroup
	for i := 0; i < 32; i++ {
		wg.Add(2)
		go func() {
			defer wg.Done()
			gen := c.currentGeneration()
			_ = c.putIfGeneration(true, gen)
		}()
		go func() {
			defer wg.Done()
			c.invalidate()
		}()
	}
	wg.Wait()
	// After races settle, either unknown or a value published with matching gen.
	gen := c.currentGeneration()
	if c.putIfGeneration(false, gen-1) {
		t.Fatal("stale generation must never win")
	}
}

// Post-invalidate joiners must not republish an old flight's result under the
// newer generation. Flight starts at gen0; invalidate→1; second caller joins
// the still-running gen0 flight; release must leave cache unknown; a third
// call after completion must start a new probe and populate.
func TestClaudeAuthPostInvalidateJoinerDoesNotRepublishOldFlightTrue(t *testing.T) {
	resetClaudeAuthCoordinatorForTest(t)
	var calls atomic.Int32
	var release sync.WaitGroup
	release.Add(1)
	var entered sync.WaitGroup
	entered.Add(1)
	claudeAuthRunnerForPkg = func(ctx context.Context, bin string, args []string, env []string) ([]byte, error) {
		n := calls.Add(1)
		if n == 1 {
			entered.Done()
			release.Wait()
		}
		return []byte(`{"loggedIn":true}`), nil
	}

	var leaderErr, joinerErr error
	var wg sync.WaitGroup
	wg.Add(1)
	go func() {
		defer wg.Done()
		leaderErr = claudeAuthPreflight()
	}()
	entered.Wait()
	invalidateClaudeAuthCache()

	wg.Add(1)
	go func() {
		defer wg.Done()
		joinerErr = claudeAuthPreflight()
	}()
	// Allow joiner to capture post-invalidate generation and attach to the
	// still-blocked gen0 flight before release.
	time.Sleep(30 * time.Millisecond)
	release.Done()
	wg.Wait()

	if leaderErr != nil {
		t.Fatalf("leader may observe probe true: %v", leaderErr)
	}
	if joinerErr != nil {
		t.Fatalf("joiner may observe probe true for its call: %v", joinerErr)
	}
	if calls.Load() != 1 {
		t.Fatalf("joiner must share gen0 flight, probe calls=%d want 1", calls.Load())
	}
	if _, _, has := globalClaudeAuthCache.snapshot(); has {
		t.Fatal("joiner must not putIfGeneration under post-invalidate generation; cache must stay unknown")
	}

	if err := claudeAuthPreflight(); err != nil {
		t.Fatalf("third post-completion probe: %v", err)
	}
	if calls.Load() != 2 {
		t.Fatalf("third probe must invoke runner again, calls=%d want 2", calls.Load())
	}
	if v, fresh, has := globalClaudeAuthCache.snapshot(); !has || !fresh || !v {
		t.Fatalf("new flight after invalidate must populate: has=%v fresh=%v v=%v", has, fresh, v)
	}
}

func TestClaudeAuthPostInvalidateBackgroundJoinerDoesNotRepublishOldFlight(t *testing.T) {
	resetClaudeAuthCoordinatorForTest(t)
	var calls atomic.Int32
	var release sync.WaitGroup
	release.Add(1)
	var entered sync.WaitGroup
	entered.Add(1)
	claudeAuthRunnerForPkg = func(ctx context.Context, bin string, args []string, env []string) ([]byte, error) {
		n := calls.Add(1)
		if n == 1 {
			entered.Done()
			release.Wait()
		}
		return []byte(`{"loggedIn":true}`), nil
	}

	var leaderErr error
	var wg sync.WaitGroup
	wg.Add(1)
	go func() {
		defer wg.Done()
		leaderErr = claudeAuthPreflight()
	}()
	entered.Wait()
	invalidateClaudeAuthCache()

	// Status path kicks background refresh; it must join the old flight, not
	// republish under the newer generation when the probe completes.
	_ = probeClaudeLoggedInCached()
	time.Sleep(30 * time.Millisecond)
	release.Done()
	wg.Wait()

	deadline := time.Now().Add(2 * time.Second)
	for time.Now().Before(deadline) {
		if !globalClaudeAuthCache.backgroundRefreshInFlight() && calls.Load() >= 1 {
			break
		}
		time.Sleep(5 * time.Millisecond)
	}
	if leaderErr != nil {
		t.Fatalf("leader may observe probe true: %v", leaderErr)
	}
	if calls.Load() != 1 {
		t.Fatalf("background joiner must share gen0 flight, calls=%d want 1", calls.Load())
	}
	if _, _, has := globalClaudeAuthCache.snapshot(); has {
		t.Fatal("background joiner must not republish old flight under newer generation")
	}

	if err := claudeAuthPreflight(); err != nil {
		t.Fatalf("third post-completion probe: %v", err)
	}
	if calls.Load() != 2 {
		t.Fatalf("third probe must invoke runner again, calls=%d want 2", calls.Load())
	}
	if v, fresh, has := globalClaudeAuthCache.snapshot(); !has || !fresh || !v {
		t.Fatalf("new flight after invalidate must populate: has=%v fresh=%v v=%v", has, fresh, v)
	}
}

func TestClaudeAuthPostInvalidateJoinerDoesNotRepublishOldFlightFalse(t *testing.T) {
	resetClaudeAuthCoordinatorForTest(t)
	var calls atomic.Int32
	var release sync.WaitGroup
	release.Add(1)
	var entered sync.WaitGroup
	entered.Add(1)
	claudeAuthRunnerForPkg = func(ctx context.Context, bin string, args []string, env []string) ([]byte, error) {
		n := calls.Add(1)
		if n == 1 {
			entered.Done()
			release.Wait()
			return []byte(`{"loggedIn":false}`), nil
		}
		return []byte(`{"loggedIn":true}`), nil
	}

	var leaderErr, joinerErr error
	var wg sync.WaitGroup
	wg.Add(1)
	go func() {
		defer wg.Done()
		leaderErr = claudeAuthPreflight()
	}()
	entered.Wait()
	invalidateClaudeAuthCache()

	wg.Add(1)
	go func() {
		defer wg.Done()
		joinerErr = claudeAuthPreflight()
	}()
	time.Sleep(30 * time.Millisecond)
	release.Done()
	wg.Wait()

	if !errors.Is(leaderErr, errClaudeNotLoggedIn) {
		t.Fatalf("leader observes probe false: %v", leaderErr)
	}
	if !errors.Is(joinerErr, errClaudeNotLoggedIn) {
		t.Fatalf("joiner observes probe false for its call: %v", joinerErr)
	}
	if calls.Load() != 1 {
		t.Fatalf("joiner must share gen0 flight, calls=%d want 1", calls.Load())
	}
	if _, _, has := globalClaudeAuthCache.snapshot(); has {
		t.Fatal("false joiner must not republish old flight under newer generation")
	}

	if err := claudeAuthPreflight(); err != nil {
		t.Fatalf("third post-completion probe: %v", err)
	}
	if calls.Load() != 2 {
		t.Fatalf("third probe must invoke runner again, calls=%d want 2", calls.Load())
	}
	if v, fresh, has := globalClaudeAuthCache.snapshot(); !has || !fresh || !v {
		t.Fatalf("new flight after invalidate must populate true: has=%v fresh=%v v=%v", has, fresh, v)
	}
}

// --- Probe I/O safety ---

func TestClaudeAuthPrepareDiscardsStderr(t *testing.T) {
	t.Parallel()
	cmd := exec.Command("/bin/echo", "hi")
	prepareClaudeAuthCmd(cmd, nil)
	if cmd.Stderr == nil {
		t.Fatal("stderr must be set (not inherited)")
	}
	// Must be io.Discard (or equivalent non-inheriting sink) — never the
	// process stderr and never a logging writer that could leak probe PII.
	if cmd.Stderr != io.Discard {
		t.Fatalf("stderr must be io.Discard, got %T", cmd.Stderr)
	}
}

func TestClaudeAuthRunnerRejectsOversizedStdoutWithoutLeaking(t *testing.T) {
	t.Parallel()
	// Produce >64KiB of stdout containing a fake secret; overflow must yield
	// a generic unavailable error with no content/PII in the message.
	secret := "PII-SECRET-do-not-leak-in-error"
	script := `python3 -c 'import sys; sys.stdout.write("{\"loggedIn\":true,\"email\":\"` + secret + `\"}" + ("x"*70000))'`
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	out, err := runClaudeAuthCommand(ctx, "/bin/sh", []string{"-c", script}, nil)
	if err == nil {
		t.Fatal("want overflow error")
	}
	if !errors.Is(err, errClaudeAuthUnavailable) && !strings.Contains(err.Error(), "auth status unavailable") {
		t.Fatalf("want generic unavailable, got %v", err)
	}
	if strings.Contains(err.Error(), secret) || strings.Contains(err.Error(), "loggedIn") {
		t.Fatalf("error must not leak probe content: %v", err)
	}
	if strings.Contains(string(out), secret) {
		t.Fatal("returned stdout must not carry overflow content with PII")
	}
}
