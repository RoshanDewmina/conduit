#if os(iOS)
import SwiftUI

/// Every named color a Cursor-style component needs, resolved per `CursorScheme`.
/// Self-contained visual language cloned from Cursor's mobile app, measured off
/// real screenshots. Intentionally does not import `DesignSystem` — this is a
/// separate look, distinct from Lancer's branded dark theme.
public struct CursorColors: Sendable {
    public let background: Color
    public let sheetBackground: Color
    public let composerBackground: Color
    public let iconButtonBackground: Color
    public let iconButtonBorder: Color
    public let primaryText: Color
    public let secondaryText: Color
    public let mutedText: Color
    public let hairline: Color
    public let statusDotActive: Color
    public let statusDotIdle: Color
    public let successGreen: Color
    public let dangerRed: Color

    /// Card/artifact background for Work Thread's plan/to-do/proof cards —
    /// distinguishable from the page background in both schemes.
    public let cardBackground: Color
    /// Stadium pill-button fill (`CursorPillButton` `.primary` style).
    public let pillPrimaryBackground: Color
    public let pillPrimaryText: Color
    /// Pill-button outline (`CursorPillButton` `.secondary` style).
    public let pillSecondaryBorder: Color
    public let pillSecondaryText: Color
    /// Background tint for added/removed lines in the unified diff view.
    public let diffAddedBackground: Color
    public let diffRemovedBackground: Color
    /// Risk-level colors for `CursorStatusBadge(.risk(...))`.
    public let riskLow: Color
    public let riskMedium: Color
    public let riskHigh: Color
    public let riskCritical: Color

    public init(
        background: Color,
        sheetBackground: Color,
        composerBackground: Color,
        iconButtonBackground: Color,
        iconButtonBorder: Color,
        primaryText: Color,
        secondaryText: Color,
        mutedText: Color,
        hairline: Color,
        statusDotActive: Color,
        statusDotIdle: Color,
        successGreen: Color,
        dangerRed: Color,
        cardBackground: Color,
        pillPrimaryBackground: Color,
        pillPrimaryText: Color,
        pillSecondaryBorder: Color,
        pillSecondaryText: Color,
        diffAddedBackground: Color,
        diffRemovedBackground: Color,
        riskLow: Color,
        riskMedium: Color,
        riskHigh: Color,
        riskCritical: Color
    ) {
        self.background = background
        self.sheetBackground = sheetBackground
        self.composerBackground = composerBackground
        self.iconButtonBackground = iconButtonBackground
        self.iconButtonBorder = iconButtonBorder
        self.primaryText = primaryText
        self.secondaryText = secondaryText
        self.mutedText = mutedText
        self.hairline = hairline
        self.statusDotActive = statusDotActive
        self.statusDotIdle = statusDotIdle
        self.successGreen = successGreen
        self.dangerRed = dangerRed
        self.cardBackground = cardBackground
        self.pillPrimaryBackground = pillPrimaryBackground
        self.pillPrimaryText = pillPrimaryText
        self.pillSecondaryBorder = pillSecondaryBorder
        self.pillSecondaryText = pillSecondaryText
        self.diffAddedBackground = diffAddedBackground
        self.diffRemovedBackground = diffRemovedBackground
        self.riskLow = riskLow
        self.riskMedium = riskMedium
        self.riskHigh = riskHigh
        self.riskCritical = riskCritical
    }

