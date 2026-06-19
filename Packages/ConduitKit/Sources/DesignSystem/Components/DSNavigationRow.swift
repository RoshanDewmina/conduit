import SwiftUI

public struct DSNavigationRow: View {
    private let title: String
    private let subtitle: String?
    private let value: String?
    private let systemImage: String
    private let action: () -> Void

    @Environment(\.conduitTokens) private var t

    public init(
        _ title: String,
        subtitle: String? = nil,
        value: String? = nil,
        systemImage: String,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.value = value
        self.systemImage = systemImage
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(t.text2)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.dsSansPt(16, weight: .medium))
                        .foregroundStyle(t.text)
                    if let subtitle {
                        Text(subtitle)
                            .font(.dsSansPt(13))
                            .foregroundStyle(t.text3)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if let value {
                    Text(value)
                        .font(.dsMonoPt(12))
                        .foregroundStyle(t.text3)
                        .lineLimit(1)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(t.text4)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}
