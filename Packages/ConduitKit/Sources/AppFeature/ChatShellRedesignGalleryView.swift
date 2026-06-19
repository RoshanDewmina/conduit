#if DEBUG && os(iOS)
import SwiftUI
import DesignSystem

enum ChatShellRedesignDirection: String, CaseIterable, Identifiable {
    case systemFirst
    case hybridTechnical
    case chatAppClean

    var id: String { rawValue }

    var title: String {
        switch self {
        case .systemFirst: "Warm Control Shell"
        case .hybridTechnical: "Conduit Operator"
        case .chatAppClean: "Minimal Chat First"
        }
    }

    var subtitle: String {
        switch self {
        case .systemFirst: "Closest to Claude: warm, rounded, and calm."
        case .hybridTechnical: "Claude-inspired with stronger agent and governance signals."
        case .chatAppClean: "The cleanest chat surface; technical controls wait until needed."
        }
    }

    var composerLabel: String {
        switch self {
        case .systemFirst: "Rounded persistent composer"
        case .hybridTechnical: "Composer with visible control-plane context"
        case .chatAppClean: "Focused bottom sheet composer"
        }
    }

    var accent: Color {
        switch self {
        case .systemFirst: Color(.sRGB, red: 0.84, green: 0.41, blue: 0.28, opacity: 1)
        case .hybridTechnical: Color(.sRGB, red: 0.29, green: 0.38, blue: 1.0, opacity: 1)
        case .chatAppClean: Color(.sRGB, red: 0.93, green: 0.93, blue: 0.88, opacity: 1)
        }
    }

    var background: Color {
        switch self {
        case .systemFirst: Color(.sRGB, red: 0.11, green: 0.11, blue: 0.10, opacity: 1)
        case .hybridTechnical: Color(.sRGB, red: 0.04, green: 0.05, blue: 0.06, opacity: 1)
        case .chatAppClean: Color(.sRGB, red: 0.06, green: 0.06, blue: 0.055, opacity: 1)
        }
    }

    var surface: Color {
        switch self {
        case .systemFirst: Color(.sRGB, red: 0.18, green: 0.18, blue: 0.17, opacity: 1)
        case .hybridTechnical: Color(.sRGB, red: 0.08, green: 0.09, blue: 0.11, opacity: 1)
        case .chatAppClean: Color(.sRGB, red: 0.14, green: 0.14, blue: 0.13, opacity: 1)
        }
    }

    var raised: Color {
        switch self {
        case .systemFirst: Color(.sRGB, red: 0.23, green: 0.23, blue: 0.21, opacity: 1)
        case .hybridTechnical: Color(.sRGB, red: 0.11, green: 0.12, blue: 0.15, opacity: 1)
        case .chatAppClean: Color(.sRGB, red: 0.19, green: 0.19, blue: 0.18, opacity: 1)
        }
    }

    var text: Color { Color(.sRGB, red: 0.94, green: 0.93, blue: 0.89, opacity: 1) }
    var secondaryText: Color { Color(.sRGB, red: 0.66, green: 0.65, blue: 0.60, opacity: 1) }
    var faintText: Color { Color(.sRGB, red: 0.46, green: 0.46, blue: 0.42, opacity: 1) }
    var border: Color { Color.white.opacity(self == .hybridTechnical ? 0.14 : 0.08) }

    var corner: CGFloat {
        switch self {
        case .systemFirst: 26
        case .hybridTechnical: 16
        case .chatAppClean: 30
        }
    }

    var useMonoMetadata: Bool { self == .hybridTechnical }
    var showSpectrum: Bool { self == .hybridTechnical }
    var showSidebarOverlay: Bool { self != .chatAppClean }
    var showSheetComposer: Bool { self == .chatAppClean }
}

struct ChatShellRedesignGalleryView: View {
    @State private var selectedDirection: ChatShellRedesignDirection = .systemFirst

