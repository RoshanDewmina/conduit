package main

import (
	"fmt"
	"os"
)

const version = "0.1.0"

func main() {
	if len(os.Args) < 2 {
		usage()
		os.Exit(1)
	}

	switch os.Args[1] {
	case "version", "--version", "-v":
		fmt.Println(version)

	case "serve":
		if err := runServe(); err != nil {
			fmt.Fprintln(os.Stderr, "conduitd serve:", err)
			os.Exit(1)
		}

	case "agent-hook":
		if err := runAgentHook(os.Args[2:]); err != nil {
			// Exit 1 = denied / error (agent hook convention)
			fmt.Fprintln(os.Stderr, "conduitd agent-hook:", err)
			os.Exit(1)
		}

	default:
		fmt.Fprintf(os.Stderr, "unknown command: %s\n", os.Args[1])
		usage()
		os.Exit(1)
	}
}

func usage() {
	fmt.Fprintln(os.Stderr, `conduitd - Conduit remote daemon

Usage:
  conduitd serve           Run JSON-RPC server (iOS app connects via SSH stdio)
  conduitd agent-hook ...  Send approval event from agent pre-tool hook
  conduitd version         Print version`)
}
