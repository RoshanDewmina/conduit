import SwiftUI

// Tiny shared building blocks every feature reuses. Default-styled.

public struct PromptLine: View {
    public let hostName: String
    public let cwd: String
    public init(hostName: String, cwd: String) {
        self.hostName = hostName; self.cwd = cwd
    }
    public var body: some View {
        HStack(spacing: 4) {
            Text(hostName).foregroundStyle(.tint)
            Text(":")
            Text(cwd).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
            Text("$").foregroundStyle(.secondary)
        }
        .font(.system(.footnote, design: .monospaced))
    }
}

public struct ExitChip: View {
    public let code: Int
    public init(code: Int) { self.code = code }
    public var body: some View {
        Text("\(code)")
            .font(.system(.caption, design: .monospaced).weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(
                Capsule().fill(code == 0 ? Color.green.opacity(0.18) : Color.red.opacity(0.18))
            )
            .foregroundStyle(code == 0 ? Color.green : Color.red)
    }
}

public struct StatusDot: View {
    public let isOk: Bool
    public init(isOk: Bool) { self.isOk = isOk }
    public var body: some View {
        Circle().fill(isOk ? Color.green : Color.gray).frame(width: 7, height: 7)
    }
}

#if os(iOS)
public extension View {
    @ViewBuilder
    func conduitGlassChrome(cornerRadius: CGFloat = 18, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            if interactive {
                self.glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
            } else {
                self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
            }
        } else {
            self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
        }
    }
}
#endif
