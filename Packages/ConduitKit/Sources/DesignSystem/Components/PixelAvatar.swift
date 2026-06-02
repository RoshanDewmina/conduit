import SwiftUI

// MARK: - PixelAvatar
// Rebuilt as two-tone seeded symmetric 8×8 grid.
// Design: low-sat palette — hue from seed, sat 14-26%, bg lightness 20-26%, fg lightness 60-78%.
// Symmetric: fills left 4 columns, mirrors to right 4.

public struct PixelAvatar: View {
    let seed: String
    let size: CGFloat
    let rounded: Bool

    public init(seed: String, size: CGFloat = 32, rounded: Bool = true) {
        self.seed = seed
        self.size = size
        self.rounded = rounded
    }

    public var body: some View {
        let (pixels, bgColor, fgColor) = makePixelData(seed: seed)
        let cellSize = size / 8

        Canvas { ctx, _ in
            // Fill entire canvas with bg
            ctx.fill(Path(CGRect(origin: .zero, size: CGSize(width: size, height: size))),
                     with: .color(bgColor))
            // Draw fg cells
            for row in 0..<8 {
                for col in 0..<8 {
                    guard pixels[row * 8 + col] else { continue }
                    let rect = CGRect(x: CGFloat(col) * cellSize, y: CGFloat(row) * cellSize,
                                     width: cellSize, height: cellSize)
                    ctx.fill(Path(rect), with: .color(fgColor))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(rounded
            ? AnyShape(RoundedRectangle(cornerRadius: size * 0.2, style: .continuous))
            : AnyShape(Rectangle()))
        // Decorative pixel art — VoiceOver should skip this and read the host
        // name from the containing row element instead.
        .accessibilityHidden(true)
    }

    private func makePixelData(seed: String) -> (pixels: [Bool], bg: Color, fg: Color) {
        var rng = SeededRng(seed: seed)

        // Derive hue from seed hash (0–360°)
        let hash = seed.unicodeScalars.reduce(0) { ($0 &* 31) &+ Int($1.value) }
        let hue = Double(abs(hash) % 360) / 360.0

        // Low-sat palette (design spec)
        let bgSat = 0.14 + rng.next() * 0.12  // 14–26%
        let bgLight = 0.20 + rng.next() * 0.06 // 20–26%
        let fgLight = 0.60 + rng.next() * 0.18 // 60–78%
        let fgSat = bgSat * 0.8

        let bgColor = Color(hue: hue, saturation: bgSat, brightness: bgLight)
        let fgColor = Color(hue: hue, saturation: fgSat, brightness: fgLight)

        // Symmetric fill: left 4 columns, mirror to right
        var pixels = [Bool](repeating: false, count: 64)
        for row in 0..<8 {
            for col in 0..<4 {
                let on = rng.next() > 0.38
                pixels[row * 8 + col] = on
                pixels[row * 8 + (7 - col)] = on
            }
        }

        return (pixels, bgColor, fgColor)
    }
}

// MARK: - Seeded LCG RNG (stable, deterministic)

private struct SeededRng {
    private var state: UInt64

    init(seed: String) {
        var h: UInt64 = 0xdeadbeef
        for c in seed.unicodeScalars {
            h = h &* 1664525 &+ UInt64(c.value) &+ 1013904223
        }
        state = h
    }

    mutating func next() -> Double {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return Double(state & 0x7fff_ffff_ffff) / Double(0x7fff_ffff_ffff)
    }
}

// Type-erased shape for clipShape
private struct AnyShape: Shape, @unchecked Sendable {
    private let pathBuilder: (CGRect) -> Path
    init<S: Shape>(_ shape: S) { pathBuilder = shape.path(in:) }
    func path(in rect: CGRect) -> Path { pathBuilder(rect) }
}
