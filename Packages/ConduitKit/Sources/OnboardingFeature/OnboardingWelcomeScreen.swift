#if os(iOS)
import SwiftUI
import DesignSystem

public struct OnboardingWelcomeScreen: View {
    public init() {}

    @Environment(\.conduitTokens) private var t

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Rectangle()
                    .fill(t.divider)
                    .frame(height: 1)
                    .padding(.horizontal, 18)
                    .padding(.top, 24)

                Text("conduit")
                    .font(.dsMonoPt(11, weight: .bold))
                    .foregroundStyle(t.text3)
                    .kerning(2.5)
                    .textCase(.uppercase)
                    .padding(.horizontal, 18)
                    .padding(.top, 10)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility3)

                VStack(alignment: .leading, spacing: 2) {
                    Text("agents ask.")
                        .foregroundStyle(t.text)
                    Text("you approve.")
                        .foregroundStyle(t.text3)
                    Text("work resumes.")
                        .foregroundStyle(t.accent)
                }
                .font(.system(size: 47, weight: .bold, design: .monospaced))
                .lineSpacing(0)
                .tracking(-0.025)
                .padding(.horizontal, 18)
                .padding(.top, 40)
                .dynamicTypeSize(...DynamicTypeSize.accessibility3)

                Text("Your coding agents run on your own machine. Conduit taps you only when one needs a decision — and resumes the moment you choose.")
                    .font(.dsSansPt(14.5))
                    .foregroundStyle(t.text3)
                    .lineSpacing(1.65)
                    .frame(maxWidth: 300, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 18)
                    .padding(.top, 26)
                    .padding(.bottom, 24)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility3)
            }
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
#endif
