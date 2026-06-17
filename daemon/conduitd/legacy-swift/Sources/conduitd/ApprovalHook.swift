import Foundation

/// Sends an approval event to conduitd's stdio server from an agent hook.
/// Usage: conduitd agent-hook approval --agent claude-code --kind command --command "rm -rf /tmp" --cwd /home/user --risk medium
struct ApprovalHook {
    static func run(args: [String]) {
        var agent = "claude-code"
        var kind = "command"
        var command: String? = nil
        var cwd = FileManager.default.currentDirectoryPath
        var risk = "medium"

        var i = 0
        let argArr = Array(args)
        while i < argArr.count {
            switch argArr[i] {
            case "--agent":   i += 1; if i < argArr.count { agent = argArr[i] }
            case "--kind":    i += 1; if i < argArr.count { kind = argArr[i] }
            case "--command": i += 1; if i < argArr.count { command = argArr[i] }
            case "--cwd":     i += 1; if i < argArr.count { cwd = argArr[i] }
            case "--risk":    i += 1; if i < argArr.count { risk = argArr[i] }
            default: break
            }
            i += 1
        }

        let approvalID = UUID().uuidString
        let event: [String: Any] = [
            "method": "agent.approval.pending",
            "params": [
                "id": approvalID,
                "agent": agent,
                "kind": kind,
                "command": command ?? "",
                "cwd": cwd,
                "risk": risk
            ]
        ]

        guard let body = try? JSONSerialization.data(withJSONObject: event) else {
            fputs("conduitd agent-hook: failed to encode event\n", stderr)
            exit(1)
        }

        // Write framed event to stdout (for piping to conduitd)
        var length = UInt32(body.count).bigEndian
        let lengthData = withUnsafeBytes(of: &length) { Data($0) }
        FileHandle.standardOutput.write(lengthData)
        FileHandle.standardOutput.write(body)

        fputs("[conduitd] approval event sent: \(approvalID)\n", stderr)
    }
}
