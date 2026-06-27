# Cloud MCP Server — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add MCP Streamable HTTP protocol support to the existing `push-backend` service so any AI agent can call `lancer_notify()` and `lancer_checkpoint()` as native MCP tools — delivering rich push notifications to the user's iOS device without requiring an SSH session or lancerd running locally.

**Architecture:** The `push-backend` (deployed on Fly.io) gains a `POST /mcp` endpoint implementing MCP JSON-RPC. Agents authenticate with a Bearer API key that maps to a registered iOS device session. `lancer_notify()` fires APNs immediately and returns. `lancer_checkpoint()` stores a pending checkpoint, fires APNs with Approve/Deny action buttons, and returns a `checkpoint_id`. The agent polls `lancer_checkpoint_status()` until the user acts on their phone.

**Tech Stack:** Go 1.25, `net/http`, `net/http/httptest` (tests), existing APNs JWT delivery, JSON file store (matches existing push-backend pattern), MCP JSON-RPC 2.0 over HTTP.

---

## File Structure

| File | Responsibility |
|---|---|
| `daemon/push-backend/mcp.go` | MCP HTTP handler, JSON-RPC dispatch, `initialize` handshake, tool routing |
| `daemon/push-backend/mcp_tools.go` | `lancer_notify`, `lancer_checkpoint`, `lancer_checkpoint_status` implementations |
| `daemon/push-backend/mcp_store.go` | Event log (append-only) and checkpoint store (mutable) using JSON file pattern |
| `daemon/push-backend/api_keys.go` | API key CRUD: generate, lookup, revoke; keys stored in `apikeys.json` |
| `daemon/push-backend/mcp_test.go` | Integration tests: full MCP request/response cycles against `httptest.Server` |
| `daemon/push-backend/main.go` | **Modify** — register `POST /mcp`, `POST /apikeys`, `DELETE /apikeys/{key}` |

---

## Task 1: API Key Store

**Files:**
- Create: `daemon/push-backend/api_keys.go`
- Create: `daemon/push-backend/mcp_test.go` (test file started here, extended in later tasks)

An API key maps to a `sessionID` (which the existing device registry uses to look up an APNs device token). Agents include `Authorization: Bearer <key>` on every MCP request.

- [ ] **Step 1: Write the failing test**

```go
// daemon/push-backend/mcp_test.go
package main

import (
    "net/http"
    "net/http/httptest"
    "strings"
    "testing"
)

func TestAPIKeyRoundtrip(t *testing.T) {
    // Reset store for test isolation
    apiKeyStore.path = t.TempDir() + "/apikeys.json"

    key, err := createAPIKey("session-abc")
    if err != nil {
        t.Fatalf("createAPIKey: %v", err)
    }
    if len(key) < 32 {
        t.Errorf("key too short: %q", key)
    }

    sessionID, ok := lookupAPIKey(key)
    if !ok {
        t.Fatal("lookupAPIKey: not found after create")
    }
    if sessionID != "session-abc" {
        t.Errorf("got sessionID %q, want session-abc", sessionID)
    }

    revokeAPIKey(key)
    _, ok = lookupAPIKey(key)
    if ok {
        t.Error("lookupAPIKey: still found after revoke")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd daemon/push-backend && go test -run TestAPIKeyRoundtrip -v
```

Expected: `FAIL — undefined: apiKeyStore, createAPIKey, lookupAPIKey, revokeAPIKey`

- [ ] **Step 3: Implement api_keys.go**

```go
// daemon/push-backend/api_keys.go
package main

import (
    "crypto/rand"
    "encoding/hex"
    "sync"
)

type apiKey struct {
    Key       string `json:"key"`
    SessionID string `json:"sessionId"`
    CreatedAt string `json:"createdAt"`
}

type apiKeysData struct {
    Keys []apiKey `json:"keys"`
}

var apiKeyStore = &jsonFileStore{path: dataFilePath("API_KEYS_PATH", "apikeys.json")}
var apiKeysMu sync.RWMutex

func createAPIKey(sessionID string) (string, error) {
    b := make([]byte, 32)
    if _, err := rand.Read(b); err != nil {
        return "", err
    }
    key := "ck_" + hex.EncodeToString(b)

    apiKeysMu.Lock()
    defer apiKeysMu.Unlock()
    var d apiKeysData
    _ = apiKeyStore.load(&d)
    d.Keys = append(d.Keys, apiKey{Key: key, SessionID: sessionID, CreatedAt: nowISO()})
    return key, apiKeyStore.save(&d)
}

func lookupAPIKey(key string) (sessionID string, ok bool) {
    apiKeysMu.RLock()
    defer apiKeysMu.RUnlock()
    var d apiKeysData
    _ = apiKeyStore.load(&d)
    for _, k := range d.Keys {
        if k.Key == key {
            return k.SessionID, true
        }
    }
    return "", false
}

func revokeAPIKey(key string) {
    apiKeysMu.Lock()
    defer apiKeysMu.Unlock()
    var d apiKeysData
    _ = apiKeyStore.load(&d)
    filtered := d.Keys[:0]
    for _, k := range d.Keys {
        if k.Key != key {
            filtered = append(filtered, k)
        }
    }
    d.Keys = filtered
    _ = apiKeyStore.save(&d)
}

// nowISO returns the current UTC time in RFC3339 format.
// Defined here; if already defined elsewhere in the package, remove this.
func nowISO() string {
    return time.Now().UTC().Format(time.RFC3339)
}
```

> **Note:** `dataFilePath`, `jsonFileStore` are already defined in `store.go`. `nowISO()` may conflict if it exists elsewhere — check with `grep -r "func nowISO" daemon/push-backend/` first and remove the duplicate if needed.

- [ ] **Step 4: Add missing import to api_keys.go**

The file needs `"time"` in the imports:

```go
import (
    "crypto/rand"
    "encoding/hex"
    "sync"
    "time"
)
```

- [ ] **Step 5: Run test to verify it passes**

```bash
cd daemon/push-backend && go test -run TestAPIKeyRoundtrip -v
```

Expected: `PASS`

- [ ] **Step 6: Commit**

```bash
cd daemon/push-backend
git add api_keys.go mcp_test.go
git commit -m "feat(mcp): API key store for MCP agent authentication"
```

---

## Task 2: MCP Event & Checkpoint Store

**Files:**
- Create: `daemon/push-backend/mcp_store.go`
- Modify: `daemon/push-backend/mcp_test.go` (append new test)

Events are append-only (fire-and-forget notifications). Checkpoints are mutable (pending → decided by user).

- [ ] **Step 1: Append failing tests to mcp_test.go**

```go
// Append to mcp_test.go

func TestEventStore(t *testing.T) {
    mcpEventStore.path = t.TempDir() + "/events.json"

    err := appendEvent(MCPEvent{
        ID:        "evt-1",
        SessionID: "session-abc",
        Message:   "Trade executed: BUY AAPL 10 @ $201",
        Level:     "info",
        AgentName: "TradingBot",
        CreatedAt: "2026-06-07T10:00:00Z",
    })
    if err != nil {
        t.Fatalf("appendEvent: %v", err)
    }

    events, err := listEvents("session-abc", 10)
    if err != nil {
        t.Fatalf("listEvents: %v", err)
    }
    if len(events) != 1 {
        t.Fatalf("got %d events, want 1", len(events))
    }
    if events[0].Message != "Trade executed: BUY AAPL 10 @ $201" {
        t.Errorf("unexpected message: %q", events[0].Message)
    }
}

func TestCheckpointStore(t *testing.T) {
    mcpCheckpointStore.path = t.TempDir() + "/checkpoints.json"

    cp := MCPCheckpoint{
        ID:        "cp-1",
        SessionID: "session-abc",
        Message:   "Sell TSLA at market? (current: $312)",
        Status:    "pending",
        CreatedAt: "2026-06-07T10:00:00Z",
    }
    if err := saveCheckpoint(cp); err != nil {
        t.Fatalf("saveCheckpoint: %v", err)
    }

    got, err := getCheckpoint("cp-1")
    if err != nil {
        t.Fatalf("getCheckpoint: %v", err)
    }
    if got.Status != "pending" {
        t.Errorf("status = %q, want pending", got.Status)
    }

    cp.Status = "approved"
    _ = saveCheckpoint(cp)
    got, _ = getCheckpoint("cp-1")
    if got.Status != "approved" {
        t.Errorf("after update: status = %q, want approved", got.Status)
    }
}
```

- [ ] **Step 2: Run to verify failure**

```bash
cd daemon/push-backend && go test -run "TestEventStore|TestCheckpointStore" -v
```

Expected: `FAIL — undefined: MCPEvent, MCPCheckpoint, appendEvent, listEvents, saveCheckpoint, getCheckpoint`

- [ ] **Step 3: Implement mcp_store.go**

