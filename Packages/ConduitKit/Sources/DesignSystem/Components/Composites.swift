import SwiftUI

// MARK: - PromptLine
// composites.css:44-53 — `host:cwd $` inline with term colors.

public struct DSPromptLine: View {
    let host: String
    let cwd: String

    @Environment(\.conduitTokens) private var t

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

// MARK: - BlockCard (dark hero shell)
// composites.css:10-130 — the Warp-style command card.

public enum DSBlockState { case editing, submitted, executing, doneOk, doneErr, starred }

public struct DSBlockCard<Header: View, Output: View>: View {
    let state: DSBlockState
    let command: String
    let exitCode: Int?
    let duration: String?
    let isStarred: Bool
    let compact: Bool
    let header: () -> Header
    let outputContent: () -> Output
    let onCopy: (() -> Void)?
    let onRerun: (() -> Void)?

    @Environment(\.conduitTokens) private var t

    public init(
        state: DSBlockState,
        command: String,
        exitCode: Int? = nil,
        duration: String? = nil,
        isStarred: Bool = false,
        compact: Bool = false,
        @ViewBuilder header: @escaping () -> Header,
        @ViewBuilder output: @escaping () -> Output,
        onCopy: (() -> Void)? = nil,
        onRerun: (() -> Void)? = nil
    ) {
        self.state = state
        self.command = command
        self.exitCode = exitCode
        self.duration = duration
        self.isStarred = isStarred
        self.compact = compact
        self.header = header
        self.outputContent = output
        self.onCopy = onCopy
        self.onRerun = onRerun
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Head: PromptLine + meta
            HStack(spacing: 8) {
                header()
                Spacer()
                // Meta: exit chip / duration
                if let code = exitCode {
                    DSExitChip(code: code)
                }
                if let dur = duration {
                    Text(dur)
                        .font(.dsMonoPt(11))
                        .foregroundStyle(t.termText3)
                        .lineLimit(1)
                }
                if isStarred {
                    DSIconView(.starFilled, size: 13, color: t.termAccent)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .overlay(alignment: .bottom) {
                Rectangle().fill(t.termBorder).frame(height: 1)
            }

            // Command line
            HStack(spacing: 0) {
                if state == .editing {
                    Text(command)
                        .font(.dsMonoPt(14))
                        .foregroundStyle(t.termText)
                    // Blinking cursor
                    Rectangle()
                        .fill(t.termAccent)
                        .frame(width: 8, height: 16)
                        .blinking()
                } else {
                    Text(command)
                        .font(.dsMonoPt(14))
                        .foregroundStyle(t.termText)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 4)

            // Output
            outputContent()
                .padding(.horizontal, 14)
                .padding(.top, 6)
                .padding(.bottom, 14)

            // Footer (unless compact)
            if !compact {
                HStack(spacing: 0) {
                    if let copy = onCopy {
                        ghostButton("COPY", action: copy)
                    }
                    if let rerun = onRerun {
                        ghostButton("RERUN", action: rerun)
                    }
                    Spacer()
                    ghostButton("···", action: {})
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.18))
                .overlay(alignment: .top) {
                    Rectangle().fill(t.termBorder).frame(height: 1)
                }
            }
        }
        .background(t.termSurface)
        .clipShape(RoundedRectangle(cornerRadius: t.r4, style: .continuous))
        .overlay(alignment: .leading) {
            // Left gutter accent bar
            Rectangle()
                .fill(gutterColor)
                .frame(width: 3)
                .clipShape(RoundedRectangle(cornerRadius: t.r4, style: .continuous))
        }
        .overlay(
            RoundedRectangle(cornerRadius: t.r4, style: .continuous)
                .strokeBorder(t.termBorder, lineWidth: 1)
        )
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
    }

    private var gutterColor: Color {
        switch state {
        case .executing:  return t.termAccent
        case .doneOk:     return t.termOk.opacity(0.55)
        case .doneErr:    return t.termErr
        case .editing:    return t.termText3
        case .starred:    return t.termAccent
        case .submitted:  return t.termText3
        }
    }

    private func ghostButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.dsMonoPt(11, weight: .medium))
                .tracking(11 * 0.04)
                .foregroundStyle(t.termText2)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}

// Convenience init — no header slot; Header is fixed to EmptyView.
extension DSBlockCard where Header == EmptyView {
    public init(
        state: DSBlockState,
        command: String,
        exitCode: Int? = nil,
        duration: String? = nil,
        isStarred: Bool = false,
        compact: Bool = false,
        @ViewBuilder output: @escaping () -> Output,
        onCopy: (() -> Void)? = nil,
        onRerun: (() -> Void)? = nil
    ) {
        self.init(
            state: state,
            command: command,
            exitCode: exitCode,
            duration: duration,
            isStarred: isStarred,
            compact: compact,
            header: { EmptyView() },
            output: output,
            onCopy: onCopy,
            onRerun: onRerun
        )
    }
}

// Blink modifier
private struct BlinkModifier: ViewModifier {
    @State private var visible = true
    func body(content: Content) -> some View {
        content.opacity(visible ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever()) { visible.toggle() }
            }
    }
}
private extension View {
    func blinking() -> some View { modifier(BlinkModifier()) }
}

