import SwiftUI

// MARK: - PrivacyBadge
// Small inline chip showing whether agent data stays local or goes to cloud.

public enum PrivacyBadgeVariant {
    /// Data stays on host — green/ok tone
    case local
    /// Data sent to a cloud provider — amber/warn tone
    case cloud(provider: String)
    /// Encrypted relay — accent/blue tone
    case e2eRelay
}

public struct PrivacyBadge: View {
    let variant: PrivacyBadgeVariant

    @Environment(\.conduitTokens) private var t

    public init(_ variant: PrivacyBadgeVariant) {
        self.variant = variant
    }

    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
                .font(.system(size: 9))
            Text(label)
                .font(.dsMonoPt(9, weight: .bold))
                .tracking(9 * 0.08)
                .textCase(.uppercase)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(softColor)
        .foregroundStyle(fgColor)
        .clipShape(RoundedRectangle(cornerRadius: t.r2, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: t.r2, style: .continuous)
                .strokeBorder(fgColor.opacity(0.3), lineWidth: 0.5)
        )
    }

    private var iconName: String {
        switch variant {
        case .local:      return "lock.shield"
        case .cloud:      return "cloud"
        case .e2eRelay:   return "lock.rotation"
        }
    }

    private var label: String {
        switch variant {
        case .local:               return "LOCAL"
        case .cloud(let provider): return "CLOUD · \(provider.uppercased())"
        case .e2eRelay:            return "E2E RELAY"
        }
    }

    private var fgColor: Color {
        switch variant {
        case .local:    return t.ok
        case .cloud:    return t.warn
        case .e2eRelay: return t.accent
        }
    }

    private var softColor: Color {
        switch variant {
        case .local:    return t.okSoft
        case .cloud:    return t.warnSoft
        case .e2eRelay: return t.accentSoft
        }
    }
}
