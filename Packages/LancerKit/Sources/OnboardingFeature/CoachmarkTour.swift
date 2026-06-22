#if os(iOS)
import SwiftUI
import DesignSystem

// MARK: - CoachmarkTour
//
// A generic, reusable interactive coach-mark (spotlight) tour engine, decoupled
// from any specific app screen. Any view can register itself as a tour target
// via `.coachmarkAnchor("someID")`; a `CoachmarkTourState` drives a sequence of
// `CoachmarkStep`s; `.coachmarkTour(state)` installs the full-screen scrim +
// callout overlay that resolves those anchors and walks the user through them.
//
// Usage sketch (see the bottom of this file for a self-contained `#Preview`):
//
//   var body: some View {
//       MyScreen()
//           .coachmarkAnchor("newChat")   // on the target view
//           .coachmarkTour(tourState)     // once, near the root
//   }
//
//   let tourState = CoachmarkTourState(steps: [
//       CoachmarkStep(id: "newChat", targetID: "newChat", title: "Start a thread", body: "…"),
//   ])
//   tourState.start()

// MARK: - Anchor registration (PreferenceKey)

/// Collects `{ id: Anchor<CGRect> }` pairs from every `.coachmarkAnchor(_:)` view
/// in the hierarchy, so a single overlay near the root can resolve all of them
/// against its own coordinate space via `.overlayPreferenceValue`.
public struct CoachmarkAnchorPreferenceKey: PreferenceKey {
    public static var defaultValue: [String: Anchor<CGRect>] { [:] }