// MARK: - HostRow
// composites.css:187-226

public struct DSHostRow: View {
    let name: String
    let address: String
    let initials: String
    let status: DSConnectionState
    let pendingApprovals: Int
    let agentCount: Int
    let lastConnected: String?
    let onTap: () -> Void

    @Environment(\.conduitTokens) private var t

    public init(
        name: String,
        address: String,
        initials: String,
        status: DSConnectionState,
        pendingApprovals: Int = 0,
        agentCount: Int = 0,
        lastConnected: String? = nil,
        onTap: @escaping () -> Void
    ) {
        self.name = name
        self.address = address
        self.initials = initials
        self.status = status
        self.pendingApprovals = pendingApprovals
        self.agentCount = agentCount
        self.lastConnected = lastConnected
        self.onTap = onTap
    }

    public var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // Mark (initials tile) with optional attention ring
                ZStack {
                    initialsView
                    if pendingApprovals > 0 {
                        AttentionFlashRing(trigger: pendingApprovals, reason: .approval, cornerRadius: 8)
                    }
                }

                // Body
                VStack(alignment: .leading, spacing: 3) {
                    Text(name)
                        .font(.dsSansPt(14, weight: .semibold))
                        .foregroundStyle(t.text)
                    Text(address)
                        .font(.dsMonoPt(12))
                        .foregroundStyle(t.text3)
                }

                Spacer()

                // Meta column
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 6) {
                        DSStatusIcon(state: status, size: 18)
                        if pendingApprovals > 0 {
                            DSChip("\(pendingApprovals)", tone: .accent, variant: .solid, size: .sm)
                        }
                        if agentCount > 0 {
                            DSChip("\(agentCount)", tone: .neutral, size: .sm)
                        }
                    }
                    if let last = lastConnected {
                        Text(last)
                            .font(.dsMonoPt(11))
                            .foregroundStyle(t.text3)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(t.surface)
            .clipShape(RoundedRectangle(cornerRadius: t.r4, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: t.r4, style: .continuous)
                    .strokeBorder(t.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var initialsView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: t.r3, style: .continuous)
                .fill(t.surfaceSunk)
                .frame(width: 38, height: 38)
            Text(initials)
                .font(.dsMonoPt(13, weight: .semibold))
                .foregroundStyle(t.text2)
        }
    }
}


// MARK: - SnippetRow
// composites.css:285-321

public struct DSSnippetRow: View {
    let name: String
    let snippetBody: String
    let argCount: Int
    let useCount: Int
    let onTap: () -> Void

    @Environment(\.conduitTokens) private var t

    public init(name: String, body: String, argCount: Int = 0, useCount: Int = 0, onTap: @escaping () -> Void) {
        self.name = name
        self.snippetBody = body
        self.argCount = argCount
        self.useCount = useCount
        self.onTap = onTap
    }

