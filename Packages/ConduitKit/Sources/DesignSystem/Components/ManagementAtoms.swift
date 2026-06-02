import SwiftUI

// MARK: - DSMetricTile
// Label + value pair used in VM detail screen. Square tile.

public struct DSMetricTile: View {
    let label: String
    let value: String
    let unit: String
    let tone: DSChipTone

    @Environment(\.conduitTokens) private var t

    public init(_ label: String, value: String, unit: String = "", tone: DSChipTone = .neutral) {
        self.label = label
        self.value = value
        self.unit = unit
        self.tone = tone
    }

    public var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.dsMonoPt(10))
                .foregroundStyle(t.text3)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            Text(value)
                .font(.dsSansPt(22, weight: .bold))
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if !unit.isEmpty {
                Text(unit)
                    .font(.dsMonoPt(10))
                    .foregroundStyle(t.text3)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
        .background(t.surface)
        .clipShape(Rectangle())
        .overlay(
            Rectangle()
                .strokeBorder(t.border, lineWidth: 0.5)
        )
    }

    private var valueColor: Color {
        switch tone {
        case .ok:      return t.ok
        case .warn:    return t.warn
        case .danger:  return t.danger
        case .accent:  return t.accent
        default:       return t.text
        }
    }
}

// MARK: - DSRiskRow
// Risk-policy row: dot + label + policy badge. Used in Agent policy screen.

public struct DSRiskRow: View {
    let level: Int    // 0=ok, 1=warn, 2=accent, 3=danger
    let label: String
    let policy: String

    @Environment(\.conduitTokens) private var t

    public init(level: Int, label: String, policy: String) {
        self.level = level
        self.label = label
        self.policy = policy
    }

    public var body: some View {
        HStack(spacing: 12) {
            DSStatusDot(tone: dotTone, size: 7)

            Text(label)
                .font(.dsMonoPt(13))
                .foregroundStyle(t.text)
                .frame(maxWidth: .infinity, alignment: .leading)

            DSChip(policy, tone: chipTone, variant: .soft)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private var dotTone: DSStatusDotTone {
        switch level {
        case 0:  return .ok
        case 1:  return .warn
        case 2:  return .accent
        default: return .danger
        }
    }

    private var chipTone: DSChipTone {
        switch level {
        case 0:  return .ok
        case 1:  return .warn
        case 2:  return .accent
        default: return .danger
        }
    }
}

// MARK: - DSStepNode
// Numbered circle + optional connector line below. Used in Workflow builder.

public struct DSStepNode: View {
    let number: Int
    let title: String
    let subtitle: String
    let isLast: Bool

    @Environment(\.conduitTokens) private var t

    public init(number: Int, title: String, subtitle: String, isLast: Bool = false) {
        self.number = number
        self.title = title
        self.subtitle = subtitle
        self.isLast = isLast
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                // Numbered circle
                ZStack {
                    Circle()
                        .strokeBorder(t.accent, lineWidth: 1.5)
                        .frame(width: 28, height: 28)
                    Text("\(number)")
                        .font(.dsMonoPt(12, weight: .medium))
                        .foregroundStyle(t.accent)
                }
                // Connector line below
                if !isLast {
                    Rectangle()
                        .fill(t.border)
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.dsMonoPt(13, weight: .semibold))
                    .foregroundStyle(t.text)
                Text(subtitle)
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text3)
            }
            .padding(.top, 4)

            Spacer()
        }
        .frame(minHeight: isLast ? 44 : 64, alignment: .top)
    }
}

// MARK: - DSHealthRow
// Health check row: status dot + label + status chip + timing. Used in Diagnostics.

public struct DSHealthRow: View {
    let label: String
    let status: String
    let timing: String
    let tone: DSStatusDotTone

    @Environment(\.conduitTokens) private var t

    public init(label: String, status: String, timing: String = "", tone: DSStatusDotTone = .ok) {
        self.label = label
        self.status = status
        self.timing = timing
        self.tone = tone
    }

    public var body: some View {
        HStack(spacing: 12) {
            DSStatusDot(tone: tone, size: 7)

            Text(label)
                .font(.dsMonoPt(13))
                .foregroundStyle(t.text)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !timing.isEmpty {
                Text(timing)
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text3)
            }

            DSChip(status, tone: chipTone, variant: .soft, size: .sm)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private var chipTone: DSChipTone {
        switch tone {
        case .ok:     return .ok
        case .warn:   return .warn
        case .danger: return .danger
        default:      return .neutral
        }
    }
}
