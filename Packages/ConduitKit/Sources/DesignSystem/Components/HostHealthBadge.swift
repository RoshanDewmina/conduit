import SwiftUI
import ConduitCore

public struct HostHealthBadge: View {
    let health: HostHealth
    @Environment(\.conduitTokens) private var t

    public init(health: HostHealth) {
        self.health = health
    }

    public var body: some View {
        HStack(spacing: 5) {
            DSStatusDot(
                tone: dotTone,
                pulse: health.status == .sleeping,
                size: 6
            )
            Text(health.status.rawValue.capitalized)
                .font(.dsMonoPt(10, weight: .medium))
                .foregroundStyle(labelColor)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(softColor)
        .clipShape(RoundedRectangle(cornerRadius: t.r2, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: t.r2, style: .continuous)
                .strokeBorder(labelColor.opacity(0.3), lineWidth: 0.5)
        )
    }

    private var dotTone: DSStatusDotTone {
        switch health.status {
        case .healthy:    return .ok
        case .degraded:   return .warn
        case .unreachable: return .danger
        case .sleeping:   return .info
        }
    }

    private var labelColor: Color {
        switch health.status {
        case .healthy:    return t.ok
        case .degraded:   return t.warn
        case .unreachable: return t.danger
        case .sleeping:   return t.info
        }
    }

    private var softColor: Color {
        switch health.status {
        case .healthy:    return t.okSoft
        case .degraded:   return t.warnSoft
        case .unreachable: return t.dangerSoft
        case .sleeping:   return t.infoSoft
        }
    }
}
