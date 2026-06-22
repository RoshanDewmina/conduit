#if os(iOS)
import SwiftUI
import DesignSystem

public struct OnboardingCautionScreen: View {
    @Binding var level: OnboardingCautionLevel
    @Environment(\.lancerTokens) private var t

    public init(level: Binding<OnboardingCautionLevel>) {
        self._level = level
    }

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 32)

                Text("How cautious?")
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .foregroundStyle(t.text)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility3)
                    .padding(.horizontal, 18)

                Text("Set the default policy. You can change any rule later — unmatched actions always ask.")
                    .font(.dsSansPt(14.5))
                    .foregroundStyle(t.text3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 18)
                    .padding(.top, 10)
                    .padding(.bottom, 16)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility3)

                VStack(spacing: 8) {
                    ForEach(OnboardingCautionLevel.allCases, id: \.self) { cautionLevel in
                        let selected = level == cautionLevel
                        Button {
                            withAnimation(.easeInOut(duration: 0.12)) { level = cautionLevel }
                        } label: {
                            HStack(alignment: .top, spacing: 14) {
                                Rectangle()
                                    .fill(selected ? t.accent : t.border)
                                    .frame(width: 3)
                                    .frame(height: 52)

                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 8) {
                                        Text(cautionLevel.title)
                                            .font(.dsMonoPt(13, weight: .bold))
                                            .foregroundStyle(selected ? t.text : t.text2)
                                        if cautionLevel.recommended {
                                            Text("recommended")
                                                .font(.dsMonoPt(9))
                                                .foregroundColor(t.accent)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(t.accentSoft)
                                                .clipShape(RoundedRectangle(cornerRadius: 2))
                                        }
                                    }
                                    .dynamicTypeSize(...DynamicTypeSize.accessibility3)

                                    Text(cautionLevel.detail)
                                        .font(.dsSansPt(13))
                                        .foregroundStyle(t.text3)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
                                }
                                .padding(.vertical, 12)

                                Spacer()
                            }
                            .padding(.horizontal, 14)
                            .background(selected ? t.surface : Color.clear)
                            .overlay(
                                Rectangle()
                                    .strokeBorder(selected ? t.borderStrong : t.border, lineWidth: selected ? 1 : 0.5)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 24)
            }
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#endif
