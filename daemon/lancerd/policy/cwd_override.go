package policy

import (
	"os"
	"path/filepath"
	"strings"

	"gopkg.in/yaml.v3"
)

const CWDOverrideFile = "permission-mode-overrides.yaml"

// cwdOverrideDoc is the on-disk map of absolute/clean cwd → coarse mode.
type cwdOverrideDoc struct {
	Overrides map[string]string `yaml:"overrides"`
}

// CWDOverridePath returns ~/.lancer/permission-mode-overrides.yaml.
func CWDOverridePath(home string) string {
	return filepath.Join(LancerDir(home), CWDOverrideFile)
}

// IsGlobalCWD reports whether cwd means the document-level (Settings) default
// rather than a per-chat repo override. Empty and "~" keep today's global
// semantics.
func IsGlobalCWD(cwd string) bool {
	trimmed := strings.TrimSpace(cwd)
	return trimmed == "" || trimmed == "~"
}

// NormalizeCWD cleans a scoped cwd for stable map keys. Abs when possible so
// "/tmp/foo/../foo" and "/tmp/foo" share a key; on Abs failure, Clean only.
func NormalizeCWD(cwd string) string {
	trimmed := strings.TrimSpace(cwd)
	if trimmed == "" {
		return ""
	}
	cleaned := filepath.Clean(trimmed)
	if abs, err := filepath.Abs(cleaned); err == nil {
		return abs
	}
	return cleaned
}

// LookupCWDOverride returns the coarse mode for cwd when a valid override
// exists. Missing file, parse errors, unknown cwd, or invalid mode → ok=false
// (fail-closed: callers keep the document default; never widen on error).
func LookupCWDOverride(home, cwd string) (Effect, bool) {
	if IsGlobalCWD(cwd) {
		return "", false
	}
	doc, err := loadCWDOverrides(home)
	if err != nil {
		return "", false
	}
	key := NormalizeCWD(cwd)
	raw, ok := doc.Overrides[key]
	if !ok {
		return "", false
	}
	switch Effect(raw) {
	case EffectDeny, EffectAsk, EffectAllow:
		return Effect(raw), true
	default:
		return "", false
	}
}

// SetCWDOverride persists a coarse deny/ask/allow for cwd. Rejects global cwd
// keys and invalid modes. Creates ~/.lancer as needed (0600 file).
func SetCWDOverride(home, cwd string, mode Effect) error {
	if IsGlobalCWD(cwd) {
		return os.ErrInvalid
	}
	switch mode {
	case EffectDeny, EffectAsk, EffectAllow:
	default:
		return os.ErrInvalid
	}
	doc, err := loadCWDOverrides(home)
	if err != nil {
		// Corrupt / unreadable → start fresh rather than refuse the write
		// (the bad file already contributes no overrides at evaluate time).
		doc = cwdOverrideDoc{Overrides: map[string]string{}}
	}
	if doc.Overrides == nil {
		doc.Overrides = map[string]string{}
	}
	doc.Overrides[NormalizeCWD(cwd)] = string(mode)
	return saveCWDOverrides(home, doc)
}

func loadCWDOverrides(home string) (cwdOverrideDoc, error) {
	data, err := os.ReadFile(CWDOverridePath(home))
	if err != nil {
		return cwdOverrideDoc{}, err
	}
	var doc cwdOverrideDoc
	if err := yaml.Unmarshal(data, &doc); err != nil {
		return cwdOverrideDoc{}, err
	}
	if doc.Overrides == nil {
		doc.Overrides = map[string]string{}
	}
	return doc, nil
}

func saveCWDOverrides(home string, doc cwdOverrideDoc) error {
	path := CWDOverridePath(home)
	if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
		return err
	}
	data, err := yaml.Marshal(doc)
	if err != nil {
		return err
	}
	return os.WriteFile(path, data, 0600)
}
