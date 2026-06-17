#if os(iOS)
import SwiftUI
import DesignSystem
import SSHTransport

public struct OnboardingScanScreen: View {
    public let onScan: (String) -> Void
    public let onUnavailable: (String) -> Void
    public let onEnterCodeInstead: () -> Void
    @Environment(\.conduitTokens) private var t
    @State private var pulse = false

    public init(
        onScan: @escaping (String) -> Void,
        onUnavailable: @escaping (String) -> Void,
        onEnterCodeInstead: @escaping () -> Void
    ) {
        self.onScan = onScan
        self.onUnavailable = onUnavailable
        self.onEnterCodeInstead = onEnterCodeInstead
    }

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 32)

                Text("SCAN TO PAIR")
                    .font(.dsMonoPt(10))
                    .tracking(10 * 0.12)
                    .foregroundStyle(t.text3)
                    .padding(.horizontal, 18)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility3)

                ZStack {
                    QRScannerView(
                        onScan: onScan,
                        onUnavailable: onUnavailable
                    )
                    .frame(width: 220, height: 220)
                    .clipped()

                    ViewfinderBrackets(color: t.accent)
                        .frame(width: 220, height: 220)
                        .allowsHitTesting(false)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 18)
                .padding(.top, 20)

                Text("Point at the QR code printed in your terminal")
                    .font(.dsSansPt(13.5))
                    .foregroundStyle(t.text3)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility3)

                HStack(spacing: 8) {
                    Circle()
                        .fill(t.accent)
                        .frame(width: 8, height: 8)
                        .opacity(pulse ? 1 : 0.3)
                        .animation(
                            .easeInOut(duration: 1).repeatForever(autoreverses: true),
                            value: pulse
                        )
                    Text("searching…")
                        .font(.dsMonoPt(12))
                        .foregroundStyle(t.text2)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 24)
            }
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dynamicTypeSize(...DynamicTypeSize.accessibility3)
        }
        .onAppear { pulse = true }
    }
}

private struct ViewfinderBrackets: View {
    let color: Color
    let length: CGFloat = 20
    let thickness: CGFloat = 3

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            Path { path in
                path.move(to: CGPoint(x: 0, y: length))
                path.addLine(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: length, y: 0))

                path.move(to: CGPoint(x: w - length, y: 0))
                path.addLine(to: CGPoint(x: w, y: 0))
                path.addLine(to: CGPoint(x: w, y: length))

                path.move(to: CGPoint(x: w, y: h - length))
                path.addLine(to: CGPoint(x: w, y: h))
                path.addLine(to: CGPoint(x: w - length, y: h))

                path.move(to: CGPoint(x: length, y: h))
                path.addLine(to: CGPoint(x: 0, y: h))
                path.addLine(to: CGPoint(x: 0, y: h - length))
            }
            .stroke(color, lineWidth: thickness)
        }
    }
}
#endif
