import Foundation

// conduitd — Conduit daemon CLI
// Usage:
//   conduitd serve --stdio         Start JSON-RPC server on stdin/stdout
//   conduitd version               Print version and exit
//   conduitd agent-hook approval   Send an approval event from an agent hook

let args = CommandLine.arguments.dropFirst()

guard let command = args.first else {
    fputs("Usage: conduitd <serve|version|agent-hook>\n", stderr)
    exit(1)
}

switch command {
case "version":
    print("0.1.0")
    exit(0)
case "serve":
    StdioServer.run()
case "agent-hook":
    ApprovalHook.run(args: Array(args.dropFirst()))
default:
    fputs("Unknown command: \(command)\n", stderr)
    exit(1)
}
