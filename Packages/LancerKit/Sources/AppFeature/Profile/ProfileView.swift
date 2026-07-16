#if os(iOS)
import SwiftUI

/// Profile sheet — real pairing/device info only; no invented usage/streak.
/// Settings is pushed on this sheet's single `NavigationStack` (not a nested sheet).
public struct ProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(RelayFleetStore.self) private var relayFleetStore
    @State private var isTrustedMachinesPresented = false

    public init() {}

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 12)

                Divider()

                ScrollView {
                    VStack(spacing: 0) {
                        identitySection
                            .padding(.top, 28)

                        Divider()
                            .padding(.horizontal, 20)
                            .padding(.top, 28)

                        usagePlaceholderSection
                            .padding(.top, 24)

                        connectionsSection
                            .padding(.top, 28)

                        moreSection
                            .padding(.top, 28)

                        footer
                            .padding(.top, 28)
                            .padding(.bottom, 32)
                    }
                }
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationBarHidden(true)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $isTrustedMachinesPresented) {
            TrustedMachinesView()
                .environment(relayFleetStore)
        }
    }

    private var header: some View {
        ZStack {
            Text("Profile")
                .font(.title3.bold())
                .frame(maxWidth: .infinity)

            HStack {
                Button {
                    dismiss()
                } label: {
                    Circle()
                        .fill(Color(.secondarySystemBackground))
                        .overlay(
                            Circle()
                                .strokeBorder(Color(.separator), lineWidth: 0.5)
                        )
                        .frame(width: 46, height: 46)
                        .overlay(
                            Image(systemName: "xmark")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.primary)
                        )
                }
                .accessibilityLabel(Text("Close"))

                Spacer()
            }
        }
    }

    private var identitySection: some View {
        VStack(spacing: 8) {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.blue.opacity(0.75), Color.purple.opacity(0.65)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 152, height: 152)

            Text("Lancer")
                .font(.title2.bold())
                .padding(.top, 8)

            Text(machineSummary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
    }

    private var machineSummary: String {
        let usable = relayFleetStore.usableMachineCount
        if usable == 0 {
            return "No paired machines yet"
        }
        let names = relayFleetStore.machines
            .prefix(3)
            .map(\.record.displayName)
        if usable == 1, let name = names.first {
            return "Paired with \(name)"
        }
        return "\(usable) paired machines"
    }

    private var usagePlaceholderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProfileSectionHeader(title: "Usage")

            VStack(alignment: .leading, spacing: 8) {
                Text("Not available yet")
                    .font(.title3.bold())
                    .padding(.horizontal, 20)
                Text("Token usage, streaks, and plan details will show here when billing is wired.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
            }
        }
    }

    private var connectionsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProfileSectionHeader(title: "Connections")

            VStack(spacing: 0) {
                Button {
                    isTrustedMachinesPresented = true
                } label: {
                    ProfileRow(
                        systemImage: "desktopcomputer",
                        title: "Trusted Machines",
                        accessory: .value("\(relayFleetStore.usableMachineCount)")
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var moreSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProfileSectionHeader(title: "More")

            VStack(spacing: 0) {
                NavigationLink {
                    AppSettingsView(embedsInParentNavigation: true)
                        .environment(relayFleetStore)
                } label: {
                    ProfileRow(systemImage: "gearshape", title: "Settings", accessory: .chevron)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("profile.row.settings")

                Link(destination: URL(string: "https://github.com/RoshanDewmina/conduit/issues")!) {
                    ProfileRow(systemImage: "questionmark.circle", title: "Help", accessory: .externalLink)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("profile.row.help")
            }
        }
    }

    private var footer: some View {
        Text(Self.versionString)
            .font(.system(size: 11, weight: .regular, design: .monospaced))
            .foregroundStyle(Color(.tertiaryLabel))
            .frame(maxWidth: .infinity)
    }

    private static var versionString: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        switch (short, build) {
        case let (s?, b?):
            return "LANCER \(s) (\(b))"
        case let (s?, nil):
            return "LANCER \(s)"
        default:
            return "LANCER"
        }
    }
}

private struct ProfileSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
    }
}

private enum ProfileRowAccessory {
    case chevron
    case externalLink
    case value(String)
    case none
}

private struct ProfileRow: View {
    let systemImage: String
    let title: String
    let accessory: ProfileRowAccessory
    var isDestructive: Bool = false

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 19, weight: .regular))
                .foregroundStyle(isDestructive ? Color.red : .secondary)
                .frame(width: 24)

            Text(title)
                .font(.system(size: 17))
                .foregroundStyle(isDestructive ? Color.red : .primary)

            Spacer()

            switch accessory {
            case .chevron:
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(.tertiaryLabel))
            case .externalLink:
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(.tertiaryLabel))
            case .value(let text):
                Text(text)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(.tertiaryLabel))
            case .none:
                EmptyView()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

#Preview {
    ProfileView()
        .environment(RelayFleetStore())
}
#endif
