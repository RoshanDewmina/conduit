import SwiftUI

// MARK: - DSButton
// BLOCKS: the single filled primary action is electric blue (accent). PRIMARY and ACCENT are both
// the blue CTA; SECONDARY = 1px line border; DESTRUCTIVE = danger outline; GHOST = bare. Square corners.

public enum DSButtonVariant {
    case primary      // bg=text (dark), fg=bg (light) — the design's default CTA
    case accent       // bg=accent (warm orange), fg=white
    case secondary    // bg=surface, border=borderStrong, fg=text
    case ghost        // transparent, fg=text2, hover=surfaceSunk
    case destructive  // bg=surface, border=danger, fg=danger
}

public enum DSButtonSize { case sm, md, lg }

public struct DSButton: View {
    let title: String
    let icon: DSIcon?
    let systemImage: String?
    let trailingImage: String?
    let variant: DSButtonVariant
    let size: DSButtonSize
    let mono: Bool
    let kbd: String?
    let iconOnly: Bool
    let isLoading: Bool
    let fullWidth: Bool
    let action: () -> Void

    @Environment(\.conduitTokens) private var t
    @Environment(\.isEnabled) private var isEnabled

    // MARK: Full init
    public init(
        _ title: String,
        icon: DSIcon? = nil,
        systemImage: String? = nil,
        trailingImage: String? = nil,
        variant: DSButtonVariant = .primary,
        size: DSButtonSize = .md,
        mono: Bool = false,
        kbd: String? = nil,
        iconOnly: Bool = false,
        isLoading: Bool = false,
        fullWidth: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.systemImage = systemImage
        self.trailingImage = trailingImage
        self.variant = variant
        self.size = size
        self.mono = mono
        self.kbd = kbd
        self.iconOnly = iconOnly
        self.isLoading = isLoading
        self.fullWidth = fullWidth
        self.action = action
    }

    // NOTE: no separate "backward-compat" init — the full init above already accepts every
    // legacy call site (icon/trailingImage/mono/kbd/iconOnly all default), so a second
    // overload with the same effective signature would be ambiguous AND recurse into itself.

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isLoading {
                    ProgressView().scaleEffect(0.75)
                } else {
                    if let icon {
                        DSIconView(icon, size: iconSize, color: fgColor)
                    } else if let img = systemImage {
                        Image(systemName: img).font(.system(size: iconSize))
                    }
                }
                if !iconOnly || isLoading {
                    labelText
                }
                if let trailing = trailingImage {
                    Image(systemName: trailing).font(.system(size: iconSize))
                }
                if let k = kbd {
                    Text(k)
                        .font(.dsMonoPt(11))
                        .foregroundStyle(t.text3)
                }
            }
            .padding(.horizontal, iconOnly ? vPad : hPad)
            .padding(.vertical, vPad)
            .frame(minHeight: minH)
            .frame(minWidth: iconOnly ? minH : nil)
            .frame(maxWidth: fullWidth ? .infinity : nil)
        }
        .background(bgColor)
        .foregroundStyle(fgColor)
        .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: t.r3, style: .continuous)
                .strokeBorder(borderColor, lineWidth: hasBorder ? 1 : 0)
        )
        .opacity(isEnabled ? 1 : 0.45)
        .animation(.easeInOut(duration: 0.12), value: isEnabled)
        .disabled(isLoading)
    }

    // MARK: Label
    private var labelText: some View {
        Group {
            if mono {
                Text(title)
                    .font(.dsMonoPt(labelSize, weight: .medium))
                    .tracking(title.count > 0 ? labelSize * 0.08 : 0)
                    .textCase(.uppercase)
            } else {
                Text(title).font(.dsSansPt(labelSize, weight: .medium))
            }
        }
        // Buttons size to their label — never wrap onto a second line when
        // horizontal space is tight (e.g. side-by-side header buttons).
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }

    // MARK: Sizes
    private var hPad: CGFloat { switch size { case .sm: 10; case .md: 12; case .lg: 16 } }
    private var vPad: CGFloat { switch size { case .sm: 4; case .md: 6; case .lg: 10 } }
    private var minH: CGFloat { switch size { case .sm: 26; case .md: 32; case .lg: 40 } }
    private var labelSize: CGFloat { switch size { case .sm: 12; case .md: 13; case .lg: 14 } }
    private var iconSize: CGFloat { switch size { case .sm: 12; case .md: 13; case .lg: 14 } }

    // MARK: Colors
    private var bgColor: Color {
        switch variant {
        case .primary:     return t.accent         // BLOCKS: the single filled CTA is electric blue
        case .accent:      return t.accent
        case .secondary:   return t.surface
        case .ghost:       return .clear
        case .destructive: return t.surface
        }
    }

    private var fgColor: Color {
        switch variant {
        case .primary:     return t.accentFg       // white on blue
        case .accent:      return t.accentFg
        case .secondary:   return t.text
        case .ghost:       return t.text2
        case .destructive: return t.danger
        }
    }

    private var borderColor: Color {
        switch variant {
        case .secondary:   return t.borderStrong
        case .destructive: return t.danger
        default:           return .clear
        }
    }

    private var hasBorder: Bool { variant == .secondary || variant == .destructive }
}