```go
// daemon/push-backend/mcp_store.go
package main

import (
    "errors"
    "fmt"
    "sync"
)

// --- Events (append-only) ---

type MCPEvent struct {
    ID        string `json:"id"`
    SessionID string `json:"sessionId"`
    Message   string `json:"message"`
    Level     string `json:"level"`   // "info" | "warning" | "critical"
    AgentName string `json:"agentName,omitempty"`
    Context   string `json:"context,omitempty"`
    CreatedAt string `json:"createdAt"`
}

type mcpEventsData struct {
    Events []MCPEvent `json:"events"`
}

var mcpEventStore = &jsonFileStore{path: dataFilePath("MCP_EVENTS_PATH", "mcp_events.json")}
var mcpEventsMu sync.Mutex

func appendEvent(evt MCPEvent) error {
    mcpEventsMu.Lock()
    defer mcpEventsMu.Unlock()
    var d mcpEventsData
    _ = mcpEventStore.load(&d)
    d.Events = append(d.Events, evt)
    return mcpEventStore.save(&d)
}

func listEvents(sessionID string, limit int) ([]MCPEvent, error) {
    mcpEventsMu.Lock()
    defer mcpEventsMu.Unlock()
    var d mcpEventsData
    if err := mcpEventStore.load(&d); err != nil {
        return nil, err
    }
    var out []MCPEvent
    for i := len(d.Events) - 1; i >= 0 && len(out) < limit; i-- {
        if d.Events[i].SessionID == sessionID {
            out = append(out, d.Events[i])
        }
    }
    return out, nil
}

// --- Checkpoints (mutable, pending → decided) ---

type MCPCheckpoint struct {
    ID          string `json:"id"`
    SessionID   string `json:"sessionId"`
    Message     string `json:"message"`
    Context     string `json:"context,omitempty"`
    Status      string `json:"status"`  // "pending" | "approved" | "denied" | "edited"
    EditedInput string `json:"editedInput,omitempty"`
    CreatedAt   string `json:"createdAt"`
    DecidedAt   string `json:"decidedAt,omitempty"`
}

type mcpCheckpointsData struct {
    Checkpoints []MCPCheckpoint `json:"checkpoints"`
}

var mcpCheckpointStore = &jsonFileStore{path: dataFilePath("MCP_CHECKPOINTS_PATH", "mcp_checkpoints.json")}
var mcpCheckpointsMu sync.Mutex

func saveCheckpoint(cp MCPCheckpoint) error {
    mcpCheckpointsMu.Lock()
    defer mcpCheckpointsMu.Unlock()
    var d mcpCheckpointsData
    _ = mcpCheckpointStore.load(&d)
    for i, existing := range d.Checkpoints {
        if existing.ID == cp.ID {
            d.Checkpoints[i] = cp
            return mcpCheckpointStore.save(&d)
        }
    }
    d.Checkpoints = append(d.Checkpoints, cp)
    return mcpCheckpointStore.save(&d)
}

func getCheckpoint(id string) (MCPCheckpoint, error) {
    mcpCheckpointsMu.Lock()
    defer mcpCheckpointsMu.Unlock()
    var d mcpCheckpointsData
    if err := mcpCheckpointStore.load(&d); err != nil {
        return MCPCheckpoint{}, err
    }
    for _, cp := range d.Checkpoints {
        if cp.ID == id {
            return cp, nil
        }
    }
    return MCPCheckpoint{}, fmt.Errorf("checkpoint %q not found", id)
}

var errCheckpointNotFound = errors.New("checkpoint not found")
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd daemon/push-backend && go test -run "TestEventStore|TestCheckpointStore" -v
```

Expected: `PASS`

- [ ] **Step 5: Commit**

```bash
git add mcp_store.go mcp_test.go
git commit -m "feat(mcp): event log and checkpoint store"
```

---

## Task 3: MCP HTTP Handler & Tool Dispatch

**Files:**
- Create: `daemon/push-backend/mcp.go`
- Modify: `daemon/push-backend/mcp_test.go` (append handler tests)

This implements the MCP Streamable HTTP transport: `POST /mcp` accepts JSON-RPC 2.0. The handler validates the API key, dispatches `initialize` / `tools/list` / `tools/call`, and returns JSON-RPC responses.

- [ ] **Step 1: Append failing handler test to mcp_test.go**

```go
// Append to mcp_test.go

import (
    // add to existing imports:
    "bytes"
    "encoding/json"
    "io"
)

func newMCPServer(t *testing.T) *httptest.Server {
    t.Helper()
    // Override stores to use temp dirs
    apiKeyStore.path = t.TempDir() + "/apikeys.json"
    mcpEventStore.path = t.TempDir() + "/events.json"
    mcpCheckpointStore.path = t.TempDir() + "/checkpoints.json"

    mux := http.NewServeMux()
    mux.HandleFunc("POST /mcp", handleMCP)
    return httptest.NewServer(mux)
}

func mcpPost(t *testing.T, srv *httptest.Server, key string, body any) map[string]any {
    t.Helper()
    b, _ := json.Marshal(body)
    req, _ := http.NewRequest("POST", srv.URL+"/mcp", bytes.NewReader(b))
    req.Header.Set("Content-Type", "application/json")
    req.Header.Set("Authorization", "Bearer "+key)
    resp, err := http.DefaultClient.Do(req)
    if err != nil {
        t.Fatalf("POST /mcp: %v", err)
    }
    defer resp.Body.Close()
    raw, _ := io.ReadAll(resp.Body)
    var result map[string]any
    if err := json.Unmarshal(raw, &result); err != nil {
        t.Fatalf("unmarshal response %q: %v", raw, err)
    }
    return result
}

func TestMCPInitialize(t *testing.T) {
    srv := newMCPServer(t)
    defer srv.Close()
    key, _ := createAPIKey("session-test")

    resp := mcpPost(t, srv, key, map[string]any{
        "jsonrpc": "2.0",
        "id":      1,
        "method":  "initialize",
        "params": map[string]any{
            "protocolVersion": "2024-11-05",
            "clientInfo":      map[string]any{"name": "test-agent", "version": "1.0"},
            "capabilities":    map[string]any{},
        },
    })

    result, ok := resp["result"].(map[string]any)
    if !ok {
        t.Fatalf("expected result, got: %v", resp)
    }
    if result["protocolVersion"] != "2024-11-05" {
        t.Errorf("unexpected protocolVersion: %v", result["protocolVersion"])
    }
}

func TestMCPToolsList(t *testing.T) {
    srv := newMCPServer(t)
    defer srv.Close()
    key, _ := createAPIKey("session-test")

    resp := mcpPost(t, srv, key, map[string]any{
        "jsonrpc": "2.0",
        "id":      2,
        "method":  "tools/list",
        "params":  map[string]any{},
    })

    result, ok := resp["result"].(map[string]any)
    if !ok {
        t.Fatalf("expected result, got: %v", resp)
    }
    tools, ok := result["tools"].([]any)
    if !ok || len(tools) == 0 {
        t.Fatalf("expected non-empty tools list, got: %v", result["tools"])
    }
    names := map[string]bool{}
    for _, tool := range tools {
        if m, ok := tool.(map[string]any); ok {
            names[m["name"].(string)] = true
        }
    }
    for _, required := range []string{"lancer_notify", "lancer_checkpoint", "lancer_checkpoint_status"} {
        if !names[required] {
            t.Errorf("missing tool %q", required)
        }
    }
}

func TestMCPUnauthorized(t *testing.T) {
    srv := newMCPServer(t)
    defer srv.Close()

    b, _ := json.Marshal(map[string]any{"jsonrpc": "2.0", "id": 1, "method": "tools/list"})
    req, _ := http.NewRequest("POST", srv.URL+"/mcp", bytes.NewReader(b))
    req.Header.Set("Content-Type", "application/json")
    // No Authorization header
    resp, _ := http.DefaultClient.Do(req)
    if resp.StatusCode != http.StatusUnauthorized {
        t.Errorf("expected 401, got %d", resp.StatusCode)
    }
}
```

- [ ] **Step 2: Run to verify failure**

```bash
cd daemon/push-backend && go test -run "TestMCPInitialize|TestMCPToolsList|TestMCPUnauthorized" -v
```

Expected: `FAIL — undefined: handleMCP`

- [ ] **Step 3: Implement mcp.go**

```go
// daemon/push-backend/mcp.go
package main

import (
    "encoding/json"
    "net/http"
    "strings"
)

// MCP Streamable HTTP transport — POST /mcp
// Implements JSON-RPC 2.0 with methods: initialize, notifications/initialized,
// tools/list, tools/call.

type mcpRequest struct {
    JSONRPC string          `json:"jsonrpc"`
    ID      any             `json:"id,omitempty"`
    Method  string          `json:"method"`
    Params  json.RawMessage `json:"params,omitempty"`
}

type mcpResponse struct {
    JSONRPC string  `json:"jsonrpc"`
    ID      any     `json:"id,omitempty"`
    Result  any     `json:"result,omitempty"`
    Error   *mcpErr `json:"error,omitempty"`
}

type mcpErr struct {
    Code    int    `json:"code"`
    Message string `json:"message"`
}

func handleMCP(w http.ResponseWriter, r *http.Request) {
    // Auth: Bearer API key
    authHeader := r.Header.Get("Authorization")
    key := strings.TrimPrefix(authHeader, "Bearer ")
    if key == "" || key == authHeader {
        http.Error(w, "unauthorized", http.StatusUnauthorized)
        return
    }
    sessionID, ok := lookupAPIKey(key)
    if !ok {
        http.Error(w, "unauthorized", http.StatusUnauthorized)
        return
    }

    var req mcpRequest
    if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
        writeJSONRPCError(w, nil, -32700, "parse error")
        return
    }

    w.Header().Set("Content-Type", "application/json")

    switch req.Method {
    case "initialize":
        json.NewEncoder(w).Encode(mcpResponse{
            JSONRPC: "2.0",
            ID:      req.ID,
            Result: map[string]any{
                "protocolVersion": "2024-11-05",
                "serverInfo":      map[string]any{"name": "lancer", "version": "1.0.0"},
                "capabilities":    map[string]any{"tools": map[string]any{}},
            },
        })

    case "notifications/initialized":
        // Client acknowledgement — no response body needed for notifications
        w.WriteHeader(http.StatusAccepted)

    case "tools/list":
        json.NewEncoder(w).Encode(mcpResponse{
            JSONRPC: "2.0",
            ID:      req.ID,
            Result:  map[string]any{"tools": mcpToolDefinitions()},
        })

    case "tools/call":
        handleToolCall(w, req, sessionID)

    default:
        writeJSONRPCError(w, req.ID, -32601, "method not found: "+req.Method)
    }
}

func writeJSONRPCError(w http.ResponseWriter, id any, code int, msg string) {
    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(mcpResponse{
        JSONRPC: "2.0",
        ID:      id,
        Error:   &mcpErr{Code: code, Message: msg},
    })
}

func mcpToolDefinitions() []map[string]any {
    return []map[string]any{
        {
            "name":        "lancer_notify",
            "description": "Send a push notification to the user's phone. Fire-and-forget — returns immediately.",
            "inputSchema": map[string]any{
                "type": "object",
                "properties": map[string]any{
                    "message":    map[string]any{"type": "string", "description": "Notification body text"},
                    "level":      map[string]any{"type": "string", "enum": []string{"info", "warning", "critical"}, "description": "Alert priority"},
                    "agent_name": map[string]any{"type": "string", "description": "Display name for this agent"},
                    "context":    map[string]any{"type": "string", "description": "Optional structured context (JSON or plain text)"},
                },
                "required": []string{"message"},
            },
        },
        {
            "name":        "lancer_checkpoint",
            "description": "Request a human decision. Returns a checkpoint_id immediately. Poll lancer_checkpoint_status() until status != 'pending'.",
            "inputSchema": map[string]any{
                "type": "object",
                "properties": map[string]any{
                    "message":    map[string]any{"type": "string", "description": "Question or action description to show the user"},
                    "context":    map[string]any{"type": "string", "description": "Additional context the user needs to decide"},
                    "agent_name": map[string]any{"type": "string", "description": "Display name for this agent"},
                },
                "required": []string{"message"},
            },
        },
        {
            "name":        "lancer_checkpoint_status",
            "description": "Poll the status of a checkpoint created with lancer_checkpoint(). Returns status: pending | approved | denied | edited. If edited, edited_input contains the user's modification.",
            "inputSchema": map[string]any{
                "type": "object",
                "properties": map[string]any{
                    "checkpoint_id": map[string]any{"type": "string", "description": "ID returned by lancer_checkpoint()"},
                },
                "required": []string{"checkpoint_id"},
            },
        },
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd daemon/push-backend && go test -run "TestMCPInitialize|TestMCPToolsList|TestMCPUnauthorized" -v
```