    var body: some View {
        ZStack {
            Color(.sRGB, red: 0.055, green: 0.055, blue: 0.05, opacity: 1)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                galleryHeader
                TabView(selection: $selectedDirection) {
                    ForEach(ChatShellRedesignDirection.allCases) { direction in
                        ChatShellRedesignPhoneView(direction: direction, mode: .overview)
                            .padding(.horizontal, 14)
                            .padding(.bottom, 18)
                            .tag(direction)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                selector
            }
        }
        .preferredColorScheme(.dark)
    }

    private var galleryHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Chat shell redesign")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("Three debug-only SwiftUI directions for the Conduit home, sidebar, composer, pickers, and active run framing.")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.white.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)
            Text(selectedDirection.composerLabel)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(selectedDirection.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(selectedDirection.accent.opacity(0.13), in: Capsule())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var selector: some View {
        HStack(spacing: 8) {
            ForEach(ChatShellRedesignDirection.allCases) { direction in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                        selectedDirection = direction
                    }
                } label: {
                    Text(direction.title)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(selectedDirection == direction ? .black : .white.opacity(0.72))
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(selectedDirection == direction ? direction.text : Color.white.opacity(0.07), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
    }
}

struct ChatShellRedesignSingleView: View {
    let direction: ChatShellRedesignDirection

    var body: some View {
        ChatShellRedesignPhoneView(direction: direction, mode: .single)
            .preferredColorScheme(.dark)
    }
}

private enum ChatShellRedesignMode {
    case overview
    case single
}

private struct ChatShellRedesignPhoneView: View {
    let direction: ChatShellRedesignDirection
    let mode: ChatShellRedesignMode

    var body: some View {
        ZStack(alignment: .leading) {
            direction.background.ignoresSafeArea()
            VStack(spacing: 0) {
                topChrome
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: direction == .chatAppClean ? 22 : 18) {
                        heroArea
                        recentChats
                        agentPickerPreview
                        activeTranscript
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, direction.showSheetComposer ? 250 : 132)
                }
            }
            if direction.showSidebarOverlay {
                sidebarPreview
            }
            if direction.showSheetComposer {
                dimmedBackdrop
                bottomSheetComposer
            } else {
                persistentComposer
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: mode == .overview ? 34 : 0, style: .continuous))
        .overlay {
            if mode == .overview {
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(direction.title) chat shell redesign option")
    }

    private var topChrome: some View {
        HStack(spacing: 14) {
            CircleIcon(systemName: "line.3.horizontal", direction: direction, filled: direction != .chatAppClean)
            Spacer()
            Text(direction == .chatAppClean ? "Conduit" : "Chats")
                .font(titleFont)
                .foregroundStyle(direction.text)
                .lineLimit(1)
            Spacer()
            CircleIcon(systemName: direction == .chatAppClean ? "slider.horizontal.3" : "bell.badge", direction: direction, filled: direction == .systemFirst)
        }
        .frame(height: 68)
        .padding(.horizontal, 20)
        .padding(.top, mode == .single ? 50 : 12)
        .background(direction.background.opacity(0.96))
    }

    private var heroArea: some View {
        VStack(alignment: direction == .chatAppClean ? .center : .leading, spacing: 12) {
            if direction.showSpectrum {
                spectrumBar
            }
            Text(heroTitle)
                .font(heroFont)
                .foregroundStyle(direction.text)
                .multilineTextAlignment(direction == .chatAppClean ? .center : .leading)
                .frame(maxWidth: .infinity, alignment: direction == .chatAppClean ? .center : .leading)
            Text(direction.subtitle)
                .font(bodyFont)
                .foregroundStyle(direction.secondaryText)
                .multilineTextAlignment(direction == .chatAppClean ? .center : .leading)
                .fixedSize(horizontal: false, vertical: true)
            if direction == .chatAppClean {
                ButtonLabel(title: "New chat", systemName: "plus", direction: direction, prominent: true)
                    .frame(maxWidth: 180)
                    .padding(.top, 4)
            } else {
                quickStatusRow
            }
        }
        .padding(.top, 12)
    }

    private var heroTitle: String {
        switch direction {
        case .systemFirst: "What should your agents do next?"
        case .hybridTechnical: "Start work, then let policy watch it."
        case .chatAppClean: "What are we building?"
        }
    }

    private var quickStatusRow: some View {
        HStack(spacing: 8) {
            StatusPill(label: "Waiting for you", count: "2", tone: Color(.sRGB, red: 1.0, green: 0.62, blue: 0.26, opacity: 1), direction: direction)
            StatusPill(label: "Running", count: "3", tone: direction.accent, direction: direction)
        }
    }

    private var recentChats: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: direction == .chatAppClean ? "Recent" : "Recent chats", trailing: "View all")
            VStack(spacing: 0) {
                ChatRow(title: "Review auth session patch", detail: "Claude Code · roshans-macbook · 4m", status: "Waiting", tone: Color(.sRGB, red: 1.0, green: 0.62, blue: 0.26, opacity: 1), direction: direction, preview: "Codex wants to edit session.swift and update 3 tests.")
                rowDivider
                ChatRow(title: "Run release smoke test", detail: "Codex · command-center · 18m", status: "Running", tone: direction.accent, direction: direction, preview: "swift test is streaming; 271 tests passed so far.")
                rowDivider
                ChatRow(title: "Landing page polish", detail: "opencode · web · 1h", status: "Done", tone: Color(.sRGB, red: 0.35, green: 0.78, blue: 0.45, opacity: 1), direction: direction, preview: direction == .chatAppClean ? nil : "All changes completed with exit 0.")
            }
            .padding(direction == .chatAppClean ? 0 : 4)
            .background(listBackground, in: RoundedRectangle(cornerRadius: listCorner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: listCorner, style: .continuous)
                    .strokeBorder(direction.border, lineWidth: direction == .chatAppClean ? 0 : 1)
            )
        }
    }

    private var agentPickerPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Pick agent", trailing: direction == .hybridTechnical ? "policy: cautious" : "Cautious")
            HStack(spacing: 10) {
                AgentChoice(title: "Claude", subtitle: "Sonnet 4.6 · low", selected: true, direction: direction)
                AgentChoice(title: "Codex", subtitle: "GPT-5 · review", selected: false, direction: direction)
            }
            HStack(spacing: 10) {
                PickerChip(title: "Host", value: "MacBook Air", icon: "desktopcomputer", direction: direction)
                PickerChip(title: "Project", value: "command-center", icon: "folder", direction: direction)
            }
        }
        .padding(14)
        .background(direction.raised.opacity(direction == .chatAppClean ? 0.0 : 0.82), in: RoundedRectangle(cornerRadius: listCorner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: listCorner, style: .continuous)
                .strokeBorder(direction == .chatAppClean ? Color.clear : direction.border, lineWidth: 1)
        )
    }

    private var activeTranscript: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(title: "Active run", trailing: "Live")
            userBubble
            assistantBubble
            toolCard
        }
    }

    private var userBubble: some View {
        HStack {
            Spacer(minLength: 48)
            Text("Add retries around relay pairing and show a clear error if approval delivery fails.")
                .font(bodyFont)
                .foregroundStyle(direction == .chatAppClean ? Color.black.opacity(0.88) : direction.text)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(userBubbleColor, in: RoundedRectangle(cornerRadius: bubbleCorner, style: .continuous))
        }
    }

    private var assistantBubble: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                pulseDot
                Text("Claude is checking the relay path and audit log handling.")
                    .font(bodyFont.weight(.medium))
                    .foregroundStyle(direction.text)
            }
            Text("I found the early return that drops delivery when the bridge is unpaired. I’m adding a visible diagnostic path before changing behavior.")
                .font(bodyFont)
                .foregroundStyle(direction.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(direction.surface.opacity(direction == .chatAppClean ? 0.62 : 1), in: RoundedRectangle(cornerRadius: bubbleCorner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: bubbleCorner, style: .continuous)
                .strokeBorder(direction.border, lineWidth: direction == .chatAppClean ? 0 : 1)
        )
    }

    private var toolCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Tool output", systemImage: "terminal")
                    .font(metaFont.weight(.semibold))
                    .foregroundStyle(direction == .chatAppClean ? direction.faintText : direction.secondaryText)
                Spacer()
                Text("exit 0")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color(.sRGB, red: 0.38, green: 0.82, blue: 0.48, opacity: 1))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("$ rg -n \"sendApproval\" daemon/conduitd")
                    .foregroundStyle(direction.text)
                Text("e2e_router.go:142 if !r.client.isPaired() { return }")
                    .foregroundStyle(direction.secondaryText)
            }
            .font(.system(size: 12, weight: .regular, design: .monospaced))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.black.opacity(direction == .chatAppClean ? 0.24 : 0.40), in: RoundedRectangle(cornerRadius: direction == .hybridTechnical ? 8 : 14, style: .continuous))
        }
        .padding(12)
        .background(toolCardBackground, in: RoundedRectangle(cornerRadius: direction == .hybridTechnical ? 12 : 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: direction == .hybridTechnical ? 12 : 20, style: .continuous)
                .strokeBorder(direction.border, lineWidth: 1)
        )
    }

    private var persistentComposer: some View {
        VStack(spacing: 8) {
            if direction == .hybridTechnical {
                HStack(spacing: 8) {
                    PickerChip(title: "Agent", value: "Claude", icon: "sparkles", direction: direction)
                    PickerChip(title: "Budget", value: "$5", icon: "dollarsign.circle", direction: direction)
                }
            }
            HStack(spacing: 10) {
                CircleIcon(systemName: "plus", direction: direction, filled: false, size: 42)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Ask your agents anything")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(direction.secondaryText)
                    Text(direction == .hybridTechnical ? "Claude · MacBook Air · ~/command-center" : "Claude Sonnet 4.6 · Low effort")
                        .font(metaFont)
                        .foregroundStyle(direction.faintText)
                }
                Spacer()
                CircleIcon(systemName: "mic", direction: direction, filled: true, size: 42)
                CircleIcon(systemName: "arrow.up", direction: direction, filled: true, size: 42)
            }
            .padding(12)
            .background(composerBackground, in: RoundedRectangle(cornerRadius: direction == .hybridTechnical ? 22 : 30, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: direction == .hybridTechnical ? 22 : 30, style: .continuous)
                    .strokeBorder(direction.border, lineWidth: 1)
            )
        }
        .padding(.horizontal, 12)
        .padding(.bottom, mode == .single ? 22 : 14)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    private var bottomSheetComposer: some View {
        VStack(alignment: .leading, spacing: 14) {
            Capsule()
                .fill(Color.white.opacity(0.32))
                .frame(width: 54, height: 5)
                .frame(maxWidth: .infinity)
            HStack {
                Text("New chat")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(direction.text)
                Spacer()
                CircleIcon(systemName: "xmark", direction: direction, filled: true, size: 44)
            }
            Text("Describe the work, pick the agent, then Conduit applies policy before anything runs.")
                .font(bodyFont)
                .foregroundStyle(direction.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Text("Fix relay approval diagnostics and add a smoke test")
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundStyle(direction.text)
                .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
                .padding(14)
                .background(Color.black.opacity(0.20), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            HStack(spacing: 10) {
                PickerChip(title: "Agent", value: "Claude", icon: "sparkles", direction: direction)
                PickerChip(title: "Host", value: "MacBook", icon: "desktopcomputer", direction: direction)
            }
            ButtonLabel(title: "Send", systemName: "arrow.up", direction: direction, prominent: true)
        }
        .padding(20)
        .background(direction.surface, in: UnevenRoundedRectangle(topLeadingRadius: 34, topTrailingRadius: 34))
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: 34, topTrailingRadius: 34)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
        .ignoresSafeArea(edges: .bottom)
    }

    private var sidebarPreview: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Circle()
                    .fill(direction.accent.opacity(0.85))
                    .frame(width: 34, height: 34)
                    .overlay(Text("C").font(.system(size: 15, weight: .bold)).foregroundStyle(direction == .systemFirst ? .black : .white))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Conduit")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(direction.text)
                    Text("Bridge connected")
                        .font(metaFont)
                        .foregroundStyle(direction.secondaryText)
                }
            }
            ButtonLabel(title: "New chat", systemName: "plus", direction: direction, prominent: direction == .systemFirst)
            sidebarSearch
            VStack(alignment: .leading, spacing: 12) {
                sidebarItem("Chats", "message", selected: true)
                sidebarItem("Waiting for you", "hand.raised", badge: "2")
                sidebarItem("Agents", "server.rack")
                sidebarItem("Settings", "gearshape")
            }
            Divider().overlay(direction.border)
            Text("Recent")
                .font(metaFont.weight(.semibold))
                .foregroundStyle(direction.faintText)
            Text("Review auth session patch")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(direction.text)
                .lineLimit(1)
            Text("Run release smoke test")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(direction.secondaryText)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(width: 246)
        .background(direction.surface.opacity(direction == .systemFirst ? 0.98 : 0.96))
        .overlay(alignment: .trailing) {
            Rectangle().fill(direction.border).frame(width: 1)
        }
        .shadow(color: .black.opacity(0.24), radius: 20, x: 12, y: 0)
        .padding(.top, mode == .single ? 28 : 0)
        .padding(.bottom, mode == .single ? 0 : 54)
    }

    private var sidebarSearch: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
            Text("Search chats")
                .font(.system(size: 14, weight: .regular, design: .rounded))
        }
        .foregroundStyle(direction.faintText)
        .padding(.horizontal, 12)
        .frame(height: 42)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func sidebarItem(_ title: String, _ icon: String, selected: Bool = false, badge: String? = nil) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 22)
            Text(title)
                .font(.system(size: 15, weight: selected ? .semibold : .medium, design: .rounded))
            Spacer()
            if let badge {
                Text(badge)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.black)
                    .frame(width: 22, height: 22)
                    .background(direction.accent, in: Circle())
            }
        }
        .foregroundStyle(selected ? direction.text : direction.secondaryText)
        .padding(.horizontal, 10)
        .frame(height: 42)
        .background(selected ? direction.raised : Color.clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var dimmedBackdrop: some View {
        Color.black.opacity(0.38)
            .ignoresSafeArea()
    }

    private func sectionHeader(title: String, trailing: String) -> some View {
        HStack {
            Text(title)
                .font(sectionFont)
                .foregroundStyle(direction.text)
            Spacer()
            Text(trailing)
                .font(metaFont.weight(.medium))
                .foregroundStyle(direction == .chatAppClean ? direction.secondaryText : direction.accent)
        }
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(direction.border)
            .frame(height: 1)
            .padding(.leading, direction == .chatAppClean ? 0 : 14)
    }

    private var spectrumBar: some View {
        HStack(spacing: 3) {
            ForEach(Array(ConduitTokens.spectrumColors.enumerated()), id: \.offset) { _, color in
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(height: 4)
            }
        }
    }

    private var pulseDot: some View {
        Circle()
            .fill(direction.accent)
            .frame(width: 8, height: 8)
            .overlay(Circle().stroke(direction.accent.opacity(0.35), lineWidth: 5))
    }

    private var titleFont: Font {
        direction.useMonoMetadata ? .system(size: 17, weight: .semibold, design: .monospaced) : .system(size: 18, weight: .bold, design: .rounded)
    }

    private var heroFont: Font {
        switch direction {
        case .systemFirst: .system(size: 30, weight: .bold, design: .rounded)
        case .hybridTechnical: .system(size: 26, weight: .bold, design: .rounded)
        case .chatAppClean: .system(size: 32, weight: .bold, design: .serif)
        }
    }

    private var sectionFont: Font {
        direction.useMonoMetadata ? .system(size: 13, weight: .semibold, design: .monospaced) : .system(size: 17, weight: .semibold, design: .rounded)
    }

    private var bodyFont: Font { .system(size: 14.5, weight: .regular, design: .rounded) }
    private var metaFont: Font { .system(size: 11.5, weight: .regular, design: direction.useMonoMetadata ? .monospaced : .rounded) }

    private var listBackground: Color {
        switch direction {
        case .systemFirst: direction.surface.opacity(0.88)
        case .hybridTechnical: direction.surface.opacity(1)
        case .chatAppClean: Color.clear
        }
    }

    private var listCorner: CGFloat { direction == .hybridTechnical ? 18 : direction.corner }
    private var bubbleCorner: CGFloat { direction == .hybridTechnical ? 14 : 22 }
    private var userBubbleColor: Color { direction == .chatAppClean ? direction.text : direction.raised }
    private var toolCardBackground: Color { direction == .hybridTechnical ? direction.raised : direction.surface.opacity(0.72) }
    private var composerBackground: Color { direction == .systemFirst ? direction.raised : direction.surface }
}

