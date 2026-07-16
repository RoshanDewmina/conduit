#if os(iOS)
import SwiftUI
import OnboardingFeature
import LancerCore

/// Minimal first-run welcome: one-sentence product pitch, Pair CTA → real
/// `RelayPairingSheet`, caution-tier picker → `OnboardingPolicy`, skippable.
public struct FirstRunOnboardingView: View {
    @Environment(RelayFleetStore.self) private var relayFleetStore

    let onFinished: () -> Void

    @State private var cautionLevel: OnboardingCautionLevel = .balanced
    @State private var isPairingPresented = false

    /// Warm-orange accent fill — matches historical `DSButton` `.accent`
    /// (DesignSystem was removed with the Cursor shell; do not use white `.primary`).
    private static let accentOrange = Color(red: 0.93, green: 0.45, blue: 0.22)

    public init(onFinished: @escaping () -> Void) {
        self.onFinished = onFinished
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Lancer")
                        .font(.largeTitle.bold())
                    Text("Steer AI coding agents on your Mac from this phone — approve risky actions without opening a laptop.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("How cautious?")
                        .font(.headline)
                    ForEach(OnboardingCautionLevel.allCases) { level in
                        cautionRow(level)
                    }
                }

                VStack(spacing: 12) {
                    Button {
                        isPairingPresented = true
                    } label: {
                        Text("Pair your Mac")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .background(Self.accentOrange)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityIdentifier("onboarding.pair")

                    Button("Set up later") {
                        finish(with: cautionLevel)
                    }
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .accessibilityIdentifier("onboarding.skip")
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 48)
            .padding(.bottom, 32)
        }
        .background(Color.black.ignoresSafeArea())
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $isPairingPresented) {
            RelayPairingSheet(existingMachineCount: relayFleetStore.usableMachineCount) { client, record in
                RelayFleetHydration.addMachine(client: client, record: record, to: relayFleetStore)
                // Sheet dismisses itself after a brief paired confirmation.
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 950_000_000)
                    finish(with: cautionLevel)
                }
            }
            .environment(relayFleetStore)
        }
    }

    @ViewBuilder
    private func cautionRow(_ level: OnboardingCautionLevel) -> some View {
        let selected = cautionLevel == level
        Button {
            cautionLevel = level
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Self.accentOrange : .secondary)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(level.title)
                            .font(.body.weight(.semibold))
                        if level.recommended {
                            Text("Recommended")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Self.accentOrange)
                        }
                    }
                    Text(level.detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(level.mappedPreset.label)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(selected ? 0.12 : 0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? Self.accentOrange.opacity(0.8) : Color.white.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("onboarding.caution.\(level.rawValue)")
    }

    private func finish(with level: OnboardingCautionLevel) {
        // Persist starter policy for the next successful daemon connect
        // (`OnboardingPolicy.applyPendingIfNeeded`). Caution tier →
        // AutonomyPreset is `level.mappedPreset` (shown on each row).
        OnboardingPolicy.markPending(level)
        onFinished()
    }
}
#endif
