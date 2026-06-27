#if os(iOS)
import SwiftUI
import DesignSystem

/// Top-level destinations inside the Governance home. AppRoot maps each to a real
/// detail view via the `destination` closure — keeping `GovernanceHomeView` decoupled
/// from the (separately-built) feature views so they can evolve independently.
/// Three merged Governance surfaces (down from seven cards). Live approvals fold
/// into Home/Inbox and setup-drift lives under Machines, so Governance holds the
/// durable governance backbone: rules, the record, and trust.
public enum GovernanceRoute: Hashable, Sendable {
    case policy   // policy presets + cross-provider matrix
    case audit    // verifiable audit trail (the record)
    case trust    // privacy/E2E proof + team & roles
}

/// Stats shown on the dashboard cards. Cheap value type so the gallery can render
/// the screen with mock data and AppRoot can feed live values.
public struct GovernanceStats: Sendable {
    public var hostCount: Int
    public var policyActive: Bool
    public var auditCount: Int
    public var auditChainVerified: Bool
    public var presetNames: [String]
    public var providerCount: Int
    public var roleLabel: String             // e.g. "owner"

    public init(
        hostCount: Int = 0, policyActive: Bool = false, auditCount: Int = 0,
        auditChainVerified: Bool = false, presetNames: [String] = [],
        providerCount: Int = 0, roleLabel: String = "owner"
    ) {
        self.hostCount = hostCount; self.policyActive = policyActive; self.auditCount = auditCount
        self.auditChainVerified = auditChainVerified; self.presetNames = presetNames
        self.providerCount = providerCount; self.roleLabel = roleLabel
    }
}

/// The Governance dashboard — the home that makes policy/audit *the product*.
/// Each section is a card that pushes into a feature view via `destination`.
public struct GovernanceHomeView: View {
    let stats: GovernanceStats
    let onEmergencyStop: () -> Void
    let onOpenSidebar: () -> Void
    let destination: (GovernanceRoute) -> AnyView

    @Environment(\.lancerTokens) private var t
    @State private var confirmStop = false

    public init(
        stats: GovernanceStats,
        onEmergencyStop: @escaping () -> Void,
        onOpenSidebar: @escaping () -> Void = {},
        destination: @escaping (GovernanceRoute) -> AnyView
    ) {
        self.stats = stats
        self.onEmergencyStop = onEmergencyStop
        self.onOpenSidebar = onOpenSidebar
        self.destination = destination
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    headerCard
                    section("GOVERNANCE") {
                        card(.policy, icon: "slider.horizontal.3", title: "Policy",
                             subtitle: stats.presetNames.isEmpty
                                ? "Define rules once · map across every provider"
                                : "\(stats.presetNames.joined(separator: " · ")) · \(stats.providerCount) providers")
                        card(.audit, icon: "checkmark.seal", title: "Audit trail",
                             subtitle: "\(stats.auditCount) events · \(stats.auditChainVerified ? "chain verified ✓" : "tap to verify")",
                             tone: stats.auditChainVerified ? .ok : .orange)
                        card(.trust, icon: "lock.shield", title: "Trust & team",
                             subtitle: "Blind E2E relay · you: \(stats.roleLabel)", tone: .ok)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .background(t.surface)
            .navigationTitle("Governance")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: GovernanceRoute.self) { destination($0) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onOpenSidebar) { Image(systemName: "line.3.horizontal") }
                        .tint(t.text2)
                        .accessibilityLabel("Open sidebar")
                }
            }
        }
        .tint(t.accent)
    }

    // MARK: header (status line + emergency stop)

    private var headerCard: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(stats.hostCount) host\(stats.hostCount == 1 ? "" : "s") · \(stats.policyActive ? "policy active" : "no policy")")
                    .font(.dsSansPt(14, weight: .semibold))
                    .foregroundStyle(t.text)
                Text(stats.auditChainVerified ? "audit chain verified ✓" : "audit chain unverified")
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text3)
            }
            Spacer(minLength: 8)
            Button(role: .destructive) { confirmStop = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "stop.circle.fill")
                    Text("STOP").font(.dsSansPt(13, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14).frame(height: 40)
                .background(t.danger, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Emergency stop all agents")
            .confirmationDialog("Stop all running agents?", isPresented: $confirmStop, titleVisibility: .visible) {
                Button("Stop everything", role: .destructive, action: onEmergencyStop)
                Button("Cancel", role: .cancel) {}
            } message: { Text("Disconnects sessions and sends stop to every active run across your hosts.") }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(t.surface2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: section + card builders

    @ViewBuilder
    private func section<Content: View>(_ title: String, trailing: String? = nil, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.dsMonoPt(10, weight: .medium)).tracking(1.2).textCase(.uppercase)
                    .foregroundStyle(t.text4)
                if let trailing {
                    Text(trailing).font(.dsSansPt(10, weight: .bold)).foregroundStyle(.white)
                        .frame(minWidth: 18, minHeight: 18).padding(.horizontal, 4)
                        .background(t.accent, in: Capsule())
                }
                Spacer()
            }
            .padding(.horizontal, 4)
            VStack(spacing: 8) { content() }
        }
    }

    private func card(_ route: GovernanceRoute, icon: String, title: String, subtitle: String, tone: DSStatusDotTone? = nil) -> some View {
        NavigationLink(value: route) {
            HStack(spacing: 13) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .medium)).symbolRenderingMode(.hierarchical)
                    .foregroundStyle(t.text2).frame(width: 26)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.dsSansPt(15, weight: .semibold)).foregroundStyle(t.text)
                    Text(subtitle).font(.dsSansPt(12.5)).foregroundStyle(t.text3).lineLimit(2)
                }
                Spacer(minLength: 6)
                if let tone { DSStatusDot(tone: tone, pulse: false, size: 8) }
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(t.text4)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(t.surface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title). \(subtitle)")
    }
}

/// Placeholder detail used by the scaffold until a feature view is wired into the
/// `destination` closure in AppRoot. Real views replace these per-route.
public struct GovernancePlaceholder: View {
    let title: String
    @Environment(\.lancerTokens) private var t
    public init(title: String) { self.title = title }
    public var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "hammer").font(.system(size: 28)).foregroundStyle(t.text3)
            Text(title).font(.dsSansPt(16, weight: .semibold)).foregroundStyle(t.text)
            Text("Wiring in progress").font(.dsSansPt(13)).foregroundStyle(t.text3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(t.surface)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("Governance Home") {
    GovernanceHomeView(
        stats: GovernanceStats(
            hostCount: 3, policyActive: true, auditCount: 412, auditChainVerified: true,
            presetNames: ["prod-strict", "dev-relaxed"], providerCount: 3, roleLabel: "owner"
        ),
        onEmergencyStop: {},
        destination: { AnyView(GovernancePlaceholder(title: "\($0)")) }
    )
}
#endif
