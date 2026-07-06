#if os(iOS)
import SwiftUI

public struct CursorConnectionBanner: View {
    @Environment(\.cursorScheme) private var cursorScheme

    public let phase: CursorShellLiveBridge.ConnectionPhase
    public let onPair: (() -> Void)?

    public init(phase: CursorShellLiveBridge.ConnectionPhase, onPair: (() -> Void)? = nil) {
        self.phase = phase
        self.onPair = onPair
    }

    public var body: some View {
        let colors = CursorColors.resolve(cursorScheme)
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(iconColor(colors: colors))
            Text(message)
                .font(CursorType.rowSecondary)
                .foregroundColor(colors.primaryText)
            Spacer()
            if phase == .needsPairing, let onPair {
                Button(action: onPair) {
                    Text("Pair")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(colors.statusDotActive)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, CursorMetrics.rowHorizontalPadding)
        .padding(.vertical, 8)
        .background(bannerBackground(colors: colors))
    }

    private var message: String {
        switch phase {
        case .connected: return ""
        case .offline: return "Can't reach your machine — check relay or Wi\u{2011}Fi"
        case .reconnecting: return "Reconnecting\u{2026}"
        case .needsPairing: return "Pair a machine to dispatch"
        }
    }

    private var iconName: String {
        switch phase {
        case .connected: return "checkmark.circle"
        case .offline: return "wifi.slash"
        case .reconnecting: return "arrow.clockwise"
        case .needsPairing: return "cable.connector"
        }
    }

    private func iconColor(colors: CursorColors) -> Color {
        switch phase {
        case .connected: return colors.successGreen
        case .offline: return colors.dangerRed
        case .reconnecting: return colors.riskMedium
        case .needsPairing: return colors.statusDotActive
        }
    }

    private func bannerBackground(colors: CursorColors) -> Color {
        switch phase {
        case .connected: return .clear
        case .offline: return colors.dangerRed.opacity(0.08)
        case .reconnecting: return colors.riskMedium.opacity(0.08)
        case .needsPairing: return colors.statusDotActive.opacity(0.08)
        }
    }
}
#endif