Expected: `PASS`

- [ ] **Step 5: Commit**

```bash
git add mcp.go mcp_test.go
git commit -m "feat(mcp): MCP HTTP handler, auth, tool definitions"
```

---

## Task 3.5: Shared APNs + Event Persistence Helpers

**Files:**
- Modify: `daemon/push-backend/mcp_tools.go` (add `sendAPNS` and `recordAndPushMCPEvent`)
- Modify: `daemon/push-backend/mcp_test.go` (add shared test helpers used by all later tasks)

The plan calls `sendAPNS(...)` in Tasks 4, 8, and 9, but the existing `main.go` only has `pushApproval()` and `pushRunComplete()`. This task adds the shared helper before any tool implementations reference it. `recordAndPushMCPEvent` ensures every notification that fires APNs is also persisted to the event store — so the mobile inbox never loses history.

- [ ] **Step 1: Verify the actual APNs function name in main.go**

```bash
grep -n "^func push" daemon/push-backend/main.go
```

Expected: lines like `func pushApproval(...)` and `func pushRunComplete(...)`. Note the exact signature — `sendAPNS` wraps whichever pattern they use internally (JWT + HTTP/2 to APNs).

- [ ] **Step 2: Append helpers to mcp_tools.go**

Add at the top of `daemon/push-backend/mcp_tools.go`, after the imports:

```go
// sendAPNS delivers a push notification to an APNs device token.
// title, body: visible notification text.
// category: APNs category string (e.g. "LANCER_NOTIFY", "LANCER_CHECKPOINT").
// extra: custom payload keys merged into the notification's data dict.
// This is best-effort — callers must not block on it.
func sendAPNS(deviceToken, title, body, category string, extra map[string]string) {
	// Reuse the APNs JWT credentials already loaded at startup.
	// Look up how pushApproval/pushRunComplete construct their HTTP/2 request
	// and replicate that pattern here. The function is intentionally a wrapper
	// so only one place needs to know the APNs wire format.
	//
	// Minimum viable implementation: copy the HTTP/2 request construction
	// from pushApproval, replacing aps.alert, aps.category, and the custom
	// payload keys with the arguments passed here.
	//
	// If the codebase has a sendPush(token, payload) helper already,
	// delegate to it instead of duplicating the HTTP/2 client setup.
	payload := map[string]any{
		"aps": map[string]any{
			"alert":    map[string]string{"title": title, "body": body},
			"sound":    "default",
			"category": category,
		},
	}
	for k, v := range extra {
		payload[k] = v
	}
	// TODO: replace the body below with the actual APNs HTTP/2 send logic
	// from pushApproval / pushRunComplete in main.go.
	_ = payload
	_ = deviceToken
}

// recordAndPushMCPEvent persists evt to the event store then fires APNs best-effort.
// Use this instead of calling appendEvent + pushMCPNotify separately so that
// every notification that reaches the phone also appears in the inbox history.
func recordAndPushMCPEvent(sessionID string, evt MCPEvent) {
	if err := appendEvent(evt); err != nil {
		// Log but don't fail — notification is best-effort.
		return
	}
	go pushMCPNotify(sessionID, evt)
}
```

- [ ] **Step 3: Add shared test helpers to mcp_test.go**

Insert these functions near the top of `daemon/push-backend/mcp_test.go`, after the import block:

```go
// setupMCPTestStores points all JSON stores at temp dirs for test isolation.
// Call at the start of every test that touches stores.
func setupMCPTestStores(t *testing.T) {
	t.Helper()
	dir := t.TempDir()
	apiKeyStore.path = dir + "/apikeys.json"
	mcpEventStore.path = dir + "/events.json"
	mcpCheckpointStore.path = dir + "/checkpoints.json"
	mcpLoopStore.path = dir + "/loops.json"
	mcpReportStore.path = dir + "/proofs.json"
}

// assertMCPResult asserts the response has no JSON-RPC error and returns the result map.
func assertMCPResult(t *testing.T, resp map[string]any) map[string]any {
	t.Helper()
	if errObj, ok := resp["error"]; ok {
		t.Fatalf("unexpected MCP error: %#v", errObj)
	}
	result, ok := resp["result"].(map[string]any)
	if !ok {
		t.Fatalf("missing result in response: %#v", resp)
	}
	return result
}
```

Update `newMCPServer` to use the new helper:

```go
func newMCPServer(t *testing.T) *httptest.Server {
	t.Helper()
	setupMCPTestStores(t) // replaces the per-test store path assignments
	mux := http.NewServeMux()
	mux.HandleFunc("POST /mcp", handleMCP)
	return httptest.NewServer(mux)
}
```

- [ ] **Step 4: Build to confirm no compile errors before proceeding**

```bash
cd daemon/push-backend && go build ./...
```

Expected: compiles cleanly. If `sendAPNS` references anything not yet defined (e.g. the APNs HTTP client from `main.go`), move that shared client setup to a package-level var accessible from both files.

- [ ] **Step 5: Commit**

```bash
git add mcp_tools.go mcp_test.go
git commit -m "feat(mcp): shared sendAPNS helper and recordAndPushMCPEvent, test store helpers"
```

---

## Task 4: Tool Implementations (notify + checkpoint + status)

**Files:**
- Create: `daemon/push-backend/mcp_tools.go`
- Modify: `daemon/push-backend/mcp_test.go` (append tool invocation tests)

`lancer_notify` stores the event and fires APNs. `lancer_checkpoint` stores a pending checkpoint, fires APNs with action category `LANCER_CHECKPOINT`, returns `checkpoint_id`. `lancer_checkpoint_status` returns current checkpoint state.

- [ ] **Step 1: Append tool tests to mcp_test.go**

```go
// Append to mcp_test.go

func TestLancerNotify(t *testing.T) {
    srv := newMCPServer(t)
    defer srv.Close()
    key, _ := createAPIKey("session-notify")

    resp := mcpPost(t, srv, key, map[string]any{
        "jsonrpc": "2.0",
        "id":      10,
        "method":  "tools/call",
        "params": map[string]any{
            "name": "lancer_notify",
            "arguments": map[string]any{
                "message":    "Trade executed: BUY AAPL 10 @ $201",
                "level":      "info",
                "agent_name": "TradingBot",
            },
        },
    })

    result, ok := resp["result"].(map[string]any)
    if !ok {
        t.Fatalf("expected result, got: %v", resp)
    }
    content, ok := result["content"].([]any)
    if !ok || len(content) == 0 {
        t.Fatalf("expected content array, got: %v", result["content"])
    }
    first := content[0].(map[string]any)
    if first["type"] != "text" {
        t.Errorf("content type = %q, want text", first["type"])
    }

    // Verify event was stored
    events, _ := listEvents("session-notify", 10)
    if len(events) == 0 {
        t.Error("event not stored")
    }
    if events[0].Message != "Trade executed: BUY AAPL 10 @ $201" {
        t.Errorf("stored message = %q", events[0].Message)
    }
}

func TestLancerCheckpointLifecycle(t *testing.T) {
    srv := newMCPServer(t)
    defer srv.Close()
    key, _ := createAPIKey("session-cp")

    // Create checkpoint
    createResp := mcpPost(t, srv, key, map[string]any{
        "jsonrpc": "2.0",
        "id":      20,
        "method":  "tools/call",
        "params": map[string]any{
            "name": "lancer_checkpoint",
            "arguments": map[string]any{
                "message": "Sell TSLA at market? Current price: $312",
                "context": "Portfolio: 50 shares TSLA. Stop-loss at $290.",
            },
        },
    })

    result := createResp["result"].(map[string]any)
    content := result["content"].([]any)[0].(map[string]any)
    text := content["text"].(string)
    // text should contain the checkpoint_id
    if !strings.Contains(text, "checkpoint_id") {
        t.Errorf("response should include checkpoint_id, got: %q", text)
    }

    // Extract checkpoint_id from response
    var cpResult struct {
        CheckpointID string `json:"checkpoint_id"`
        Status       string `json:"status"`
    }
    json.Unmarshal([]byte(text), &cpResult)
    if cpResult.CheckpointID == "" {
        t.Fatal("no checkpoint_id in response")
    }
    if cpResult.Status != "pending" {
        t.Errorf("initial status = %q, want pending", cpResult.Status)
    }

    // Poll status — should be pending
    statusResp := mcpPost(t, srv, key, map[string]any{
        "jsonrpc": "2.0",
        "id":      21,
        "method":  "tools/call",
        "params": map[string]any{
            "name":      "lancer_checkpoint_status",
            "arguments": map[string]any{"checkpoint_id": cpResult.CheckpointID},
        },
    })

    statusResult := statusResp["result"].(map[string]any)
    statusContent := statusResult["content"].([]any)[0].(map[string]any)
    statusText := statusContent["text"].(string)
    var statusObj struct {
        Status string `json:"status"`
    }
    json.Unmarshal([]byte(statusText), &statusObj)
    if statusObj.Status != "pending" {
        t.Errorf("polled status = %q, want pending", statusObj.Status)
    }

    // Simulate user approving (direct store update — iOS does this via /mcp-decide)
    cp, _ := getCheckpoint(cpResult.CheckpointID)
    cp.Status = "approved"
    cp.DecidedAt = nowISO()
    saveCheckpoint(cp)

    // Poll again — should be approved
    statusResp2 := mcpPost(t, srv, key, map[string]any{
        "jsonrpc": "2.0",
        "id":      22,
        "method":  "tools/call",
        "params": map[string]any{
            "name":      "lancer_checkpoint_status",
            "arguments": map[string]any{"checkpoint_id": cpResult.CheckpointID},
        },
    })

    statusResult2 := statusResp2["result"].(map[string]any)
    content2 := statusResult2["content"].([]any)[0].(map[string]any)
    var statusObj2 struct{ Status string `json:"status"` }
    json.Unmarshal([]byte(content2["text"].(string)), &statusObj2)
    if statusObj2.Status != "approved" {
        t.Errorf("final status = %q, want approved", statusObj2.Status)
    }
}
```

