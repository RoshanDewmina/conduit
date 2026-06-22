package main

import "testing"

func TestScopeMatches_SegmentWise(t *testing.T) {
	cases := []struct {
		authorized, secret string
		want               bool
		why                string
	}{
		{"api:github", "api:github", true, "exact match"},
		{"api", "api:github", true, "segment-prefix broadens"},
		{"api", "api:github:repo", true, "multi-segment prefix"},
		{"api", "api-admin", false, "substring is NOT a segment match (bypass closed)"},
		{"prod", "production-admin", false, "prefix bypass closed"},
		{"read", "readALLSECRETS", false, "unanchored prefix bypass closed"},
		{"api:github", "api:gitlab", false, "sibling segment differs"},
		{"api:github", "api", false, "narrow auth cannot cover broader secret"},
		{"", "api:github", false, "empty auth matches nothing (fail-closed)"},
		{"*", "api:github", false, "wildcard auth matches nothing (fail-closed)"},
		{"api:github", "", false, "empty secret scope never matches"},
	}
	for _, c := range cases {
		if got := scopeMatches(c.authorized, c.secret); got != c.want {
			t.Errorf("scopeMatches(%q, %q) = %v, want %v — %s", c.authorized, c.secret, got, c.want, c.why)
		}
	}
}

func TestAuthorize_RejectsBroadScopes(t *testing.T) {
	s := &secretsStore{
		path:           t.TempDir() + "/secrets.json",
		secrets:        map[string]*secretEntry{},
		authorizations: map[string]*secretAuth{},
		pending:        map[string]*pendingSecretRequest{},
	}
	for _, bad := range []string{"", "  ", "*"} {
		if err := s.authorize("req1", bad, nil, false, "user"); err == nil {
			t.Errorf("authorize accepted broad scope %q; want rejection", bad)
		}
		if _, ok := s.authorizations["req1"]; ok {
			t.Errorf("authorize stored an authorization for rejected scope %q", bad)
		}
	}
	if err := s.authorize("req2", "api:github", nil, false, "user"); err != nil {
		t.Errorf("authorize rejected a concrete scope: %v", err)
	}
}
