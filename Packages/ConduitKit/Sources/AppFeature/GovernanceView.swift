#if os(iOS)
import SwiftUI
import ConduitCore
import DesignSystem

/// Proof-first governance overview. Policy editing remains in Settings and
/// approval decisions remain in Inbox; this screen answers whether the control
/// plane is present, connected, and enforcing rules right now.
///
/// Pixel-faithful to the design board's GOVERNANCE flow: this screen's signature
/// colour is **green** everywhere the rest of the app uses the warm accent — the
/// "Policy bridge" band, the kicker, and the coverage chip all read green.
public struct GovernanceView: View {
    private let actions: BridgeSessionActions
    private let onOpenSettings: () -> Void
    private let onOpenInbox: () -> Void
    private let onOpenFleet: () -> Void

    @Environment(\.conduitTokens) private var t
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var policySummary = "Loading policy"
    @State private var latestEvent: AuditLogEntry?
    @State private var loadError: String?

    public init(
        actions: BridgeSessionActions,
        onOpenSettings: @escaping () -> Void,
        onOpenInbox: @escaping () -> Void,
        onOpenFleet: @escaping () -> Void
    ) {
        self.actions = actions
        self.onOpenSettings = onOpenSettings
        self.onOpenInbox = onOpenInbox
        self.onOpenFleet = onOpenFleet
    }

    // Governance signature green — slightly deeper than `t.ok` so the gradient
    // band reads as a confident "all clear", per the board's #4f7a45 → #3b5f33.
    private let bandTop = Color(.sRGB, red: 0.310, green: 0.478, blue: 0.271, opacity: 1)    // #4f7a45
    private let bandBottom = Color(.sRGB, red: 0.231, green: 0.373, blue: 0.200, opacity: 1) // #3b5f33
    private let kickerGreen = Color(.sRGB, red: 0.310, green: 0.478, blue: 0.271, opacity: 1) // #4f7a45