- [ ] **Step 2: Run to verify failure**

```bash
cd daemon/push-backend && go test -run "TestLancerNotify|TestLancerCheckpointLifecycle" -v
```

Expected: `FAIL — undefined: handleToolCall`

- [ ] **Step 3: Implement mcp_tools.go**

```go
// daemon/push-backend/mcp_tools.go
package main

import (
    "crypto/rand"
    "encoding/hex"
    "encoding/json"
    "fmt"
    "net/http"
)

type toolCallParams struct {
    Name      string          `json:"name"`
    Arguments json.RawMessage `json:"arguments"`
}

func handleToolCall(w http.ResponseWriter, req mcpRequest, sessionID string) {
    var params toolCallParams
    if err := json.Unmarshal(req.Params, &params); err != nil {
        writeJSONRPCError(w, req.ID, -32602, "invalid params")
        return
    }

    var result any
    var toolErr error

    switch params.Name {
    case "lancer_notify":
        result, toolErr = toolNotify(params.Arguments, sessionID)
    case "lancer_checkpoint":
        result, toolErr = toolCheckpoint(params.Arguments, sessionID)
    case "lancer_checkpoint_status":
        result, toolErr = toolCheckpointStatus(params.Arguments, sessionID)
    default:
        writeJSONRPCError(w, req.ID, -32601, "unknown tool: "+params.Name)
        return
    }

    if toolErr != nil {
        writeJSONRPCError(w, req.ID, -32603, toolErr.Error())
        return
    }

    json.NewEncoder(w).Encode(mcpResponse{
        JSONRPC: "2.0",
        ID:      req.ID,
        Result:  result,
    })
}

// mcpTextResult wraps a string in the MCP content array format.
func mcpTextResult(text string) map[string]any {
    return map[string]any{
        "content": []map[string]any{{"type": "text", "text": text}},
    }
}

// mcpJSONResult marshals v and wraps it as a text content item.
func mcpJSONResult(v any) (map[string]any, error) {
    b, err := json.Marshal(v)
    if err != nil {
        return nil, err
    }
    return mcpTextResult(string(b)), nil
}

// --- lancer_notify ---

type notifyArgs struct {
    Message   string `json:"message"`
    Level     string `json:"level"`
    AgentName string `json:"agent_name"`
    Context   string `json:"context"`
}

func toolNotify(raw json.RawMessage, sessionID string) (any, error) {
    var args notifyArgs
    if err := json.Unmarshal(raw, &args); err != nil {
        return nil, fmt.Errorf("invalid arguments: %w", err)
    }
    if args.Message == "" {
        return nil, fmt.Errorf("message is required")
    }
    if args.Level == "" {
        args.Level = "info"
    }

    evt := MCPEvent{
        ID:        newID("evt"),
        SessionID: sessionID,
        Message:   args.Message,
        Level:     args.Level,
        AgentName: args.AgentName,
        Context:   args.Context,
        CreatedAt: nowISO(),
    }
    if err := appendEvent(evt); err != nil {
        return nil, fmt.Errorf("store event: %w", err)
    }

    // Fire APNs (best-effort — failure doesn't fail the tool call)
    go pushMCPNotify(sessionID, evt)

    return mcpTextResult("notification sent"), nil
}

// --- lancer_checkpoint ---

type checkpointArgs struct {
    Message   string `json:"message"`
    Context   string `json:"context"`
    AgentName string `json:"agent_name"`
}

func toolCheckpoint(raw json.RawMessage, sessionID string) (any, error) {
    var args checkpointArgs
    if err := json.Unmarshal(raw, &args); err != nil {
        return nil, fmt.Errorf("invalid arguments: %w", err)
    }
    if args.Message == "" {
        return nil, fmt.Errorf("message is required")
    }

    cp := MCPCheckpoint{
        ID:        newID("cp"),
        SessionID: sessionID,
        Message:   args.Message,
        Context:   args.Context,
        Status:    "pending",
        CreatedAt: nowISO(),
    }
    if err := saveCheckpoint(cp); err != nil {
        return nil, fmt.Errorf("store checkpoint: %w", err)
    }

    // Fire APNs with action buttons (best-effort)
    go pushMCPCheckpoint(sessionID, cp)

    return mcpJSONResult(map[string]string{
        "checkpoint_id": cp.ID,
        "status":        "pending",
    })
}

// --- lancer_checkpoint_status ---

type checkpointStatusArgs struct {
    CheckpointID string `json:"checkpoint_id"`
}

func toolCheckpointStatus(raw json.RawMessage, sessionID string) (any, error) {
    var args checkpointStatusArgs
    if err := json.Unmarshal(raw, &args); err != nil {
        return nil, fmt.Errorf("invalid arguments: %w", err)
    }
    if args.CheckpointID == "" {
        return nil, fmt.Errorf("checkpoint_id is required")
    }

    cp, err := getCheckpoint(args.CheckpointID)
    if err != nil {
        return nil, fmt.Errorf("checkpoint not found: %s", args.CheckpointID)
    }
    if cp.SessionID != sessionID {
        return nil, fmt.Errorf("checkpoint not found: %s", args.CheckpointID)
    }

    result := map[string]string{
        "checkpoint_id": cp.ID,
        "status":        cp.Status,
    }
    if cp.EditedInput != "" {
        result["edited_input"] = cp.EditedInput
    }
    return mcpJSONResult(result)
}

// --- APNs delivery (stubs that delegate to existing push infrastructure) ---

func pushMCPNotify(sessionID string, evt MCPEvent) {
    token := deviceTokenForSession(sessionID)
    if token == "" {
        return
    }
    title := evt.AgentName
    if title == "" {
        title = "Agent"
    }
    sendAPNS(token, title, evt.Message, "LANCER_NOTIFY", map[string]string{
        "eventId":   evt.ID,
        "level":     evt.Level,
        "sessionId": sessionID,
    })
}

func pushMCPCheckpoint(sessionID string, cp MCPCheckpoint) {
    token := deviceTokenForSession(sessionID)
    if token == "" {
        return
    }
    sendAPNS(token, "Decision needed", cp.Message, "LANCER_CHECKPOINT", map[string]string{
        "checkpointId": cp.ID,
        "sessionId":    sessionID,
    })
}

// deviceTokenForSession looks up the APNs device token for a session.
// Uses the existing registry map from main.go.
func deviceTokenForSession(sessionID string) string {
    registry.RLock()
    defer registry.RUnlock()
    return registry.tokens[sessionID]
}

// newID generates a random prefixed ID (e.g. "evt_a3f2...").
func newID(prefix string) string {
    b := make([]byte, 12)
    rand.Read(b)
    return prefix + "_" + hex.EncodeToString(b)
}
```

- [ ] **Step 4: Run tests**

```bash
cd daemon/push-backend && go test -run "TestLancerNotify|TestLancerCheckpointLifecycle" -v
```

Expected: `PASS`

- [ ] **Step 5: Verify full test suite still passes**

```bash
cd daemon/push-backend && go test ./... -v 2>&1 | tail -20
```

Expected: no new failures.

- [ ] **Step 6: Commit**

```bash
git add mcp_tools.go mcp_test.go
git commit -m "feat(mcp): lancer_notify, lancer_checkpoint, lancer_checkpoint_status tools"
```

---

## Task 5: iOS Decision Endpoint

**Files:**
- Modify: `daemon/push-backend/mcp.go` (add `POST /mcp-decide` handler)
- Modify: `daemon/push-backend/main.go` (register routes)
- Modify: `daemon/push-backend/mcp_test.go` (append decide test)

The iOS app calls `POST /mcp-decide` when the user taps Approve/Deny/Edit on a checkpoint notification. This updates the checkpoint status so the polling agent sees the decision.

- [ ] **Step 1: Append test**

```go
// Append to mcp_test.go

func TestMCPDecide(t *testing.T) {
    apiKeyStore.path = t.TempDir() + "/apikeys.json"
    mcpCheckpointStore.path = t.TempDir() + "/checkpoints.json"

    // Pre-create a pending checkpoint
    cp := MCPCheckpoint{
        ID:        "cp-decide-1",
        SessionID: "session-decide",
        Message:   "Sell TSLA?",
        Status:    "pending",
        CreatedAt: nowISO(),
    }
    saveCheckpoint(cp)

    // Simulate iOS app approving
    mux := http.NewServeMux()
    mux.HandleFunc("POST /mcp-decide", handleMCPDecide)
    srv := httptest.NewServer(mux)
    defer srv.Close()

    body, _ := json.Marshal(map[string]string{
        "checkpointId": "cp-decide-1",
        "sessionId":    "session-decide",
        "decision":     "approved",
    })
    req, _ := http.NewRequest("POST", srv.URL+"/mcp-decide", bytes.NewReader(body))
    req.Header.Set("Content-Type", "application/json")
    resp, _ := http.DefaultClient.Do(req)
    if resp.StatusCode != http.StatusOK {
        t.Errorf("status = %d, want 200", resp.StatusCode)
    }

    got, _ := getCheckpoint("cp-decide-1")
    if got.Status != "approved" {
        t.Errorf("status after decide = %q, want approved", got.Status)
    }
    if got.DecidedAt == "" {
        t.Error("decidedAt not set")
    }
}
```

- [ ] **Step 2: Run to verify failure**

```bash
cd daemon/push-backend && go test -run TestMCPDecide -v
```

Expected: `FAIL — undefined: handleMCPDecide`

- [ ] **Step 3: Add handleMCPDecide to mcp.go**

Add this function at the bottom of `daemon/push-backend/mcp.go`:

