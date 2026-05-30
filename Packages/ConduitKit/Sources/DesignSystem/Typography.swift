import SwiftUI

// MARK: - Font helpers
// Uses Bricolage Grotesque (display/titles), DM Sans (UI/body), Fragment Mono (code/terminal/labels).
// Custom fonts don't respond to .weight(), so weight is mapped to face name.

public extension Font {
    /// Bricolage Grotesque at the given TextStyle — use for screen titles and large headers.
    static func dsDisplay(_ style: TextStyle, weight: Weight = .semibold) -> Font {
        .custom(displayFaceName(weight), size: dsSize(style), relativeTo: style)
    }

    /// Bricolage Grotesque at an exact point size, scaled relative to the nearest TextStyle.
    static func dsDisplayPt(_ size: CGFloat, weight: Weight = .semibold) -> Font {
        .custom(displayFaceName(weight), size: size, relativeTo: nearestTextStyle(size))
    }

    /// DM Sans at the given TextStyle with weight.
    static func dsSans(_ style: TextStyle, weight: Weight = .regular) -> Font {
        .custom(sansFaceName(weight), size: dsSize(style), relativeTo: style)
    }

    /// Fragment Mono at the given TextStyle with weight.
    static func dsMono(_ style: TextStyle, weight: Weight = .regular) -> Font {
        .custom(monoFaceName(weight), size: dsSize(style), relativeTo: style)
    }

    /// DM Sans at an exact point size, scaled relative to the nearest TextStyle.
    static func dsSansPt(_ size: CGFloat, weight: Weight = .regular) -> Font {
        .custom(sansFaceName(weight), size: size, relativeTo: nearestTextStyle(size))
    }

    /// Fragment Mono at an exact point size, scaled relative to the nearest TextStyle.
    static func dsMonoPt(_ size: CGFloat, weight: Weight = .regular) -> Font {
        .custom(monoFaceName(weight), size: size, relativeTo: nearestTextStyle(size))
    }
}

// MARK: - Caps View modifier (uppercase + letter-spacing used by section labels)
public struct DSCapsStyle: ViewModifier {
    let size: CGFloat
    // Use @ScaledMetric so letter-spacing grows with Dynamic Type.
    @ScaledMetric private var scaledTracking: CGFloat

    public init(size: CGFloat, tracking: CGFloat) {
        self.size = size
        self._scaledTracking = ScaledMetric(wrappedValue: tracking)
    }

    public func body(content: Content) -> some View {
        content
            .font(.dsMonoPt(size))
            .tracking(scaledTracking)
            .textCase(.uppercase)
    }
}

public extension View {
    func dsCapsStyle(size: CGFloat = 11, trackingMultiplier: CGFloat = 0.08) -> some View {
        modifier(DSCapsStyle(size: size, tracking: size * trackingMultiplier))
    }
}

// MARK: - Point size → TextStyle mapping (for relativeTo: in Pt helpers)
// Maps a raw point size to the nearest system TextStyle so .custom(face, size:, relativeTo:)
// scales the font in proportion to the user's preferred content size.
private func nearestTextStyle(_ size: CGFloat) -> Font.TextStyle {
    switch size {
    case ..<12: return .caption2
    case ..<13: return .caption
    case ..<14: return .footnote
    case ..<15: return .callout
    case ..<16: return .body
    case ..<17: return .headline
    case ..<19: return .title3
    case ..<21: return .title2
    case ..<25: return .title
    default:    return .largeTitle
    }
}

// MARK: - Design type scale (from tokens.css --fz-* values)
private func dsSize(_ style: Font.TextStyle) -> CGFloat {
    switch style {
    case .largeTitle:   return 30
    case .title:        return 24
    case .title2:       return 20
    case .title3:       return 18
    case .headline:     return 16
    case .body:         return 15
    case .callout:      return 14
    case .subheadline:  return 14
    case .footnote:     return 13
    case .caption:      return 12
    case .caption2:     return 11
    @unknown default:   return 14
    }
}

// MARK: - Face name helpers

private func displayFaceName(_ weight: Font.Weight) -> String {
    switch weight {
    case .black:                         return "BricolageGrotesque-ExtraBold"
    case .heavy, .bold:                  return "BricolageGrotesque-Bold"
    case .semibold:                      return "BricolageGrotesque-SemiBold"
    case .medium:                        return "BricolageGrotesque-Medium"
    default:                             return "BricolageGrotesque-Regular"
    }
}

private func sansFaceName(_ weight: Font.Weight) -> String {
    switch weight {
    case .bold, .heavy, .black:          return "DMSans-Bold"
    case .semibold:                      return "DMSans-SemiBold"
    case .medium:                        return "DMSans-Medium"
    default:                             return "DMSans-Regular"
    }
}

private func monoFaceName(_ weight: Font.Weight) -> String {
    // Fragment Mono ships Regular only; all weights map to it.
    return "FragmentMono-Regular"
}
