import SwiftUI

// MARK: - Font helpers
// Shell UI uses a compact brand face, a readable UI face, and explicit mono.

public extension Font {
    /// Playwrite US Modern is reserved for short brand/display moments.
    static func dsDisplay(_ style: TextStyle, weight: Weight = .semibold) -> Font {
        .custom(displayFaceName(weight), size: dsSize(style), relativeTo: style)
    }

    /// Playwrite US Modern at an exact point size.
    static func dsDisplayPt(_ size: CGFloat, weight: Weight = .semibold) -> Font {
        .custom(displayFaceName(weight), size: size, relativeTo: nearestTextStyle(size))
    }

    /// Instrument Sans at the given TextStyle with weight.
    static func dsSans(_ style: TextStyle, weight: Weight = .regular) -> Font {
        .custom(sansFaceName(weight), size: dsSize(style), relativeTo: style)
    }

    /// Fragment Mono at the given TextStyle with weight.
    static func dsMono(_ style: TextStyle, weight: Weight = .regular) -> Font {
        .custom(monoFaceName(weight), size: dsSize(style), relativeTo: style)
    }

    /// Instrument Sans at an exact point size.
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
    // BLOCKS scale: display 48 / title 34 / heading 22 / body 16 / callout 14 / caption 12 / micro 10.
    switch style {
    case .largeTitle:   return 34
    case .title:        return 28
    case .title2:       return 24
    case .title3:       return 22
    case .headline:     return 18
    case .body:         return 16
    case .callout:      return 14
    case .subheadline:  return 14
    case .footnote:     return 13
    case .caption:      return 12
    case .caption2:     return 11
    @unknown default:   return 14
    }
}

// MARK: - Face name helpers

private func monoFaceName(_ weight: Font.Weight) -> String {
    switch weight {
    case .black, .heavy, .bold:          return "JetBrainsMono-Bold"
    case .semibold, .medium:             return "JetBrainsMono-Medium"
    default:                             return "JetBrainsMono-Regular"
    }
}

private func sansFaceName(_ weight: Font.Weight) -> String {
    switch weight {
    case .black, .heavy, .bold:          return "InstrumentSans-Bold"
    case .semibold:                      return "InstrumentSans-SemiBold"
    case .medium:                        return "InstrumentSans-Medium"
    default:                             return "InstrumentSans-Regular"
    }
}

private func displayFaceName(_ weight: Font.Weight) -> String {
    // Display headlines use Instrument Sans (bold) — distinct from body via
    // size/weight, no script/cursive face. Was PlaywriteUSModern; swapped out
    // per design feedback. Re-point here to change the display face globally.
    switch weight {
    case .black, .heavy, .bold: return "InstrumentSans-Bold"
    case .semibold:             return "InstrumentSans-SemiBold"
    default:                    return "InstrumentSans-Medium"
    }
}
