package policy

import "testing"

func TestPresetDocuments(t *testing.T) {
	for _, name := range []string{"cautious", "balanced", "bypass"} {
		doc, ok := PresetDocument(name)
		if !ok {
			t.Fatalf("preset %q not found", name)
		}
		if doc.Default == "" {
			t.Fatalf("preset %q has empty default", name)
		}
	}
	c, _ := PresetDocument("cautious")
	if !hasDenyKind(c, "network") || !hasDenyKind(c, "credential") {
		t.Fatalf("cautious must deny network+credential: %+v", c.Rules)
	}
	b, _ := PresetDocument("bypass")
	if !hasEffectKind(b, "allow", "command") {
		t.Fatalf("bypass must allow commands: %+v", b.Rules)
	}
	if _, ok := PresetDocument("nope"); ok {
		t.Fatal("unknown preset should return ok=false")
	}
}

func hasDenyKind(d Document, kind string) bool {
	for _, r := range d.Rules {
		if r.Effect == "deny" && r.Kind == kind {
			return true
		}
	}
	return false
}
func hasEffectKind(d Document, effect, kind string) bool {
	for _, r := range d.Rules {
		if r.Effect == effect && r.Kind == kind {
			return true
		}
	}
	return false
}