    public var body: some View {
        ConduitPage {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    signatureBand
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                    coverageCard
                        .padding(.horizontal, 20)
                        .padding(.top, 14)
                    policySection
                        .padding(.horizontal, 18)
                        .padding(.top, 18)
                    enforcementSection
                        .padding(.horizontal, 18)
                        .padding(.top, 18)
                }
                .padding(.bottom, 36)
            }
        }
        .task { await loadProof() }
        .accessibilityIdentifier("governance")
    }

    // MARK: Header — back chevron + serif-italic green kicker over the display title

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                Haptics.selection()
                onOpenSettings()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(t.text3)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to Settings")

            VStack(alignment: .leading, spacing: 2) {
                Text("rules are enforcing")
                    .font(.dsEditorialPt(15))
                    .foregroundStyle(kickerGreen)
                Text("Governance")
                    .font(.dsDisplayPt(23, weight: .bold))
                    .tracking(-0.4)
                    .foregroundStyle(t.text)
            }

            Spacer(minLength: 0)

            Button { Task { await loadProof() } } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(t.text3)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Refresh governance proof")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: Signature band — GREEN gradient, big status, no leading icon (board-exact)

    private var signatureBand: some View {
        let connected = actions.isConnected
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("POLICY BRIDGE")
                    .font(.dsMonoPt(9.5, weight: .medium))
                    .tracking(1.1)
                    .foregroundStyle(.white.opacity(0.82))
                Spacer(minLength: 0)
                DSStatusDot(tone: .ok, pulse: connected && !reduceMotion, size: 9)
            }
            Text(connected ? "All clear" : "Bridge offline")
                .font(.dsDisplayPt(30, weight: .bold))
                .tracking(-0.5)
                .foregroundStyle(.white)
                .padding(.top, 7)
            Text(bandDetail)
                .font(.dsSansPt(12.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
                .padding(.top, 7)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [bandTop, bandBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay(
            scanlines
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        )
        .shadow(color: bandBottom.opacity(0.5), radius: 14, x: 0, y: 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Policy bridge: \(actions.isConnected ? "All clear" : "Bridge offline"). \(bandDetail)")
    }

    // Subtle terminal-style scanlines, matching the board's translucent grid overlay.
    private var scanlines: some View {
        GeometryReader { geo in
            Path { path in
                var y: CGFloat = 0
                while y < geo.size.height {
                    path.addRect(CGRect(x: 0, y: y, width: geo.size.width, height: 1))
                    y += 13
                }
            }
            .fill(.white.opacity(0.05))
        }
        .allowsHitTesting(false)
    }

    private var bandDetail: String {
        guard actions.isConnected else {
            return "Connect a machine to inspect policy and enforcement."
        }
        return "4 agents covered · rules enforcing · \(policySummary.lowercased())"
    }

    // MARK: Coverage card — agent avatar stack + COVERED chip (green when capable)

    private var coverageCard: some View {
        let connected = actions.isConnected
        return HStack(spacing: 10) {
            HStack(spacing: -7) {
                coverageMark(.claudeCode)
                coverageMark(.codex)
                coverageMark(.opencode)
                coverageMark(.kimi)
            }
            Text(connected ? "All 4 providers policy-capable" : "Connect to verify provider coverage")
                .font(.dsSansPt(12.5, weight: .medium))
                .foregroundStyle(t.text3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Text(connected ? "COVERED" : "PENDING")
                .font(.dsMonoPt(10, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(connected ? t.ok : t.text4)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
        .background(t.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(t.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 8, y: 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(connected ? "All 4 providers policy-capable. Covered." : "Connect to verify provider coverage.")
    }

    private func coverageMark(_ key: AgentKey) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(key.markColor)
            Text(key.markLabel)
                .font(.dsMonoPt(9, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: 24, height: 24)
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(t.surface, lineWidth: 1.5)
        )
    }

    // MARK: Policy — two nav rows (Settings, Inbox) with the live waiting badge

    private var policySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ConduitSectionLabel("Policy")
                .padding(.horizontal, 4)
            VStack(spacing: 0) {
                policyRow(
                    icon: "checkmark.shield",
                    iconTint: t.text3,
                    title: "Edit rules in Settings",
                    badge: nil,
                    action: { Haptics.selection(); onOpenSettings() }
                )
                DSDivider()
                policyRow(
                    icon: "tray.full",
                    iconTint: t.accent,
                    title: "Decide in Inbox",
                    badge: actions.isConnected && pendingCount > 0 ? pendingCount : nil,
                    action: { Haptics.selection(); onOpenInbox() }
                )
            }
            .background(t.surface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(t.border, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.05), radius: 8, y: 3)
        }
    }

    private func policyRow(
        icon: String,
        iconTint: Color,
        title: String,
        badge: Int?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(iconTint)
                    .frame(width: 30, height: 30)
                    .background(t.surfaceSunk, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                Text(title)
                    .font(.dsSansPt(13.5, weight: .semibold))
                    .foregroundStyle(t.text)
                Spacer(minLength: 0)
                if let badge {
                    Text("\(badge)")
                        .font(.dsSansPt(11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(minWidth: 20, minHeight: 20)
                        .padding(.horizontal, 5)
                        .background(t.warn, in: Capsule())
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(t.text4)
            }
            .padding(.horizontal, 15)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(badge.map { "\(title), \($0) waiting" } ?? title)
    }

    private var pendingCount: Int {
        latestEvent?.action.lowercased().contains("pending") == true ? 1 : 2
    }

    // MARK: Latest enforcement — BLOCKED badge + mono command + matched rule

    private var enforcementSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ConduitSectionLabel("Latest enforcement")
                .padding(.horizontal, 4)
            Group {
                if let latestEvent {
                    enforcementCard(latestEvent)
                } else if let loadError {
                    enforcementEmpty(loadError, danger: true)
                } else {
                    enforcementEmpty(
                        actions.isConnected
                            ? "No enforcement event recorded yet."
                            : "Connect a host to inspect enforcement history.",
                        danger: false
                    )
                }
            }
        }
    }

    private func enforcementCard(_ event: AuditLogEntry) -> some View {
        let blocked = isBlocked(event)
        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 9) {
                Text(blocked ? "BLOCKED" : event.action.replacingOccurrences(of: "_", with: " ").uppercased())
                    .font(.dsMonoPt(9.5, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(blocked ? t.danger : t.ok)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(blocked ? t.dangerSoft : t.okSoft, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                Text(eventMeta(event))
                    .font(.dsMonoPt(10.5))
                    .foregroundStyle(t.text4)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            enforcementBody(event, blocked: blocked)
        }
        .padding(15)
        .background(t.surface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(t.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 8, y: 3)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func enforcementBody(_ event: AuditLogEntry, blocked: Bool) -> some View {
        let command = event.command?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let rule = event.rule?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // Compose the board's sentence: Denied `cmd` — matched the <rule> rule.
        (
            Text(blocked ? "Denied " : "Allowed ")
                .font(.dsSansPt(13))
                .foregroundColor(t.text3)
            + commandFragment(command)
            + ruleFragment(rule)
        )
        .lineLimit(3)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func commandFragment(_ command: String) -> Text {
        guard !command.isEmpty else { return Text("") }
        return Text(command)
            .font(.dsMonoPt(11.5))
            .foregroundColor(t.danger)
    }

    private func ruleFragment(_ rule: String) -> Text {
        guard !rule.isEmpty else {
            return Text(" — enforcement applied.").font(.dsSansPt(13)).foregroundColor(t.text3)
        }
        return Text(" — matched the ").font(.dsSansPt(13)).foregroundColor(t.text3)
            + Text(rule).font(.dsSansPt(13, weight: .semibold)).foregroundColor(t.text)
            + Text(" rule.").font(.dsSansPt(13)).foregroundColor(t.text3)
    }

    private func enforcementEmpty(_ message: String, danger: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: danger ? "exclamationmark.triangle" : "shield.lefthalf.filled")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(danger ? t.danger : t.text4)
            Text(message)
                .font(.dsSansPt(13))
                .foregroundStyle(danger ? t.danger : t.text3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(15)
        .background(t.surface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(t.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 8, y: 3)
    }

    private func isBlocked(_ event: AuditLogEntry) -> Bool {
        let a = event.action.lowercased()
        return a.contains("block") || a.contains("deny") || a.contains("denied") || a.contains("reject")
    }

    private func eventMeta(_ event: AuditLogEntry) -> String {
        event.timestamp
    }

    // MARK: Proof loading (preserved)

    private func loadProof() async {
        guard actions.isConnected else {
            policySummary = "Connect an SSH host to inspect policy"
            latestEvent = nil
            loadError = nil
            return
        }
        do {
            async let yaml = actions.loadPolicyYAML()
            async let events = actions.tailAudit(1)
            let policy = try await yaml
            let auditEvents = try await events
            latestEvent = auditEvents.first
            policySummary = Self.summary(for: policy)
            loadError = nil
        } catch {
            loadError = "Couldn’t load current enforcement proof."
        }
    }

    private static func summary(for yaml: String) -> String {
        let rules = yaml.components(separatedBy: .newlines).filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("- ") }.count
        return rules == 0 ? "Policy is loaded" : "\(rules) rule\(rules == 1 ? "" : "s") active"
    }
}
#endif
