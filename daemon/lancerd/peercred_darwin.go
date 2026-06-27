//go:build darwin

package main

import (
	"fmt"
	"net"

	"golang.org/x/sys/unix"
)

// peerUID returns the effective UID of the process on the other end of conn,
// queried via the LOCAL_PEERCRED socket option (BSD/Darwin's analog of Linux's
// SO_PEERCRED). conn must be a *net.UnixConn; anything else is rejected so a
// non-Unix-socket transport can never bypass the same-user check.
func peerUID(conn net.Conn) (uint32, error) {
	uc, ok := conn.(*net.UnixConn)
	if !ok {
		return 0, fmt.Errorf("peerUID: not a unix socket connection")
	}
	rawConn, err := uc.SyscallConn()
	if err != nil {
		return 0, err
	}

	var cred *unix.Xucred
	var ctrlErr error
	err = rawConn.Control(func(fd uintptr) {
		cred, ctrlErr = unix.GetsockoptXucred(int(fd), unix.SOL_LOCAL, unix.LOCAL_PEERCRED)
	})
	if err != nil {
		return 0, err
	}
	if ctrlErr != nil {
		return 0, ctrlErr
	}
	return cred.Uid, nil
}
