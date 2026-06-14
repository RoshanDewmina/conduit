import SwiftUI

// MARK: - DSSpendHero — Fleet header spend hero
// Big today-spend figure, brand spectrum vendor breakdown bar (R5.3),
// and a metadata line showing run/concurrency/cap stats.

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

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(String(format: "$%.2f", todayUSD))
                    .font(.dsMonoPt(30, weight: .bold))
                    .foregroundStyle(t.text)
                    .monospacedDigit()
            }

            if !vendors.isEmpty {
                vendorBar
            }

            metaLine
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

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

    private var metaLine: some View {
        HStack(spacing: 6) {
            Text("\(runs) runs")
                .font(.dsMonoPt(11))
                .foregroundStyle(t.text3)

            Text("·")
                .font(.dsMonoPt(11))
                .foregroundStyle(t.text3)

            Text("\(concurrent) concurrent")
                .font(.dsMonoPt(11))
                .foregroundStyle(t.text3)

            if let cap = capUSD {
                Text("·")
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text3)

                Text(String(format: "cap $%.2f", cap))
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text3)
            }

            Spacer(minLength: 0)
        }
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
