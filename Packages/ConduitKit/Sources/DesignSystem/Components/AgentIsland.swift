#if os(iOS)
import SwiftUI

// ============================================================
// Agent Island — an in-app agent HUD banner.
//
// NOTE: this is NOT the hardware Dynamic Island. iOS only renders a real
// Live Activity in the hardware island when Conduit is BACKGROUNDED (see
// ConduitLiveActivityWidget / LiveActivityManager) — never over our own
// foreground app. So this is an honest in-app banner: it seats just below
// the safe area (not flush with the camera cutout) and does not pretend to
// merge with the hardware island.
//
// A dark squircle that sits collapsed as a pill (state + host + approval
// badge) and morphs (width / height / cornerRadius together, on an iOS
// spring) into a dropped panel with a scrim: primary agent, tool line,
// progress stats, inline approval, and a roster of other agents.
//
// Recreates `island/Agent Island.html` (island.css + island*.jsx) from the
// "mother-duck-header" Claude Design bundle. The animated 3×3 state glyph is
// the existing `PixelBox(state:)`; avatars are `PixelAvatar`.
//
// Store-free: hand it `agents` + callbacks. `AgentIslandHost` mounts it.
// ============================================================

public enum AgentDecision: Sendable { case approve, deny }

public struct AgentIsland: View {
    let agents: [AgentInfo]
    var screenWidth: CGFloat
    var onJump: (UUID) -> Void
    var onResolve: (UUID, AgentDecision) -> Void

    @State private var expanded = false
    @State private var panelH: CGFloat = 220
    @State private var nudge = false

    public init(
        agents: [AgentInfo],
        screenWidth: CGFloat = 390,
        defaultExpanded: Bool = false,
        onJump: @escaping (UUID) -> Void = { _ in },
        onResolve: @escaping (UUID, AgentDecision) -> Void = { _, _ in }
    ) {
        self.agents = agents
        self.screenWidth = screenWidth
        self.onJump = onJump
        self.onResolve = onResolve
        _expanded = State(initialValue: defaultExpanded)
    }

    // ── derived roster ──
    private var active: [AgentInfo]   { agents.filter { $0.state != .offline } }
    private var approvals: [AgentInfo] { agents.filter { $0.state == .approval } }
    private var primary: AgentInfo {
        approvals.first ?? active.first ?? agents.first
            ?? AgentInfo(name: "Idle", agentKey: .unknown, host: "—", cwd: "", state: .offline)
    }
    private var others: [AgentInfo] { agents.filter { $0.id != primary.id } }
    private var hasApproval: Bool { !approvals.isEmpty }

    // ── shell geometry ──
    private var compactW: CGFloat { (hasApproval ? 272 : 250) }
    private var panelW: CGFloat { min(screenWidth - 28, 372) }
    private var shellW: CGFloat { expanded ? panelW : compactW }
    private var shellH: CGFloat { expanded ? panelH : 38 }
    private var shellR: CGFloat { expanded ? 34 : 19 }