    public var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(name)
                        .font(.dsSansPt(14, weight: .medium))
                        .foregroundStyle(t.text)
                    parameterizedText
                        .font(.dsMonoPt(12))
                        .foregroundStyle(t.text3)
                        .lineLimit(2)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    if argCount > 0 {
                        DSChip("\(argCount) args", tone: .neutral, size: .sm)
                    }
                    if useCount > 0 {
                        Text("×\(useCount)")
                            .font(.dsMonoPt(11))
                            .foregroundStyle(t.text4)
                    }
                    DSIconView(.chevronRight, size: 14, color: t.text4)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(t.surface)
            .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: t.r3, style: .continuous)
                    .strokeBorder(t.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // Highlight {{param}} spans using Text concatenation
    private var parameterizedText: some View {
        let parts = snippetBody.components(separatedBy: "{{")
        return parts.enumerated().reduce(Text("")) { acc, item in
            let (i, part) = item
            if i == 0 { return acc + Text(part) }
            let inner = part.components(separatedBy: "}}")
            if inner.count >= 2 {
                return acc
                    + Text("{{" + inner[0] + "}}")
                        .foregroundColor(t.accentInk)
                    + Text(inner.dropFirst().joined(separator: "}}"))
            }
            return acc + Text(part)
        }
    }
}

// MARK: - PaletteItem
// composites.css:323-339

public struct DSPaletteItem: View {
    let icon: DSIcon
    let name: String
    let subtitle: String?
    let hotkey: String?
    let isActive: Bool
    let onTap: () -> Void

    @Environment(\.conduitTokens) private var t

    public init(
        icon: DSIcon,
        name: String,
        subtitle: String? = nil,
        hotkey: String? = nil,
        isActive: Bool = false,
        onTap: @escaping () -> Void
    ) {
        self.icon = icon
        self.name = name
        self.subtitle = subtitle
        self.hotkey = hotkey
        self.isActive = isActive
        self.onTap = onTap
    }

