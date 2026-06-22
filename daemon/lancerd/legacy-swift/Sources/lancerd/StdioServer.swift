import Foundation

/// JSON-RPC server that reads from stdin and writes to stdout.
/// Frame format: 4-byte big-endian length prefix + UTF-8 JSON body.
struct StdioServer {
    static func run() {
        fputs("[lancerd] serve --stdio started (pid=\(ProcessInfo.processInfo.processIdentifier))\n", stderr)

        // Handle pings and echo them back as pongs
        let stdinFH = FileHandle.standardInput
        let stdoutFH = FileHandle.standardOutput

        while true {
            // Read 4-byte length prefix
            guard let lengthData = try? stdinFH.read(upToCount: 4), lengthData.count == 4 else {
                break
            }
            let length = lengthData.withUnsafeBytes { ptr in
                ptr.load(as: UInt32.self).bigEndian
            }
            guard length > 0 && length < 16_000_000 else { break }

            // Read body
            guard let body = try? stdinFH.read(upToCount: Int(length)), body.count == Int(length) else {
                break
            }

            guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
                  let method = json["method"] as? String else {
                continue
            }

            switch method {
            case "ping":
                let id = json["id"]
                let pong: [String: Any] = ["id": id ?? NSNull(), "method": "pong", "result": [:]]
                if let pongData = try? JSONSerialization.data(withJSONObject: pong) {
                    writeFramed(data: pongData, to: stdoutFH)
                }
            default:
                fputs("[lancerd] unknown method: \(method)\n", stderr)
            }
        }
    }

    static func writeFramed(data: Data, to fh: FileHandle) {
        var length = UInt32(data.count).bigEndian
        let lengthData = withUnsafeBytes(of: &length) { Data($0) }
        fh.write(lengthData)
        fh.write(data)
    }
}
