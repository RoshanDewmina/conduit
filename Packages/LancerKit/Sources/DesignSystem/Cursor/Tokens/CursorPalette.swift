#if os(iOS)
import SwiftUI

/// Every named color a Cursor-style component needs, resolved per `CursorScheme`.
/// Values extracted from the 2026-07-08 Cursor mobile reference set (light IMG_2408–2422,
/// dark IMG_2423–2431). Green/red diff semantics are identical in both schemes; orange
/// accent follows Lancer's `.accent` orange (charts, streaks) — not white/primary.
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

    /// Merge/pass/added-diff green — same hue in light and dark (spec).
    public let successGreen: Color
    /// Deletion/diff-removed red — same hue in light and dark (spec).
    public let dangerRed: Color

    /// Charts, streak dots, token bars — Lancer orange accent family.
    public let orangeAccent: Color

    /// Card/artifact background distinguishable from page background.
    public let cardBackground: Color
    /// User chat bubble fill (dark gray on dark theme).
    public let userBubbleBackground: Color

    /// Stadium pill-button fill (`CursorPillButton` `.primary` style).
    public let pillPrimaryBackground: Color
    public let pillPrimaryText: Color
    /// Pill-button outline (`CursorPillButton` `.secondary` style).
    public let pillSecondaryBorder: Color
    public let pillSecondaryText: Color
    /// Full-width merge CTA (`CursorPillButton` `.success` style).
    public let mergeButtonBackground: Color
    public let mergeButtonText: Color

    /// Desaturated purple/indigo "Merged" badge on dark (and light analog).
    public let mergedBadgeBackground: Color
    public let mergedBadgeText: Color
    /// Green-tinted "Open" PR badge.
    public let openBadgeBackground: Color
    public let openBadgeText: Color

    /// Background tint for added/removed lines in the unified diff view.
    public let diffAddedBackground: Color
    public let diffRemovedBackground: Color
    /// Very dark green-tinted code block background (dark diff viewer).
    public let codeBlockBackground: Color

    /// Risk-level colors for `CursorStatusBadge(.risk(...))`.
    public let riskLow: Color
    public let riskMedium: Color
    public let riskHigh: Color
    public let riskCritical: Color

    /// Dimmed scrim behind bottom sheets.
    public let sheetScrim: Color

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
        orangeAccent: Color,
        cardBackground: Color,
        userBubbleBackground: Color,
        pillPrimaryBackground: Color,
        pillPrimaryText: Color,
        pillSecondaryBorder: Color,
        pillSecondaryText: Color,
        mergeButtonBackground: Color,
        mergeButtonText: Color,
        mergedBadgeBackground: Color,
        mergedBadgeText: Color,
        openBadgeBackground: Color,
        openBadgeText: Color,
        diffAddedBackground: Color,
        diffRemovedBackground: Color,
        codeBlockBackground: Color,
        riskLow: Color,
        riskMedium: Color,
        riskHigh: Color,
        riskCritical: Color,
        sheetScrim: Color
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
        self.orangeAccent = orangeAccent
        self.cardBackground = cardBackground
        self.userBubbleBackground = userBubbleBackground
        self.pillPrimaryBackground = pillPrimaryBackground
        self.pillPrimaryText = pillPrimaryText
        self.pillSecondaryBorder = pillSecondaryBorder
        self.pillSecondaryText = pillSecondaryText
        self.mergeButtonBackground = mergeButtonBackground
        self.mergeButtonText = mergeButtonText
        self.mergedBadgeBackground = mergedBadgeBackground
        self.mergedBadgeText = mergedBadgeText
        self.openBadgeBackground = openBadgeBackground
        self.openBadgeText = openBadgeText
        self.diffAddedBackground = diffAddedBackground
        self.diffRemovedBackground = diffRemovedBackground
        self.codeBlockBackground = codeBlockBackground
        self.riskLow = riskLow
        self.riskMedium = riskMedium
        self.riskHigh = riskHigh
        self.riskCritical = riskCritical
        self.sheetScrim = sheetScrim
    }

    // MARK: - Shared semantics (identical in light + dark per spec)

    private static let diffGreen = Color(red: 0.157, green: 0.549, blue: 0.302)   // ≈ #288C4D
    private static let diffRed = Color(red: 0.749, green: 0.204, blue: 0.204)       // ≈ #BF3434
    private static let chartOrange = Color(red: 0.753, green: 0.357, blue: 0.212)  // Lancer light .accent #c05b36

    /// Light — near-white canvas, dark ink, hairline separators (IMG_2408–2422).
    public static let light = CursorColors(
        background: Color(red: 0.976, green: 0.976, blue: 0.969),          // #F9F9F7
        sheetBackground: .white,
        composerBackground: Color(red: 0.945, green: 0.945, blue: 0.933),  // #F1F1EE
        iconButtonBackground: .white,
        iconButtonBorder: Color.black.opacity(0.08),
        primaryText: Color(red: 0.102, green: 0.102, blue: 0.102),         // #1A1A1A
        secondaryText: Color(white: 0.45),
        mutedText: Color(white: 0.62),
        hairline: Color.black.opacity(0.08),
        statusDotActive: Color(red: 0.20, green: 0.47, blue: 0.93),
        statusDotIdle: Color(white: 0.82),
        successGreen: diffGreen,
        dangerRed: diffRed,
        orangeAccent: chartOrange,
        cardBackground: .white,
        userBubbleBackground: Color(red: 0.925, green: 0.925, blue: 0.910), // #ECECE8
        pillPrimaryBackground: Color.black.opacity(0.88),
        pillPrimaryText: .white,
        pillSecondaryBorder: Color.black.opacity(0.12),
        pillSecondaryText: Color(red: 0.102, green: 0.102, blue: 0.102),
        mergeButtonBackground: diffGreen,
        mergeButtonText: .white,
        mergedBadgeBackground: Color(red: 0.90, green: 0.88, blue: 0.96), // soft indigo wash
        mergedBadgeText: Color(red: 0.38, green: 0.32, blue: 0.58),
        openBadgeBackground: Color(red: 0.90, green: 0.96, blue: 0.92),
        openBadgeText: diffGreen,
        diffAddedBackground: Color(red: 0.902, green: 0.965, blue: 0.925),
        diffRemovedBackground: Color(red: 1.0, green: 0.925, blue: 0.925),
        codeBlockBackground: Color(red: 0.965, green: 0.980, blue: 0.969),
        riskLow: diffGreen,
        riskMedium: Color(red: 0.80, green: 0.58, blue: 0.05),
        riskHigh: Color(red: 0.85, green: 0.45, blue: 0.05),
        riskCritical: diffRed,
        sheetScrim: Color.black.opacity(0.35)
    )

    /// Dark — near-black canvas (#0A–#0D), elevated #1C–#26 (IMG_2423–2431).
    public static let dark = CursorColors(
        background: Color(red: 0.043, green: 0.043, blue: 0.047),           // #0B0B0C
        sheetBackground: Color(red: 0.110, green: 0.110, blue: 0.118),     // #1C1C1E
        composerBackground: Color(red: 0.133, green: 0.133, blue: 0.137), // #222224
        iconButtonBackground: Color(red: 0.149, green: 0.149, blue: 0.153), // #262628
        iconButtonBorder: Color.white.opacity(0.10),
        primaryText: Color(white: 0.95),
        secondaryText: Color(white: 0.40),
        mutedText: Color(white: 0.48),
        hairline: Color.white.opacity(0.10),
        statusDotActive: Color(red: 0.20, green: 0.47, blue: 0.93),
        statusDotIdle: Color(white: 0.35),
        successGreen: diffGreen,
        dangerRed: diffRed,
        orangeAccent: Color(red: 0.894, green: 0.482, blue: 0.341),        // Lancer dark .accent #e47b57
        cardBackground: Color(red: 0.149, green: 0.149, blue: 0.157),      // #262628
        userBubbleBackground: Color(red: 0.180, green: 0.180, blue: 0.188), // #2E2E30
        pillPrimaryBackground: Color(red: 0.235, green: 0.235, blue: 0.243),
        pillPrimaryText: Color(white: 0.95),
        pillSecondaryBorder: Color.white.opacity(0.14),
        pillSecondaryText: Color(white: 0.90),
        mergeButtonBackground: diffGreen,
        mergeButtonText: .white,
        mergedBadgeBackground: Color(red: 0.22, green: 0.20, blue: 0.32),
        mergedBadgeText: Color(red: 0.72, green: 0.68, blue: 0.90),
        openBadgeBackground: Color(red: 0.10, green: 0.22, blue: 0.15),
        openBadgeText: diffGreen,
        diffAddedBackground: Color(red: 0.10, green: 0.22, blue: 0.15),
        diffRemovedBackground: Color(red: 0.28, green: 0.10, blue: 0.10),
        codeBlockBackground: Color(red: 0.06, green: 0.10, blue: 0.08),
        riskLow: diffGreen,
        riskMedium: Color(red: 0.85, green: 0.65, blue: 0.15),
        riskHigh: Color(red: 0.90, green: 0.55, blue: 0.20),
        riskCritical: diffRed,
        sheetScrim: Color.black.opacity(0.55)
    )

    public static func resolve(_ scheme: CursorScheme) -> CursorColors {
        scheme == .light ? .light : .dark
    }
}
#endif
