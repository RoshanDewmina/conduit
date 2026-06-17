#if os(iOS)
import SwiftUI
import DesignSystem

public struct OnboardingPairedScreen: View {
    let hostName: String
    let agents: String
    @Environment(\.conduitTokens) private var t

    public init(hostName: String, agents: String) {
        self.hostName = hostName
        self.agents = agents
    }

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                Spacer(minLength: 40)

                ZStack {
                    Circle()
                        .fill(t.ok)
                        .frame(width: 74, height: 74)
                    Image(systemName: "checkmark")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(t.bg)
                }
                .shadow(color: t.ok.opacity(0.3), radius: 10, x: 0, y: 0)
                .shadow(color: t.ok.opacity(0.1), radius: 22, x: 0, y: 0)

                Text("Bridge paired")
                    .font(.system(size: 34, weight: .bold, design: .monospaced))
                    .foregroundStyle(t.text)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility3)
                    .padding(.horizontal, 18)
                    .padding(.top, 30)

                Text("Your phone and the bridge are connected. Approvals now route straight here.")
                    .font(.dsSansPt(13.5))
                    .foregroundStyle(t.text3)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 250)
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility3)

                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Circle()
                            .fill(t.ok)
                            .frame(width: 8, height: 8)
                        Text(hostName)
                            .font(.dsSansPt(13))
                            .foregroundStyle(t.text)
                        Spacer()
                        Text(agents)
                            .font(.dsMonoPt(11))
                            .foregroundStyle(t.text3)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .overlay(
                        Rectangle()
                            .strokeBorder(t.divider, lineWidth: 0.5)
                    )

                    HStack {
                        Image(systemName: "lock.shield")
                            .font(.system(size: 15, weight: .regular))
                            .foregroundColor(t.ok)
                        Text("End-to-end encrypted relay")
                            .font(.dsSansPt(13))
                            .foregroundStyle(t.text2)
                        Spacer()
                        Text("E2E")
                            .font(.dsMonoPt(10))
                            .foregroundColor(t.ok)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(t.okSoft)
                            .clipShape(RoundedRectangle(cornerRadius: 2))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .background(t.surface)
                .clipShape(RoundedRectangle(cornerRadius: t.r4))
                .overlay(
                    RoundedRectangle(cornerRadius: t.r4)
                        .strokeBorder(t.border, lineWidth: 1)
                )
                .padding(.horizontal, 18)
                .padding(.top, 26)
                .padding(.bottom, 24)

                Spacer()
            }
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

#endif
