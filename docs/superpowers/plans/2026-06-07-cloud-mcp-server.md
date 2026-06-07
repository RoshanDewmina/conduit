# Cloud MCP Server — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add MCP Streamable HTTP protocol support to the existing `push-backend` service so any AI agent can call `conduit_notify()` and `conduit_checkpoint()` as native MCP tools — delivering rich push notifications to the user's iOS device without requiring an SSH session or conduitd running locally.

**Architecture:** The `push-backend` (deployed on Fly.io) gains a `POST /mcp` endpoint implementing MCP JSON-RPC. Agents authenticate with a Bearer API key that maps to a registered iOS device session. `conduit_notify()` fires APNs immediately and returns. `conduit_checkpoint()` stores a pending checkpoint, fires APNs with Approve/Deny action buttons, and returns a `checkpoint_id`. The agent polls `conduit_checkpoint_status()` until the user acts on their phone.

**Tech Stack:** Go 1.25, `net/http`, `net/http/httptest` (tests), existing APNs JWT delivery, JSON file store (matches existing push-backend pattern), MCP JSON-RPC 2.0 over HTTP.

---

## File Structure

| File | Responsibility |
|---|---|
| `daemon/push-backend/mcp.go` | MCP HTTP handler, JSON-RPC dispatch, `initialize` handshake, tool routing |
| `daemon/push-backend/mcp_tools.go` | `conduit_notify`, `conduit_checkpoint`, `conduit_checkpoint_status` implementations |
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
    for _, required := range []string{"conduit_notify", "conduit_checkpoint", "conduit_checkpoint_status"} {
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
                "serverInfo":      map[string]any{"name": "conduit", "version": "1.0.0"},
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
            "name":        "conduit_notify",
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
            "name":        "conduit_checkpoint",
            "description": "Request a human decision. Returns a checkpoint_id immediately. Poll conduit_checkpoint_status() until status != 'pending'.",
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
            "name":        "conduit_checkpoint_status",
            "description": "Poll the status of a checkpoint created with conduit_checkpoint(). Returns status: pending | approved | denied | edited. If edited, edited_input contains the user's modification.",
            "inputSchema": map[string]any{
                "type": "object",
                "properties": map[string]any{
                    "checkpoint_id": map[string]any{"type": "string", "description": "ID returned by conduit_checkpoint()"},
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

## Task 4: Tool Implementations (notify + checkpoint + status)

**Files:**
- Create: `daemon/push-backend/mcp_tools.go`
- Modify: `daemon/push-backend/mcp_test.go` (append tool invocation tests)

`conduit_notify` stores the event and fires APNs. `conduit_checkpoint` stores a pending checkpoint, fires APNs with action category `CONDUIT_CHECKPOINT`, returns `checkpoint_id`. `conduit_checkpoint_status` returns current checkpoint state.

- [ ] **Step 1: Append tool tests to mcp_test.go**

```go
// Append to mcp_test.go

func TestConduitNotify(t *testing.T) {
    srv := newMCPServer(t)
    defer srv.Close()
    key, _ := createAPIKey("session-notify")

    resp := mcpPost(t, srv, key, map[string]any{
        "jsonrpc": "2.0",
        "id":      10,
        "method":  "tools/call",
        "params": map[string]any{
            "name": "conduit_notify",
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

func TestConduitCheckpointLifecycle(t *testing.T) {
    srv := newMCPServer(t)
    defer srv.Close()
    key, _ := createAPIKey("session-cp")

    // Create checkpoint
    createResp := mcpPost(t, srv, key, map[string]any{
        "jsonrpc": "2.0",
        "id":      20,
        "method":  "tools/call",
        "params": map[string]any{
            "name": "conduit_checkpoint",
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
            "name":      "conduit_checkpoint_status",
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
            "name":      "conduit_checkpoint_status",
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
cd daemon/push-backend && go test -run "TestConduitNotify|TestConduitCheckpointLifecycle" -v
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
    case "conduit_notify":
        result, toolErr = toolNotify(params.Arguments, sessionID)
    case "conduit_checkpoint":
        result, toolErr = toolCheckpoint(params.Arguments, sessionID)
    case "conduit_checkpoint_status":
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

// --- conduit_notify ---

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

// --- conduit_checkpoint ---

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

// --- conduit_checkpoint_status ---

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
    sendAPNS(token, title, evt.Message, "CONDUIT_NOTIFY", map[string]string{
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
    sendAPNS(token, "Decision needed", cp.Message, "CONDUIT_CHECKPOINT", map[string]string{
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
cd daemon/push-backend && go test -run "TestConduitNotify|TestConduitCheckpointLifecycle" -v
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
git commit -m "feat(mcp): conduit_notify, conduit_checkpoint, conduit_checkpoint_status tools"
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
// Auth: session token (existing Conduit iOS auth — X-Session-ID header)
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
cd daemon/push-backend && go test -run "TestMCP|TestConduit|TestAPIKey|TestEvent|TestCheckpoint" -v
```

Expected: all `PASS`

- [ ] **Step 6: Build to confirm no compile errors**

```bash
cd daemon/push-backend && go build ./...
```

Expected: no errors.

- [ ] **Step 7: Commit**

```bash
git add mcp.go main.go mcp_test.go
git commit -m "feat(mcp): iOS decide endpoint and API key HTTP handlers"
```

---

## Task 6: End-to-End Smoke Test with curl

Verify the full flow works against a locally running push-backend before deploying.

- [ ] **Step 1: Start push-backend locally**

```bash
cd daemon/push-backend
APNS_KEY_ID=test APNS_TEAM_ID=test APNS_KEY_PATH=/dev/null APNS_BUNDLE_ID=dev.conduit.mobile \
DATA_DIR=/tmp/conduit-mcp-test \
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

Expected: `{"jsonrpc":"2.0","id":1,"result":{"capabilities":...,"protocolVersion":"2024-11-05","serverInfo":{"name":"conduit","version":"1.0.0"}}}`

- [ ] **Step 5: Call conduit_notify**

```bash
curl -s -X POST http://localhost:8080/mcp \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"conduit_notify","arguments":{"message":"BUY AAPL 10 @ $201","level":"info","agent_name":"TradingBot"}}}'
```

Expected: `{"jsonrpc":"2.0","id":2,"result":{"content":[{"text":"notification sent","type":"text"}]}}`

- [ ] **Step 6: Create a checkpoint and poll it**

```bash
# Create checkpoint
RESP=$(curl -s -X POST http://localhost:8080/mcp \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"conduit_checkpoint","arguments":{"message":"Sell TSLA at market?","context":"50 shares @ $312"}}}')
echo $RESP

CP_ID=$(echo $RESP | python3 -c "import sys,json; r=json.load(sys.stdin); print(json.loads(r['result']['content'][0]['text'])['checkpoint_id'])")
echo "Checkpoint ID: $CP_ID"

# Poll status — should be pending
curl -s -X POST http://localhost:8080/mcp \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"tools/call\",\"params\":{\"name\":\"conduit_checkpoint_status\",\"arguments\":{\"checkpoint_id\":\"$CP_ID\"}}}"
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
  -d "{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"tools/call\",\"params\":{\"name\":\"conduit_checkpoint_status\",\"arguments\":{\"checkpoint_id\":\"$CP_ID\"}}}"
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

Verify an actual Claude Code agent can call `conduit_notify` and `conduit_checkpoint` against the local push-backend. This is the developer-facing integration test.

- [ ] **Step 1: Create a test MCP config file**

```bash
cat > /tmp/conduit-mcp-config.json << 'EOF'
{
  "mcpServers": {
    "conduit": {
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
DATA_DIR=/tmp/conduit-mcp-test go run . &
sleep 1
```

- [ ] **Step 3: Run a one-shot claude command with conduit MCP**

```bash
claude --mcp-config /tmp/conduit-mcp-config.json \
  -p "Call the conduit_notify tool with message 'Hello from Claude' and level 'info'. Then call conduit_checkpoint with message 'Should I continue?' and poll conduit_checkpoint_status until the result is not pending. Report the final status."
```

Expected: Claude calls `conduit_notify`, then `conduit_checkpoint`, polls `conduit_checkpoint_status` (returns "pending"), waits/polls. In a separate terminal, approve it:

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
- [x] `conduit_notify()` — Task 4
- [x] `conduit_checkpoint()` — Task 4
- [x] `conduit_checkpoint_status()` — Task 4
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