```go
// handleMCPDecide is called by the iOS app when the user acts on a checkpoint.
// POST /mcp-decide
// Body: {"checkpointId": "...", "sessionId": "...", "decision": "approved"|"denied"|"edited", "editedInput": "..."}
// Auth: session token (existing Lancer iOS auth — X-Session-ID header)
func handleMCPDecide(w http.ResponseWriter, r *http.Request) {
    var body struct {
        CheckpointID string `json:"checkpointId"`
        SessionID    string `json:"sessionId"`
        Decision     string `json:"decision"`
        EditedInput  string `json:"editedInput,omitempty"`
    }
    if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
        http.Error(w, "bad request", http.StatusBadRequest)
        return
    }
    if body.CheckpointID == "" || body.SessionID == "" || body.Decision == "" {
        http.Error(w, "missing fields", http.StatusBadRequest)
        return
    }
    allowed := map[string]bool{"approved": true, "denied": true, "edited": true}
    if !allowed[body.Decision] {
        http.Error(w, "invalid decision", http.StatusBadRequest)
        return
    }

    cp, err := getCheckpoint(body.CheckpointID)
    if err != nil || cp.SessionID != body.SessionID {
        http.Error(w, "not found", http.StatusNotFound)
        return
    }
    cp.Status = body.Decision
    cp.EditedInput = body.EditedInput
    cp.DecidedAt = nowISO()
    if err := saveCheckpoint(cp); err != nil {
        http.Error(w, "internal error", http.StatusInternalServerError)
        return
    }
    w.WriteHeader(http.StatusOK)
}
```

- [ ] **Step 4: Register routes in main.go**

Find the `mux.HandleFunc` block in `daemon/push-backend/main.go` and add:

```go
mux.HandleFunc("POST /mcp", handleMCP)
mux.HandleFunc("POST /mcp-decide", handleMCPDecide)
mux.HandleFunc("POST /apikeys", handleCreateAPIKey)
mux.HandleFunc("DELETE /apikeys/{key}", handleRevokeAPIKey)
```

Also add the HTTP handlers for API key management at the bottom of `mcp.go`:

```go
// handleCreateAPIKey lets an authenticated iOS user generate an API key for their agents.
// POST /apikeys
// Header: X-Session-ID: <sessionId>
func handleCreateAPIKey(w http.ResponseWriter, r *http.Request) {
    sessionID := r.Header.Get("X-Session-ID")
    if sessionID == "" {
        http.Error(w, "missing X-Session-ID", http.StatusUnauthorized)
        return
    }
    key, err := createAPIKey(sessionID)
    if err != nil {
        http.Error(w, "internal error", http.StatusInternalServerError)
        return
    }
    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(map[string]string{"apiKey": key})
}

// handleRevokeAPIKey deletes an API key.
// DELETE /apikeys/{key}
// Header: X-Session-ID: <sessionId>  (must own the key)
func handleRevokeAPIKey(w http.ResponseWriter, r *http.Request) {
    key := r.PathValue("key")
    sessionID := r.Header.Get("X-Session-ID")
    owner, ok := lookupAPIKey(key)
    if !ok || owner != sessionID {
        http.Error(w, "not found", http.StatusNotFound)
        return
    }
    revokeAPIKey(key)
    w.WriteHeader(http.StatusNoContent)
}
```

- [ ] **Step 5: Run all MCP tests**

```bash
cd daemon/push-backend && go test -run "TestMCP|TestLancer|TestAPIKey|TestEvent|TestCheckpoint" -v
```

Expected: all `PASS`

- [ ] **Step 6: Build to confirm no compile errors**

```bash
cd daemon/push-backend && go build ./...
```

Expected: no errors.

- [ ] **Step 7: Update CORS middleware in main.go**

Find the `corsMiddleware` or equivalent CORS handler in `daemon/push-backend/main.go`:

```bash
grep -n "CORS\|Access-Control\|cors" daemon/push-backend/main.go | head -10
```

Add `Authorization`, `X-Session-ID`, and `DELETE` to the allowed methods/headers. The exact location depends on the existing middleware — update the allowed headers list to include:

```go
w.Header().Set("Access-Control-Allow-Methods", "GET, POST, DELETE, OPTIONS")
w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization, X-Session-ID, X-Customer-Id, X-App-Account-Token, Stripe-Signature")
```

- [ ] **Step 8: Build and run tests**

```bash
cd daemon/push-backend && go test -run "TestMCP|TestLancer|TestAPIKey|TestEvent|TestCheckpoint" -v && go build ./...
```

Expected: all `PASS`, clean build.

- [ ] **Step 9: Commit**

```bash
git add mcp.go main.go mcp_test.go
git commit -m "feat(mcp): iOS decide endpoint, API key HTTP handlers, CORS update"
```

---

## Task 6: End-to-End Smoke Test with curl

Verify the full flow works against a locally running push-backend before deploying.

- [ ] **Step 1: Start push-backend locally**

```bash
cd daemon/push-backend
APNS_KEY_ID=test APNS_TEAM_ID=test APNS_KEY_PATH=/dev/null APNS_BUNDLE_ID=dev.lancer.mobile \
DATA_DIR=/tmp/lancer-mcp-test \
go run . &
sleep 1
```

- [ ] **Step 2: Register a fake device**

```bash
curl -s -X POST http://localhost:8080/register \
  -H "Content-Type: application/json" \
  -d '{"sessionId": "smoke-session-1", "deviceToken": "fake-device-token"}' 
```

Expected: `200 OK` (or `{}`)

- [ ] **Step 3: Create an API key**

```bash
curl -s -X POST http://localhost:8080/apikeys \
  -H "X-Session-ID: smoke-session-1"
```

Expected: `{"apiKey": "ck_<hex>"}` — save the key as `$API_KEY`

```bash
API_KEY="ck_<paste key here>"
```

- [ ] **Step 4: Initialize MCP session**

```bash
curl -s -X POST http://localhost:8080/mcp \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","clientInfo":{"name":"test","version":"1"},"capabilities":{}}}'
```

Expected: `{"jsonrpc":"2.0","id":1,"result":{"capabilities":...,"protocolVersion":"2024-11-05","serverInfo":{"name":"lancer","version":"1.0.0"}}}`

- [ ] **Step 5: Call lancer_notify**

```bash
curl -s -X POST http://localhost:8080/mcp \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"lancer_notify","arguments":{"message":"BUY AAPL 10 @ $201","level":"info","agent_name":"TradingBot"}}}'
```

Expected: `{"jsonrpc":"2.0","id":2,"result":{"content":[{"text":"notification sent","type":"text"}]}}`

- [ ] **Step 6: Create a checkpoint and poll it**

```bash
# Create checkpoint
RESP=$(curl -s -X POST http://localhost:8080/mcp \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"lancer_checkpoint","arguments":{"message":"Sell TSLA at market?","context":"50 shares @ $312"}}}')
echo $RESP

CP_ID=$(echo $RESP | python3 -c "import sys,json; r=json.load(sys.stdin); print(json.loads(r['result']['content'][0]['text'])['checkpoint_id'])")
echo "Checkpoint ID: $CP_ID"

# Poll status — should be pending
curl -s -X POST http://localhost:8080/mcp \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"tools/call\",\"params\":{\"name\":\"lancer_checkpoint_status\",\"arguments\":{\"checkpoint_id\":\"$CP_ID\"}}}"
```

Expected status: `"pending"`

- [ ] **Step 7: Simulate iOS app approving**

```bash
curl -s -X POST http://localhost:8080/mcp-decide \
  -H "Content-Type: application/json" \
  -d "{\"checkpointId\":\"$CP_ID\",\"sessionId\":\"smoke-session-1\",\"decision\":\"approved\"}"

# Poll again — should be approved
curl -s -X POST http://localhost:8080/mcp \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d "{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"tools/call\",\"params\":{\"name\":\"lancer_checkpoint_status\",\"arguments\":{\"checkpoint_id\":\"$CP_ID\"}}}"
```

Expected status: `"approved"`

- [ ] **Step 8: Stop the local server**

```bash
kill %1
```

- [ ] **Step 9: Commit smoke test notes**

```bash
git add .
git commit -m "test(mcp): smoke test verified end-to-end (notify + checkpoint + decide cycle)"
```

---

## Task 7: Wire MCP Config to Claude Code Agent

Verify an actual Claude Code agent can call `lancer_notify` and `lancer_checkpoint` against the local push-backend. This is the developer-facing integration test.

- [ ] **Step 1: Create a test MCP config file**

```bash
cat > /tmp/lancer-mcp-config.json << 'EOF'
{
  "mcpServers": {
    "lancer": {
      "type": "http",
      "url": "http://localhost:8080/mcp",
      "headers": {
        "Authorization": "Bearer REPLACE_WITH_API_KEY"
      }
    }
  }
}
EOF
```

Replace `REPLACE_WITH_API_KEY` with the key generated in Task 6.

- [ ] **Step 2: Start push-backend (same as Task 6 Step 1)**

```bash
cd daemon/push-backend
DATA_DIR=/tmp/lancer-mcp-test go run . &
sleep 1
```

- [ ] **Step 3: Run a one-shot claude command with lancer MCP**

```bash
claude --mcp-config /tmp/lancer-mcp-config.json \
  -p "Call the lancer_notify tool with message 'Hello from Claude' and level 'info'. Then call lancer_checkpoint with message 'Should I continue?' and poll lancer_checkpoint_status until the result is not pending. Report the final status."
```

Expected: Claude calls `lancer_notify`, then `lancer_checkpoint`, polls `lancer_checkpoint_status` (returns "pending"), waits/polls. In a separate terminal, approve it:

```bash
# In a separate terminal — simulate the iOS app approving
CP_ID="<checkpoint id from claude output>"
curl -X POST http://localhost:8080/mcp-decide \
  -H "Content-Type: application/json" \
  -d "{\"checkpointId\":\"$CP_ID\",\"sessionId\":\"smoke-session-1\",\"decision\":\"approved\"}"
```

Claude should then report `"approved"`.

- [ ] **Step 4: Stop push-backend**

```bash
kill %1
```

- [ ] **Step 5: Final commit**

```bash
git add .
git commit -m "docs(mcp): integration verified with claude --mcp-config"
```

---

## Self-Review Checklist