    public static func reduce(
        value: inout [String: Anchor<CGRect>],
        nextValue: () -> [String: Anchor<CGRect>]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

public extension View {
    /// Registers this view as a named coach-mark target. The overlay installed by
    /// `.coachmarkTour(_:)` resolves this anchor's frame (in the overlay's local
    /// coordinate space) to draw the spotlight cut-out and callout around it.
    func coachmarkAnchor(_ id: String) -> some View {
        anchorPreference(key: CoachmarkAnchorPreferenceKey.self, value: .bounds) { anchor in
            [id: anchor]
        }
    }
}

// MARK: - CoachmarkStep

/// One stop in a coach-mark tour. `targetID == nil` renders a centered card with
/// no spotlight cut-out (useful for an intro/outro step with no specific anchor).
public struct CoachmarkStep: Identifiable, Equatable, Sendable {
    public let id: String
    public let targetID: String?
    public let title: String
    public let body: String
    public let systemImage: String?
    public let usesPixelBoxHero: Bool
    public let primaryActionTitle: String?

    public init(
        id: String,
        targetID: String? = nil,
        title: String,
        body: String,
        systemImage: String? = nil,
        usesPixelBoxHero: Bool = false,
        primaryActionTitle: String? = nil
    ) {
        self.id = id
        self.targetID = targetID
        self.title = title
        self.body = body
        self.systemImage = systemImage
        self.usesPixelBoxHero = usesPixelBoxHero
        self.primaryActionTitle = primaryActionTitle
    }

    public static func == (lhs: CoachmarkStep, rhs: CoachmarkStep) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - CoachmarkTourState

/// Drives a sequence of `CoachmarkStep`s. Owns only sequencing state — the
/// overlay (`CoachmarkOverlay`) is purely a function of this state plus the
/// resolved anchor rects.
@MainActor
@Observable
public final class CoachmarkTourState {
    public private(set) var steps: [CoachmarkStep]
    public private(set) var index: Int = 0
    public private(set) var isActive: Bool = false

    public init(steps: [CoachmarkStep] = []) {
        self.steps = steps
    }

    public var currentStep: CoachmarkStep? {
        guard isActive, steps.indices.contains(index) else { return nil }
        return steps[index]
    }

    public var isLastStep: Bool { index >= steps.count - 1 }
    public var stepNumber: Int { index + 1 }
    public var stepCount: Int { steps.count }

    /// Replace the step sequence (e.g. once the host screen knows its real
    /// anchors). Resets to the first step.
    public func configure(steps: [CoachmarkStep]) {
        self.steps = steps
        self.index = 0
    }

    public func start() {
        guard !steps.isEmpty else { return }
        index = 0
        isActive = true
    }

    public func advance() {
        guard isActive else { return }
        if isLastStep {
            finish()
        } else {
            index += 1
        }
    }

    public func skip() {
        finish()
    }

    public func finish() {
        isActive = false
        Self.markSeen()
    }

    // MARK: Persistence — `UserDefaults`-backed "have they seen the tour" flag.
    // Exposed as static members so the host app can gate `start()` without
    // needing a live `CoachmarkTourState` instance up front.

    private static let seenKey = "lancer.tour.seen"

    public static var hasSeenTour: Bool {
        UserDefaults.standard.bool(forKey: seenKey)
    }

    public static func markSeen() {
        UserDefaults.standard.set(true, forKey: seenKey)
    }

    /// Test/debug helper — clears the persisted flag so the tour can replay.
    public static func resetSeen() {
        UserDefaults.standard.removeObject(forKey: seenKey)
    }
}

// MARK: - Motion helper
//
// This package doesn't (yet) expose a shared `LancerMotion` helper, so the
// coach-mark engine derives its own reduce-motion-aware springs/eases inline —
// mirroring the pattern `PixelBox` already uses (collapse to a still/instant
// equivalent under `accessibilityReduceMotion`).
private enum CoachmarkMotion {
    static func transition(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.01) : .spring(response: 0.42, dampingFraction: 0.82)
    }

    static func pulse(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeInOut(duration: 1.1).repeatForever(autoreverses: true)
    }
}

// MARK: - CoachmarkOverlay

/// Full-screen scrim + spotlight cut-out + callout card for the tour's current
/// step. Installed by `.coachmarkTour(_:)` above the host content; reads anchor
/// rects via `.overlayPreferenceValue(CoachmarkAnchorPreferenceKey.self)`.
private struct CoachmarkOverlay: View {
    @Bindable var state: CoachmarkTourState
    let anchors: [String: Anchor<CGRect>]

    @Environment(\.lancerTokens) private var t
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            if let step = state.currentStep {
                ZStack {
                    scrim(step: step, proxy: proxy)

                    if let targetID = step.targetID, let anchor = anchors[targetID] {
                        let rect = proxy[anchor]
                        focusRing(around: rect)
                        callout(for: step, targetRect: rect, in: proxy.size)
                    } else {
                        callout(for: step, targetRect: nil, in: proxy.size)
                    }
                }
                .transition(.opacity)
                .animation(CoachmarkMotion.transition(reduceMotion: reduceMotion), value: step.id)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(state.isActive)
    }

    // MARK: Scrim with spotlight cut-out

    @ViewBuilder
    private func scrim(step: CoachmarkStep, proxy: GeometryProxy) -> some View {
        let cutout: CGRect? = step.targetID.flatMap { anchors[$0] }.map { proxy[$0] }
        Color.black.opacity(0.62)
            .compositingGroup()
            .mask(
                ScrimMaskShape(cutout: cutout, cornerRadius: t.r3, inset: 8)
                    .fill(style: FillStyle(eoFill: true))
            )
            // Tapping the scrim itself is a deliberate no-op — only the callout's
            // explicit buttons (primary / skip) advance or dismiss the tour.
            .onTapGesture { }
    }

    // MARK: Focus ring

    @ViewBuilder
    private func focusRing(around rect: CGRect) -> some View {
        let inset: CGFloat = 8
        let ringRect = rect.insetBy(dx: -inset, dy: -inset)
        let corner = t.r3 + inset * 0.5
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            // `cycle` runs 0→1 each ~1.6s; `breathe` is a smooth 0↔1 sine.
            let phase = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            let cycle = reduceMotion ? 0 : (phase.truncatingRemainder(dividingBy: 1.6) / 1.6)
            let breathe = reduceMotion ? 0 : (0.5 + 0.5 * sin(phase * 3.0))
            ZStack {
                // Expanding "radar" pulse: grows outward and fades, on a loop.
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(t.accent.opacity(reduceMotion ? 0 : (1 - cycle) * 0.7), lineWidth: 2.5)
                    .frame(width: ringRect.width, height: ringRect.height)
                    .scaleEffect(1 + 0.28 * cycle)
                // Solid breathing ring on the target.
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(t.accent.opacity(0.95), lineWidth: 2.5)
                    .frame(width: ringRect.width, height: ringRect.height)
                    .shadow(color: t.accent.opacity(0.5 + 0.4 * breathe), radius: 7 + 9 * breathe)
                    .scaleEffect(1 + 0.04 * breathe)
            }
            .position(x: ringRect.midX, y: ringRect.midY)
            .accessibilityHidden(true)
        }
    }

    // MARK: Callout card

    private func callout(for step: CoachmarkStep, targetRect: CGRect?, in containerSize: CGSize) -> some View {
        CoachmarkCalloutCard(
            step: step,
            stepNumber: state.stepNumber,
            stepCount: state.stepCount,
            isLastStep: state.isLastStep,
            onPrimary: { Haptics.light(); state.advance() },
            onSkip: { Haptics.selection(); state.skip() }
        )
        .frame(maxWidth: min(containerSize.width - 32, 360))
        .position(calloutPosition(for: targetRect, containerSize: containerSize))
    }

    /// Places the callout just below the target (or centered, if no target /
    /// the target is in the lower half of the screen — then place above it).
    private func calloutPosition(for targetRect: CGRect?, containerSize: CGSize) -> CGPoint {
        guard let rect = targetRect else {
            return CGPoint(x: containerSize.width / 2, y: containerSize.height / 2)
        }
        let cardHalfHeight: CGFloat = 110
        let margin: CGFloat = 24
        let placeBelow = rect.maxY + margin + cardHalfHeight < containerSize.height - 16
        let y = placeBelow
            ? rect.maxY + margin + cardHalfHeight
            : max(cardHalfHeight + 16, rect.minY - margin - cardHalfHeight)
        let x = min(max(containerSize.width / 2, 180), containerSize.width - 180)
        return CGPoint(x: x, y: y)
    }
}

/// Even-odd scrim mask: the full-bleed rect, minus an optional rounded-rect
/// cut-out around the current target. Filled with `FillStyle(eoFill: true)` by
/// the caller so the cut-out reads as a hole rather than a second filled shape.
private struct ScrimMaskShape: Shape {
    let cutout: CGRect?
    let cornerRadius: CGFloat
    let inset: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        if let cutout {
            let hole = cutout.insetBy(dx: -inset, dy: -inset)
            path.addPath(Path(roundedRect: hole, cornerRadius: cornerRadius + inset * 0.5))
        }
        return path
    }
}

