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
    case quiet        // demoted secondary: no fill, 0.5px hairline, fg=text2; h=40 (R3.4)
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
            .frame(minHeight: visualMinH)
            .frame(minWidth: iconOnly ? visualMinH : nil)
            .frame(maxWidth: fullWidth ? .infinity : nil)
        }
        .background(effectiveBgColor)
        .foregroundStyle(effectiveFgColor)
        .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: t.r3, style: .continuous)
                .strokeBorder(borderColor, lineWidth: hasBorder ? borderLineWidth : 0)
        )
        .conduitGlassChrome(cornerRadius: t.r3, interactive: true)
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
        // Filled CTAs get a neutral "clearly disabled" treatment (sunk surface +
        // muted text) rather than a 45%-opacity accent that reads as half-tappable.
        // Non-filled variants keep the simple opacity fade.
        .opacity(isEnabled || isFilledVariant ? 1 : 0.45)
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
    private var hPad: CGFloat {
        guard variant != .quiet else { return 8 }
        switch size { case .sm: return 10; case .md: return 12; case .lg: return 16 }
    }
    private var vPad: CGFloat {
        guard variant != .quiet else { return 4 }
        switch size { case .sm: return 4; case .md: return 6; case .lg: return 10 }
    }
    private var visualMinH: CGFloat {
        guard variant != .quiet else { return 40 }
        switch size { case .sm: return 26; case .md: return 36; case .lg: return 44 }
    }
    private var labelSize: CGFloat { switch size { case .sm: 12; case .md: 13; case .lg: 14 } }
    private var iconSize: CGFloat { switch size { case .sm: 12; case .md: 13; case .lg: 14 } }

    // MARK: Colors
    private var isFilledVariant: Bool {
        switch variant { case .primary, .accent: return true; default: return false }
    }

    /// Filled CTAs render a neutral sunk surface when disabled (legible "off"),
    /// instead of a faded accent that looks half-enabled.
    private var effectiveBgColor: Color {
        (!isEnabled && isFilledVariant) ? t.surfaceSunk : bgColor
    }

    private var effectiveFgColor: Color {
        (!isEnabled && isFilledVariant) ? t.text4 : fgColor
    }

    private var bgColor: Color {
        switch variant {
        case .primary:     return t.accent
        case .accent:      return t.accent
        case .secondary:   return t.surface
        case .ghost:       return .clear
        case .destructive: return t.surface
        case .quiet:       return .clear
        }
    }

    private var fgColor: Color {
        switch variant {
        case .primary:     return t.accentFg
        case .accent:      return t.accentFg
        case .secondary:   return t.text
        case .ghost:       return t.text2
        case .destructive: return t.danger
        case .quiet:       return t.text2
        }
    }

    private var borderColor: Color {
        switch variant {
        case .secondary:   return t.borderStrong
        case .destructive: return t.danger
        case .quiet:       return t.border
        default:           return .clear
        }
    }

    private var hasBorder: Bool {
        switch variant {
        case .secondary, .destructive: return true
        case .quiet:                   return true
        default:                       return false
        }
    }

    private var borderLineWidth: CGFloat { variant == .quiet ? 0.5 : 1 }
}
