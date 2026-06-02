#if os(iOS)
import SwiftUI
import DesignSystem
import ConduitCore
import KeysFeature
import PersistenceKit
import SecurityKit

// MARK: - Screen 1: HostDetailView (M1b)

public struct HostDetailView: View {
    let hostName: String
    let hostAddress: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.conduitTokens) private var t

    private enum Tab: String, CaseIterable, Hashable, Sendable {
        case info, network, danger
    }

    @State private var selectedTab: Tab = .info
    @State private var autoReconnect: AutoReconnect = .wifi

    private enum AutoReconnect: String, CaseIterable, Hashable, Sendable {
        case off, wifi, always
    }

    public init(hostName: String, hostAddress: String) {
        self.hostName = hostName
        self.hostAddress = hostAddress
    }

    public var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                DSDetailHeader("host detail", onBack: { dismiss() })

                DSSegmentedPicker(
                    options: Tab.allCases.map { (label: $0.rawValue, value: $0) },
                    selection: $selectedTab
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

                ScrollView {
                    switch selectedTab {
                    case .info:    infoTab
                    case .network: networkTab
                    case .danger:  dangerTab
                    }
                }
            }
        }
        .navigationBarHidden(true)
    }

    // MARK: Info tab

    private var infoTab: some View {
        VStack(spacing: 0) {
            // Identity section
            VStack(spacing: 14) {
                HStack(spacing: 14) {
                    DSIconView(.server, size: 22, color: t.text2)
                        .frame(width: 44, height: 44)
                        .background(t.surface)
                        .clipShape(Rectangle())
                        .overlay(Rectangle().strokeBorder(t.border, lineWidth: 1))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(hostName)
                            .font(.dsMonoPt(14, weight: .semibold))
                            .foregroundStyle(t.text)
                        Text(hostAddress)
                            .font(.dsMonoPt(12))
                            .foregroundStyle(t.text2)
                    }
                    Spacer()
                    DSStatusDot(tone: .off, size: 8)
                }
            }
            .padding(16)
            .background(t.surface)
            .overlay(Rectangle().strokeBorder(t.border, lineWidth: 0.5))
            .padding(.horizontal, 16)
            .padding(.top, 8)

            DSListSectionHead("DETAILS")

            detailRow(label: "auth method", value: "Ed25519 key")
            DSDivider()
            detailRow(label: "tmux session", value: "conduit")
            DSDivider()
            detailRow(label: "startup cmd", value: "—")
            DSDivider()

            HStack {
                Text("auto-resume")
                    .font(.dsMonoPt(13))
                    .foregroundStyle(t.text)
                Spacer()
                Toggle("", isOn: .constant(true))
                    .tint(t.accent)
                    .labelsHidden()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            DSDivider()
        }
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.dsMonoPt(13))
                .foregroundStyle(t.text2)
            Spacer()
            Text(value)
                .font(.dsMonoPt(13))
                .foregroundStyle(t.text)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: Network tab

    private var networkTab: some View {
        VStack(spacing: 0) {
            DSListSectionHead("PORT FORWARDS")

            ForEach(ManagementMocks.portForwards) { pf in
                HStack {
                    Text("\(pf.local) → \(pf.remote)")
                        .font(.dsMonoPt(13, weight: .medium))
                        .foregroundStyle(t.text)
                    Spacer()
                    Text(pf.description)
                        .font(.dsMonoPt(11))
                        .foregroundStyle(t.text3)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                DSDivider()
            }

            // Add forward dashed row
            Button {
                // TODO: add port forward
            } label: {
                HStack(spacing: 8) {
                    DSIconView(.plus, size: 14, color: t.text3)
                    Text("add forward")
                        .font(.dsMonoPt(13))
                        .foregroundStyle(t.text3)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .overlay(Rectangle().strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3])).foregroundStyle(t.border))
                .padding(.horizontal, 16)
                .padding(.top, 4)
            }
            .buttonStyle(.plain)

            DSListSectionHead("HOST KEY")
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 6) {
                Text("SHA256:aB3cD4eF5gH6iJ7kL8mN9oP0qR1sT2uV3wX4yZ5")
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text2)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                DSChip("trusted", tone: .ok, variant: .soft, size: .sm)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(t.surface)
            .overlay(Rectangle().strokeBorder(t.border, lineWidth: 0.5))
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            DSListSectionHead("AUTO-RECONNECT")

            DSSegmentedPicker(
                options: AutoReconnect.allCases.map { (label: $0.rawValue, value: $0) },
                selection: $autoReconnect
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    // MARK: Danger tab

    private var dangerTab: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Removing this host will also remove any associated sessions and snippets tagged to it.")
                    .font(.dsMonoPt(12))
                    .foregroundStyle(t.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .background(t.dangerSoft)
            .overlay(Rectangle().strokeBorder(t.danger.opacity(0.3), lineWidth: 0.5))
            .padding(.horizontal, 16)

            DSButton("remove host", variant: .destructive, fullWidth: true) {
                // TODO: delete host action
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 16)
    }
}