**Spec coverage:**
- [x] Cloud MCP endpoint — Tasks 3, 5
- [x] `lancer_notify()` — Task 4
- [x] `lancer_checkpoint()` — Task 4
- [x] `lancer_checkpoint_status()` — Task 4
- [x] API key auth — Tasks 1, 5
- [x] Event storage — Task 2
- [x] Checkpoint storage — Task 2
- [x] APNs delivery on notify/checkpoint — Task 4 (`pushMCPNotify`, `pushMCPCheckpoint`)
- [x] iOS decide endpoint — Task 5
- [x] Smoke test — Task 6
- [x] Real agent integration test — Task 7

**Known dependency:** `sendAPNS()` is referenced in `mcp_tools.go` but defined in `main.go` (the existing APNs delivery function). Before running, confirm:
```bash
grep -n "func sendAPNS" daemon/push-backend/main.go
```
If the function is named differently (e.g. `sendPush`, `pushToDevice`), update the calls in `mcp_tools.go` to match.

**Type consistency check:**
- `MCPEvent.SessionID` (string) ↔ `registry.tokens[sessionID]` (string) ✓
- `MCPCheckpoint.Status` values: `"pending"`, `"approved"`, `"denied"`, `"edited"` — used consistently across `mcp_tools.go`, `mcp_test.go`, `handleMCPDecide` ✓
- `apiKey.Key` prefix `"ck_"` — consistent across `createAPIKey`, `lookupAPIKey`, `revokeAPIKey` ✓

**What this plan does NOT cover (Plan 2):**
- iOS inbox UI changes to consume cloud events (not SSH-required)
- Rich notification card UI
- Notification rule builder
- Apple Watch app

---

## Task 8: Loop Tracking — lancer_loop_start + lancer_step_complete

**Files:**
- Modify: `daemon/push-backend/mcp_store.go` (add `MCPLoop` type + store)
- Modify: `daemon/push-backend/mcp_tools.go` (add tool implementations)
- Modify: `daemon/push-backend/mcp.go` (add to `mcpToolDefinitions()`)
- Modify: `daemon/push-backend/mcp_test.go` (append loop tests)

Loops let the mobile app show structured progress ("Step 4/8 — running tests") instead of a flat notification stream. `lancer_loop_start` returns a `loop_id`; each `lancer_step_complete` call advances the progress and fires a notification only when `status` is `"failed"` or `"blocked"`.

- [ ] **Step 1: Append failing test to mcp_test.go**

```go
// Append to mcp_test.go

func TestLoopLifecycle(t *testing.T) {
    mcpLoopStore.path = t.TempDir() + "/loops.json"
    srv := newMCPServer(t)
    defer srv.Close()
    key, _ := createAPIKey("session-loop")

    // Start loop
    startResp := mcpPost(t, srv, key, map[string]any{
        "jsonrpc": "2.0", "id": 30, "method": "tools/call",
        "params": map[string]any{
            "name": "lancer_loop_start",
            "arguments": map[string]any{
                "name":        "Deploy Loop",
                "total_steps": 6,
                "agent_name":  "DeployBot",
            },
        },
    })
    content := startResp["result"].(map[string]any)["content"].([]any)[0].(map[string]any)
    var startObj struct {
        LoopID     string `json:"loop_id"`
        TotalSteps int    `json:"total_steps"`
    }
    json.Unmarshal([]byte(content["text"].(string)), &startObj)
    if startObj.LoopID == "" {
        t.Fatal("no loop_id in response")
    }
    if startObj.TotalSteps != 6 {
        t.Errorf("total_steps = %d, want 6", startObj.TotalSteps)
    }

    // Complete step 1
    stepResp := mcpPost(t, srv, key, map[string]any{
        "jsonrpc": "2.0", "id": 31, "method": "tools/call",
        "params": map[string]any{
            "name": "lancer_step_complete",
            "arguments": map[string]any{
                "loop_id": startObj.LoopID,
                "step":    1,
                "status":  "ok",
                "summary": "Build passed",
            },
        },
    })
    stepContent := stepResp["result"].(map[string]any)["content"].([]any)[0].(map[string]any)
    if !strings.Contains(stepContent["text"].(string), "1") {
        t.Errorf("step response missing step number: %s", stepContent["text"])
    }

    // Verify stored
    loop, err := getLoop(startObj.LoopID)
    if err != nil {
        t.Fatalf("getLoop: %v", err)
    }
    if loop.CurrentStep != 1 {
        t.Errorf("current_step = %d, want 1", loop.CurrentStep)
    }
    if loop.Steps[0].Status != "ok" {
        t.Errorf("step status = %q, want ok", loop.Steps[0].Status)
    }
}
```

- [ ] **Step 2: Run to verify failure**

```bash
cd daemon/push-backend && go test -run TestLoopLifecycle -v
```

Expected: `FAIL — undefined: mcpLoopStore, lancer_loop_start, getLoop`

- [ ] **Step 3: Add MCPLoop type and store to mcp_store.go**

Append to `daemon/push-backend/mcp_store.go`:

```go
// --- Loops (progress tracking) ---

type MCPLoopStep struct {
    Step      int    `json:"step"`
    Status    string `json:"status"`  // "ok" | "failed" | "blocked" | "skipped"
    Summary   string `json:"summary"`
    CreatedAt string `json:"createdAt"`
}

type MCPLoop struct {
    ID          string        `json:"id"`
    SessionID   string        `json:"sessionId"`
    Name        string        `json:"name"`
    TotalSteps  int           `json:"totalSteps"`
    CurrentStep int           `json:"currentStep"`
    Status      string        `json:"status"`  // "running" | "completed" | "failed" | "blocked"
    AgentName   string        `json:"agentName,omitempty"`
    Steps       []MCPLoopStep `json:"steps"`
    CreatedAt   string        `json:"createdAt"`
    UpdatedAt   string        `json:"updatedAt"`
}

type mcpLoopsData struct {
    Loops []MCPLoop `json:"loops"`
}

var mcpLoopStore = &jsonFileStore{path: dataFilePath("MCP_LOOPS_PATH", "mcp_loops.json")}
var mcpLoopsMu sync.Mutex

func createLoop(loop MCPLoop) error {
    mcpLoopsMu.Lock()
    defer mcpLoopsMu.Unlock()
    var d mcpLoopsData
    _ = mcpLoopStore.load(&d)
    d.Loops = append(d.Loops, loop)
    return mcpLoopStore.save(&d)
}

func getLoop(id string) (MCPLoop, error) {
    mcpLoopsMu.Lock()
    defer mcpLoopsMu.Unlock()
    var d mcpLoopsData
    if err := mcpLoopStore.load(&d); err != nil {
        return MCPLoop{}, err
    }
    for _, l := range d.Loops {
        if l.ID == id {
            return l, nil
        }
    }
    return MCPLoop{}, fmt.Errorf("loop %q not found", id)
}

func updateLoop(loop MCPLoop) error {
    // Internal: caller must hold mcpLoopsMu. Used only by updateLoopAtomic.
    var d mcpLoopsData
    _ = mcpLoopStore.load(&d)
    for i, l := range d.Loops {
        if l.ID == loop.ID {
            d.Loops[i] = loop
            return mcpLoopStore.save(&d)
        }
    }
    return fmt.Errorf("loop %q not found", loop.ID)
}

// updateLoopAtomic loads the loop, verifies sessionID ownership, calls mutate
// under the same lock, then saves — preventing lost-update races from concurrent
// lancer_step_complete calls.
func updateLoopAtomic(loopID, sessionID string, mutate func(*MCPLoop) error) error {
    mcpLoopsMu.Lock()
    defer mcpLoopsMu.Unlock()
    var d mcpLoopsData
    if err := mcpLoopStore.load(&d); err != nil {
        return err
    }
    for i, l := range d.Loops {
        if l.ID == loopID {
            if l.SessionID != sessionID {
                return fmt.Errorf("loop %q not found", loopID)
            }
            if err := mutate(&d.Loops[i]); err != nil {
                return err
            }
            return mcpLoopStore.save(&d)
        }
    }
    return fmt.Errorf("loop %q not found", loopID)
}
```

- [ ] **Step 4: Add tool implementations to mcp_tools.go**

Append to `daemon/push-backend/mcp_tools.go`:

```go
// --- lancer_loop_start ---

type loopStartArgs struct {
    Name       string `json:"name"`
    TotalSteps int    `json:"total_steps"`
    AgentName  string `json:"agent_name"`
}

func toolLoopStart(raw json.RawMessage, sessionID string) (any, error) {
    var args loopStartArgs
    if err := json.Unmarshal(raw, &args); err != nil {
        return nil, fmt.Errorf("invalid arguments: %w", err)
    }
    if args.Name == "" || args.TotalSteps < 1 {
        return nil, fmt.Errorf("name and total_steps (>=1) are required")
    }
    loop := MCPLoop{
        ID:         newID("loop"),
        SessionID:  sessionID,
        Name:       args.Name,
        TotalSteps: args.TotalSteps,
        Status:     "running",
        AgentName:  args.AgentName,
        CreatedAt:  nowISO(),
        UpdatedAt:  nowISO(),
    }
    if err := createLoop(loop); err != nil {
        return nil, fmt.Errorf("store loop: %w", err)
    }
    return mcpJSONResult(map[string]any{
        "loop_id":     loop.ID,
        "total_steps": loop.TotalSteps,
        "status":      loop.Status,
    })
}

// --- lancer_step_complete ---

type stepCompleteArgs struct {
    LoopID  string `json:"loop_id"`
    Step    int    `json:"step"`
    Status  string `json:"status"`
    Summary string `json:"summary"`
}

func toolStepComplete(raw json.RawMessage, sessionID string) (any, error) {
    var args stepCompleteArgs
    if err := json.Unmarshal(raw, &args); err != nil {
        return nil, fmt.Errorf("invalid arguments: %w", err)
    }
    if args.LoopID == "" || args.Step < 1 {
        return nil, fmt.Errorf("loop_id and step (>=1) are required")
    }
    allowed := map[string]bool{"ok": true, "failed": true, "blocked": true, "skipped": true}
    if !allowed[args.Status] {
        return nil, fmt.Errorf("status must be ok|failed|blocked|skipped")
    }

    // Atomic read-mutate-write under a single lock to avoid lost-update races
    // when two concurrent lancer_step_complete calls arrive for the same loop.
    var loopSnapshot MCPLoop
    err = updateLoopAtomic(args.LoopID, sessionID, func(loop *MCPLoop) error {
        if args.Step > loop.TotalSteps {
            return fmt.Errorf("step %d exceeds total_steps %d", args.Step, loop.TotalSteps)
        }
        // Guard terminal states: once failed/completed don't silently revert.
        if loop.Status == "completed" || loop.Status == "failed" {
            return fmt.Errorf("loop already in terminal state %q", loop.Status)
        }
        loop.CurrentStep = args.Step
        loop.UpdatedAt = nowISO()
        loop.Steps = append(loop.Steps, MCPLoopStep{
            Step:      args.Step,
            Status:    args.Status,
            Summary:   args.Summary,
            CreatedAt: nowISO(),
        })
        if args.Step >= loop.TotalSteps && args.Status == "ok" {
            loop.Status = "completed"
        } else if args.Status == "failed" {
            loop.Status = "failed"
        } else if args.Status == "blocked" {
            loop.Status = "blocked"
        }
        loopSnapshot = *loop
        return nil
    })
    if err != nil {
        return nil, fmt.Errorf("update loop: %w", err)
    }

    // Only notify on failure or block — not every step.
    // recordAndPushMCPEvent persists the event before firing APNs so the
    // inbox history is never missing a notification.
    if args.Status == "failed" || args.Status == "blocked" {
        recordAndPushMCPEvent(sessionID, MCPEvent{
            ID:        newID("evt"),
            SessionID: sessionID,
            Message:   fmt.Sprintf("%s: step %d/%d %s — %s", loopSnapshot.Name, args.Step, loopSnapshot.TotalSteps, args.Status, args.Summary),
            Level:     "warning",
            AgentName: loopSnapshot.AgentName,
            CreatedAt: nowISO(),
        })
    }

    return mcpJSONResult(map[string]any{
        "loop_id":      loop.ID,
        "step":         args.Step,
        "total_steps":  loop.TotalSteps,
        "loop_status":  loop.Status,
    })
}
```

