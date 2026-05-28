import SwiftUI

public enum DSButtonVariant { case primary, secondary, ghost, destructive }
public enum DSButtonSize    { case sm, md }

public struct DSButton: View {
    let title: String
    let systemImage: String?
    let variant: DSButtonVariant
    let size: DSButtonSize
    let isLoading: Bool
    let action: () -> Void

    @Environment(\.conduitTokens) private var t

    public init(
        _ title: String,
        systemImage: String? = nil,
        variant: DSButtonVariant = .primary,
        size: DSButtonSize = .md,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.variant = variant
        self.size = size
        self.isLoading = isLoading
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isLoading {
                    ProgressView().scaleEffect(0.7)
                } else if let img = systemImage {
                    Image(systemName: img).font(iconFont)
                }
                Text(title).font(labelFont).fontWeight(.medium)
            }
            .padding(.horizontal, hPad)
            .padding(.vertical, vPad)
            .frame(minHeight: minH)
        }
        .background(bg)
        .foregroundStyle(fg)
        .clipShape(RoundedRectangle(cornerRadius: t.radiusMD, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: t.radiusMD, style: .continuous)
                .strokeBorder(border, lineWidth: variant == .secondary ? 1 : 0)
        )
        .disabled(isLoading)
    }

    // MARK: Computed style values

    private var hPad: CGFloat { size == .sm ? 10 : 14 }
    private var vPad: CGFloat { size == .sm ? 6  : 9  }
    private var minH: CGFloat { size == .sm ? 30 : 38 }
    private var labelFont: Font { size == .sm ? .caption : .subheadline }
    private var iconFont:  Font { size == .sm ? .caption : .subheadline }

    private var bg: Color {
        switch variant {
        case .primary:     return t.accent
        case .secondary:   return t.surf2
        case .ghost:       return .clear
        case .destructive: return t.danger
        }
    }

    private var fg: Color {
        switch variant {
        case .primary, .destructive: return .white
        case .secondary, .ghost:     return t.text1
        }
    }

    private var border: Color {
        variant == .secondary ? t.surf3 : .clear
    }
}