    public var body: some View {
        ZStack(alignment: .top) {
            // Scrim behind the expanded panel.
            Color.black.opacity(expanded ? 0.55 : 0)
                .ignoresSafeArea()
                .allowsHitTesting(expanded)
                .onTapGesture { setExpanded(false) }

            shell
                .padding(.top, 4) // seats just under the hardware island, grows downward
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.5, dampingFraction: 0.82), value: expanded)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                nudge = true
            }
        }
    }

    private var shell: some View {
        ZStack(alignment: .top) {
            compactLayer
                .opacity(expanded ? 0 : 1)
                .scaleEffect(expanded ? 0.92 : 1)

            expandedLayer
                .frame(width: panelW, alignment: .top)
                .measureHeight { panelH = $0 }
                .opacity(expanded ? 1 : 0)
                .scaleEffect(expanded ? 1 : 0.97, anchor: .top)
        }
        .frame(width: shellW, height: shellH, alignment: .top)
        .background(DI.bg(approval: hasApproval))
        .clipShape(RoundedRectangle(cornerRadius: shellR, style: .continuous))
        .overlay(approvalGlow)
        .shadow(color: .black.opacity(0.45), radius: 17, y: 12)
        // subtle nudge/pulse when an approval is waiting and we're collapsed
        .scaleEffect((!expanded && hasApproval && nudge) ? 1.025 : 1.0)
        .contentShape(RoundedRectangle(cornerRadius: shellR, style: .continuous))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onEnded { v in
                    let dy = v.translation.height
                    let moved = abs(v.translation.width) + abs(dy)
                    if moved < 8 { setExpanded(!expanded) }            // tap
                    else if !expanded && dy > 16 { setExpanded(true) }  // swipe down
                    else if expanded && dy < -16 { setExpanded(false) } // swipe up
                }
        )
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder private var approvalGlow: some View {
        if hasApproval {
            RoundedRectangle(cornerRadius: shellR, style: .continuous)
                .strokeBorder(DI.approval.opacity(nudge ? 0.9 : 0.5), lineWidth: 1)
                .shadow(color: DI.approval.opacity(0.35), radius: 16)
                .allowsHitTesting(false)
        }
    }

    private func setExpanded(_ v: Bool) {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) { expanded = v }
    }

    // ───────── COMPACT: state + host + badge ─────────
    private var compactLayer: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                PixelBox(state: primary.state, size: 14)
                Text(primary.state.islandLabel)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(PixelBox.stateColor(primary.state))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Text(primary.host)
                    .font(DI.mono(11))
                    .foregroundStyle(DI.ink2)
                    .lineLimit(1)
                if hasApproval {
                    Text("\(approvals.count)")
                        .font(DI.mono(11, weight: .bold))
                        .foregroundStyle(Color(.sRGB, red: 0.10, green: 0.07, blue: 0, opacity: 1))
                        .frame(minWidth: 20, minHeight: 20)
                        .padding(.horizontal, 6)
                        .background(DI.approval, in: Capsule())
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
        .frame(width: compactW)
    }

    // ───────── EXPANDED: full panel ─────────
    private var expandedLayer: some View {
        VStack(alignment: .leading, spacing: 0) {
            // header
            HStack(spacing: 11) {
                PixelAvatar(seed: primary.host + primary.name, size: 38)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(primary.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(DI.ink).lineLimit(1)
                    (Text(primary.host + " · ").foregroundStyle(DI.ink3)
                     + Text(primary.cwd).foregroundStyle(DI.streaming))
                        .font(DI.mono(11.5)).lineLimit(1).truncationMode(.head)
                }
                Spacer(minLength: 0)
                StateBadge(state: primary.state)
            }

            if let tool = primary.tool { ToolLine(tool: tool) }

            if let ap = approvals.first {
                InlineApproval(agent: ap, onResolve: onResolve)
            }

            if primary.state != .approval, let p = primary.progress {
                ProgressStats(progress: p)
            }

            if !others.isEmpty {
                HStack {
                    Text("OTHER AGENTS")
                        .font(DI.mono(9.5)).tracking(1.6).foregroundStyle(DI.ink3)
                    Spacer()
                    Text("\(active.filter { $0.id != primary.id }.count) running · \(agents.count) total")
                        .font(DI.mono(10)).foregroundStyle(DI.ink3)
                }
                .padding(.top, 14).padding(.bottom, 4)

                ForEach(others) { a in
                    AgentRow(agent: a, onJump: onJump)
                }
            }

            // grab handle
            RoundedRectangle(cornerRadius: 999)
                .fill(Color.white.opacity(0.16))
                .frame(width: 36, height: 4)
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
        }
        .padding(EdgeInsets(top: 14, leading: 14, bottom: 12, trailing: 14))
    }
}

// ============================================================
// Sub-components
// ============================================================

private struct StateBadge: View {
    let state: AgentState
    var body: some View {
        HStack(spacing: 6) {
            PixelBox(state: state, size: 11)
            Text(state.islandLabel)
                .font(.system(size: 12.5, weight: .semibold))
        }
        .foregroundStyle(PixelBox.stateColor(state))
        .padding(.init(top: 4, leading: 8, bottom: 4, trailing: 10))
        .background(Color.white.opacity(0.06), in: Capsule())
        .fixedSize()
    }
}

private struct ToolLine: View {
    let tool: String
    var body: some View {
        HStack(spacing: 8) {
            Text("›").foregroundStyle(DI.ink3)
            Text(tool).foregroundStyle(DI.ink).lineLimit(1).truncationMode(.middle)
        }
        .font(DI.mono(12))
        .padding(.horizontal, 11).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.05), lineWidth: 1))
        .padding(.top, 11)
    }
}

