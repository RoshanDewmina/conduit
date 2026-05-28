import SwiftUI

// Deterministic seeded 8×8 symmetric pixel-art avatar.
// Port of the JS seededRng / makePixelData approach from mother-duck-2.
// Same seed always produces the same avatar — stable across launches.
public struct PixelAvatar: View {
    let seed: String
    let size: CGFloat

    public init(seed: String, size: CGFloat = 32) {
        self.seed = seed
        self.size = size
    }

    public var body: some View {
        let data = makePixelData(seed: seed)
        let cols = 8
        let rows = 8
        let cellSize = size / CGFloat(cols)
        Canvas { ctx, _ in
            for row in 0..<rows {
                for col in 0..<cols {
                    let on = data[row * cols + col]
                    guard on else { continue }
                    let rect = CGRect(
                        x: CGFloat(col) * cellSize,
                        y: CGFloat(row) * cellSize,
                        width: cellSize,
                        height: cellSize
                    )
                    ctx.fill(Path(rect), with: .color(avatarColor(seed: seed)))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.2, style: .continuous))
    }

    // MARK: - Helpers

    private func makePixelData(seed: String) -> [Bool] {
        var rng = seededRng(seed: seed)
        var data = [Bool](repeating: false, count: 64)
        // Fill left half, mirror to right (symmetric design)
        for row in 0..<8 {
            for col in 0..<4 {
                let on = rng.next() > 0.35
                data[row * 8 + col] = on
                data[row * 8 + (7 - col)] = on   // mirror
            }
        }
        return data
    }

    private func avatarColor(seed: String) -> Color {
        let hue = Double(abs(seed.hashValue) % 360) / 360.0
        return Color(hue: hue, saturation: 0.62, brightness: 0.78)
    }
}

// MARK: - Simple seeded LCG RNG (matches JS Math.sin-based seeder semantics)

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
        // xorshift64
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return Double(state & 0x7fff_ffff_ffff) / Double(0x7fff_ffff_ffff)
    }
}

private func seededRng(seed: String) -> SeededRng { SeededRng(seed: seed) }
