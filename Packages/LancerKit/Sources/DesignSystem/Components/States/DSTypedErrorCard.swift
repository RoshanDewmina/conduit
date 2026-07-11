import SwiftUI

// MARK: - Error type enum

public enum DSConnectError: Equatable {
    case authRejected
    case hostUnreachable
    case hostKeyMismatch
    case dnsFailed
    case runFailed(String)
    case other(String)
}

extension DSConnectError {
    var title: String {
        switch self {
        case .authRejected:          return "authentication failed"
        case .hostUnreachable:       return "host unreachable"
        case .hostKeyMismatch:       return "host key mismatch"
        case .dnsFailed:             return "can't resolve host"
        case .runFailed(let detail): return detail.isEmpty ? "run failed" : detail
        case .other(let m):          return m
        }
    }

    var body: String {
        switch self {
        case .authRejected:
            return "The server refused the key or password. Check your credentials."
        case .hostUnreachable:
            return "Connection refused or timed out. The host may be down or the port blocked."
        case .hostKeyMismatch:
            return "The server's fingerprint has changed — possible MITM. Verify the host key before reconnecting."
        case .dnsFailed:
            return "The hostname couldn't be resolved. Check the address or try connecting by IP."
        case .runFailed:
            return "The agent run ended with an error. Check the run output for details, then retry or start a new run."
        case .other:
            return "An unexpected error occurred. Check the address and credentials, then retry."
        }
    }

    var badgeLabel: String {
        switch self {
        case .authRejected:     return "AUTH"
        case .hostUnreachable:  return "NETWORK"
        case .hostKeyMismatch:  return "HOST KEY"
        case .dnsFailed:        return "DNS"
        case .runFailed:        return "RUN"
        case .other:            return "ERROR"
        }
    }

    var badgeTone: DSChipTone {
        switch self {
        case .authRejected:     return .danger
        case .hostUnreachable:  return .warn
        case .hostKeyMismatch:  return .danger
        case .dnsFailed:        return .warn
        case .runFailed:        return .danger
        case .other:            return .danger
        }
    }

    var primaryAction: String {
        switch self {
        case .authRejected:     return "copy public key"
        case .hostUnreachable:  return "retry"
        case .hostKeyMismatch:  return "review fingerprint"
        case .dnsFailed:        return "edit address"
        case .runFailed:        return "retry"
        case .other:            return "retry"
        }
    }

    var secondaryAction: String {
        switch self {
        case .authRejected:     return "edit host · try password"
        case .hostUnreachable:  return "run diagnostics"
        case .hostKeyMismatch:  return "cancel connection"
        case .dnsFailed:        return "connect by ip"
        case .runFailed:        return "view output"
        case .other:            return "dismiss"
        }
    }
}

#if os(iOS)
// MARK: - DSTypedErrorCard

public struct DSTypedErrorCard: View {
    let error: DSConnectError
    let onPrimary: (() -> Void)?
    let onSecondary: (() -> Void)?

    @Environment(\.lancerTokens) private var t

    public init(
        error: DSConnectError,
        onPrimary: (() -> Void)? = nil,
        onSecondary: (() -> Void)? = nil
    ) {
        self.error = error
        self.onPrimary = onPrimary
        self.onSecondary = onSecondary
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                DotMatrixView(state: .error, cols: 12, rows: 4, cell: 7, dot: 3)
                    .frame(width: 100, height: 36)
                CursorStatusBadge(kind: .risk(level: .critical), label: error.badgeLabel)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(error.title)
                    .font(.dsMonoPt(15, weight: .semibold))
                    .foregroundStyle(t.text)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility3)

                Text(error.body)
                    .font(.dsMonoPt(12))
                    .foregroundStyle(t.text3)
                    .fixedSize(horizontal: false, vertical: true)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility3)
            }

            VStack(spacing: 8) {
                if let onPrimary {
                    CursorPillButton(title: error.primaryAction, style: .primary, fullWidth: true, action: onPrimary)
                }
                if let onSecondary {
                    Button(action: onSecondary) {
                        Text(error.secondaryAction)
                            .font(.dsMonoPt(12))
                            .foregroundStyle(t.accent)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(18)
        .background(t.surface)
        .overlay(
            Rectangle()
                .strokeBorder(t.border, lineWidth: 0.5)
        )
    }
}
#endif
