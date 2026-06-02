import Foundation

/// A flat, exhaustive set of user-facing errors. Engines raise typed errors
/// from this enum so the UI can map errors to messages and recovery actions
/// without `as?` chains.
public enum ConduitError: Error, LocalizedError, Sendable, Equatable {
    // Connectivity
    case notConnected
    case connectionRefused(host: String)
    case dnsResolutionFailed(host: String)
    case authFailed(reason: String)
    case hostKeyMismatch(expected: String, actual: String)
    case hostKeyUnknown(fingerprint: String)
    case channelClosed
    case timeout
    case networkUnavailable
    case cancelled

    // Crypto / Keys
    case keyNotFound(tag: String)
    case keyDecodeFailed(reason: String)
    case enclaveUnavailable

    // Agent / AI
    case providerUnavailable(name: String, status: Int?)
    case rateLimited
    case apiKeyMissing(provider: String)
    case invalidResponse(detail: String)
    case promptInjectionDetected

    // Persistence
    case databaseFailure(detail: String)

    // Approvals
    case approvalExpired
    case approvalUnknown(id: String)

    // Generic
    case unsupportedPlatform
    case noCredentialAvailable
    case configurationMissing(key: String)
    case unknown(detail: String)

    public var errorDescription: String? {
        switch self {
        case .notConnected:                       "Not connected."
        case .connectionRefused(let h):           "Connection refused by \(h)."
        case .dnsResolutionFailed(let h):         "Can't find host \"\(h)\". Check the hostname and your network."
        case .authFailed(let r):                  "Authentication failed: \(r)"
        case .hostKeyMismatch(let e, let a):      "Host key changed (expected \(e), got \(a))."
        case .hostKeyUnknown(let fp):             "First-time host key. Verify fingerprint: \(fp)"
        case .channelClosed:                      "Channel closed unexpectedly."
        case .timeout:                            "Operation timed out."
        case .networkUnavailable:                 "Network unavailable."
        case .cancelled:                          "Cancelled."
        case .keyNotFound(let tag):               "SSH key '\(tag)' not found in the device keychain."
        case .keyDecodeFailed(let r):             "Could not decode key: \(r)"
        case .enclaveUnavailable:                 "Secure Enclave not available on this device."
        case .providerUnavailable(let n, let s):
            s.map { "\(n) provider error (HTTP \($0))." } ?? "\(n) provider unavailable."
        case .rateLimited:                        "Rate limited. Try again shortly."
        case .apiKeyMissing(let p):               "No \(p) API key configured."
        case .invalidResponse(let d):             "Invalid response: \(d)"
        case .promptInjectionDetected:            "Potential prompt injection detected in output."
        case .databaseFailure(let d):             "Local database error: \(d)"
        case .approvalExpired:                    "This approval expired."
        case .approvalUnknown(let id):            "Unknown approval id: \(id)"
        case .unsupportedPlatform:                "This feature is not supported on this device."
        case .noCredentialAvailable:              "No saved credential to reconnect. Please sign in again."
        case .configurationMissing(let k):        "Missing configuration: \(k)"
        case .unknown(let d):                     "Unexpected error: \(d)"
        }
    }
}