private struct ProgressStats: View {
    let progress: AgentProgress
    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                stat("STEP", "\(progress.step)", sub: "/ \(progress.total)")
                stat("ELAPSED", progress.elapsed)
                stat("TOKENS", progress.tokens)
            }
            if progress.total > 0 {
                HStack(spacing: 3) {
                    ForEach(0..<progress.total, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(i < progress.step ? DI.streaming : Color.white.opacity(0.12))
                            .frame(height: 3)
                    }
                }
            }
        }
        .padding(.top, 10)
    }

    private func stat(_ k: String, _ v: String, sub: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(k).font(DI.mono(9.5)).tracking(1.2).foregroundStyle(DI.ink3)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(v).font(.system(size: 15, weight: .semibold)).foregroundStyle(DI.ink)
                if let sub { Text(sub).font(.system(size: 10)).foregroundStyle(DI.ink3) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct InlineApproval: View {
    let agent: AgentInfo
    let onResolve: (UUID, AgentDecision) -> Void
    var body: some View {
        let ap = agent.approval
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                PixelBox(state: .approval, size: 12)
                Text("\(agent.name) wants to run")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(DI.approval)
                Spacer(minLength: 0)
                if let risk = ap?.risk {
                    Text(risk.label)
                        .font(DI.mono(10)).tracking(0.8)
                        .foregroundStyle(riskColor(risk))
                }
            }
            Text(ap?.cmd ?? agent.tool ?? "")
                .font(DI.mono(12)).foregroundStyle(DI.ink)
                .lineLimit(1).truncationMode(.middle)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .padding(.vertical, 9)
            HStack(spacing: 7) {
                Button { onResolve(agent.id, .deny) } label: {
                    Text("Deny").font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DI.ink)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                Button { onResolve(agent.id, .approve) } label: {
                    Text("Approve").font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(.sRGB, red: 0.10, green: 0.07, blue: 0, opacity: 1))
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(DI.approval, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(11)
        .background(DI.approval.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(DI.approval.opacity(0.30), lineWidth: 1))
        .padding(.top, 11)
    }

    private func riskColor(_ r: AgentApproval.Risk) -> Color {
        switch r {
        case .low: PixelBox.stateColor(.done)
        case .medium: DI.approval
        case .high: PixelBox.stateColor(.thinking)
        case .critical: PixelBox.stateColor(.error)
        }
    }
}

private struct AgentRow: View {
    let agent: AgentInfo
    let onJump: (UUID) -> Void
    var body: some View {
        Button { onJump(agent.id) } label: {
            HStack(spacing: 11) {
                PixelAvatar(seed: agent.host + agent.name, size: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .opacity(agent.state == .offline ? 0.55 : 1)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 7) {
                        Text(agent.name).font(.system(size: 13.5, weight: .medium)).foregroundStyle(DI.ink)
                        Text(agent.host).font(DI.mono(10.5)).foregroundStyle(DI.ink3)
                    }
                    Text(agent.tool ?? agent.cwd).font(DI.mono(10.5)).foregroundStyle(DI.ink3)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 0)
                Text(agent.state.islandLabel)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(PixelBox.stateColor(agent.state))
                PixelBox(state: agent.state, size: 11)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color(.sRGB, red: 0.27, green: 0.255, blue: 0.235, opacity: 1))
            }
            .padding(.horizontal, 8).padding(.vertical, 9)
            .opacity(agent.state == .offline ? 0.55 : 1)
        }
        .buttonStyle(.plain)
    }
}

// ============================================================
// Always-dark Island palette (from island.css; oklch state colors reuse
// the existing per-state sRGB approximations in PixelBox so glyph + island agree).
// ============================================================

enum DI {
    static let ink  = Color(.sRGB, red: 0.957, green: 0.949, blue: 0.933, opacity: 1) // #f4f2ee
    static let ink2 = Color(.sRGB, red: 0.608, green: 0.588, blue: 0.553, opacity: 1) // #9b968d
    static let ink3 = Color(.sRGB, red: 0.400, green: 0.384, blue: 0.357, opacity: 1) // #66625b
    // Match PixelBox.stateColor (kept as literals so DI stays nonisolated).
    static let approval  = Color(.sRGB, red: 0.780, green: 0.584, blue: 0.157, opacity: 1)
    static let streaming = Color(.sRGB, red: 0.318, green: 0.573, blue: 0.929, opacity: 1)

    static func bg(approval: Bool) -> Color {
        approval ? Color(.sRGB, red: 0.110, green: 0.075, blue: 0.020, opacity: 1) // #1c1305
                 : .black
    }
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

// ── height measurement (mirrors the design's ResizeObserver) ──
private struct HeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
private extension View {
    func measureHeight(_ onChange: @escaping (CGFloat) -> Void) -> some View {
        background(GeometryReader { g in
            Color.clear.preference(key: HeightKey.self, value: g.size.height)
        })
        .onPreferenceChange(HeightKey.self, perform: onChange)
    }
}
#endif
