package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

// ToolMapping describes a single MCP tool exposed by conduit-mcp.
// The Name is what the agent sees; Kind is passed to conduitd agent-hook --kind.
type ToolMapping struct {
	Name        string `json:"name"`
	Description string `json:"description"`
	AgentHook   string `json:"agentHook"`
	Kind        string `json:"kind"`
	Risk        int    `json:"risk"`
}

// Config is the top-level configuration file for conduit-mcp.
type Config struct {
	Agent      string        `json:"agent"`
	SocketPath string        `json:"socketPath"`
	Tools      []ToolMapping `json:"tools"`
}

// jsonrpcRequest is a minimal JSON-RPC 2.0 request.
type jsonrpcRequest struct {
	JSONRPC string          `json:"jsonrpc"`
	ID      interface{}     `json:"id"`
	Method  string          `json:"method"`
	Params  json.RawMessage `json:"params,omitempty"`
}

// jsonrpcResponse is a minimal JSON-RPC 2.0 response.
type jsonrpcResponse struct {
	JSONRPC string      `json:"jsonrpc"`
	ID      interface{} `json:"id"`
	Result  interface{} `json:"result,omitempty"`
	Error   *rpcError   `json:"error,omitempty"`
}

type rpcError struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
}

type toolCallParams struct {
	Name      string          `json:"name"`
	Arguments json.RawMessage `json:"arguments,omitempty"`
}

type toolCallResult struct {
	Content []toolResultContent `json:"content"`
	IsError bool                `json:"isError,omitempty"`
}

type toolResultContent struct {
	Type string `json:"type"`
	Text string `json:"text"`
}

var configPath string
var config *Config

func main() {
	configPath = resolveConfigPath()
	config = loadConfig(configPath)

	scanner := bufio.NewScanner(os.Stdin)
	scanner.Buffer(make([]byte, 1024*1024), 1024*1024)

	for scanner.Scan() {
		line := scanner.Bytes()
		if len(line) == 0 {
			continue
		}

		var req jsonrpcRequest
		if err := json.Unmarshal(line, &req); err != nil {
			sendError(nil, -32700, "Parse error")
			continue
		}

		handleRequest(&req)
	}
}

func handleRequest(req *jsonrpcRequest) {
	switch req.Method {
	case "initialize":
		handleInitialize(req)
	case "tools/list":
		handleToolsList(req)
	case "tools/call":
		handleToolsCall(req)
	case "notifications/initialized":
		// No response needed for notifications.
	case "ping":
		sendResult(req.ID, map[string]string{})
	default:
		sendError(req.ID, -32601, fmt.Sprintf("Method not found: %s", req.Method))
	}
}

func handleInitialize(req *jsonrpcRequest) {
	result := map[string]interface{}{
		"protocolVersion": "2024-11-05",
		"capabilities": map[string]interface{}{
			"tools": map[string]interface{}{},
		},
		"serverInfo": map[string]string{
			"name":    "conduit-mcp",
			"version": "0.1.0",
		},
	}
	sendResult(req.ID, result)
}

func handleToolsList(req *jsonrpcRequest) {
	tools := make([]map[string]interface{}, 0, len(config.Tools))
	for _, t := range config.Tools {
		tool := map[string]interface{}{
			"name":        t.Name,
			"description": t.Description,
			"inputSchema": toolInputSchema(t),
		}
		tools = append(tools, tool)
	}
	sendResult(req.ID, map[string]interface{}{
		"tools": tools,
	})
}

func handleToolsCall(req *jsonrpcRequest) {
	var params toolCallParams
	if err := json.Unmarshal(req.Params, &params); err != nil {
		sendError(req.ID, -32602, "Invalid params")
		return
	}

	mapping := findTool(params.Name)
	if mapping == nil {
		sendError(req.ID, -32602, fmt.Sprintf("Unknown tool: %s", params.Name))
		return
	}

	output, err := callAgentHook(config, mapping, string(params.Arguments))
	if err != nil {
		sendResult(req.ID, toolCallResult{
			Content: []toolResultContent{{Type: "text", Text: err.Error()}},
			IsError: true,
		})
		return
	}

	sendResult(req.ID, toolCallResult{
		Content: []toolResultContent{{Type: "text", Text: output}},
	})
}

