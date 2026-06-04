package main

import (
	"encoding/json"
	"fmt"
	"io"
	"net"
	"os"
	"time"
)

func runServe() error {
	sockPath, err := socketPath()
	if err != nil {
		return err
	}
	conn, err := net.DialTimeout("unix", sockPath, 2*time.Second)
	if err == nil {
		defer conn.Close()
		return runServeAttach(conn)
	}

	fmt.Fprintf(os.Stderr,
		"conduitd serve: resident daemon not reachable (%v); self-hosting socket (run `conduitd install` + `conduitd daemon` for a persistent bridge)\n",
		err,
	)
	return runServeLegacy()
}

// runServeAttach relays length-prefixed JSON-RPC between stdin/stdout and the resident daemon.
func runServeAttach(conn net.Conn) error {
	hello, _ := json.Marshal(attachHello{Op: "attach"})
	if err := writeFrame(conn, hello); err != nil {
		return fmt.Errorf("attach handshake: %w", err)
	}

	errCh := make(chan error, 2)
	go func() {
		for {
			frame, err := readFrame(conn)
			if err != nil {
				errCh <- err
				return
			}
			if err := writeFrame(os.Stdout, frame); err != nil {
				errCh <- err
				return
			}
		}
	}()
	go func() {
		for {
			frame, err := readFrame(os.Stdin)
			if err != nil {
				errCh <- err
				return
			}
			if err := writeFrame(conn, frame); err != nil {
				errCh <- err
				return
			}
		}
	}()
	err := <-errCh
	if err == io.EOF {
		return nil
	}
	return err
}

func runServeLegacy() error {
	b := newBridge()
	b.setEmitter(func(data []byte) error {
		return writeFrame(os.Stdout, data)
	})

	sockPath, err := socketPath()
	if err != nil {
		return fmt.Errorf("socket path: %w", err)
	}
	_ = os.Remove(sockPath)

	ln, err := net.Listen("unix", sockPath)
	if err != nil {
		return fmt.Errorf("listen unix %s: %w", sockPath, err)
	}
	defer func() { ln.Close(); os.Remove(sockPath) }()

	go func() {
		for {
			conn, err := ln.Accept()
			if err != nil {
				return
			}
			go func(c net.Conn) {
				first, framed, err := readFirstMessage(c)
				if err != nil || framed {
					c.Close()
					return
				}
				b.handleHook(c, first)
			}(conn)
		}
	}()

	return b.readStdioLoop(os.Stdin)
}
