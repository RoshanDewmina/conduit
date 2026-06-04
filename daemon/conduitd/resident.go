package main

import (
	"encoding/json"
	"fmt"
	"io"
	"net"
	"os"
	"sync"
	"time"
)

// resident owns the Unix socket, approval state, persistent queue, and optional attach client.
type resident struct {
	bridge *bridge
	queue  *diskQueue

	attachMu sync.Mutex
	attach   io.ReadWriteCloser
	writeMu  sync.Mutex
}

func runDaemon() error {
	r, err := newResident()
	if err != nil {
		return err
	}
	return r.listen()
}

func newResident() (*resident, error) {
	qPath, err := queuePath()
	if err != nil {
		return nil, err
	}
	r := &resident{
		bridge: newBridge(),
		queue:  newDiskQueue(qPath),
	}
	r.bridge.setEmitter(r.writeToAttach)
	if err := r.restoreQueue(); err != nil {
		return nil, fmt.Errorf("restore queue: %w", err)
	}
	return r, nil
}

func (r *resident) listen() error {
	sockPath, err := socketPath()
	if err != nil {
		return err
	}
	_ = os.Remove(sockPath)

	ln, err := net.Listen("unix", sockPath)
	if err != nil {
		return fmt.Errorf("listen unix %s: %w", sockPath, err)
	}
	defer func() { ln.Close(); os.Remove(sockPath) }()

	fmt.Fprintf(os.Stderr, "conduitd daemon listening on %s\n", sockPath)
	for {
		conn, err := ln.Accept()
		if err != nil {
			return err
		}
		go r.handleConnection(conn)
	}
}

func (r *resident) restoreQueue() error {
	events, err := r.queue.readAll()
	if err != nil {
		return err
	}
	for _, event := range events {
		r.bridge.approvals.add(event)
	}
	return nil
}

func (r *resident) handleConnection(conn net.Conn) {
	_ = conn.SetReadDeadline(time.Now().Add(10 * time.Second))
	first, framed, err := readFirstMessage(conn)
	if err != nil {
		conn.Close()
		return
	}
	_ = conn.SetReadDeadline(time.Time{})

	if framed && isAttachHello(first) {
		r.serveAttach(conn, first)
		return
	}
	if !framed {
		r.serveHook(conn, first)
		return
	}
	conn.Close()
}

func (r *resident) serveAttach(conn net.Conn, _ []byte) {
	r.attachMu.Lock()
	if r.attach != nil {
		r.attachMu.Unlock()
		conn.Close()
		fmt.Fprintln(os.Stderr, "conduitd daemon: attach rejected (another client connected)")
		return
	}
	r.attach = conn
	r.attachMu.Unlock()

	defer func() {
		r.attachMu.Lock()
		if r.attach == conn {
			r.attach = nil
		}
		r.attachMu.Unlock()
		conn.Close()
	}()

	if err := r.drainToAttach(); err != nil {
		fmt.Fprintf(os.Stderr, "conduitd daemon: drain queue: %v\n", err)
	}

	for {
		frame, err := readFrame(conn)
		if err != nil {
			if err != io.EOF {
				fmt.Fprintf(os.Stderr, "conduitd daemon: attach read: %v\n", err)
			}
			return
		}
		var msg rpcMessage
		if err := json.Unmarshal(frame, &msg); err != nil {
			continue
		}
		r.handleAttachMessage(&msg)
	}
}

func (r *resident) handleAttachMessage(msg *rpcMessage) {
	switch msg.Method {
	case "ping":
		r.bridge.writeResult(msg.ID, "pong")

	case "agent.approval.response":
		var decision ApprovalDecision
		if err := json.Unmarshal(msg.Params, &decision); err != nil {
			r.bridge.writeError(msg.ID, -32602, "invalid params")
			return
		}
		event, ok := r.bridge.approvals.resolve(decision.ApprovalID, decision.Decision, decision.EditedToolInput)
		if ok && decision.Decision == "approveAlways" {
			r.bridge.always.add(alwaysRuleFromEvent(event))
		}
		_ = r.queue.remove(decision.ApprovalID)
		_ = r.queue.syncFromStore(r.bridge.approvals)
		r.bridge.writeResult(msg.ID, "ok")

	case "conduit.device.register":
		var info registeredDevice
		if err := json.Unmarshal(msg.Params, &info); err != nil {
			r.bridge.writeError(msg.ID, -32602, "invalid params")
			return
		}
		r.bridge.deviceMu.Lock()
		r.bridge.device = &info
		r.bridge.deviceMu.Unlock()
		r.bridge.writeResult(msg.ID, "ok")

	default:
		r.bridge.writeError(msg.ID, -32601, "method not found")
	}
}

func (r *resident) drainToAttach() error {
	events := r.bridge.approvals.pendingEvents()
	for _, event := range events {
		notification, err := marshalPendingNotification(event)
		if err != nil {
			continue
		}
		if err := r.writeToAttach(notification); err != nil {
			return err
		}
	}
	return r.queue.replace(nil)
}

func (r *resident) serveHook(conn net.Conn, first []byte) {
	defer conn.Close()
	conn.SetDeadline(time.Now().Add(130 * time.Second))

	var event ApprovalEvent
	if err := json.Unmarshal(first, &event); err != nil || event.ApprovalID == "" {
		fmt.Fprintf(conn, `{"error":"bad request"}`)
		return
	}

	if r.bridge.always.matches(event) {
		_ = json.NewEncoder(conn).Encode(ApprovalDecision{ApprovalID: event.ApprovalID, Decision: "approve"})
		return
	}

	decisionCh := r.bridge.approvals.add(event)
	if err := r.notifyAttachOrQueue(event); err != nil {
		fmt.Fprintf(conn, `{"error":"internal"}`)
		return
	}

	r.bridge.deviceMu.RLock()
	dev := r.bridge.device
	r.bridge.deviceMu.RUnlock()
	if dev != nil && dev.PushBackendURL != "" {
		go r.bridge.postApprovalPush(dev, event)
	}

	result := waitWithTimeout(decisionCh, 120*time.Second)
	decision := result.decision
	if decision == "approveAlways" {
		r.bridge.always.add(alwaysRuleFromEvent(event))
		decision = "approve"
	}
	_ = r.queue.remove(event.ApprovalID)
	_ = r.queue.syncFromStore(r.bridge.approvals)

	resp := ApprovalDecision{
		ApprovalID:      event.ApprovalID,
		Decision:        decision,
		EditedToolInput: result.editedToolInput,
	}
	_ = json.NewEncoder(conn).Encode(resp)
}

func (r *resident) notifyAttachOrQueue(event ApprovalEvent) error {
	notification, err := marshalPendingNotification(event)
	if err != nil {
		return err
	}
	if err := r.writeToAttach(notification); err == nil {
		return nil
	}
	if err := r.queue.add(event); err != nil {
		return err
	}
	return r.queue.syncFromStore(r.bridge.approvals)
}

func (r *resident) writeToAttach(data []byte) error {
	r.attachMu.Lock()
	conn := r.attach
	r.attachMu.Unlock()
	if conn == nil {
		return fmt.Errorf("no attach client")
	}
	r.writeMu.Lock()
	defer r.writeMu.Unlock()
	return writeFrame(conn, data)
}
