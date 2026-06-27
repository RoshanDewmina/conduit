#if canImport(WebKit)
import Foundation
import WebKit
import SSHTransport
import LancerCore

/// Bridges WKWebView requests to a remote workspace by piping each request
/// through an SSH exec channel running `curl`. This is the M6 baseline
/// (Helm's pattern). M7 upgrades to SOCKS-over-stream-RPC for websocket
/// support.
public final class SSHProxyURLSchemeHandler: NSObject, WKURLSchemeHandler, @unchecked Sendable {
    public let session: SSHSession
    public let remotePort: Int

    private static let shellMetas = CharacterSet(charactersIn: ";|&`$(){}[]<>\\\n\r\0\t")

    public init(session: SSHSession, remotePort: Int) {
        self.session = session
        self.remotePort = remotePort
    }

    public func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        let url = task.request.url ?? URL(string: "lancer-preview://localhost/")!
        let path = url.path.isEmpty ? "/" : url.path
        let query = url.query

        Task {
            do {
                try Self.validate(path: path, query: query)
                let queryString = query.map { "?\($0)" } ?? ""
                let raw = "http://localhost:\(remotePort)\(path)\(queryString)"
                let quoted = Self.shellQuote(raw)
                let body = try await session.executeCollected("curl -s -i \(quoted)")
                let (response, data, mime) = Self.parse(body, requestURL: url)
                task.didReceive(response)
                task.didReceive(data)
                task.didFinish()
                _ = mime
            } catch {
                let html = """
                <html><body style='font-family:-apple-system;color:#fff;background:#111;padding:16px'>
                <h2>Preview error</h2><pre>\(error.localizedDescription)</pre>
                </body></html>
                """
                let data = Data(html.utf8)
                let resp = URLResponse(url: url, mimeType: "text/html",
                                       expectedContentLength: data.count, textEncodingName: "utf-8")
                task.didReceive(resp); task.didReceive(data); task.didFinish()
            }
        }
    }

    public func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}

    // MARK: - Helpers

    private static func validate(path: String, query: String?) throws {
        let decodedPath = path.removingPercentEncoding ?? path
        let decodedQuery = query.flatMap { $0.removingPercentEncoding } ?? query ?? ""
        if decodedPath.unicodeScalars.contains(where: { shellMetas.contains($0) }) {
            throw LancerError.invalidResponse(detail: "shell metacharacters in path")
        }
        if decodedQuery.unicodeScalars.contains(where: { shellMetas.contains($0) }) {
            throw LancerError.invalidResponse(detail: "shell metacharacters in query")
        }
    }

    private static func shellQuote(_ s: String) -> String {
        "'\(s.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private static func parse(_ raw: String, requestURL: URL) -> (URLResponse, Data, String) {
        let separators = ["\r\n\r\n", "\n\n"]
        var headers = ""
        var body = ""
        for sep in separators {
            if let r = raw.range(of: sep) {
                headers = String(raw[raw.startIndex..<r.lowerBound])
                body    = String(raw[r.upperBound...])
                break
            }
        }
        if headers.isEmpty && body.isEmpty { body = raw }
        var mime = "text/html"
        for line in headers.components(separatedBy: .newlines) {
            if line.lowercased().hasPrefix("content-type:") {
                let v = line.dropFirst("content-type:".count).trimmingCharacters(in: .whitespaces)
                mime = v.components(separatedBy: ";").first?.trimmingCharacters(in: .whitespaces) ?? mime
                break
            }
        }
        let data = Data(body.utf8)
        let response = URLResponse(url: requestURL, mimeType: mime,
                                   expectedContentLength: data.count, textEncodingName: "utf-8")
        return (response, data, mime)
    }
}
#endif
