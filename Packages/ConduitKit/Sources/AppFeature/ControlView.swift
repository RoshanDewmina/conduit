#if os(iOS)
import SwiftUI
import DesignSystem
import ConduitCore
import NotificationsKit
import SettingsFeature
import SSHTransport

/// **Control** — the guardrails surface (tab 3). Consolidates the rules that
/// govern agents: emergency stop, autonomy level (when agents ask permission),
/// budget limits, risk rules, and quiet hours. These were previously scattered
/// across Settings and Fleet; Control gives them one home so a user can answer
/// "change when agents need permission / set a spend limit / stop everything".
public struct ControlView: View {
    let fleetStore: FleetStore
    let bridgeActions: BridgeSessionActions
    let daemonChannel: DaemonChannel?
    let onOpenBudget: () -> Void

    @AppStorage("inbox.autonomyPreset") private var autonomyPresetRaw: String = AutonomyPreset.alwaysAsk.rawValue
    @State private var notificationFilter = NotificationFilter()
    @State private var confirmingStop = false

    @Environment(\.conduitTokens) private var t

    public init(
        fleetStore: FleetStore,
        bridgeActions: BridgeSessionActions,
        daemonChannel: DaemonChannel?,
        onOpenBudget: @escaping () -> Void
    ) {
        self.fleetStore = fleetStore
        self.bridgeActions = bridgeActions
        self.daemonChannel = daemonChannel
        self.onOpenBudget = onOpenBudget
    }

    private var liveAgentCount: Int {
        fleetStore.slots.filter { $0.sessionViewModel.status == .connected }.count
    }

    private var autonomy: AutonomyPreset {
        AutonomyPreset(rawValue: autonomyPresetRaw) ?? .alwaysAsk
    }

