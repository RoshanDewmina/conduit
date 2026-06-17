import SwiftUI

// MARK: - DSSpendHero — Fleet header spend hero
// Big today-spend figure with progress ring, brand spectrum vendor breakdown bar,
// and a metadata line showing run/concurrency/cap stats. Alert thresholds at 50/75/90%.

public struct DSSpendHero: View {
    public let todayUSD: Double
    public let vendors: [(label: String, amount: Double)]
    public let runs: Int
    public let concurrent: Int
    public let capUSD: Double?

    @Environment(\.conduitTokens) private var t

    public init(
        todayUSD: Double,
        vendors: [(label: String, amount: Double)],
        runs: Int,
        concurrent: Int,
        capUSD: Double? = nil
    ) {
        self.todayUSD = todayUSD
        self.vendors = vendors
        self.runs = runs
        self.concurrent = concurrent
        self.capUSD = capUSD
    }

    private var totalVendorAmount: Double {
        vendors.reduce(0) { $0 + $1.amount }
    }

    private var percentUsed: Double {
        guard let cap = capUSD, cap > 0 else { return 0 }
        return min(todayUSD / cap, 1.0)
    }

    private var thresholdColor: Color {
        if percentUsed >= 0.90 { return t.danger }
        if percentUsed >= 0.75 { return t.warn }
        if percentUsed >= 0.50 { return Color(.sRGB, red: 0.886, green: 0.400, blue: 0.173, opacity: 1) }
        return t.ok
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("today")
                    .font(.dsMonoPt(10, weight: .medium))
                    .tracking(1)
                    .textCase(.uppercase)
                    .foregroundStyle(t.text3)

                Text(String(format: "$%.2f", todayUSD))
                    .font(.dsSansPt(36, weight: .bold))
                    .foregroundStyle(t.text)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }

            Spacer()

            if capUSD != nil {
                ProgressRing(
                    fraction: percentUsed,
                    color: thresholdColor,
                    size: 64,
                    lineWidth: 5
                )
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)

        if !vendors.isEmpty {
            vendorBar
                .padding(.horizontal, 18)
                .padding(.bottom, 12)
        }

        HStack(spacing: 6) {
            metaTag("\(runs) runs")
            metaDot
            metaTag("\(concurrent) active")
            if let cap = capUSD {
                metaDot
                metaTag(String(format: "$%.2f cap", cap))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
    }

    // MARK: - Vendor Bar

    private var vendorBar: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let total = max(totalVendorAmount, 0.001)
            let spectra = ConduitTokens.spectrumColors
            let gap: CGFloat = 2

            HStack(spacing: gap) {
                ForEach(Array(vendors.enumerated()), id: \.offset) { idx, vendor in
                    let fraction = CGFloat(vendor.amount / total)
                    let segW = max(4, (w - gap * CGFloat(vendors.count - 1)) * fraction)
                    let color = spectra[idx % spectra.count]

                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(color)
                        .frame(width: segW, height: 6)
                }
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }

    // MARK: - Meta Line

    private func metaTag(_ text: String) -> some View {
        Text(text)
            .font(.dsMonoPt(10, weight: .medium))
            .foregroundStyle(t.text3)
    }

    private var metaDot: some View {
        Text("·")
            .font(.dsMonoPt(10))
            .foregroundStyle(t.text4)
    }
}

// MARK: - ProgressRing

public struct ProgressRing: View {
    let fraction: Double
    let color: Color
    let size: CGFloat
    let lineWidth: CGFloat

    @Environment(\.conduitTokens) private var t

    public init(fraction: Double, color: Color, size: CGFloat = 64, lineWidth: CGFloat = 5) {
        self.fraction = fraction
        self.color = color
        self.size = size
        self.lineWidth = lineWidth
    }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(t.border, lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: CGFloat(fraction))
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.6), value: fraction)

            Text(String(format: "%.0f", fraction * 100))
                .font(.dsMonoPt(12, weight: .bold))
                .foregroundStyle(color)
                .monospacedDigit()
        }
        .frame(width: size, height: size)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 0) {
        DSSpendHero(
            todayUSD: 4.94,
            vendors: [
                (label: "anthropic", amount: 2.80),
                (label: "openai", amount: 1.44),
                (label: "local", amount: 0.70),
            ],
            runs: 18,
            concurrent: 3,
            capUSD: 20.00
        )

        Divider()

        DSSpendHero(
            todayUSD: 16.20,
            vendors: [
                (label: "anthropic", amount: 12.00),
                (label: "openai", amount: 4.20),
            ],
            runs: 42,
            concurrent: 5,
            capUSD: 20.00
        )

        Divider()

        DSSpendHero(
            todayUSD: 0.00,
            vendors: [],
            runs: 0,
            concurrent: 0,
            capUSD: nil
        )
    }
    .environment(\.conduitTokens, .dark)
    .background(Color(.sRGB, red: 0.039, green: 0.043, blue: 0.051, opacity: 1))
}