private struct ChatRow: View {
    let title: String
    let detail: String
    let status: String
    let tone: Color
    let direction: ChatShellRedesignDirection
    let preview: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: direction == .hybridTechnical ? 8 : 14, style: .continuous)
                    .fill(Color.black.opacity(direction == .chatAppClean ? 0.20 : 0.30))
                    .frame(width: 48, height: 48)
                Circle().fill(tone).frame(width: 10, height: 10).offset(x: 2, y: -2)
                Image(systemName: status == "Done" ? "checkmark" : "circle.dotted")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(direction.secondaryText)
            }
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(direction.text)
                        .lineLimit(1)
                    Spacer()
                    Text(status)
                        .font(.system(size: 11, weight: .semibold, design: direction.useMonoMetadata ? .monospaced : .rounded))
                        .foregroundStyle(tone)
                }
                Text(detail)
                    .font(.system(size: 12.5, weight: .regular, design: direction.useMonoMetadata ? .monospaced : .rounded))
                    .foregroundStyle(direction.secondaryText)
                    .lineLimit(1)
                if let preview {
                    Text(preview)
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(direction.faintText)
                        .lineLimit(2)
                        .padding(.top, 2)
                }
            }
        }
        .padding(.horizontal, direction == .chatAppClean ? 0 : 12)
        .padding(.vertical, 12)
    }
}

