import SwiftUI

// MARK: - Pro craft components
// The "refined-clean" polish lifted from the professional reference design:
// soft-tint initials avatars, left-bar quote callouts, A→B diff chips,
// inline accent links, and a warm-paper texture. Crisp 1px borders throughout
// (no hand-drawn strokes) so everything stays sharp in dark mode and at small sizes.

// MARK: Tone helpers (shared)

private func toneSoft(_ tone: DSChipTone, _ t: LancerTokens) -> Color {
    switch tone {
    case .accent:  return t.accentSoft
    case .ok:      return t.okSoft
    case .warn:    return t.warnSoft
    case .orange:  return LancerTokens.riskOrange.opacity(0.16)
    case .danger:  return t.dangerSoft
    case .info:    return t.infoSoft
    case .neutral: return t.neutralSoft
    }
}

private func toneInk(_ tone: DSChipTone, _ t: LancerTokens) -> Color {
    switch tone {
    case .accent:  return t.accentInk
    case .ok:      return t.ok
    case .warn:    return t.warn
    case .orange:  return LancerTokens.riskOrange
    case .danger:  return t.danger
    case .info:    return t.info
    case .neutral: return t.text2
    }
}

// MARK: - DSQuoteBlock
// Left accent bar + a mono context label, optional tag chips, optional body.
// (the orange-barred "GULF EV PRODUCTS / TABLE ENTRY / RELEVANCE" callout)

public struct DSQuoteBlock: View {
    let title: String
    let tags: [String]
    let message: String?
    let tone: DSChipTone

    @Environment(\.lancerTokens) private var t

    public init(title: String, tags: [String] = [], message: String? = nil, tone: DSChipTone = .accent) {
        self.title = title
        self.tags = tags
        self.message = message
        self.tone = tone
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if !title.isEmpty || !tags.isEmpty {
                HStack(spacing: 6) {
                    if !title.isEmpty {
                        Text(title.uppercased())
                            .font(.dsMonoPt(11, weight: .medium))
                            .tracking(11 * 0.07)
                            .foregroundStyle(t.text2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(tags, id: \.self) { tag in
                        DSChip(tag, variant: .mono, size: .sm)
                    }
                }
            }
            if let message {
                Text(message)
                    .font(.dsSansPt(14))
                    .foregroundStyle(t.text)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 11)
        // Bar is a leading overlay so it hugs the content height (never stretches).
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(toneInk(tone, t))
                .frame(width: 3)
        }
    }
}

// MARK: - DSDiffChips
// "PRIMARY → SECONDARY" — a neutral source chip, arrow, accent destination chip.

public struct DSDiffChips: View {
    let from: String
    let to: String
    let tone: DSChipTone

    @Environment(\.lancerTokens) private var t

    public init(from: String, to: String, tone: DSChipTone = .accent) {
        self.from = from
        self.to = to
        self.tone = tone
    }

    public var body: some View {
        HStack(spacing: 8) {
            DSChip(from, variant: .mono, size: .sm)
            DSIconView(.arrowRight, size: 13, color: t.text3)
            DSChip(to, tone: tone, variant: .monoInverse, size: .sm)
        }
    }
}

// MARK: - DSLink
// Inline underlined accent link (the "Gulf Oil Ltd." references).

public struct DSLink: View {
    let text: String
    let size: CGFloat
    let weight: Font.Weight
    let action: () -> Void

    @Environment(\.lancerTokens) private var t

    public init(_ text: String, size: CGFloat = 14, weight: Font.Weight = .medium, action: @escaping () -> Void = {}) {
        self.text = text
        self.size = size
        self.weight = weight
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(text)
                .font(.dsSansPt(size, weight: weight))
                .foregroundStyle(t.accent)
                .underline(true, color: t.accent.opacity(0.5))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - DSPaperBackground
// Very faint diagonal hatch over the page bg — the warm-paper feel from the
// reference margins. Apply with `.dsPaperBackground()`; safe behind any content.

public struct DSPaperTexture: View {
    let spacing: CGFloat
    let opacity: Double

    @Environment(\.lancerTokens) private var t

    public init(spacing: CGFloat = 8, opacity: Double = 0.022) {
        self.spacing = spacing
        self.opacity = opacity
    }

    public var body: some View {
        Canvas { ctx, size in
            let line = StrokeStyle(lineWidth: 0.5)
            let color = GraphicsContext.Shading.color(t.text.opacity(opacity))
            var x: CGFloat = -size.height
            while x < size.width {
                var p = Path()
                p.move(to: CGPoint(x: x, y: 0))
                p.addLine(to: CGPoint(x: x + size.height, y: size.height))
                ctx.stroke(p, with: color, style: line)
                x += spacing
            }
        }
        .allowsHitTesting(false)
    }
}

public extension View {
    /// Lays a faint diagonal-hatch paper texture behind the view, over `tokens.bg`.
    func dsPaperBackground() -> some View {
        background {
            ZStack {
                EnvironmentReaderBG()
                DSPaperTexture()
            }
            .ignoresSafeArea()
        }
    }
}

private struct EnvironmentReaderBG: View {
    @Environment(\.lancerTokens) private var t
    var body: some View { t.bg }
}