    /// Light look — Workspaces/Home lists (IMG_2352/2353), light bottom sheets
    /// (IMG_2354-2356), and the light PR/diff screen (IMG_2364-2367). Values for
    /// properties that existed on the old flat `CursorPalette` are unchanged.
    public static let light = CursorColors(
        background: Color(red: 0.961, green: 0.957, blue: 0.941),
        sheetBackground: .white,
        composerBackground: Color(red: 0.918, green: 0.914, blue: 0.898),
        iconButtonBackground: .white,
        iconButtonBorder: Color.black.opacity(0.08),
        primaryText: .black,
        secondaryText: Color(white: 0.55),
        mutedText: Color(white: 0.68),
        hairline: Color.black.opacity(0.08),
        statusDotActive: Color(red: 0.20, green: 0.47, blue: 0.93),
        statusDotIdle: Color(white: 0.82),
        successGreen: Color(red: 0.16, green: 0.55, blue: 0.30),
        dangerRed: Color(red: 0.75, green: 0.20, blue: 0.20),
        // "Resolve Conflicts to Merge" card in IMG_2364 reads as white-on-page-gray,
        // i.e. just the sheetBackground white — same value, named separately so
        // callers don't couple card styling to sheet styling.
        cardBackground: .white,
        // Stadium buttons aren't shown filled-dark in the light screenshots; derive
        // a dark-filled primary consistent with iOS default button conventions —
        // estimated, sanity-check visually.
        pillPrimaryBackground: Color.black.opacity(0.85),
        pillPrimaryText: .white,
        pillSecondaryBorder: Color.black.opacity(0.12),
        pillSecondaryText: .black,
        // Diff view in IMG_2365/2367 shows a pale green wash for added lines; no
        // removed-line example is visible in the captured frames, so the removed
        // tint is estimated as the red analog of the same wash strength.
        diffAddedBackground: Color(red: 0.902, green: 0.965, blue: 0.925),
        diffRemovedBackground: Color(red: 1.0, green: 0.925, blue: 0.925),
        riskLow: Color(red: 0.16, green: 0.55, blue: 0.30),
        riskMedium: Color(red: 0.80, green: 0.58, blue: 0.05),
        riskHigh: Color(red: 0.85, green: 0.45, blue: 0.05),
        riskCritical: Color(red: 0.75, green: 0.20, blue: 0.20)
    )

    /// Dark look — Work Thread transcript (IMG_2357-2361). Background/card/text
    /// values derived from inspecting those screenshots (not given explicitly in
    /// the spec) — sanity-check visually.
    public static let dark = CursorColors(
        background: Color(red: 0.075, green: 0.075, blue: 0.075),
        sheetBackground: Color(red: 0.11, green: 0.11, blue: 0.11),
        composerBackground: Color(red: 0.18, green: 0.18, blue: 0.18),
        iconButtonBackground: Color(red: 0.20, green: 0.20, blue: 0.20),
        iconButtonBorder: Color.white.opacity(0.10),
        primaryText: Color(white: 0.95),
        secondaryText: Color(white: 0.62),
        mutedText: Color(white: 0.48),
        hairline: Color.white.opacity(0.10),
        statusDotActive: Color(red: 0.20, green: 0.47, blue: 0.93),
        statusDotIdle: Color(white: 0.35),
        successGreen: Color(red: 0.30, green: 0.72, blue: 0.45),
        dangerRed: Color(red: 0.90, green: 0.40, blue: 0.40),
        // User-message bubble + plan/to-do cards read as a lighter charcoal than
        // the near-black page background (IMG_2360/2361).
        cardBackground: Color(red: 0.16, green: 0.16, blue: 0.16),
        pillPrimaryBackground: Color(red: 0.24, green: 0.24, blue: 0.24),
        pillPrimaryText: Color(white: 0.95),
        pillSecondaryBorder: Color.white.opacity(0.14),
        pillSecondaryText: Color(white: 0.90),
        diffAddedBackground: Color(red: 0.10, green: 0.22, blue: 0.15),
        diffRemovedBackground: Color(red: 0.28, green: 0.10, blue: 0.10),
        riskLow: Color(red: 0.30, green: 0.72, blue: 0.45),
        riskMedium: Color(red: 0.85, green: 0.65, blue: 0.15),
        riskHigh: Color(red: 0.90, green: 0.55, blue: 0.20),
        riskCritical: Color(red: 0.90, green: 0.40, blue: 0.40)
    )

    public static func resolve(_ scheme: CursorScheme) -> CursorColors {
        scheme == .light ? .light : .dark
    }
}
#endif