private struct AgentChoice: View {
    let title: String
    let subtitle: String
    let selected: Bool
    let direction: ChatShellRedesignDirection

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(direction.text)
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(direction.accent)
                }
            }
            Text(subtitle)
                .font(.system(size: 12, weight: .regular, design: direction.useMonoMetadata ? .monospaced : .rounded))
                .foregroundStyle(direction.secondaryText)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? direction.accent.opacity(direction == .systemFirst ? 0.18 : 0.13) : direction.surface.opacity(0.70), in: RoundedRectangle(cornerRadius: direction == .hybridTechnical ? 12 : 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: direction == .hybridTechnical ? 12 : 18, style: .continuous)
                .strokeBorder(selected ? direction.accent.opacity(0.45) : direction.border, lineWidth: 1)
        )
    }
}

private struct PickerChip: View {
    let title: String
    let value: String
    let icon: String
    let direction: ChatShellRedesignDirection

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(direction.secondaryText)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 10.5, weight: .medium, design: direction.useMonoMetadata ? .monospaced : .rounded))
                    .foregroundStyle(direction.faintText)
                Text(value)
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(direction.text)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(direction.faintText)
        }
        .padding(.horizontal, 12)
        .frame(height: 48)
        .frame(maxWidth: .infinity)
        .background(direction.surface.opacity(direction == .chatAppClean ? 0.80 : 1), in: RoundedRectangle(cornerRadius: direction == .hybridTechnical ? 12 : 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: direction == .hybridTechnical ? 12 : 18, style: .continuous)
                .strokeBorder(direction.border, lineWidth: 1)
        )
    }
}