// MARK: - Callout card content

private struct CoachmarkCalloutCard: View {
    let step: CoachmarkStep
    let stepNumber: Int
    let stepCount: Int
    let isLastStep: Bool
    let onPrimary: () -> Void
    let onSkip: () -> Void

    @Environment(\.lancerTokens) private var t

    private var primaryTitle: String {
        step.primaryActionTitle ?? (isLastStep ? "Got it" : "Next")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: t.s4) {
            HStack(spacing: t.s4) {
                hero
                VStack(alignment: .leading, spacing: 2) {
                    Text(step.title)
                        .font(.dsSansPt(15, weight: .semibold))
                        .foregroundStyle(t.text)
                    Text("\(stepNumber) of \(stepCount)")
                        .font(.dsSansPt(11))
                        .foregroundStyle(t.text3)
                }
                Spacer(minLength: 0)
            }

            Text(step.body)
                .font(.dsSansPt(13))
                .foregroundStyle(t.text2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: t.s4) {
                Button("Skip tour", action: onSkip)
                    .font(.dsSansPt(12, weight: .medium))
                    .foregroundStyle(t.text3)
                    .buttonStyle(.plain)

                Spacer(minLength: 0)

                DSButton(primaryTitle, variant: .accent, size: .sm, action: onPrimary)
            }
        }
        .padding(t.s5)
        .background(t.surface)
        .clipShape(RoundedRectangle(cornerRadius: t.r4, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: t.r4, style: .continuous)
                .strokeBorder(t.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.28), radius: 24, y: 8)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var hero: some View {
        if step.usesPixelBoxHero {
            PixelBox(state: .thinking, size: 7, gap: 1.5)
                .frame(width: 28, height: 28)
        } else if let symbol = step.systemImage {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(t.accent)
                .frame(width: 28, height: 28)
        }
    }
}

// MARK: - .coachmarkTour(_:) modifier

private struct CoachmarkTourModifier: ViewModifier {
    @Bindable var state: CoachmarkTourState

    func body(content: Content) -> some View {
        content
            .overlayPreferenceValue(CoachmarkAnchorPreferenceKey.self) { anchors in
                CoachmarkOverlay(state: state, anchors: anchors)
            }
    }
}

public extension View {
    /// Installs the coach-mark tour overlay above this view's content. Place it
    /// near the screen root that contains all `.coachmarkAnchor(_:)` targets the
    /// tour references — anchors are resolved relative to this view's geometry.
    func coachmarkTour(_ state: CoachmarkTourState) -> some View {
        modifier(CoachmarkTourModifier(state: state))
    }
}

// MARK: - Preview

#Preview("Coachmark Tour") {
    CoachmarkTourDemoScreen()
}

private struct CoachmarkTourDemoScreen: View {
    @State private var tour = CoachmarkTourState(steps: [
        CoachmarkStep(
            id: "newChat",
            targetID: "newChat",
            title: "Start a new thread",
            body: "Tap here any time to spin up a fresh chat with an agent.",
            systemImage: "plus.bubble",
            primaryActionTitle: "Next"
        ),
        CoachmarkStep(
            id: "inbox",
            targetID: "inbox",
            title: "Approvals live here",
            body: "Anything that needs your sign-off — risky commands, spend limits — surfaces in the Inbox.",
            usesPixelBoxHero: true,
            primaryActionTitle: "Next"
        ),
        CoachmarkStep(
            id: "settings",
            targetID: "settings",
            title: "You're set",
            body: "Connection, security, and billing all live in Settings. That's the whole tour.",
            systemImage: "checkmark.circle",
            primaryActionTitle: "Got it"
        ),
    ])

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("Lancer")
                .font(.dsSansPt(20, weight: .semibold))

            Spacer()

            HStack(spacing: 32) {
                Image(systemName: "plus.bubble.fill")
                    .font(.system(size: 22))
                    .frame(width: 44, height: 44)
                    .coachmarkAnchor("newChat")

                Image(systemName: "tray.fill")
                    .font(.system(size: 22))
                    .frame(width: 44, height: 44)
                    .coachmarkAnchor("inbox")

                Image(systemName: "gearshape.fill")
                    .font(.system(size: 22))
                    .frame(width: 44, height: 44)
                    .coachmarkAnchor("settings")
            }
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .lancerTokens()
        .coachmarkTour(tour)
        .task {
            tour.start()
        }
    }
}
#endif
