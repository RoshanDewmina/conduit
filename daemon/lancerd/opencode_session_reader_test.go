package main

import "testing"

func TestOpenCodePartToMessage(t *testing.T) {
	cases := []struct {
		name     string
		raw      string
		msgRole  string
		wantRole string
		wantText string
		wantTool string
		wantOK   bool
	}{
		{"user text", `{"type":"text","text":"fix the bug"}`, "user", "user", "fix the bug", "", true},
		{"assistant text", `{"type":"text","text":"done"}`, "assistant", "assistant", "done", "", true},
		{"tool with command", `{"type":"tool","tool":"bash","state":{"input":{"command":"go test ./..."}}}`, "assistant", "toolCall", "go test ./...", "bash", true},
		{"tool with path", `{"type":"tool","tool":"read","state":{"input":{"filePath":"/a/b.go"}}}`, "assistant", "toolCall", "/a/b.go", "read", true},
		{"reasoning → system", `{"type":"reasoning","text":"thinking"}`, "assistant", "system", "thinking", "", true},
		{"step-start skipped", `{"type":"step-start"}`, "assistant", "", "", "", false},
		{"empty text skipped", `{"type":"text","text":""}`, "user", "", "", "", false},
		{"malformed skipped", `{not json`, "user", "", "", "", false},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			m, ok := openCodePartToMessage(c.raw, c.msgRole)
			if ok != c.wantOK {
				t.Fatalf("ok = %v, want %v", ok, c.wantOK)
			}
			if !ok {
				return
			}
			if m.Role != c.wantRole || m.Text != c.wantText || m.ToolName != c.wantTool {
				t.Fatalf("got {role:%q text:%q tool:%q}, want {role:%q text:%q tool:%q}",
					m.Role, m.Text, m.ToolName, c.wantRole, c.wantText, c.wantTool)
			}
		})
	}
}

func TestAsEpochMillis(t *testing.T) {
	if asEpochMillis(float64(0)).IsZero() == false {
		t.Fatal("zero epoch should map to zero time")
	}
	if asEpochMillis(float64(1782153547949)).IsZero() {
		t.Fatal("valid epoch ms should map to a non-zero time")
	}
	if got := asEpochMillis("1782153547949"); got.IsZero() {
		t.Fatal("string epoch ms should parse")
	}
}
