package main

import (
	"encoding/binary"
	"encoding/json"
	"fmt"
	"io"
)

// readFrame reads one length-prefixed JSON frame from r.
func readFrame(r io.Reader) ([]byte, error) {
	var length uint32
	if err := binary.Read(r, binary.BigEndian, &length); err != nil {
		return nil, err
	}
	if length == 0 || length > maxFrameBytes {
		return nil, fmt.Errorf("invalid frame length: %d", length)
	}
	buf := make([]byte, length)
	if _, err := io.ReadFull(r, buf); err != nil {
		return nil, err
	}
	return buf, nil
}

// writeFrame writes a length-prefixed frame to w.
func writeFrame(w io.Writer, data []byte) error {
	length := uint32(len(data))
	if err := binary.Write(w, binary.BigEndian, length); err != nil {
		return err
	}
	_, err := w.Write(data)
	return err
}

// attachHello is the first message sent by `conduitd serve` when attaching to the resident daemon.
type attachHello struct {
	Op string `json:"op"`
}

func isAttachHello(data []byte) bool {
	var hello attachHello
	if err := json.Unmarshal(data, &hello); err != nil {
		return false
	}
	return hello.Op == "attach"
}