- [ ] **Step 5: Update mcpToolDefinitions() in mcp.go**

Add two entries to the slice returned by `mcpToolDefinitions()`:

```go
{
    "name":        "lancer_loop_start",
    "description": "Start a named multi-step loop. Returns a loop_id. Call lancer_step_complete() after each step. The mobile app shows a progress bar.",
    "inputSchema": map[string]any{
        "type": "object",
        "properties": map[string]any{
            "name":        map[string]any{"type": "string", "description": "Human-readable loop name, e.g. 'Deploy Loop'"},
            "total_steps": map[string]any{"type": "integer", "description": "Total number of steps in this loop"},
            "agent_name":  map[string]any{"type": "string", "description": "Display name for this agent"},
        },
        "required": []string{"name", "total_steps"},
    },
},
{
    "name":        "lancer_step_complete",
    "description": "Report completion of one step in a loop started with lancer_loop_start(). Fires a push notification only when status is 'failed' or 'blocked'.",
    "inputSchema": map[string]any{
        "type": "object",
        "properties": map[string]any{
            "loop_id": map[string]any{"type": "string", "description": "loop_id returned by lancer_loop_start()"},
            "step":    map[string]any{"type": "integer", "description": "Step number (1-indexed)"},
            "status":  map[string]any{"type": "string", "enum": []string{"ok", "failed", "blocked", "skipped"}},
            "summary": map[string]any{"type": "string", "description": "One-line description of what happened"},
        },
        "required": []string{"loop_id", "step", "status", "summary"},
    },
},
```

Also add the new cases to the `switch params.Name` block in `handleToolCall` in `mcp_tools.go`:

```go
case "lancer_loop_start":
    result, toolErr = toolLoopStart(params.Arguments, sessionID)
case "lancer_step_complete":
    result, toolErr = toolStepComplete(params.Arguments, sessionID)
```

- [ ] **Step 6: Run tests**

```bash
cd daemon/push-backend && go test -run TestLoopLifecycle -v
```

Expected: `PASS`

- [ ] **Step 7: Build to confirm no compile errors**

```bash
cd daemon/push-backend && go build ./...
```

- [ ] **Step 8: Commit**

```bash
git add mcp_store.go mcp_tools.go mcp.go mcp_test.go
git commit -m "feat(mcp): lancer_loop_start and lancer_step_complete for loop progress tracking"
```

---

## Task 9: Proof-of-Work — lancer_report

**Files:**
- Modify: `daemon/push-backend/mcp_store.go` (add `MCPReport` type + store)
- Modify: `daemon/push-backend/mcp_tools.go` (add tool implementation)
- Modify: `daemon/push-backend/mcp.go` (add to `mcpToolDefinitions()`)
- Modify: `daemon/push-backend/mcp_test.go` (append proof test)

Every loop completion or significant checkpoint should produce a structured proof card. Forced schema prevents agents from sending prose summaries that can't be trusted.

- [ ] **Step 1: Append failing test to mcp_test.go**

```go
// Append to mcp_test.go

func TestLancerProof(t *testing.T) {
    mcpReportStore.path = t.TempDir() + "/proofs.json"
    srv := newMCPServer(t)
    defer srv.Close()
    key, _ := createAPIKey("session-proof")

    resp := mcpPost(t, srv, key, map[string]any{
        "jsonrpc": "2.0", "id": 40, "method": "tools/call",
        "params": map[string]any{
            "name": "lancer_report",
            "arguments": map[string]any{
                "goal":          "Fix failing login test",
                "changed_files": []string{"src/auth/session.ts", "tests/auth.test.ts"},
                "commands_run":  []string{"npm test", "npm run lint"},
                "test_status":   "passed",
                "diff_summary":  "Fixed token refresh race condition",
                "risks":         []string{"Did not manually test Safari"},
                "unverified":    []string{"Production OAuth provider not tested"},
                "recommended_next_action": "approve_pr",
            },
        },
    })

    result, ok := resp["result"].(map[string]any)
    if !ok {
        t.Fatalf("expected result, got: %v", resp)
    }
    content := result["content"].([]any)[0].(map[string]any)
    var proofResp struct {
        ProofID    string `json:"proof_id"`
        TestStatus string `json:"test_status"`
    }
    if err := json.Unmarshal([]byte(content["text"].(string)), &proofResp); err != nil {
        t.Fatalf("unmarshal proof response: %v", err)
    }
    if proofResp.ProofID == "" {
        t.Fatal("no proof_id in response")
    }
    if proofResp.TestStatus != "passed" {
        t.Errorf("test_status = %q, want passed", proofResp.TestStatus)
    }

    // Verify stored
    proof, err := getReport(proofResp.ProofID)
    if err != nil {
        t.Fatalf("getReport: %v", err)
    }
    if proof.Goal != "Fix failing login test" {
        t.Errorf("goal = %q", proof.Goal)
    }
    if len(proof.ChangedFiles) != 2 {
        t.Errorf("changed_files len = %d, want 2", len(proof.ChangedFiles))
    }
}
```

- [ ] **Step 2: Run to verify failure**

```bash
cd daemon/push-backend && go test -run TestLancerProof -v
```

Expected: `FAIL — undefined: mcpReportStore, getReport`

- [ ] **Step 3: Add MCPReport type and store to mcp_store.go**

Append to `daemon/push-backend/mcp_store.go`:

```go
// --- Proofs (structured proof-of-work cards) ---

type MCPReport struct {
    ID                    string   `json:"id"`
    SessionID             string   `json:"sessionId"`
    LoopID                string   `json:"loopId,omitempty"`
    AgentName             string   `json:"agentName,omitempty"`
    Goal                  string   `json:"goal"`
    ChangedFiles          []string `json:"changedFiles"`
    CommandsRun           []string `json:"commandsRun"`
    TestStatus            string   `json:"testStatus"`  // "passed" | "failed" | "skipped" | "unknown"
    DiffSummary           string   `json:"diffSummary"`
    Screenshots           []string `json:"screenshots,omitempty"`
    Risks                 []string `json:"risks,omitempty"`
    Unverified            []string `json:"unverified,omitempty"`
    RecommendedNextAction string   `json:"recommendedNextAction,omitempty"`
    CreatedAt             string   `json:"createdAt"`
}

type mcpReportsData struct {
    Proofs []MCPReport `json:"proofs"`
}

var mcpReportStore = &jsonFileStore{path: dataFilePath("MCP_PROOFS_PATH", "mcp_proofs.json")}
var mcpProofsMu sync.Mutex

func saveReport(proof MCPReport) error {
    mcpProofsMu.Lock()
    defer mcpProofsMu.Unlock()
    var d mcpReportsData
    _ = mcpReportStore.load(&d)
    d.Proofs = append(d.Proofs, proof)
    return mcpReportStore.save(&d)
}

func getReport(id string) (MCPReport, error) {
    mcpProofsMu.Lock()
    defer mcpProofsMu.Unlock()
    var d mcpReportsData
    if err := mcpReportStore.load(&d); err != nil {
        return MCPReport{}, err
    }
    for _, p := range d.Proofs {
        if p.ID == id {
            return p, nil
        }
    }
    return MCPReport{}, fmt.Errorf("proof %q not found", id)
}
```

- [ ] **Step 4: Add tool implementation to mcp_tools.go**

Append to `daemon/push-backend/mcp_tools.go`:

