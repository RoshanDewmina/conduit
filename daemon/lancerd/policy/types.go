package policy

// Effect is the policy decision for a matched rule or default.
type Effect string

const (
	EffectDeny  Effect = "deny"
	EffectAsk   Effect = "ask"
	EffectAllow Effect = "allow"
)

func effectRank(e Effect) int {
	switch e {
	case EffectDeny:
		return 3
	case EffectAsk:
		return 2
	case EffectAllow:
		return 1
	default:
		return 0
	}
}

// ParseEffect normalizes YAML/JSON effect strings; unknown → ask (fail-closed).
func ParseEffect(s string) Effect {
	switch Effect(s) {
	case EffectDeny, EffectAsk, EffectAllow:
		return Effect(s)
	case "escalate":
		return EffectAsk
	default:
		return EffectAsk
	}
}

// Document is one YAML policy file (global, always-allow, or repo-local).
type Document struct {
	Default string `yaml:"default,omitempty" json:"default,omitempty"`
	Rules   []Rule `yaml:"rules,omitempty" json:"rules,omitempty"`
}

// Rule matches hook events; multiple rules may match — Evaluate picks strictest effect.
type Rule struct {
	ID      string `yaml:"id,omitempty" json:"id,omitempty"`
	Effect  string `yaml:"effect" json:"effect"`
	Agent   string `yaml:"agent,omitempty" json:"agent,omitempty"`
	Tool    string `yaml:"tool,omitempty" json:"tool,omitempty"`
	Kind    string `yaml:"kind,omitempty" json:"kind,omitempty"`
	Match   string `yaml:"match,omitempty" json:"match,omitempty"`
	CWD     string `yaml:"cwd,omitempty" json:"cwd,omitempty"`
	MinRisk string `yaml:"minRisk,omitempty" json:"minRisk,omitempty"`
	MaxRisk string `yaml:"maxRisk,omitempty" json:"maxRisk,omitempty"`
	// Scoped fields for allow-always rules with expiry
	Repo        string `yaml:"repo,omitempty" json:"repo,omitempty"`
	PathPattern string `yaml:"pathPattern,omitempty" json:"pathPattern,omitempty"`
	ExpiresAt   string `yaml:"expiresAt,omitempty" json:"expiresAt,omitempty"`
	TimeWindow  string `yaml:"timeWindow,omitempty" json:"timeWindow,omitempty"`
	CreatedAt   string `yaml:"createdAt,omitempty" json:"createdAt,omitempty"`
}

// Request carries fields needed to evaluate a hook / approval event.
type Request struct {
	Agent   string
	Tool    string
	Kind    string
	Command string
	CWD     string
	Risk    int // 0=low … 3=critical; -1 triggers local scoring
}

// Result is returned from Evaluate.
type Result struct {
	Effect          Effect
	MatchedRule     string
	FromDefault     bool
	ShouldEscalate  bool
	ScoredRisk      int
	ScoredRiskLabel string
}

// PresetDocument returns a named, human-recognizable policy preset. These map 1:1
// to the iOS autonomy quick-set. Unknown names return ok=false.
func PresetDocument(name string) (Document, bool) {
	switch name {
	case "cautious":
		return Document{
			Default: string(EffectAsk),
			Rules: []Rule{
				{ID: "deny-credential", Effect: "deny", Kind: "credential"},
				{ID: "deny-network", Effect: "deny", Kind: "network"},
				{ID: "deny-critical", Effect: "deny", MinRisk: "critical"},
				{ID: "deny-high", Effect: "deny", MinRisk: "high"},
				{ID: "ask-rest", Effect: "ask"},
			},
		}, true
	case "balanced":
		return DefaultDocument(), true
	case "bypass":
		return Document{
			Default: string(EffectAsk),
			Rules: []Rule{
				{ID: "deny-credential", Effect: "deny", Kind: "credential"},
				{ID: "deny-network", Effect: "deny", Kind: "network"},
				{ID: "deny-critical", Effect: "deny", MinRisk: "critical"},
				{ID: "allow-command", Effect: "allow", Kind: "command", MaxRisk: "high"},
				{ID: "allow-patch", Effect: "allow", Kind: "patch"},
				{ID: "allow-write", Effect: "allow", Kind: "fileWrite"},
				{ID: "ask-rest", Effect: "ask"},
			},
		}, true
	default:
		return Document{}, false
	}
}

// DefaultDocument is the bundled safe-default policy (fail-closed ask).
func DefaultDocument() Document {
	return Document{
		Default: string(EffectAsk),
		Rules: []Rule{
			{ID: "deny-credential", Effect: "deny", Kind: "credential"},
			{ID: "deny-network", Effect: "deny", Kind: "network"},
			{ID: "deny-critical", Effect: "deny", MinRisk: "critical"},
			{ID: "allow-low-readonly", Effect: "allow", Kind: "command", MaxRisk: "low"},
			{ID: "ask-patch", Effect: "ask", Kind: "patch"},
			{ID: "ask-file-write", Effect: "ask", Kind: "fileWrite"},
			{ID: "ask-file-delete", Effect: "ask", Kind: "fileDelete"},
			{ID: "ask-browser", Effect: "ask", Kind: "browser"},
			{ID: "ask-mcp", Effect: "ask", Kind: "callMCP"},
			{ID: "ask-high", Effect: "ask", MinRisk: "high"},
			{ID: "ask-medium", Effect: "ask", MinRisk: "medium"},
		},
	}
}