// MARK: - Screen 2: AgentPolicyView (M2a)

public struct AgentPolicyView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.conduitTokens) private var t

    public init() {}

    private let riskRows: [(level: Int, label: String, policy: String)] = [
        (0, "low risk",      "auto"),
        (1, "medium risk",   "auto"),
        (2, "high risk",     "ask"),
        (3, "critical risk", "ask + Face ID"),
    ]

    public var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                DSDetailHeader("agent policy", onBack: { dismiss() })

                ScrollView {
                    VStack(spacing: 0) {
                        // Agent card
                        agentCard

                        DSListSectionHead("RISK POLICY")
                            .padding(.top, 8)

                        ForEach(riskRows, id: \.label) { row in
                            DSRiskRow(level: row.level, label: row.label, policy: row.policy)
                            DSDivider()
                        }

                        // Footer
                        Text("Auto-run actions never appear in inbox. Approval-required actions pause until you respond.")
                            .font(.dsMonoPt(11))
                            .foregroundStyle(t.text3)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(16)
                    }
                }
            }
        }
        .navigationBarHidden(true)
    }

    private var agentCard: some View {
        HStack(spacing: 12) {
            DSIconView(.sparkles, size: 18, color: t.accent)
                .frame(width: 40, height: 40)
                .background(t.accentSoft)
                .clipShape(Rectangle())

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    DSChip("claude-sonnet-4-5", tone: .accent, variant: .soft, size: .sm)
                    DSChip("Anthropic", tone: .neutral, variant: .soft, size: .sm)
                }
                Text("anthropic/claude-sonnet-4-5")
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text3)
            }

            Spacer()

            Button {
                // TODO: change agent
            } label: {
                Text("change")
                    .font(.dsMonoPt(12))
                    .foregroundStyle(t.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(t.surface)
        .overlay(Rectangle().strokeBorder(t.border, lineWidth: 0.5))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

// MARK: - Screen 3: AgentListView (M2b)

public struct AgentListView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.conduitTokens) private var t

    public init() {}

    public var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                DSScreenHeader("agents", breadcrumb: "hosted · SSH", spectrumMode: .idle) {
                    DSIconButton(.plus) { /* TODO: create agent */ }
                }

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(ManagementMocks.agents) { agent in
                            agentCard(agent)
                            DSDivider()
                        }
                    }
                }
            }
        }
        .navigationBarHidden(true)
    }

    @ViewBuilder
    private func agentCard(_ agent: MockAgent) -> some View {
        HStack(spacing: 14) {
            // Status indicator
            ZStack {
                Rectangle()
                    .fill(statusBg(agent.status))
                    .frame(width: 40, height: 40)
                DSIconView(.sparkles, size: 16, color: statusColor(agent.status))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(agent.name)
                    .font(.dsMonoPt(13, weight: .semibold))
                    .foregroundStyle(t.text)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(agent.provider)
                        .font(.dsMonoPt(11))
                        .foregroundStyle(t.text3)
                    if agent.byok {
                        DSChip("BYOK", tone: .accent, variant: .soft, size: .sm)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                DSChip(agent.status, tone: statusChipTone(agent.status), variant: .soft, size: .sm)
                if let cost = agent.costMonth {
                    Text(String(format: "$%.2f/mo", cost))
                        .font(.dsMonoPt(11))
                        .foregroundStyle(t.text3)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "working": return t.accent
        case "idle":    return t.text3
        default:        return t.text4
        }
    }

    private func statusBg(_ status: String) -> Color {
        switch status {
        case "working": return t.accentSoft
        case "idle":    return t.surfaceSunk
        default:        return t.surfaceSunk
        }
    }

    private func statusChipTone(_ status: String) -> DSChipTone {
        switch status {
        case "working": return .accent
        case "idle":    return .neutral
        default:        return .neutral
        }
    }
}

// MARK: - Screen 4: VMListView (M3a)

public struct VMListView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.conduitTokens) private var t

    public init() {}

    private var totalCost: Double {
        ManagementMocks.vms.reduce(0) { $0 + $1.costToday }
    }

    public var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                DSDetailHeader("workspaces", onBack: { dismiss() }) {
                    Text(String(format: "$%.2f today", totalCost))
                        .font(.dsMonoPt(12, weight: .medium))
                        .foregroundStyle(t.text2)
                }

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(ManagementMocks.vms) { vm in
                            vmRow(vm)
                            DSDivider()
                        }
                    }

                    Text("Metered compute. Your own SSH hosts are always free.")
                        .font(.dsMonoPt(11))
                        .foregroundStyle(t.text3)
                        .padding(16)
                }
            }
        }
        .navigationBarHidden(true)
    }

    @ViewBuilder
    private func vmRow(_ vm: MockVM) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                DSIconView(.server, size: 16, color: statusColor(vm.status))
                    .frame(width: 32, height: 32)
                    .background(statusBg(vm.status))
                    .clipShape(Rectangle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(vm.name)
                        .font(.dsMonoPt(13, weight: .semibold))
                        .foregroundStyle(t.text)
                    Text("\(vm.vcpu) vCPU · \(vm.memGB) GB")
                        .font(.dsMonoPt(11))
                        .foregroundStyle(t.text3)
                }

                Spacer()

                DSChip(vm.status, tone: statusChipTone(vm.status), variant: .soft, size: .sm)
            }

            if vm.status == "running" {
                HStack(spacing: 8) {
                    if let rate = vm.ratePerHour {
                        Text(String(format: "$%.2f/hr", rate))
                            .font(.dsMonoPt(11))
                            .foregroundStyle(t.text3)
                    }
                    Spacer()
                    DSButton("connect", variant: .primary, size: .sm, mono: true) {
                        // TODO: connect action
                    }
                    DSButton("stop", variant: .ghost, size: .sm, mono: true) {
                        // TODO: stop action
                    }
                }
            } else {
                HStack {
                    Spacer()
                    DSButton("start", variant: .secondary, size: .sm, mono: true) {
                        // TODO: start action
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "running":  return t.ok
        case "sleeping": return t.warn
        default:         return t.text4
        }
    }

    private func statusBg(_ status: String) -> Color {
        switch status {
        case "running":  return t.okSoft
        case "sleeping": return t.warnSoft
        default:         return t.surfaceSunk
        }
    }

    private func statusChipTone(_ status: String) -> DSChipTone {
        switch status {
        case "running":  return .ok
        case "sleeping": return .warn
        default:         return .neutral
        }
    }
}

