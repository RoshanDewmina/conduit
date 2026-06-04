package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net"
)

// readFirstMessage distinguishes agent-hook (raw JSON) from attach (length-prefixed).
// Agent-hook writes '{' as the first byte; attach framing uses a big-endian length whose
// first byte is typically 0x00 for small payloads.
func readFirstMessage(conn net.Conn) (payload []byte, framed bool, err error) {
	var lead [1]byte
	if _, err := io.ReadFull(conn, lead[:]); err != nil {
		return nil, false, err
	}
	if lead[0] == '{' {
		var raw json.RawMessage
		r := io.MultiReader(bytes.NewReader([]byte{'{'}), conn)
		if err := json.NewDecoder(r).Decode(&raw); err != nil {
			return nil, false, err
		}
		return raw, false, nil
	}

	var lenBuf [3]byte
	if _, err := io.ReadFull(conn, lenBuf[:]); err != nil {
		return nil, false, err
	}
	length := uint32(lead[0])<<24 | uint32(lenBuf[0])<<16 | uint32(lenBuf[1])<<8 | uint32(lenBuf[2])
	if length == 0 || length > maxFrameBytes {
		return nil, false, fmt.Errorf("invalid frame length: %d", length)
	}
	buf := make([]byte, length)
	if _, err := io.ReadFull(conn, buf); err != nil {
		return nil, false, err
	}
	return buf, true, nil
}
