#if os(iOS)
import SwiftUI
import DesignSystem
import AgentKit

// MARK: - Runner Setup: self-host vs hosted cloud

struct RunnerSetupView: View {
    @Binding var selectedChoice: HostedRuntimeChoice
    var onContinue: () -> Void

    @Environment(\.conduitTokens) private var t
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .top) {
            t.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                navBar
                headerSection
                choiceCards
                Spacer(minLength: 0)
                continueButton
            }
        }
        .navigationBarHidden(true)
    }

    // MARK: - Nav bar

    private var navBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(t.text)
                    .frame(width: 36, height: 36)
                    .background(t.surface2)
                    .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: t.r3, style: .continuous)
                            .strokeBorder(t.border, lineWidth: 1))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Text("Runner Setup")
                .font(.dsSansPt(17, weight: .semibold))
                .foregroundStyle(t.text)
            Spacer()
            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.horizontal, 22)
        .padding(.top, 60)
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
        .padding(.top, 18)
    }

    // MARK: - Choice cards

    private var choiceCards: some View {
        VStack(spacing: 14) {
            choiceCard(
                choice: .sshHost,
                title: "Self-host",
                subtitle: "Run conduitd on your own infrastructure",
                bullets: [
                    "Your hardware, your keys",
                    "Full control over runtime",
                ],
                accentBullet: "Free — no per-run fees",
                accentBulletColor: t.ok
            )
            choiceCard(
                choice: .cloud,
                title: "Hosted cloud",
                subtitle: "Let us manage the runner for you",
                bullets: [
                    "Zero setup — click to deploy",
                    "We run it, you ship",
                ],
                accentBullet: "Billed per compute hour",
                accentBulletColor: t.warn
            )
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
    }

    @ViewBuilder
    private func choiceCard(
        choice: HostedRuntimeChoice,
        title: String,
        subtitle: String,
        bullets: [String],
        accentBullet: String,
        accentBulletColor: Color
    ) -> some View {
        let isSelected = selectedChoice == choice
        Button {
            selectedChoice = choice
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
                    Text(title)
                        .font(.dsSansPt(14, weight: .semibold))
                        .foregroundStyle(t.text)
                    Text(subtitle)
                        .font(.dsMonoPt(10.5))
                        .foregroundStyle(t.text3)
                        .lineSpacing(1)
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(bullets, id: \.self) { bullet in
                            Text("• \(bullet)")
                                .font(.dsMonoPt(10))
                                .foregroundStyle(t.text2)
                        }
                        Text("• \(accentBullet)")
                            .font(.dsMonoPt(10))
                            .foregroundStyle(accentBulletColor)
                    }
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
        Button(action: onContinue) {
            Text("Continue with \(selectedChoice == .cloud ? "Hosted" : "Self-host")")
                .font(.dsSansPt(13, weight: .semibold))
                .foregroundStyle(t.accentFg)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
        }
        .background(t.accent)
        .clipShape(RoundedRectangle(cornerRadius: t.r2, style: .continuous))
        .padding(.horizontal, 22)
        .padding(.bottom, 10)
    }
}
#endif