    public var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Terminal icon
                ZStack {
                    RoundedRectangle(cornerRadius: t.r2, style: .continuous)
                        .fill(t.surfaceSunk)
                        .frame(width: 28, height: 28)
                    DSIconView(icon, size: 15, color: t.text2)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.dsSansPt(14))
                        .foregroundStyle(t.text)
                    if let sub = subtitle {
                        Text(sub)
                            .font(.dsMonoPt(12))
                            .foregroundStyle(t.text3)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if let key = hotkey {
                    Text(key)
                        .font(.dsMonoPt(11))
                        .foregroundStyle(t.text3)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(isActive ? t.surfaceSunk : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - DSSegmentedPicker
// A design-system–styled segmented control for small option sets (2–4 items).
// Replaces stock Picker(.segmented) so the control picks up DS surface/text tokens.

public struct DSSegmentedPicker<V: Hashable & Sendable>: View {
    public let options: [(label: String, value: V)]
    @Binding public var selection: V
    @Environment(\.conduitTokens) private var t

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
                        .font(.dsSansPt(13, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? t.text : t.text3)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(
                            selected
                                ? RoundedRectangle(cornerRadius: t.r2, style: .continuous)
                                    .fill(t.surface)
                                    .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
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

// MARK: - SectionHead (list variant with dashed bottom border)

public struct DSListSectionHead: View {
    let title: String
    let count: Int?

    @Environment(\.conduitTokens) private var t

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

// MARK: - DSTabBar (shared app chrome)
// composites.css:459-485 — 4-tab bar replacing system TabView.

public struct DSTabItem: Identifiable, Sendable {
    public let id: String
    public let icon: DSIcon
    public let label: String
    public let badge: Bool

    public init(id: String, icon: DSIcon, label: String, badge: Bool = false) {
        self.id = id
        self.icon = icon
        self.label = label
        self.badge = badge
    }
}

public struct DSTabBar: View {
    let items: [DSTabItem]
    @Binding var selectedID: String

    @Environment(\.conduitTokens) private var t

    public init(items: [DSTabItem], selectedID: Binding<String>) {
        self.items = items
        self._selectedID = selectedID
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                tabButton(item)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 50)
        // Clear the home indicator (pad), THEN paint the surface over both the
        // row and that padding and let it bleed under the indicator — so the bar
        // reads as one filled band instead of a 64pt row floating above a
        // transparent gap.
        .safeAreaPadding(.bottom)
        .background(t.surface, ignoresSafeAreaEdges: .bottom)
        .overlay(alignment: .top) {
            Rectangle().fill(t.border).frame(height: 1)
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
    }

    private func tabButton(_ item: DSTabItem) -> some View {
        let isActive = item.id == selectedID
        return Button {
            selectedID = item.id
        } label: {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    DSIconView(item.icon, size: 20, color: isActive ? t.text : t.text3)
                    if item.badge {
                        Circle()
                            .fill(t.accent)
                            .frame(width: 6, height: 6)
                            .overlay(Circle().strokeBorder(t.surface, lineWidth: 2))
                            .offset(x: 4, y: -4)
                    }
                }
                Text(item.label)
                    .font(.dsMonoPt(10))
                    .tracking(10 * 0.06)
                    .textCase(.uppercase)
                    .foregroundStyle(isActive ? t.text : t.text3)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Timeline
// composites.css:392-453

public enum DSTimelineNodeState { case done, active, ok, danger, pending }

public struct DSTimelineItem: Identifiable {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let meta: String?
    public let state: DSTimelineNodeState

    public init(id: String, title: String, subtitle: String? = nil, meta: String? = nil, state: DSTimelineNodeState = .pending) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.meta = meta
        self.state = state
    }
}

public struct DSTimeline: View {
    let items: [DSTimelineItem]
    @Environment(\.conduitTokens) private var t

    public init(_ items: [DSTimelineItem]) { self.items = items }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                HStack(alignment: .top, spacing: 12) {
                    // Rail
                    VStack(spacing: 0) {
                        nodeView(item.state)
                        if idx < items.count - 1 {
                            Rectangle()
                                .fill(t.borderStrong)
                                .frame(width: 1)
                                .frame(maxHeight: .infinity)
                        }
                    }
                    .frame(width: 9)

                    // Content
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title)
                            .font(.dsSansPt(item.state == .active ? 14 : 13,
                                           weight: item.state == .active ? .semibold : .regular))
                            .foregroundStyle(t.text)
                        if let sub = item.subtitle {
                            Text(sub)
                                .font(.dsMonoPt(11))
                                .foregroundStyle(t.text3)
                        }
                        if let meta = item.meta {
                            Text(meta)
                                .font(.dsMonoPt(11))
                                .foregroundStyle(t.text4)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(t.surfaceSunk)
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.bottom, 16)
                }
            }
        }
    }

    private func nodeView(_ state: DSTimelineNodeState) -> some View {
        ZStack {
            if state == .active {
                Circle()
                    .fill(t.accent.opacity(0.25))
                    .frame(width: 16, height: 16)
            }
            Circle()
                .fill(nodeColor(state))
                .frame(width: 9, height: 9)
        }
    }

    private func nodeColor(_ state: DSTimelineNodeState) -> Color {
        switch state {
        case .done:    return t.text
        case .active:  return t.accent
        case .ok:      return t.ok
        case .danger:  return t.danger
        case .pending: return t.borderStrong
        }
    }
}

// MARK: - KeyboardRail
// primitives.css:439-446 — horizontal scroll of DSKey chips.

public struct DSKeyboardRail: View {
    let keys: [String]
    let onKey: (String) -> Void

    @Environment(\.conduitTokens) private var t

    public init(keys: [String], onKey: @escaping (String) -> Void) {
        self.keys = keys
        self.onKey = onKey
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(keys, id: \.self) { key in
                    Button { onKey(key) } label: { DSKey(key) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(t.termBg)
        .overlay(alignment: .top) {
            Rectangle().fill(t.termBorder).frame(height: 1)
        }
    }
}
