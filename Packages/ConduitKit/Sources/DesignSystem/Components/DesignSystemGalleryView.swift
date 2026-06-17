import SwiftUI

private func galleryListStyle() -> some ListStyle {
    #if os(iOS)
    .insetGrouped
    #else
    .plain
    #endif
}

// MARK: - DesignSystemGalleryView — full component showcase
// Seven sections: Navigation & IA, Buttons, Chips & Tags, Status & State,
// Avatars & Identity, Cards & Composite, Atoms & Primitives.

public struct DesignSystemGalleryView: View {
    @Environment(\.conduitTokens) private var t

    public init() {}

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink("Navigation & IA (§01)") {
                        NavigationSectionView()
                    }
                    NavigationLink("Buttons (§02)") {
                        ButtonsSectionView()
                    }
                    NavigationLink("Chips & Tags (§03)") {
                        ChipsSectionView()
                    }
                    NavigationLink("Status & State (§04)") {
                        StatusSectionView()
                    }
                    NavigationLink("Avatars & Identity (§05)") {
                        AvatarsSectionView()
                    }
                    NavigationLink("Cards & Composite (§06)") {
                        CardsSectionView()
                    }
                    NavigationLink("Atoms & Primitives (§07)") {
                        AtomsSectionView()
                    }
                } header: {
                    HStack {
                        SpectrumBar(mode: .idle, height: 4, gap: 1)
                    }
                    .listRowInsets(EdgeInsets())
                }
            }
            .listStyle(galleryListStyle())
            .background(t.bg)
            .scrollContentBackground(.hidden)
            .navigationTitle("Design System")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }
}

// MARK: - §01 Navigation & IA

private struct NavigationSectionView: View {
    @Environment(\.conduitTokens) private var t

