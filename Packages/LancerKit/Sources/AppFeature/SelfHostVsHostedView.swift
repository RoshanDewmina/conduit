#if os(iOS)
import SwiftUI
import DesignSystem
import AgentKit

// MARK: - Self-host vs Hosted cloud choice

public struct SelfHostVsHostedView: View {
    @Binding var selection: HostedRuntimeChoice
    var onContinue: () -> Void

    @Environment(\.lancerTokens) private var t

    public init(selection: Binding<HostedRuntimeChoice>, onContinue: @escaping () -> Void) {
        self._selection = selection
        self.onContinue = onContinue
    }

    public var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                headerSection
                choiceCards
                Spacer(minLength: 0)
                continueButton
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Where should\nagents run?")
                .font(.dsDisplayPt(21, weight: .bold))
                .foregroundStyle(t.text)
                .lineSpacing(2)
            Text("Choose how to execute agent workloads")
                .font(.dsMonoPt(11))
                .foregroundStyle(t.text3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 22)
        .padding(.top, 60)
    }

    // MARK: - Choice cards

    private var choiceCards: some View {
        VStack(spacing: 14) {
            choiceCard(
                choice: .sshHost,
                icon: .server,
                title: "Self-host",
                description: "Run lancerd on your own infrastructure. Free, full control.",
                badge: "Free",
                badgeTone: .ok
            )
            choiceCard(
                choice: .cloud,
                icon: .globe,
                title: "Hosted cloud",
                description: "Managed runner, zero setup, billed per compute hour.",
                badge: "From $0.10/hr",
                badgeTone: .warn
            )
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
    }

    @ViewBuilder
    private func choiceCard(
        choice: HostedRuntimeChoice,
        icon: DSIcon,
        title: String,
        description: String,
        badge: String,
        badgeTone: DSChipTone
    ) -> some View {
        let isSelected = selection == choice
        Button {
            selection = choice
        } label: {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .strokeBorder(isSelected ? t.accent : t.text4, lineWidth: 2)
                        .frame(width: 20, height: 20)
                    if isSelected {
                        Circle()
                            .fill(t.accent)
                            .frame(width: 10, height: 10)
                            .overlay(
                                Circle()
                                    .fill(.white)
                                    .frame(width: 4, height: 4))
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        DSIconView(icon, size: 16, color: isSelected ? t.accent : t.text2)
                        Text(title)
                            .font(.dsSansPt(14, weight: .semibold))
                            .foregroundStyle(t.text)
                    }
                    Text(description)
                        .font(.dsMonoPt(10.5))
                        .foregroundStyle(t.text3)
                        .lineSpacing(1)
                    DSChip(badge, tone: badgeTone, variant: .outlined, size: .sm)
                        .padding(.top, 2)
                }
                Spacer()
            }
            .padding(16)
            .background(t.surface)
            .clipShape(RoundedRectangle(cornerRadius: t.r2, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: t.r2, style: .continuous)
                    .strokeBorder(isSelected ? t.accent : t.border, lineWidth: isSelected ? 2 : 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Continue button

    private var continueButton: some View {
        DSButton(
            "Continue with \(selection == .cloud ? "Hosted" : "Self-host")",
            variant: .primary,
            fullWidth: true,
            action: onContinue
        )
        .padding(.horizontal, 22)
        .padding(.bottom, 10)
    }
}
#endif
