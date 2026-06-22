#if os(iOS)
import SwiftUI
import DesignSystem

public struct OnboardingFirstRunScreen: View {
    public let cautionTitle: String
    public let onRunDemo: () -> Void
    @Environment(\.lancerTokens) private var t

    public init(
        cautionTitle: String,
        onRunDemo: @escaping () -> Void
    ) {
        self.cautionTitle = cautionTitle
        self.onRunDemo = onRunDemo
    }

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 40)

                ZStack {
                    Circle()
                        .fill(t.ok)
                        .frame(width: 56, height: 56)
                    Image(systemName: "checkmark")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(t.bg)
                }
                .shadow(color: t.ok.opacity(0.3), radius: 10, x: 0, y: 0)
                .shadow(color: t.ok.opacity(0.1), radius: 22, x: 0, y: 0)
                .padding(.horizontal, 18)
                .dynamicTypeSize(...DynamicTypeSize.accessibility3)

                Text("You're set")
                    .font(.system(size: 30, weight: .bold, design: .monospaced))
                    .foregroundStyle(t.text)
                    .padding(.horizontal, 18)
                    .padding(.top, 24)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility3)

                Text("Bridge paired and policy \(cautionTitle). Run a safe demo to watch an approval land on your phone.")
                    .font(.dsSansPt(14.5))
                    .foregroundStyle(t.text3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility3)

                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(t.ok)
                            .frame(width: 22, height: 22)
                        Text("Install & pair the bridge")
                            .font(.dsSansPt(13))
                            .foregroundStyle(t.text)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .overlay(
                        Rectangle()
                            .fill(t.divider)
                            .frame(height: 0.5),
                        alignment: .bottom
                    )

                    HStack(spacing: 12) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(t.ok)
                            .frame(width: 22, height: 22)
                        Text("Set how cautious it should be")
                            .font(.dsSansPt(13))
                            .foregroundStyle(t.text)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .overlay(
                        Rectangle()
                            .fill(t.divider)
                            .frame(height: 0.5),
                        alignment: .bottom
                    )

                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .stroke(t.text3.opacity(0.4), lineWidth: 1.5)
                                .frame(width: 22, height: 22)
                            Text("3")
                                .font(.dsMonoPt(12, weight: .bold))
                                .foregroundStyle(t.text3)
                        }
                        Text("Approve the first action it escalates")
                            .font(.dsSansPt(13))
                            .foregroundStyle(t.text)
                        Spacer()
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
                .padding(.top, 24)
                .dynamicTypeSize(...DynamicTypeSize.accessibility3)

                HStack(spacing: 12) {
                    PixelAvatar(seed: "claude-code", size: 20)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Claude Code · demo")
                            .font(.dsMonoPt(12, weight: .semibold))
                            .foregroundStyle(t.text)
                        Text("nothing will actually run")
                            .font(.dsSansPt(12))
                            .foregroundStyle(t.text3)
                    }

                    Spacer()

                    Text("SAMPLE")
                        .font(.dsMonoPt(9, weight: .bold))
                        .foregroundStyle(t.text3)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(t.border.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                .padding(14)
                .background(t.surface)
                .clipShape(RoundedRectangle(cornerRadius: t.r4))
                .overlay(
                    RoundedRectangle(cornerRadius: t.r4)
                        .strokeBorder(t.border, lineWidth: 1)
                )
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 24)
                .dynamicTypeSize(...DynamicTypeSize.accessibility3)

                Spacer()
            }
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
#endif
