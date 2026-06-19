import SwiftUI

// MARK: - Font helpers
// Shell UI now uses system rounded typography for a calmer, chat-first feel.
// Monospace remains custom and explicit for paths, commands, code, and terminal output.

public extension Font {
    /// Chakra Petch at the given TextStyle — use for screen titles and large headers.
    static func dsDisplay(_ style: TextStyle, weight: Weight = .semibold) -> Font {
        .system(style, design: .rounded, weight: weight)
    }

    /// Chakra Petch at an exact point size, scaled relative to the nearest TextStyle.
    static func dsDisplayPt(_ size: CGFloat, weight: Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    /// DM Sans at the given TextStyle with weight.
    static func dsSans(_ style: TextStyle, weight: Weight = .regular) -> Font {
        .system(style, design: .rounded, weight: weight)
    }

    /// Fragment Mono at the given TextStyle with weight.
    static func dsMono(_ style: TextStyle, weight: Weight = .regular) -> Font {
        .custom(monoFaceName(weight), size: dsSize(style), relativeTo: style)
    }

    /// DM Sans at an exact point size, scaled relative to the nearest TextStyle.
    static func dsSansPt(_ size: CGFloat, weight: Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
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
    // Fira Code — the BLOCKS mono face (body, terminal, list rows, captions, code).
    switch weight {
    case .black, .heavy, .bold:          return "FiraCode-Bold"
    case .semibold:                      return "FiraCode-SemiBold"
    case .medium:                        return "FiraCode-Medium"
    default:                             return "FiraCode-Regular"
    }
}