    public var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                DSScreenHeader("control", breadcrumb: "rules & guardrails")
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        emergencyStopSection
                        autonomySection
                        budgetAndRulesSection
                        quietHoursSection
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                    .padding(.bottom, 28)
                }
            }
        }
        .task { notificationFilter = await Notifications.shared.loadFilter() }
        .confirmationDialog(
            "Stop all agents?",
            isPresented: $confirmingStop,
            titleVisibility: .visible
        ) {
            Button("Stop \(liveAgentCount) agent\(liveAgentCount == 1 ? "" : "s")", role: .destructive) {
                stopAllAgents()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Disconnects every running agent immediately. In-flight work on the host is interrupted.")
        }
    }

    // MARK: - Emergency stop (the missing phone affordance)

    private var emergencyStopSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            DSListSectionHead("Emergency stop", count: liveAgentCount > 0 ? liveAgentCount : nil)
            Button {
                Haptics.warning()
                confirmingStop = true
            } label: {
                HStack(spacing: 12) {
                    DSIconView(.alertTri, size: 20, color: liveAgentCount > 0 ? t.danger : t.text4)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Stop all agents")
                            .font(.dsSansPt(15, weight: .semibold))
                            .foregroundStyle(liveAgentCount > 0 ? t.text : t.text3)
                        Text(liveAgentCount > 0
                             ? "Disconnect every running agent now"
                             : "No agents are running")
                            .font(.dsSansPt(12))
                            .foregroundStyle(t.text3)
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(liveAgentCount > 0 ? t.dangerSoft : t.surface)
                .overlay(Rectangle().strokeBorder(liveAgentCount > 0 ? t.danger : t.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(liveAgentCount == 0)
            .accessibilityLabel("Stop all agents")
            .accessibilityHint(liveAgentCount > 0 ? "Disconnects \(liveAgentCount) running agents" : "No agents running")
        }
    }

    private func stopAllAgents() {
        Haptics.success()
        let slots = fleetStore.slots
        Task {
            for slot in slots where slot.sessionViewModel.status == .connected {
                await slot.sessionViewModel.disconnect()
            }
        }
    }

    // MARK: - Autonomy (when agents ask permission)

    private var autonomySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            DSListSectionHead("When agents ask permission", count: nil)
            VStack(spacing: 8) {
                ForEach(AutonomyPreset.allCases, id: \.self) { preset in
                    Button {
                        Haptics.selection()
                        withAnimation(.easeInOut(duration: 0.14)) { autonomyPresetRaw = preset.rawValue }
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            DSStatusDot(tone: autonomy == preset ? .accent : .off, size: 9)
                                .padding(.top, 5)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(preset.label)
                                    .font(.dsSansPt(15, weight: .semibold))
                                    .foregroundStyle(t.text)
                                Text(preset.description)
                                    .font(.dsSansPt(13))
                                    .foregroundStyle(t.text3)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(autonomy == preset ? t.accentSoft : t.surface)
                        .overlay(Rectangle().strokeBorder(autonomy == preset ? t.accent : t.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("autonomy_\(preset.rawValue)")
                    .accessibilityValue(autonomy == preset ? "selected" : "unselected")
                }
            }
        }
    }

    // MARK: - Budget + risk rules

    private var budgetAndRulesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            DSListSectionHead("Limits & rules", count: nil)
            VStack(spacing: 8) {
                Button {
                    Haptics.selection()
                    onOpenBudget()
                } label: {
                    controlNavRow(icon: .flash, title: "Budget limits", detail: "Spend caps per run and per day")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("control_budget")

                NavigationLink {
                    PolicyEditorBridgeScreen(actions: bridgeActions, daemonChannel: daemonChannel)
                } label: {
                    controlNavRow(icon: .shield, title: "Risk rules", detail: "Allow / ask / deny by tool and risk")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("control_rules")
            }
        }
    }

    private func controlNavRow(icon: DSIcon, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            DSIconView(icon, size: 17, color: t.text2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.dsSansPt(15, weight: .semibold))
                    .foregroundStyle(t.text)
                Text(detail)
                    .font(.dsSansPt(12))
                    .foregroundStyle(t.text3)
            }
            Spacer(minLength: 0)
            DSIconView(.chevronRight, size: 14, color: t.text4)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(t.surface)
        .overlay(Rectangle().strokeBorder(t.border, lineWidth: 1))
    }

    // MARK: - Quiet hours / notification escalation

    private var quietHoursSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            DSListSectionHead("Quiet hours & escalation", count: nil)
            VStack(alignment: .leading, spacing: 12) {
                Text("Minimum risk to notify")
                    .font(.dsSansPt(13, weight: .medium))
                    .foregroundStyle(t.text2)
                DSSegmentedPicker(
                    options: [
                        (label: "Low+", value: Approval.Risk.low),
                        (label: "Med+", value: Approval.Risk.medium),
                        (label: "High+", value: Approval.Risk.high),
                        (label: "Crit", value: Approval.Risk.critical),
                    ],
                    selection: Binding(
                        get: { notificationFilter.minRisk },
                        set: { newValue in
                            notificationFilter.minRisk = newValue
                            persistFilter()
                        }
                    )
                )

                Toggle(isOn: Binding(
                    get: { notificationFilter.quietHoursEnabled },
                    set: { newValue in
                        notificationFilter.quietHoursEnabled = newValue
                        persistFilter()
                    }
                )) {
                    Text("Quiet hours")
                        .font(.dsSansPt(14))
                        .foregroundStyle(t.text)
                }
                .tint(t.accent)

                if notificationFilter.quietHoursEnabled {
                    Text("Silenced \(hourLabel(notificationFilter.quietHoursStart))–\(hourLabel(notificationFilter.quietHoursEnd)). Critical approvals still break through.")
                        .font(.dsSansPt(12))
                        .foregroundStyle(t.text3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(t.surface)
            .overlay(Rectangle().strokeBorder(t.border, lineWidth: 1))
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        String(format: "%02d:00", hour)
    }

    private func persistFilter() {
        let filter = notificationFilter
        Task { await Notifications.shared.saveFilter(filter) }
    }
}
#endif
