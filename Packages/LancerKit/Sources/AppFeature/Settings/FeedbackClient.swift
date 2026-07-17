import Darwin
import Foundation
import SSHTransport
#if canImport(UIKit)
import UIKit
#endif

/// Feedback category posted to `POST /feedback`.
public enum FeedbackType: String, Codable, Sendable, CaseIterable, Identifiable {
    case bug
    case feature
    case other

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .bug: return "Bug"
        case .feature: return "Feature request"
        case .other: return "Other"
        }
    }
}

/// Auto-collected diagnostics attached to every feedback submission.
public struct FeedbackDiagnostics: Sendable, Equatable {
    public let appVersion: String
    public let build: String
    public let osVersion: String
    public let deviceModel: String

    public init(appVersion: String, build: String, osVersion: String, deviceModel: String) {
        self.appVersion = appVersion
        self.build = build
        self.osVersion = osVersion
        self.deviceModel = deviceModel
    }
}

/// Successful `201` response from `POST /feedback`.
public struct FeedbackSubmission: Sendable, Equatable {
    public let issue: Int
    public let url: String

    public init(issue: Int, url: String) {
        self.issue = issue
        self.url = url
    }
}

/// User-facing errors from feedback validation or submission.
public enum FeedbackClientError: Error, LocalizedError, Sendable, Equatable {
    case messageTooShort
    case messageTooLong
    case notConfigured
    case server(String)
    case network

    public var isNotConfigured: Bool {
        if case .notConfigured = self { return true }
        return false
    }

    public var isRetryable: Bool {
        if case .network = self { return true }
        return false
    }

    public var userMessage: String {
        switch self {
        case .messageTooShort:
            return "Write at least 10 characters."
        case .messageTooLong:
            return "Keep feedback under 4,000 characters."
        case .notConfigured:
            return "Feedback is not configured on this server."
        case .server(let message):
            return message
        case .network:
            return "Couldn't reach the server. Check your connection and try again."
        }
    }

    public var errorDescription: String? { userMessage }
}

/// Submits feature requests / bug reports to the push-backend `POST /feedback` endpoint.
public struct FeedbackClient: Sendable {
    public static let messageMinLength = 10
    public static let messageMaxLength = 4000

    private let baseURL: URL
    private let session: URLSession
    private let diagnostics: FeedbackDiagnostics

    public init(
        baseURL: URL,
        session: URLSession = .shared,
        diagnostics: FeedbackDiagnostics = .collect()
    ) {
        self.baseURL = baseURL
        self.session = session
        self.diagnostics = diagnostics
    }

    /// Production client: HTTPS base from `LANCER_PUSH_BACKEND_URL` / `RelaySettings`.
    public static func makeDefault(session: URLSession = .shared) -> FeedbackClient {
        FeedbackClient(
            baseURL: resolveBackendBaseURL(),
            session: session,
            diagnostics: .collect()
        )
    }

    public static func isValidMessage(_ message: String) -> Bool {
        let count = message.count
        return count >= messageMinLength && count <= messageMaxLength
    }

    /// Converts a stored push/relay URL to an HTTPS REST base (wss→https, ws→http).
    public static func httpsBaseURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty,
              !trimmed.hasPrefix("$("),
              var components = URLComponents(string: trimmed)
        else { return nil }

        switch components.scheme?.lowercased() {
        case "wss":
            components.scheme = "https"
        case "ws":
            components.scheme = "http"
        case "https", "http":
            break
        default:
            return nil
        }

        guard components.host?.isEmpty == false else { return nil }
        // REST calls hit the service root; strip any websocket path segments.
        components.path = ""
        components.query = nil
        components.fragment = nil
        return components.url
    }

    /// Prefer Info.plist `LANCER_PUSH_BACKEND_URL`, else `RelaySettings` (wss→https).
    public static func resolveBackendBaseURL(
        bundle: Bundle = .main,
        defaults: UserDefaults = .standard
    ) -> URL {
        if let plist = bundle.object(forInfoDictionaryKey: "LANCER_PUSH_BACKEND_URL") as? String,
           let url = httpsBaseURL(from: plist) {
            return url
        }
        if let url = httpsBaseURL(from: RelaySettings.urlString(defaults: defaults)) {
            return url
        }
        // Fail-safe: derive HTTPS from the same default RelaySettings already owns.
        return httpsBaseURL(from: RelaySettings.defaultURLString)!
    }

    public func submit(type: FeedbackType, message: String) async throws -> FeedbackSubmission {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= Self.messageMinLength else { throw FeedbackClientError.messageTooShort }
        guard trimmed.count <= Self.messageMaxLength else { throw FeedbackClientError.messageTooLong }

        let endpoint = baseURL.appendingPathComponent("feedback")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let payload = FeedbackPayload(
            type: type.rawValue,
            message: trimmed,
            appVersion: diagnostics.appVersion,
            build: diagnostics.build,
            osVersion: diagnostics.osVersion,
            deviceModel: diagnostics.deviceModel
        )
        request.httpBody = try JSONEncoder().encode(payload)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw FeedbackClientError.network
        }

        guard let http = response as? HTTPURLResponse else {
            throw FeedbackClientError.network
        }

        if http.statusCode == 201 {
            let decoded = try JSONDecoder().decode(FeedbackSuccessBody.self, from: data)
            return FeedbackSubmission(issue: decoded.issue, url: decoded.url)
        }

        if http.statusCode == 503 {
            throw FeedbackClientError.notConfigured
        }

        if let err = try? JSONDecoder().decode(FeedbackErrorBody.self, from: data),
           !err.error.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw FeedbackClientError.server(err.error)
        }
        throw FeedbackClientError.server("Something went wrong (\(http.statusCode)). Try again.")
    }
}

public extension FeedbackDiagnostics {
    static func collect(bundle: Bundle = .main) -> FeedbackDiagnostics {
        let appVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
#if canImport(UIKit) && os(iOS)
        let osVersion = UIDevice.current.systemVersion
#else
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
#endif
        return FeedbackDiagnostics(
            appVersion: appVersion,
            build: build,
            osVersion: osVersion,
            deviceModel: Self.utsnameMachine()
        )
    }

    private static func utsnameMachine() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: 1) { cString in
                String(cString: cString)
            }
        }
    }
}

private struct FeedbackPayload: Encodable {
    let type: String
    let message: String
    let appVersion: String
    let build: String
    let osVersion: String
    let deviceModel: String
}

private struct FeedbackSuccessBody: Decodable {
    let issue: Int
    let url: String
}

private struct FeedbackErrorBody: Decodable {
    let error: String
}
