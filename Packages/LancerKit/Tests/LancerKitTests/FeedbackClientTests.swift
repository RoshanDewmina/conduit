import Foundation
import Testing
@testable import AppFeature

// MARK: - URLProtocol stub

private final class FeedbackStubState: @unchecked Sendable {
    private let lock = NSLock()
    var statusCode: Int = 201
    var responseBody: Data = Data()
    var error: Error?
    var lastRequest: URLRequest?
    var lastBody: Data?

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        statusCode = 201
        responseBody = Data()
        error = nil
        lastRequest = nil
        lastBody = nil
    }

    func record(request: URLRequest, body: Data?) {
        lock.lock()
        defer { lock.unlock() }
        lastRequest = request
        lastBody = body
    }

    func snapshot() -> (status: Int, body: Data, error: Error?, request: URLRequest?, bodyData: Data?) {
        lock.lock()
        defer { lock.unlock() }
        return (statusCode, responseBody, error, lastRequest, lastBody)
    }
}

private let feedbackStub = FeedbackStubState()

private final class FeedbackStubURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = request.httpBodyStreamedData() ?? request.httpBody
        feedbackStub.record(request: request, body: body)

        let snap = feedbackStub.snapshot()
        if let error = snap.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let resp = HTTPURLResponse(
            url: request.url!,
            statusCode: snap.status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: snap.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private extension URLRequest {
    func httpBodyStreamedData() -> Data? {
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read > 0 { data.append(buffer, count: read) } else { break }
        }
        return data.isEmpty ? nil : data
    }
}

private func makeStubSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [FeedbackStubURLProtocol.self]
    return URLSession(configuration: config)
}

private let fixedDiagnostics = FeedbackDiagnostics(
    appVersion: "1.2.3",
    build: "456",
    osVersion: "18.0",
    deviceModel: "iPhone17,1"
)

// MARK: - Validation

@Suite("FeedbackClient validation")
struct FeedbackClientValidationTests {
    @Test("message below 10 chars is invalid")
    func tooShort() {
        #expect(FeedbackClient.isValidMessage(String(repeating: "a", count: 9)) == false)
        #expect(FeedbackClient.isValidMessage("") == false)
    }

    @Test("message at 10 and 4000 chars is valid")
    func boundsInclusive() {
        #expect(FeedbackClient.isValidMessage(String(repeating: "a", count: 10)) == true)
        #expect(FeedbackClient.isValidMessage(String(repeating: "b", count: 4000)) == true)
    }

    @Test("message above 4000 chars is invalid")
    func tooLong() {
        #expect(FeedbackClient.isValidMessage(String(repeating: "c", count: 4001)) == false)
    }
}

// MARK: - HTTPS base URL

@Suite("FeedbackClient backendBaseURL")
struct FeedbackClientBaseURLTests {
    @Test("converts wss relay URL to https")
    func convertsWSS() {
        let url = FeedbackClient.httpsBaseURL(from: "wss://conduit-push.fly.dev")
        #expect(url?.absoluteString == "https://conduit-push.fly.dev")
    }

    @Test("keeps https push-backend URL")
    func keepsHTTPS() {
        let url = FeedbackClient.httpsBaseURL(from: "https://conduit-push.fly.dev")
        #expect(url?.absoluteString == "https://conduit-push.fly.dev")
    }
}

// MARK: - Submit

@Suite("FeedbackClient submit", .serialized)
struct FeedbackClientSubmitTests {
    @Test("POST encodes all six payload fields")
    func encodesPayload() async throws {
        feedbackStub.reset()
        feedbackStub.statusCode = 201
        feedbackStub.responseBody = Data(#"{"issue":42,"url":"https://example.com/42"}"#.utf8)

        let client = FeedbackClient(
            baseURL: URL(string: "https://push.test")!,
            session: makeStubSession(),
            diagnostics: fixedDiagnostics
        )
        _ = try await client.submit(type: .bug, message: "Something broke in settings")

        let body = try #require(feedbackStub.snapshot().bodyData)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["type"] as? String == "bug")
        #expect(json["message"] as? String == "Something broke in settings")
        #expect(json["appVersion"] as? String == "1.2.3")
        #expect(json["build"] as? String == "456")
        #expect(json["osVersion"] as? String == "18.0")
        #expect(json["deviceModel"] as? String == "iPhone17,1")

        let request = try #require(feedbackStub.snapshot().request)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://push.test/feedback")
    }

    @Test("201 parses issue and url")
    func parsesSuccess() async throws {
        feedbackStub.reset()
        feedbackStub.statusCode = 201
        feedbackStub.responseBody = Data(#"{"issue":99,"url":"https://github.com/org/repo/issues/99"}"#.utf8)

        let client = FeedbackClient(
            baseURL: URL(string: "https://push.test")!,
            session: makeStubSession(),
            diagnostics: fixedDiagnostics
        )
        let result = try await client.submit(type: .feature, message: "Please add dark mode toggle")
        #expect(result.issue == 99)
        #expect(result.url == "https://github.com/org/repo/issues/99")
    }

    @Test("503 maps to user-facing not configured error")
    func maps503() async {
        feedbackStub.reset()
        feedbackStub.statusCode = 503
        feedbackStub.responseBody = Data(#"{"error":"feedback disabled"}"#.utf8)

        let client = FeedbackClient(
            baseURL: URL(string: "https://push.test")!,
            session: makeStubSession(),
            diagnostics: fixedDiagnostics
        )
        do {
            _ = try await client.submit(type: .other, message: "Just saying hello there")
            Issue.record("expected throw")
        } catch let error as FeedbackClientError {
            #expect(error.isNotConfigured)
            #expect(error.userMessage.lowercased().contains("not configured"))
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }

    @Test("network error maps to retryable message")
    func mapsNetworkError() async {
        feedbackStub.reset()
        feedbackStub.error = URLError(.notConnectedToInternet)

        let client = FeedbackClient(
            baseURL: URL(string: "https://push.test")!,
            session: makeStubSession(),
            diagnostics: fixedDiagnostics
        )
        do {
            _ = try await client.submit(type: .feature, message: "Network path should fail here")
            Issue.record("expected throw")
        } catch let error as FeedbackClientError {
            #expect(error.isRetryable)
            let lower = error.userMessage.lowercased()
            #expect(lower.contains("try again") || lower.contains("connection") || lower.contains("network"))
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }
}
