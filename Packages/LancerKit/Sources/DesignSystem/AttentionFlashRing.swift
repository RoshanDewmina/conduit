// Adapted from cmux (MIT) — Sources/Panels/WorkspaceAttentionFlashRingView.swift
// + WorkspaceAttentionCoordinator (cmux-internal helpers we don't port).
//
// A rounded-rectangle ring that pulses on the leading edge of any
// `trigger` value change. Drop on top of a host row via `.overlay` to
// visually signal "this card needs your attention" — e.g. an approval
// landed, the session reconnected after a drop, or the agent emitted a
// notification. allowsHitTesting(false) so taps still pass through.

import SwiftUI

public enum AttentionFlashReason: Sendable, Hashable {
    /// Default — a generic "something happened" pulse.
    case generic
    /// An agent on the remote host needs human attention (approval, prompt).
    case approval
    /// The session just reconnected after a network drop.
    case reconnect
    /// A debug-only flash used to confirm wiring during development.
    case debug

    public var color: Color {
        switch self {
        case .generic:   .accentColor
        case .approval:  .orange
        case .reconnect: .green
        case .debug:     .pink
        }
    }

    public var glowRadius: CGFloat {
        switch self {
        case .approval:  6
        case .reconnect: 4
        default:         3
        }
    }
}

/// SwiftUI view that runs one pulse animation each time `trigger` changes.
/// Drop on a card via `.overlay { AttentionFlashRing(trigger: vm.attention) }`.
///
/// The `trigger` is `AnyHashable` so callers can pass anything — usually an
/// incrementing counter or a typed event id; SwiftUI fires the `.onChange`
/// when the boxed value changes.
public struct AttentionFlashRing: View {
    private let trigger: AnyHashable
    private let reason: AttentionFlashReason
    private let cornerRadius: CGFloat
    private let lineWidth: CGFloat
    private let inset: CGFloat
    private let duration: Double

    @State private var opacity: Double = 0

    public init(
        trigger: some Hashable & Sendable,
        reason: AttentionFlashReason = .generic,
        cornerRadius: CGFloat = 10,
        lineWidth: CGFloat = 2,
        inset: CGFloat = 0,
        duration: Double = 0.6
    ) {
        self.trigger = AnyHashable(trigger)
        self.reason = reason
        self.cornerRadius = cornerRadius
        self.lineWidth = lineWidth
        self.inset = inset
        self.duration = duration
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(reason.color.opacity(opacity), lineWidth: lineWidth)
            .shadow(
                color: reason.color.opacity(opacity * 0.8),
                radius: reason.glowRadius
            )
            .padding(inset)
            .allowsHitTesting(false)
            .onChange(of: trigger) { _, _ in
                pulse()
            }
    }

    private func pulse() {
        // Fade in fast, fade out slow — matches cmux's "attention" feel.
        withAnimation(.easeOut(duration: duration * 0.15)) {
            opacity = 1.0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration * 0.15) {
            withAnimation(.easeIn(duration: duration * 0.85)) {
                opacity = 0
            }
        }
    }
}

#if DEBUG
#Preview {
    struct PreviewHarness: View {
        @State private var trigger = 0
        var body: some View {
            VStack(spacing: 16) {
                ForEach(
                    [
                        AttentionFlashReason.generic,
                        .approval, .reconnect, .debug
                    ],
                    id: \.self
                ) { reason in
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.gray.opacity(0.2))
                        .frame(height: 80)
                        .overlay {
                            AttentionFlashRing(trigger: trigger, reason: reason)
                        }
                        .overlay(Text("\(String(describing: reason))").font(.caption))
                }
                Button("Pulse") { trigger += 1 }
                    .buttonStyle(.borderedProminent)
            }
            .padding()
            .preferredColorScheme(.dark)
        }
    }
    return PreviewHarness()
}
#endif