    var body: some View {
        List {
            Section("DSScreenHeader") {
                DSScreenHeader("sessions",
                               breadcrumb: "connected",
                               count: "3",
                               spectrumMode: .loading)
                .padding(.vertical, t.s3)
            }

            Section("SpectrumBar Modes") {
                VStack(alignment: .leading, spacing: t.s5) {
                    LabeledPair("idle") {
                        SpectrumBar(mode: .idle, height: 6, gap: 1.5)
                    }
                    LabeledPair("loading") {
                        SpectrumBar(mode: .loading, height: 6, gap: 1.5)
                    }
                    LabeledPair("scan") {
                        SpectrumBar(mode: .scan, height: 6, gap: 1.5)
                    }
                    LabeledPair("working") {
                        SpectrumBar(mode: .working, height: 6, gap: 1.5)
                    }
                }
                .padding(.vertical, t.s3)
            }
        }
        .listStyle(galleryListStyle())
        .background(t.bg)
        .scrollContentBackground(.hidden)
        .navigationTitle("Navigation & IA")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

// MARK: - §02 Buttons

private struct ButtonsSectionView: View {
    @Environment(\.conduitTokens) private var t

    var body: some View {
        List {
            Section("Variants") {
                VStack(spacing: t.s4) {
                    ForEach([
                        DSButtonVariant.primary,
                        .accent,
                        .secondary,
                        .ghost,
                        .destructive,
                        .quiet,
                    ], id: \.label) { v in
                        DSButton(v.label, variant: v, size: .md, action: {})
                    }
                }
                .padding(.vertical, t.s3)
            }

            Section("Sizes") {
                VStack(alignment: .leading, spacing: t.s4) {
                    DSButton("Small (sm)", variant: .primary, size: .sm, action: {})
                    DSButton("Medium (md)", variant: .primary, size: .md, action: {})
                    DSButton("Large (lg)", variant: .primary, size: .lg, action: {})
                }
                .padding(.vertical, t.s3)
            }

            Section("Mono") {
                VStack(alignment: .leading, spacing: t.s4) {
                    DSButton("mono primary", variant: .primary, size: .md, mono: true, action: {})
                    DSButton("mono accent", variant: .accent, size: .md, mono: true, action: {})
                    DSButton("mono destructive", variant: .destructive, size: .md, mono: true, action: {})
                }
                .padding(.vertical, t.s3)
            }
        }
        .listStyle(galleryListStyle())
        .background(t.bg)
        .scrollContentBackground(.hidden)
        .navigationTitle("Buttons")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

// MARK: - §03 Chips & Tags

private struct ChipsSectionView: View {
    @Environment(\.conduitTokens) private var t

    var body: some View {
        List {
            Section("DSChip Tones") {
                VStack(alignment: .leading, spacing: t.s3) {
                    ForEach([
                        DSChipTone.accent,
                        .ok,
                        .warn,
                        .orange,
                        .danger,
                        .info,
                        .neutral,
                    ], id: \.label) { tone in
                        DSChip(tone.label, tone: tone, variant: .default)
                    }
                }
                .padding(.vertical, t.s3)
            }

            Section("DSChip Variants") {
                VStack(alignment: .leading, spacing: t.s3) {
                    DSChip("default", tone: .accent, variant: .default)
                    DSChip("outlined", tone: .accent, variant: .outlined)
                    DSChip("mono", tone: .accent, variant: .mono)
                    DSChip("monoInverse", tone: .accent, variant: .monoInverse)
                    DSChip("solid", tone: .accent, variant: .solid)
                    DSChip("dashed", tone: .accent, variant: .dashed)
                }
                .padding(.vertical, t.s3)
            }

            Section("RiskBadge") {
                VStack(alignment: .leading, spacing: t.s3) {
                    RiskBadge(risk: 0)
                    RiskBadge(risk: 1)
                    RiskBadge(risk: 2)
                    RiskBadge(risk: 3)
                }
                .padding(.vertical, t.s3)
            }

            Section("AgentBadge") {
                VStack(alignment: .leading, spacing: t.s3) {
                    AgentBadge(.thinking)
                    AgentBadge(.streaming)
                    AgentBadge(.approval)
                    AgentBadge(.done)
                    AgentBadge(.error)
                    AgentBadge(.offline)
                }
                .padding(.vertical, t.s3)
            }

            Section("DSExitChip") {
                VStack(alignment: .leading, spacing: t.s3) {
                    DSExitChip(code: 0)
                    DSExitChip(code: 1)
                }
                .padding(.vertical, t.s3)
            }
        }
        .listStyle(galleryListStyle())
        .background(t.bg)
        .scrollContentBackground(.hidden)
        .navigationTitle("Chips & Tags")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

// MARK: - §04 Status & State

private struct StatusSectionView: View {
    @Environment(\.conduitTokens) private var t

    var body: some View {
        List {
            Section("StatusIcon") {
                VStack(spacing: t.s3) {
                    StatusIcon(.thinking, size: 16)
                    StatusIcon(.streaming, size: 16)
                    StatusIcon(.approval, size: 16)
                    StatusIcon(.done, size: 16)
                    StatusIcon(.error, size: 16)
                    StatusIcon(.offline, size: 16)
                }
                .padding(.vertical, t.s3)
            }

            Section("DSStatusDot") {
                VStack(spacing: t.s3) {
                    ForEach([
                        DSStatusDotTone.ok,
                        .warn,
                        .danger,
                        .info,
                        .accent,
                        .orange,
                        .off,
                    ], id: \.label) { tone in
                        HStack(spacing: t.s3) {
                            DSStatusDot(tone: tone, pulse: false, size: 12)
                            Text(tone.label)
                                .font(.dsMonoPt(13))
                        }
                    }
                }
                .padding(.vertical, t.s3)
            }

            Section("PixelBox") {
                VStack(spacing: t.s4) {
                    ForEach(AgentState.allCases, id: \.self) { state in
                        HStack(spacing: t.s3) {
                            PixelBox(state: state, size: 12, gap: 2)
                            Text(state.label)
                                .font(.dsMonoPt(13))
                        }
                    }
                }
                .padding(.vertical, t.s3)
            }

            Section("DotMatrixView") {
                VStack(spacing: t.s5) {
                    ForEach(DotMatrixState.allCases, id: \.self) { ds in
                        VStack(alignment: .leading, spacing: t.s1) {
                            Text(ds.rawValue)
                                .font(.dsMonoPt(10))
                                .foregroundStyle(t.text3)
                            DotMatrixView(state: ds, cols: 20, rows: 4, cell: 6, dot: 3)
                        }
                    }
                }
                .padding(.vertical, t.s3)
            }
        }
        .listStyle(galleryListStyle())
        .background(t.bg)
        .scrollContentBackground(.hidden)
        .navigationTitle("Status & State")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

// MARK: - §05 Avatars & Identity

private struct AvatarsSectionView: View {
    @Environment(\.conduitTokens) private var t

    var body: some View {
        List {
            Section("PixelAvatar") {
                VStack(spacing: t.s4) {
                    HStack(spacing: t.s4) {
                        PixelAvatar(seed: "host-1", size: 32)
                        PixelAvatar(seed: "roshan", size: 32)
                        PixelAvatar(seed: "server-prod", size: 32)
                        PixelAvatar(seed: "localhost", size: 32)
                    }
                    HStack(spacing: t.s4) {
                        PixelAvatar(seed: "host-1", size: 48)
                        PixelAvatar(seed: "roshan", size: 48)
                        PixelAvatar(seed: "server-prod", size: 48)
                    }
                }
                .padding(.vertical, t.s3)
            }

            Section("AgentIdentityBadge") {
                VStack(spacing: t.s3) {
                    ForEach([
                        AgentKey.claudeCode,
                        .codex,
                        .cursor,
                        .opencode,
                        .devin,
                    ], id: \.rawValue) { key in
                        AgentIdentityBadge(agent: key, label: key.rawValue, dark: false)
                    }
                }
                .padding(.vertical, t.s3)
            }

            Section("AgentIdentityBadge (dark)") {
                VStack(spacing: t.s3) {
                    ForEach([
                        AgentKey.claudeCode,
                        .codex,
                        .cursor,
                        .opencode,
                        .devin,
                    ], id: \.rawValue) { key in
                        AgentIdentityBadge(agent: key, label: key.rawValue, dark: true)
                    }
                }
                .padding(.vertical, t.s3)
                .padding(.horizontal, t.s3)
                .background(t.termBg)
                .clipShape(RoundedRectangle(cornerRadius: t.r5))
            }
        }
        .listStyle(galleryListStyle())
        .background(t.bg)
        .scrollContentBackground(.hidden)
        .navigationTitle("Avatars & Identity")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

// MARK: - §06 Cards & Composite

private struct CardsSectionView: View {
    @Environment(\.conduitTokens) private var t

    var body: some View {
        List {
            Section("DSBlockCard") {
                VStack(spacing: t.s5) {
                    DSBlockCard(
                        state: .doneOk,
                        command: "npm run test",
                        exitCode: 0,
                        duration: "3.2s"
                    ) {
                        AgentIdentityBadge(agent: .opencode, label: "opencode")
                    } output: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("  PASS  src/App.test.tsx")
                                .font(.dsMonoPt(12))
                                .foregroundStyle(t.termOk)
                            Text("  PASS  src/utils.test.tsx")
                                .font(.dsMonoPt(12))
                                .foregroundStyle(t.termOk)
                        }
                        .padding(.vertical, 4)
                    }

                    DSBlockCard(
                        state: .doneErr,
                        command: "deploy --env prod",
                        exitCode: 1,
                        duration: "1.1s"
                    ) {
                        AgentIdentityBadge(agent: .claudeCode, label: "claude")
                    } output: {
                        Text("Error: build failed\n       at DeployStep.validate")
                            .font(.dsMonoPt(12))
                            .foregroundStyle(t.termErr)
                            .padding(.vertical, 4)
                    }

                    DSBlockCard(
                        state: .executing,
                        command: "terraform plan",
                        duration: "12.4s"
                    ) {
                        AgentIdentityBadge(agent: .opencode, label: "opencode")
                    } output: {
                        Text("Planning...")
                            .font(.dsMonoPt(12))
                            .foregroundStyle(t.termText2)
                            .padding(.vertical, 4)
                    }
                }
                .padding(.vertical, t.s3)
            }

            Section("DSSpendHero") {
                DSSpendHero(
                    todayUSD: 142.53,
                    vendors: [
                        ("Anthropic", 82.10),
                        ("OpenAI", 45.20),
                        ("Groq", 15.23),
                    ],
                    runs: 1287,
                    concurrent: 6,
                    capUSD: 500
                )
                .padding(.vertical, t.s3)
            }

            Section("DSProgressBar") {
                VStack(spacing: t.s5) {
                    DSProgressBar(value: 0.25, tone: .info, label: "Downloading...")
                    DSProgressBar(value: 0.60, tone: .accent, label: "Processing")
                    DSProgressBar(value: 0.90, tone: .warn, label: "Almost done")
                    DSProgressBar(value: 1.0, tone: .ok, label: "Complete")
                }
                .padding(.vertical, t.s3)
            }

            Section("DSProgressSegmented") {
                VStack(spacing: t.s4) {
                    DSProgressSegmented(total: 5, done: 2, active: 2)
                    DSProgressSegmented(total: 8, done: 4, active: -1)
                    DSProgressSegmented(total: 3, done: 0, active: 0)
                }
                .padding(.vertical, t.s3)
            }
        }
        .listStyle(galleryListStyle())
        .background(t.bg)
        .scrollContentBackground(.hidden)
        .navigationTitle("Cards & Composite")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

// MARK: - §07 Atoms & Primitives

private struct AtomsSectionView: View {
    @Environment(\.conduitTokens) private var t

    var body: some View {
        List {
            Section("DSDivider") {
                VStack(spacing: t.s5) {
                    LabeledPair(".soft") {
                        DSDivider(.soft)
                    }
                    LabeledPair(".line") {
                        DSDivider(.line)
                    }
                    LabeledPair(".strong") {
                        DSDivider(.strong)
                    }
                }
                .padding(.vertical, t.s3)
            }

            Section("SpectrumBar") {
                VStack(spacing: t.s5) {
                    LabeledPair("idle") {
                        SpectrumBar(mode: .idle, height: 6, gap: 1.5)
                    }
                    LabeledPair("loading") {
                        SpectrumBar(mode: .loading, height: 6, gap: 1.5)
                    }
                    LabeledPair("scan") {
                        SpectrumBar(mode: .scan, height: 6, gap: 1.5)
                    }
                    LabeledPair("working") {
                        SpectrumBar(mode: .working, height: 6, gap: 1.5)
                    }
                }
                .padding(.vertical, t.s3)
            }

            Section("DotMatrixView (small)") {
                VStack(spacing: t.s5) {
                    DotMatrixView(state: .idle, cols: 16, rows: 3, cell: 5, dot: 2)
                    DotMatrixView(state: .thinking, cols: 16, rows: 3, cell: 5, dot: 2)
                    DotMatrixView(state: .working, cols: 16, rows: 3, cell: 5, dot: 2)
                }
                .padding(.vertical, t.s3)
            }

            Section("Spectrum Colors") {
                HStack(spacing: t.s1) {
                    ForEach(0..<ConduitTokens.spectrumColors.count, id: \.self) { i in
                        RoundedRectangle(cornerRadius: t.r2)
                            .fill(ConduitTokens.spectrumColors[i])
                            .aspectRatio(1, contentMode: .fit)
                    }
                }
                .frame(height: 32)
                .padding(.vertical, t.s2)
            }
        }
        .listStyle(galleryListStyle())
        .background(t.bg)
        .scrollContentBackground(.hidden)
        .navigationTitle("Atoms & Primitives")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

// MARK: - Helpers

private struct LabeledPair<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content
    @Environment(\.conduitTokens) private var t

    init(_ label: String, @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: t.s1) {
            Text(label)
                .font(.dsMonoPt(10))
                .foregroundStyle(t.text3)
            content()
        }
    }
}

private extension DSButtonVariant {
    var label: String {
        switch self {
        case .primary:     return "Primary"
        case .accent:      return "Accent"
        case .secondary:   return "Secondary"
        case .ghost:       return "Ghost"
        case .destructive: return "Destructive"
        case .quiet:       return "Quiet"
        }
    }
}

private extension DSChipTone {
    var label: String {
        switch self {
        case .accent:  return "accent"
        case .ok:      return "ok"
        case .warn:    return "warn"
        case .orange:  return "orange"
        case .danger:  return "danger"
        case .info:    return "info"
        case .neutral: return "neutral"
        }
    }
}

private extension DSStatusDotTone {
    var label: String {
        switch self {
        case .ok:      return "ok"
        case .warn:    return "warn"
        case .danger:  return "danger"
        case .info:    return "info"
        case .accent:  return "accent"
        case .orange:  return "orange"
        case .off:     return "off"
        }
    }
}