```go
// --- lancer_report ---

type reportArgs struct {
    LoopID                string   `json:"loop_id"`
    AgentName             string   `json:"agent_name"`
    Goal                  string   `json:"goal"`
    ChangedFiles          []string `json:"changed_files"`
    CommandsRun           []string `json:"commands_run"`
    TestStatus            string   `json:"test_status"`
    DiffSummary           string   `json:"diff_summary"`
    Screenshots           []string `json:"screenshots"`
    Risks                 []string `json:"risks"`
    Unverified            []string `json:"unverified"`
    RecommendedNextAction string   `json:"recommended_next_action"`
}

func toolReport(raw json.RawMessage, sessionID string) (any, error) {
    var args reportArgs
    if err := json.Unmarshal(raw, &args); err != nil {
        return nil, fmt.Errorf("invalid arguments: %w", err)
    }
    if args.Goal == "" {
        return nil, fmt.Errorf("goal is required")
    }
    validStatus := map[string]bool{"passed": true, "failed": true, "skipped": true, "unknown": true}
    if args.TestStatus == "" {
        args.TestStatus = "unknown"
    }
    if !validStatus[args.TestStatus] {
        return nil, fmt.Errorf("test_status must be passed|failed|skipped|unknown")
    }

    proof := MCPReport{
        ID:                    newID("proof"),
        SessionID:             sessionID,
        LoopID:                args.LoopID,
        AgentName:             args.AgentName,
        Goal:                  args.Goal,
        ChangedFiles:          args.ChangedFiles,
        CommandsRun:           args.CommandsRun,
        TestStatus:            args.TestStatus,
        DiffSummary:           args.DiffSummary,
        Screenshots:           args.Screenshots,
        Risks:                 args.Risks,
        Unverified:            args.Unverified,
        RecommendedNextAction: args.RecommendedNextAction,
        CreatedAt:             nowISO(),
    }
    if err := saveReport(proof); err != nil {
        return nil, fmt.Errorf("store proof: %w", err)
    }

    // recordAndPushMCPEvent persists the event first so the inbox history is
    // never missing a report notification, then fires APNs best-effort.
    recordAndPushMCPEvent(sessionID, MCPEvent{
        ID:        newID("evt"),
        SessionID: sessionID,
        Message:   fmt.Sprintf("Task complete: %s — tests %s", args.Goal, args.TestStatus),
        Level:     map[string]string{"passed": "info", "failed": "critical", "skipped": "warning", "unknown": "warning"}[args.TestStatus],
        AgentName: args.AgentName,
        CreatedAt: nowISO(),
    })

    return mcpJSONResult(map[string]any{
        "report_id":   proof.ID,
        "test_status": proof.TestStatus,
    })
}
```

- [ ] **Step 5: Update mcpToolDefinitions() in mcp.go**

Add to the slice:

```go
{
    "name":        "lancer_report",
    "description": "Submit a structured proof-of-work card when a task completes. Creates a rich card in the mobile inbox showing what changed, what was tested, risks, and what could not be verified.",
    "inputSchema": map[string]any{
        "type": "object",
        "properties": map[string]any{
            "goal":           map[string]any{"type": "string", "description": "One sentence: what was the task?"},
            "changed_files":  map[string]any{"type": "array", "items": map[string]any{"type": "string"}, "description": "List of files modified"},
            "commands_run":   map[string]any{"type": "array", "items": map[string]any{"type": "string"}, "description": "Commands executed (e.g. npm test, go build)"},
            "test_status":    map[string]any{"type": "string", "enum": []string{"passed", "failed", "skipped", "unknown"}},
            "diff_summary":   map[string]any{"type": "string", "description": "One sentence describing what changed and why"},
            "screenshots":    map[string]any{"type": "array", "items": map[string]any{"type": "string"}, "description": "Base64 or URLs of screenshots/visual verification"},
            "risks":          map[string]any{"type": "array", "items": map[string]any{"type": "string"}, "description": "Known risks or caveats"},
            "unverified":     map[string]any{"type": "array", "items": map[string]any{"type": "string"}, "description": "Things the agent could not verify"},
            "recommended_next_action": map[string]any{"type": "string", "description": "e.g. approve_pr, run_staging, needs_review"},
            "loop_id":        map[string]any{"type": "string", "description": "Optional: loop_id this proof is associated with"},
            "agent_name":     map[string]any{"type": "string"},
        },
        "required": []string{"goal", "test_status"},
    },
},
```

Add the case to `handleToolCall`:

```go
case "lancer_report":
    result, toolErr = toolReport(params.Arguments, sessionID)
```

- [ ] **Step 6: Run tests**

```bash
cd daemon/push-backend && go test -run TestLancerProof -v
```

Expected: `PASS`

- [ ] **Step 7: Build**

```bash
cd daemon/push-backend && go build ./...
```

- [ ] **Step 8: Commit**

```bash
git add mcp_store.go mcp_tools.go mcp.go mcp_test.go
git commit -m "feat(mcp): lancer_report structured proof-of-work cards"
```

---

## Task 10: Agent Provenance Metadata

**Files:**
- Modify: `daemon/push-backend/mcp_store.go` (add `Provenance` struct, embed in `MCPEvent` and `MCPCheckpoint`)
- Modify: `daemon/push-backend/mcp_tools.go` (populate provenance from tool args)
- Modify: `daemon/push-backend/mcp.go` (add provenance fields to `lancer_notify` and `lancer_checkpoint` input schemas)
- Modify: `daemon/push-backend/mcp_test.go` (append provenance test)

Every event and checkpoint must carry agent identity: which agent, on which machine, in which repo/branch, with what permission mode. Without this, the inbox is a notification bucket with no trust signal.

- [ ] **Step 1: Append failing test to mcp_test.go**

```go
// Append to mcp_test.go

func TestProvenanceStored(t *testing.T) {
    mcpEventStore.path = t.TempDir() + "/events.json"
    srv := newMCPServer(t)
    defer srv.Close()
    key, _ := createAPIKey("session-prov")

    mcpPost(t, srv, key, map[string]any{
        "jsonrpc": "2.0", "id": 50, "method": "tools/call",
        "params": map[string]any{
            "name": "lancer_notify",
            "arguments": map[string]any{
                "message":    "Build passed",
                "level":      "info",
                "agent_name": "ClaudeCode",
                "provenance": map[string]any{
                    "agent_type":      "claude-code",
                    "host":            "mac-mini-prod",
                    "repo":            "command-center",
                    "branch":          "feat/mcp",
                    "session_id":      "cc_82fa",
                    "permission_mode": "cautious",
                },
            },
        },
    })

    events, _ := listEvents("session-prov", 1)
    if len(events) == 0 {
        t.Fatal("no events stored")
    }
    p := events[0].Provenance
    if p.Host != "mac-mini-prod" {
        t.Errorf("host = %q, want mac-mini-prod", p.Host)
    }
    if p.PermissionMode != "cautious" {
        t.Errorf("permission_mode = %q, want cautious", p.PermissionMode)
    }
}
```

- [ ] **Step 2: Run to verify failure**

```bash
cd daemon/push-backend && go test -run TestProvenanceStored -v
```

Expected: `FAIL — MCPEvent has no field Provenance`

- [ ] **Step 3: Add Provenance type to mcp_store.go**

Add the `AgentProvenance` struct and update `MCPEvent` and `MCPCheckpoint` in `mcp_store.go`:

```go
// AgentProvenance records the identity of the agent that sent an event.
// All fields are optional — agents fill in what they know.
type AgentProvenance struct {
    AgentType      string `json:"agent_type,omitempty"`      // "claude-code" | "codex" | "custom"
    Host           string `json:"host,omitempty"`            // machine hostname
    Repo           string `json:"repo,omitempty"`            // git repo name
    Branch         string `json:"branch,omitempty"`          // git branch
    SessionID      string `json:"session_id,omitempty"`      // agent session ID
    PermissionMode string `json:"permission_mode,omitempty"` // "cautious" | "auto" | "bypass"
}
// IMPORTANT: JSON tags use snake_case to match what agents send in tool arguments.
// The test passes {"agent_type": "...", "permission_mode": "..."} — camelCase tags
// would silently leave those fields empty without any unmarshal error.
```

In the `MCPEvent` struct, add the field:
```go
Provenance AgentProvenance `json:"provenance,omitempty"`
```

In the `MCPCheckpoint` struct, add the field:
```go
Provenance AgentProvenance `json:"provenance,omitempty"`
```

- [ ] **Step 4: Update notifyArgs and checkpointArgs in mcp_tools.go**

In `mcp_tools.go`, update the arg structs to accept provenance:

```go
// Replace the existing notifyArgs struct:
type notifyArgs struct {
    Message    string          `json:"message"`
    Level      string          `json:"level"`
    AgentName  string          `json:"agent_name"`
    Context    string          `json:"context"`
    Provenance AgentProvenance `json:"provenance"`
}

// Replace the existing checkpointArgs struct:
type checkpointArgs struct {
    Message    string          `json:"message"`
    Context    string          `json:"context"`
    AgentName  string          `json:"agent_name"`
    Provenance AgentProvenance `json:"provenance"`
}
```

In `toolNotify`, set `evt.Provenance = args.Provenance` after setting the other fields.
In `toolCheckpoint`, set `cp.Provenance = args.Provenance` after setting the other fields.

- [ ] **Step 5: Update input schemas in mcpToolDefinitions()**

Add to the `lancer_notify` and `lancer_checkpoint` properties maps:

```go
"provenance": map[string]any{
    "type": "object",
    "description": "Agent identity metadata",
    "properties": map[string]any{
        "agent_type":      map[string]any{"type": "string", "description": "e.g. claude-code, codex, custom"},
        "host":            map[string]any{"type": "string", "description": "Machine hostname"},
        "repo":            map[string]any{"type": "string", "description": "Git repository name"},
        "branch":          map[string]any{"type": "string", "description": "Git branch"},
        "session_id":      map[string]any{"type": "string", "description": "Agent session identifier"},
        "permission_mode": map[string]any{"type": "string", "description": "e.g. cautious, auto, bypass"},
    },
},
```

- [ ] **Step 6: Run all tests**

```bash
cd daemon/push-backend && go test ./... -v 2>&1 | grep -E "^(=== RUN|--- PASS|--- FAIL|FAIL|ok)"
```

Expected: all `PASS`, zero `FAIL`.

- [ ] **Step 7: Build**

```bash
cd daemon/push-backend && go build ./...
```

- [ ] **Step 8: Commit**

```bash
git add mcp_store.go mcp_tools.go mcp.go mcp_test.go
git commit -m "feat(mcp): agent provenance metadata on all events and checkpoints"
```

---

## Updated Self-Review Checklist

**All tools covered:**
- [x] `lancer_notify` — Task 4
- [x] `lancer_checkpoint` — Task 4
- [x] `lancer_checkpoint_status` — Task 4
- [x] `lancer_loop_start` — Task 8
- [x] `lancer_step_complete` — Task 8
- [x] `lancer_report` — Task 9
- [x] Agent provenance on all events/checkpoints — Task 10

**Type consistency (updated):**
- `MCPLoop.Status` values: `"running"`, `"completed"`, `"failed"`, `"blocked"` — consistent across Task 8 ✓
- `MCPLoopStep.Status` values: `"ok"`, `"failed"`, `"blocked"`, `"skipped"` — consistent across Task 8 ✓
- `MCPReport.TestStatus` values: `"passed"`, `"failed"`, `"skipped"`, `"unknown"` — consistent across Task 9 ✓
- `AgentProvenance` struct embedded in both `MCPEvent` and `MCPCheckpoint` — consistent across Task 10 ✓
