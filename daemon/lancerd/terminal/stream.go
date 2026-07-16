package terminal

import "encoding/binary"

// EncodeStreamFrame ports Orca encodeTerminalStreamFrame
// (src/shared/terminal-stream-protocol.ts).
func EncodeStreamFrame(opcode StreamOpcode, streamID uint32, seq uint64, payload []byte) []byte {
	out := make([]byte, headerBytes+len(payload))
	out[0] = streamKind
	out[1] = streamVersion
	out[2] = byte(opcode)
	out[3] = 0
	binary.LittleEndian.PutUint32(out[4:8], streamID)
	binary.LittleEndian.PutUint32(out[8:12], uint32(seq>>32))
	binary.LittleEndian.PutUint32(out[12:16], uint32(seq))
	copy(out[headerBytes:], payload)
	return out
}

// DecodeStreamFrame ports Orca decodeTerminalStreamFrame.
func DecodeStreamFrame(b []byte) (opcode StreamOpcode, streamID uint32, seq uint64, payload []byte, ok bool) {
	if len(b) < headerBytes {
		return 0, 0, 0, nil, false
	}
	if b[0] != streamKind || b[1] != streamVersion {
		return 0, 0, 0, nil, false
	}
	opcode = StreamOpcode(b[2])
	streamID = binary.LittleEndian.Uint32(b[4:8])
	high := binary.LittleEndian.Uint32(b[8:12])
	low := binary.LittleEndian.Uint32(b[12:16])
	seq = (uint64(high) << 32) | uint64(low)
	payload = append([]byte(nil), b[headerBytes:]...)
	return opcode, streamID, seq, payload, true
}
