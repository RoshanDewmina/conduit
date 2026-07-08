package policy

import (
	"errors"
	"time"
)

// MaxRememberedRuleTTL bounds how far in the future a phone-created "approve
// and remember" allow rule may expire. Unbounded phone-created allows are
// forbidden — see ValidateAllowRule.
const MaxRememberedRuleTTL = 30 * 24 * time.Hour

// ValidateAllowRule is the fail-closed gate a phone-supplied "approve and
// remember" rule must pass before AppendAllowRule ever writes it to
// policy-always.yaml: it must be an allow rule, scoped to something narrower
// than "everything" (a repo, a path pattern, or a tool), and bounded by an
// ExpiresAt no further out than MaxRememberedRuleTTL. Any violation rejects
// the rule; the approve decision itself is unaffected — only the remembered
// rule is dropped, so the same event will simply prompt again next time.
func ValidateAllowRule(rule Rule) error {
	if ParseEffect(rule.Effect) != EffectAllow {
		return errors.New("allow rule must have effect \"allow\"")
	}
	if rule.Repo == "" && rule.PathPattern == "" && rule.Tool == "" {
		return errors.New("allow rule must be scoped by repo, pathPattern, or tool")
	}
	if rule.ExpiresAt == "" {
		return errors.New("allow rule must set expiresAt")
	}
	expiresAt, err := time.Parse(time.RFC3339, rule.ExpiresAt)
	if err != nil {
		return errors.New("allow rule expiresAt must be RFC3339")
	}
	now := time.Now()
	if !expiresAt.After(now) {
		return errors.New("allow rule expiresAt must be in the future")
	}
	if expiresAt.After(now.Add(MaxRememberedRuleTTL)) {
		return errors.New("allow rule expiresAt exceeds the 30-day maximum for phone-created rules")
	}
	return nil
}
