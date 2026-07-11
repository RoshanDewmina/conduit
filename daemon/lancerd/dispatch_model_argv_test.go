package main

import "testing"

// Regression: --model must never displace the trailing "-p", prompt pair —
// claudeStdinPromptArgv only engages stdin-prompt mode when argv[len-2]=="-p".
// A model-specified dispatch previously appended --model after the pair,
// disabling the rewrite: claude launched with --input-format stream-json and
// an unfed stdin, exiting on EOF with zero output (live, 2026-07-11).
func TestClaudeModelKeepsPromptPairTrailing(t *testing.T) {
	cases := []struct {
		name string
		argv []string
		ok   bool
	}{}
	_ = cases

	for _, model := range []string{"", "haiku", "sonnet", "opus"} {
		argv, ok := agentArgv("claudeCode", "do the thing", model)
		if !ok {
			t.Fatalf("agentArgv failed for model %q", model)
		}
		if argv[len(argv)-2] != "-p" || argv[len(argv)-1] != "do the thing" {
			t.Fatalf("model %q: -p/prompt not trailing: %v", model, argv)
		}
		if _, prompt, ok := claudeStdinPromptArgv(argv); !ok || prompt != "do the thing" {
			t.Fatalf("model %q: claudeStdinPromptArgv disengaged: %v", model, argv)
		}
		cont, ok := continueArgv("claudeCode", "again", model)
		if !ok || cont[len(cont)-2] != "-p" {
			t.Fatalf("continueArgv model %q: -p not trailing: %v", model, cont)
		}
		res, ok := resumeArgv("claudeCode", "sess-123", "again", model)
		if !ok || res[len(res)-2] != "-p" {
			t.Fatalf("resumeArgv model %q: -p not trailing: %v", model, res)
		}
	}
}
