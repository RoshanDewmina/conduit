package main

import (
	"encoding/json"
	"net"
	"os"
	"testing"
	"time"
)

// TestRelayE2EReceiptAfterPairedDaemon is invoked by scripts/validation/relay-approval-e2e.sh
// after the phone has paired and the approval round-trip succeeded. It dispatches a
// fake terminal run against the already-running resident daemon (LANCER_RELAY_E2E_FAKE_DISPATCH=1)
// and asserts agent.run.receipt.get returns lancer.proof/v0 with the contract echoed.
func TestRelayE2EReceiptAfterPairedDaemon(t *testing.T) {
	if os.Getenv("LANCER_RELAY_E2E_RECEIPT_PROBE") != "1" {
		t.Skip("set LANCER_RELAY_E2E_RECEIPT_PROBE=1 to run against a live relay-e2e daemon")
	}

	token, err := readIPCToken()
	if err != nil {
		t.Fatalf("read ipc token: %v", err)
	}
	conn := dialResident(t)
	defer conn.Close()

	resp := controlHandshake(t, conn, token, IPCProtocolVersion)
	if resp.Error != nil {
		t.Fatalf("control handshake: %+v", resp.Error)
	}

	contract := runContract{
		Goal:               "Prove relay receipt path",
		DoneCriteria:       []string{"receipt schema valid"},
		ValidationCommands: []string{"go test ./..."},
	}
	dispatchParams := map[string]any{
		"agent":    "claudeCode",
		"cwd":      "/tmp/lancer-relay-e2e",
		"prompt":   "relay e2e receipt probe",
		"model":    "sonnet",
		"contract": contract,
	}
	dispatchRaw, _ := json.Marshal(dispatchParams)
	dispatchResp := rpcRoundTrip(t, conn, 10, "agent.dispatch", dispatchRaw)
	if dispatchResp.Error != nil {
		t.Fatalf("agent.dispatch error: %+v", dispatchResp.Error)
	}

	var dispatchResult dispatchResult
	raw, _ := json.Marshal(dispatchResp.Result)
	if err := json.Unmarshal(raw, &dispatchResult); err != nil {
		t.Fatalf("decode dispatch result: %v", err)
	}
	if dispatchResult.Status != "started" || dispatchResult.RunID == "" {
		t.Fatalf("dispatch result = %+v, want started with runId", dispatchResult)
	}

	var receipt *runReceipt
	deadline := time.After(5 * time.Second)
	for receipt == nil {
		select {
		case <-deadline:
			t.Fatal("timed out waiting for agent.run.receipt.get")
		default:
			params, _ := json.Marshal(map[string]string{"runId": dispatchResult.RunID})
			receiptResp := rpcRoundTrip(t, conn, 11, "agent.run.receipt.get", params)
			if receiptResp.Error != nil {
				if receiptResp.Error.Code == -32000 {
					time.Sleep(20 * time.Millisecond)
					continue
				}
				t.Fatalf("agent.run.receipt.get error: %+v", receiptResp.Error)
			}
			raw, _ := json.Marshal(receiptResp.Result)
			var got runReceipt
			if err := json.Unmarshal(raw, &got); err != nil {
				t.Fatalf("decode receipt: %v", err)
			}
			receipt = &got
		}
	}

	if receipt.Schema != receiptSchema {
		t.Fatalf("schema = %q, want %q", receipt.Schema, receiptSchema)
	}
	if receipt.RunID != dispatchResult.RunID {
		t.Fatalf("runId = %q, want %q", receipt.RunID, dispatchResult.RunID)
	}
	if receipt.Contract == nil || receipt.Contract.Goal != contract.Goal {
		t.Fatalf("contract = %+v, want goal %q", receipt.Contract, contract.Goal)
	}
	if receipt.Status != "completed" {
		t.Fatalf("status = %q, want completed", receipt.Status)
	}
}

func rpcRoundTrip(t *testing.T, conn net.Conn, id float64, method string, params json.RawMessage) rpcMessage {
	t.Helper()
	msg := rpcMessage{JSONRPC: "2.0", ID: id, Method: method, Params: params}
	data, err := json.Marshal(msg)
	if err != nil {
		t.Fatalf("marshal %s: %v", method, err)
	}
	if err := writeFrame(conn, data); err != nil {
		t.Fatalf("write %s: %v", method, err)
	}
	// The control connection also carries pushed event frames (agent.tool.start,
	// agent.run.status — the fake launcher emits them the instant dispatch
	// launches), so the first frame after a request is NOT necessarily its
	// reply. Skip frames until the one carrying our request ID.
	for {
		respData, err := readFrame(conn)
		if err != nil {
			t.Fatalf("read %s reply: %v", method, err)
		}
		var resp rpcMessage
		if err := json.Unmarshal(respData, &resp); err != nil {
			t.Fatalf("unmarshal %s reply: %v", method, err)
		}
		if respID, ok := resp.ID.(float64); ok && respID == id {
			return resp
		}
	}
}