private struct StatusPill: View {
    let label: String
    let count: String
    let tone: Color
    let direction: ChatShellRedesignDirection

    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(tone).frame(width: 7, height: 7)
            Text(count)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(direction.text)
            Text(label)
                .font(.system(size: 12, weight: .medium, design: direction.useMonoMetadata ? .monospaced : .rounded))
                .foregroundStyle(direction.secondaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, 11)
        .frame(height: 34)
        .background(direction.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(direction.border, lineWidth: 1))
    }
}

private struct ButtonLabel: View {
    let title: String
    let systemName: String
    let direction: ChatShellRedesignDirection
    let prominent: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .bold))
            Text(title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(prominent ? (direction == .systemFirst || direction == .chatAppClean ? Color.black : Color.white) : direction.text)
        .frame(maxWidth: .infinity)
        .frame(height: 46)
        .background(prominent ? direction.accent : direction.raised, in: Capsule())
        .overlay(Capsule().strokeBorder(prominent ? Color.clear : direction.border, lineWidth: 1))
    }
}

private struct CircleIcon: View {
    let systemName: String
    let direction: ChatShellRedesignDirection
    let filled: Bool
    var size: CGFloat = 50

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size <= 42 ? 16 : 18, weight: .semibold))
            .foregroundStyle(filled ? iconForeground : direction.secondaryText)
            .frame(width: size, height: size)
            .background(filled ? iconBackground : direction.surface.opacity(0.72), in: Circle())
            .overlay(Circle().strokeBorder(direction.border, lineWidth: 1))
    }

    private var iconForeground: Color {
        if direction == .systemFirst || direction == .chatAppClean { return .black.opacity(0.86) }
        return .white
    }

    private var iconBackground: Color {
        if systemName == "arrow.up" || systemName == "plus" { return direction.accent }
        return direction.raised
    }
}

#Preview("Chat shell redesign gallery") {
    ChatShellRedesignGalleryView()
}

#endif