// MARK: - Screen 5: VMDetailView (M3b)

public struct VMDetailView: View {
    let vm: MockVM

    @Environment(\.dismiss) private var dismiss
    @Environment(\.conduitTokens) private var t

    public init(vm: MockVM) {
        self.vm = vm
    }

    public var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                DSDetailHeader(vm.name, onBack: { dismiss() })

                ScrollView {
                    VStack(spacing: 16) {
                        // 2x2 metric grid
                        LazyVGrid(
                            columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                            spacing: 12
                        ) {
                            DSMetricTile("CPU", value: "\(Int(vm.cpuPercent))%",
                                         tone: vm.cpuPercent > 80 ? .warn : .neutral)
                            DSMetricTile("Memory", value: String(format: "%.1f", vm.memUsedGB),
                                         unit: "/ \(vm.memGB) GB")
                            DSMetricTile("GPU", value: "\(Int(vm.gpuPercent))%",
                                         tone: vm.gpuPercent > 90 ? .warn : .neutral)
                            DSMetricTile("Cost", value: String(format: "$%.2f", vm.costToday),
                                         unit: "today", tone: .neutral)
                        }
                        .padding(.horizontal, 16)

                        // CPU sparkline
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("CPU — last 30s")
                                    .font(.dsMonoPt(11, weight: .medium))
                                    .foregroundStyle(t.text3)
                                Spacer()
                            }
                            TickBars(
                                values: Array(ManagementMocks.cpuSparkline.suffix(30)).map { $0 / 100.0 },
                                barColor: t.accent,
                                barWidth: 4,
                                spacing: 2,
                                maxHeight: 40
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .padding(14)
                        .background(t.surface)
                        .overlay(Rectangle().strokeBorder(t.border, lineWidth: 0.5))
                        .padding(.horizontal, 16)

                        // Footer buttons
                        HStack(spacing: 12) {
                            DSButton("stop instance", variant: .secondary, fullWidth: true) {
                                // TODO: stop
                            }
                            DSButton("destroy", variant: .destructive, fullWidth: true) {
                                // TODO: destroy
                            }
                        }
                        .padding(.horizontal, 16)

                        Text("// TODO: wire live metrics")
                            .font(.dsMonoPt(10))
                            .foregroundStyle(t.text4)
                            .padding(.bottom, 8)
                    }
                    .padding(.top, 12)
                }
            }
        }
        .navigationBarHidden(true)
    }
}
#endif