func callAgentHook(cfg *Config, tool *ToolMapping, input string) (string, error) {
	args := []string{
		"agent-hook",
		"--agent", cfg.Agent,
		"--kind", tool.Kind,
		"--command", input,
		"--risk", riskString(tool.Risk),
	}

	cmd := exec.Command("conduitd", args...)
	output, err := cmd.CombinedOutput()
	if err != nil {
		return "", fmt.Errorf("agent-hook denied or failed: %s", strings.TrimSpace(string(output)))
	}
	return string(output), nil
}

func findTool(name string) *ToolMapping {
	for i := range config.Tools {
		if config.Tools[i].Name == name {
			return &config.Tools[i]
		}
	}
	return nil
}

func toolInputSchema(t ToolMapping) map[string]interface{} {
	schema := map[string]interface{}{
		"type": "object",
	}

	switch t.Kind {
	case "command":
		schema["properties"] = map[string]interface{}{
			"command": map[string]interface{}{
				"type":        "string",
				"description": "The shell command to execute",
			},
		}
		schema["required"] = []string{"command"}
	case "fileWrite", "patch":
		schema["properties"] = map[string]interface{}{
			"path": map[string]interface{}{
				"type":        "string",
				"description": "File path to write or edit",
			},
			"content": map[string]interface{}{
				"type":        "string",
				"description": "File content or patch",
			},
		}
		schema["required"] = []string{"path", "content"}
	case "read":
		schema["properties"] = map[string]interface{}{
			"path": map[string]interface{}{
				"type":        "string",
				"description": "File path to read",
			},
		}
		schema["required"] = []string{"path"}
	default:
		schema["properties"] = map[string]interface{}{
			"input": map[string]interface{}{
				"type":        "string",
				"description": "Tool input",
			},
		}
	}

	return schema
}

func riskString(risk int) string {
	switch risk {
	case 1:
		return "medium"
	case 2:
		return "high"
	case 3:
		return "critical"
	default:
		return "low"
	}
}

func sendResult(id interface{}, result interface{}) {
	resp := jsonrpcResponse{
		JSONRPC: "2.0",
		ID:      id,
		Result:  result,
	}
	writeJSON(resp)
}

func sendError(id interface{}, code int, message string) {
	resp := jsonrpcResponse{
		JSONRPC: "2.0",
		ID:      id,
		Error:   &rpcError{Code: code, Message: message},
	}
	writeJSON(resp)
}

func writeJSON(v interface{}) {
	data, err := json.Marshal(v)
	if err != nil {
		return
	}
	data = append(data, '\n')
	os.Stdout.Write(data)
}

func loadConfig(path string) *Config {
	data, err := os.ReadFile(path)
	if err != nil {
		fmt.Fprintf(os.Stderr, "conduit-mcp: cannot read config %s: %v\n", path, err)
		os.Exit(1)
	}
	var cfg Config
	if err := json.Unmarshal(data, &cfg); err != nil {
		fmt.Fprintf(os.Stderr, "conduit-mcp: invalid config: %v\n", err)
		os.Exit(1)
	}
	if cfg.Agent == "" {
		cfg.Agent = "unknown"
	}
	if cfg.SocketPath == "" {
		cfg.SocketPath = "~/.conduit/conduitd.sock"
	}
	return &cfg
}

func resolveConfigPath() string {
	if v := os.Getenv("CONDUIT_MCP_CONFIG"); v != "" {
		return v
	}
	if len(os.Args) > 1 {
		return os.Args[1]
	}
	home, err := os.UserHomeDir()
	if err != nil {
		fmt.Fprintln(os.Stderr, "conduit-mcp: cannot determine home directory")
		os.Exit(1)
	}
	return filepath.Join(home, ".conduit", "conduit-mcp.json")
}

// stdin is used by the scanner; ensure io is imported.
var _ io.Reader
