import SwiftUI

// MARK: - PromptLine

public struct DSPromptLine: View {
    let host: String
    let cwd: String

    @Environment(\.lancerTokens) private var t

    public init(host: String, cwd: String) {
        self.host = host
        self.cwd = cwd
    }

    public var body: some View {
        HStack(spacing: 0) {
            Text(host)
                .foregroundStyle(t.termPrompt)
                .fontWeight(.medium)
            Text(":")
                .foregroundStyle(t.termText3)
            Text(cwd)
                .foregroundStyle(t.termCwd)
            Text(" $")
                .foregroundStyle(t.termText3)
        }
        .font(.dsMonoPt(12))
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
    }
}

// MARK: - DSSegmentedPicker

public struct DSSegmentedPicker<V: Hashable & Sendable>: View {
    public let options: [(label: String, value: V)]
    @Binding public var selection: V

    @Environment(\.lancerTokens) private var t

    public init(options: [(label: String, value: V)], selection: Binding<V>) {
        self.options = options
        self._selection = selection
    }

    public var body: some View {
        HStack(spacing: 3) {
            ForEach(options, id: \.value) { opt in
                let selected = selection == opt.value
                Button { selection = opt.value } label: {
                    Text(opt.label)
                        .font(.dsMonoPt(12, weight: .medium))
                        .foregroundStyle(selected ? t.accentFg : t.text3)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(
                            selected
                                ? RoundedRectangle(cornerRadius: t.r2, style: .continuous).fill(t.accent)
                                : nil
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(t.surfaceSunk, in: RoundedRectangle(cornerRadius: t.r3, style: .continuous))
        .animation(.easeInOut(duration: 0.15), value: selection)
    }
}

// MARK: - SectionHead

public struct DSListSectionHead: View {
    let title: String
    let count: Int?

    @Environment(\.lancerTokens) private var t

    public init(_ title: String, count: Int? = nil) {
        self.title = title
        self.count = count
    }

    public var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.dsMonoPt(11, weight: .medium))
                .tracking(11 * 0.10)
                .textCase(.uppercase)
                .foregroundStyle(t.text3)
            if let n = count {
                Text("· \(n)")
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text4)
            }
            Spacer()
        }
        .padding(.horizontal, t.s5)
        .padding(.vertical, t.s3)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(t.divider)
                .frame(height: 1)
        }
    }
}
