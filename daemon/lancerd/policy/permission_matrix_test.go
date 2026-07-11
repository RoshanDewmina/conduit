package policy

import (
	"testing"
	"time"
)

// Permission matrix — shape ported from Happier's per-provider × per-mode ×
// timeout harness (patterns only; Happier is not MIT). Encodes Lancer's
// stronger semantics: scoped-with-expiry allow rules, fail-closed default ask,
// deny beats allow. Production policy code is not modified here.
//
// Dimensions covered:
//
//	vendors: claudeCode, codex, opencode, kimi
//	modes:   auto-approve (scoped+expiry), ask/hold, deny-rule
//	plus:    expiry-elapsed, scope-mismatch (repo/tool/agent), deny-beats-allow

var matrixVendors = []string{"claudeCode", "codex", "opencode", "kimi"}

func futureExpiry() string {
	return time.Now().UTC().Add(24 * time.Hour).Format(time.RFC3339)
}

func pastExpiry() string {
	return time.Now().UTC().Add(-time.Hour).Format(time.RFC3339)
}

func scopedAllow(vendor string) Rule {
	return Rule{
		ID:        "matrix-allow-" + vendor,
		Effect:    string(EffectAllow),
		Agent:     vendor,
		Tool:      "Bash",
		Repo:      "/repo/**",
		Match:     "npm test*",
		ExpiresAt: futureExpiry(),
	}
}

func matrixReq(vendor, command, cwd, tool string) Request {
	return Request{
		Agent:   vendor,
		Kind:    "command",
		Command: command,
		CWD:     cwd,
		Tool:    tool,
		Risk:    -1,
	}
}

func TestPermissionMatrixAutoApproveScoped(t *testing.T) {
	for _, vendor := range matrixVendors {
		vendor := vendor
		t.Run(vendor, func(t *testing.T) {
			doc := Document{
				Default: string(EffectAsk),
				Rules:   []Rule{scopedAllow(vendor)},
			}
			res := Evaluate(doc, matrixReq(vendor, "npm test --filter a", "/repo/app", "Bash"))
			if res.Effect != EffectAllow {
				t.Fatalf("scoped allow with future expiry must approve, got %v (%s)", res.Effect, res.MatchedRule)
			}
			if res.FromDefault || res.ShouldEscalate {
				t.Fatalf("matched allow must not escalate/fromDefault: %+v", res)
			}
		})
	}
}

func TestPermissionMatrixAutoApproveExpiryElapsed(t *testing.T) {
	for _, vendor := range matrixVendors {
		vendor := vendor
		t.Run(vendor, func(t *testing.T) {
			rule := scopedAllow(vendor)
			rule.ExpiresAt = pastExpiry()
			doc := Document{Default: string(EffectAsk), Rules: []Rule{rule}}
			res := Evaluate(doc, matrixReq(vendor, "npm test", "/repo/app", "Bash"))
			if res.Effect != EffectAsk || !res.FromDefault {
				t.Fatalf("elapsed expiry must fall through to ask, got %v fromDefault=%v (%s)",
					res.Effect, res.FromDefault, res.MatchedRule)
			}
		})
	}
}

func TestPermissionMatrixAutoApproveScopeMismatch(t *testing.T) {
	type mismatch struct {
		name string
		mut  func(Rule) Rule
		req  func(vendor string) Request
	}
	cases := []mismatch{
		{
			name: "repo",
			mut:  func(r Rule) Rule { return r },
			req: func(vendor string) Request {
				return matrixReq(vendor, "npm test", "/other/app", "Bash")
			},
		},
		{
			name: "tool",
			mut:  func(r Rule) Rule { return r },
			req: func(vendor string) Request {
				return matrixReq(vendor, "npm test", "/repo/app", "Edit")
			},
		},
		{
			name: "agent",
			mut:  func(r Rule) Rule { return r },
			req: func(vendor string) Request {
				other := "codex"
				if vendor == "codex" {
					other = "kimi"
				}
				return matrixReq(other, "npm test", "/repo/app", "Bash")
			},
		},
		{
			name: "command-prefix",
			mut:  func(r Rule) Rule { return r },
			req: func(vendor string) Request {
				return matrixReq(vendor, "rm -rf /tmp", "/repo/app", "Bash")
			},
		},
		{
			name: "pathPattern",
			mut: func(r Rule) Rule {
				r.Match = ""
				r.PathPattern = "src/**"
				r.Kind = "fileWrite"
				return r
			},
			req: func(vendor string) Request {
				return Request{
					Agent:   vendor,
					Kind:    "fileWrite",
					Command: "README.md",
					CWD:     "/repo/app",
					Tool:    "Bash",
					Risk:    -1,
				}
			},
		},
	}

	for _, vendor := range matrixVendors {
		vendor := vendor
		t.Run(vendor, func(t *testing.T) {
			for _, tc := range cases {
				tc := tc
				t.Run(tc.name, func(t *testing.T) {
					doc := Document{
						Default: string(EffectAsk),
						Rules:   []Rule{tc.mut(scopedAllow(vendor))},
					}
					res := Evaluate(doc, tc.req(vendor))
					if res.Effect == EffectAllow {
						t.Fatalf("scope mismatch %q must not allow, got allow (%s)", tc.name, res.MatchedRule)
					}
					if res.Effect != EffectAsk {
						t.Fatalf("scope mismatch %q want ask, got %v (%s)", tc.name, res.Effect, res.MatchedRule)
					}
				})
			}
		})
	}
}

