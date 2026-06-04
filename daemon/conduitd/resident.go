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

// resident owns the Unix socket, policy-aware approval state, persistent queue, and optional attach client.
type resident struct {
	core *server
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
	r.core.startScheduler(make(chan struct{})) // fires due schedules for the process lifetime
	return r.listen()
}

func newResident() (*resident, error) {
	qPath, err := queuePath()
	if err != nil {
		return nil, err
	}
	core := newServer(serverHome())
	r := &resident{
		core:  core,
		queue: newDiskQueue(qPath),
	}
	core.setEmitter(r.writeToAttach)
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
		r.core.approvals.add(event)
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
		r.core.handleHookWithNotify(conn, first, r.notifyAttachOrQueue)
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
	if msg.Method == "agent.approval.response" {
		var decision ApprovalDecision
		if err := json.Unmarshal(msg.Params, &decision); err == nil {
			_ = r.queue.remove(decision.ApprovalID)
			_ = r.queue.syncFromStore(r.core.approvals)
		}
	}
	r.core.handleMessage(msg)
}

func (r *resident) drainToAttach() error {
	events := r.core.approvals.pendingEvents()
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

func (r *resident) notifyAttachOrQueue(event ApprovalEvent) error {
	if err := r.queue.add(event); err != nil {
		return err
	}
	if err := r.queue.syncFromStore(r.core.approvals); err != nil {
		return err
	}
	notification, err := marshalPendingNotification(event)
	if err != nil {
		return err
	}
	if err := r.writeToAttach(notification); err == nil {
		return nil
	}
	return nil
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