func TestPermissionMatrixAskHold(t *testing.T) {
	for _, vendor := range matrixVendors {
		vendor := vendor
		t.Run(vendor, func(t *testing.T) {
			doc := Document{Default: string(EffectAsk)}
			res := Evaluate(doc, matrixReq(vendor, "npm install left-pad", "/repo/app", "Bash"))
			if res.Effect != EffectAsk {
				t.Fatalf("ask/hold mode must ask, got %v", res.Effect)
			}
			if !res.ShouldEscalate {
				t.Fatal("ask/hold must set ShouldEscalate")
			}
			if !res.FromDefault {
				t.Fatal("empty rules must come from default")
			}
		})
	}
}

func TestPermissionMatrixDenyRule(t *testing.T) {
	for _, vendor := range matrixVendors {
		vendor := vendor
		t.Run(vendor, func(t *testing.T) {
			doc := Document{
				Default: string(EffectAsk),
				Rules: []Rule{{
					ID:     "matrix-deny-" + vendor,
					Effect: string(EffectDeny),
					Agent:  vendor,
					Match:  "rm -rf*",
				}},
			}
			res := Evaluate(doc, matrixReq(vendor, "rm -rf /tmp/x", "/repo/app", "Bash"))
			if res.Effect != EffectDeny {
				t.Fatalf("deny-rule must deny, got %v (%s)", res.Effect, res.MatchedRule)
			}
			if res.ShouldEscalate {
				t.Fatal("deny must not escalate")
			}
		})
	}
}

func TestPermissionMatrixDenyBeatsScopedAllow(t *testing.T) {
	for _, vendor := range matrixVendors {
		vendor := vendor
		t.Run(vendor, func(t *testing.T) {
			allow := scopedAllow(vendor)
			allow.Match = "rm -rf*"
			doc := Document{
				Default: string(EffectAsk),
				Rules: []Rule{
					allow,
					{
						ID:     "matrix-deny-strict-" + vendor,
						Effect: string(EffectDeny),
						Agent:  vendor,
						Match:  "rm -rf*",
					},
				},
			}
			res := Evaluate(doc, matrixReq(vendor, "rm -rf /tmp/x", "/repo/app", "Bash"))
			if res.Effect != EffectDeny {
				t.Fatalf("deny must beat scoped allow, got %v (%s)", res.Effect, res.MatchedRule)
			}
		})
	}
}

func TestPermissionMatrixFailClosedEmptyDefault(t *testing.T) {
	for _, vendor := range matrixVendors {
		vendor := vendor
		t.Run(vendor, func(t *testing.T) {
			res := Evaluate(Document{}, matrixReq(vendor, "echo hi", "/repo", "Bash"))
			if res.Effect != EffectAsk || !res.FromDefault {
				t.Fatalf("empty doc must fail-closed ask, got %v fromDefault=%v", res.Effect, res.FromDefault)
			}
		})
	}
}

func TestPermissionMatrixValidateAllowRuleGate(t *testing.T) {
	for _, vendor := range matrixVendors {
		vendor := vendor
		t.Run(vendor+"/valid", func(t *testing.T) {
			rule := scopedAllow(vendor)
			if err := ValidateAllowRule(rule); err != nil {
				t.Fatalf("valid scoped+expiry allow must pass ValidateAllowRule: %v", err)
			}
		})
		t.Run(vendor+"/missing-expiry", func(t *testing.T) {
			rule := scopedAllow(vendor)
			rule.ExpiresAt = ""
			if err := ValidateAllowRule(rule); err == nil {
				t.Fatal("missing ExpiresAt must be rejected")
			}
		})
		t.Run(vendor+"/unscoped", func(t *testing.T) {
			rule := Rule{
				Effect:    string(EffectAllow),
				Agent:     vendor,
				ExpiresAt: futureExpiry(),
			}
			if err := ValidateAllowRule(rule); err == nil {
				t.Fatal("unscoped allow must be rejected")
			}
		})
		t.Run(vendor+"/past-expiry", func(t *testing.T) {
			rule := scopedAllow(vendor)
			rule.ExpiresAt = pastExpiry()
			if err := ValidateAllowRule(rule); err == nil {
				t.Fatal("past ExpiresAt must be rejected at remember-time")
			}
		})
	}
}

// Invalid ExpiresAt on an already-persisted rule: fail-closed expectation is that
// the rule does not match (treat unparseable expiry as expired / non-matching).
// If production still honors the allow, record as a real bug and skip.
func TestPermissionMatrixInvalidExpiresAtFailClosed(t *testing.T) {
	for _, vendor := range matrixVendors {
		vendor := vendor
		t.Run(vendor, func(t *testing.T) {
			rule := scopedAllow(vendor)
			rule.ExpiresAt = "not-a-timestamp"
			doc := Document{Default: string(EffectAsk), Rules: []Rule{rule}}
			res := Evaluate(doc, matrixReq(vendor, "npm test", "/repo/app", "Bash"))
			if res.Effect != EffectAsk {
				t.Fatalf("invalid ExpiresAt want ask, got %v (%s)", res.Effect, res.MatchedRule)
			}
		})
	}
}

func TestPermissionMatrixPermitsNoClientGraceBands(t *testing.T) {
	// Unreachable-client grace is only for low/medium; high/critical must stay held.
	// Asserted here so the matrix documents the risk-band dimension that the
	// daemon unreachable seam depends on.
	for _, tc := range []struct {
		risk int
		want bool
	}{
		{0, true},
		{1, true},
		{2, false},
		{3, false},
	} {
		if got := PermitsNoClientGrace(tc.risk); got != tc.want {
			t.Fatalf("PermitsNoClientGrace(%d)=%v want %v", tc.risk, got, tc.want)
		}
	}
}
