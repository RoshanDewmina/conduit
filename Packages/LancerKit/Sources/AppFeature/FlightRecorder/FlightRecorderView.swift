#if os(iOS)
import SwiftUI
import LancerCore
import PersistenceKit

/// Vertical step timeline for one turn — Pocket Trace Review / Flight Recorder.
public struct FlightRecorderView: View {
    let conversationID: String
    let turnID: String
    let prompt: String
    let runID: String?

    @Environment(\.dismiss) private var dismiss
    @State private var timeline: FlightRecorderTimeline?
    @State private var selectedIndex: Int = 0
    @State private var expandedOutputIDs: Set<String> = []
    @State private var loadError: String?

    public init(
        conversationID: String,
        turnID: String,
        prompt: String,
        runID: String? = nil
    ) {
        self.conversationID = conversationID
        self.turnID = turnID
        self.prompt = prompt
        self.runID = runID
    }

    public var body: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 4)

            if let loadError {
                Text(loadError)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let timeline {
                if timeline.isIncomplete {
                    incompleteBanner(timeline.incompleteReason ?? "recording incomplete")
                }

                if timeline.steps.isEmpty {
                    Text("No ledger events for this turn.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    scrubber(timeline)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)

                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(timeline.steps.enumerated()), id: \.element.id) { index, step in
                                    stepRow(step, index: index, isSelected: index == selectedIndex)
                                        .id(step.id)
                                    if index < timeline.steps.count - 1 {
                                        Rectangle()
                                            .fill(Color(.separator))
                                            .frame(width: 2, height: 16)
                                            .padding(.leading, 27)
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 32)
                        }
                        .onChange(of: selectedIndex) { _, newValue in
                            guard timeline.steps.indices.contains(newValue) else { return }
                            withAnimation(.easeInOut(duration: 0.2)) {
                                proxy.scrollTo(timeline.steps[newValue].id, anchor: .center)
                            }
                        }
                    }
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(.systemBackground))
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task { await load() }
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Circle()
                    .fill(Color(.secondarySystemBackground))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .medium))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Back"))

            Spacer()

            VStack(spacing: 2) {
                Text("Flight Recorder")
                    .font(.system(size: 17, weight: .semibold))
                Text(prompt)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Color.clear.frame(width: 40, height: 40)
        }
    }

    private func incompleteBanner(_ reason: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text(reason)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground))
    }

    private func scrubber(_ timeline: FlightRecorderTimeline) -> some View {
        let count = max(timeline.steps.count - 1, 1)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(formatOffset(timeline.steps[safe: selectedIndex]?.offsetFromStart ?? 0))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formatOffset(timeline.totalDuration))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: { Double(selectedIndex) },
                    set: { selectedIndex = Int($0.rounded()) }
                ),
                in: 0...Double(count),
                step: 1
            )
            .tint(.primary)
            .accessibilityLabel(Text("Scrub timeline"))
        }
    }

    private func stepRow(_ step: FlightRecorderStep, index: Int, isSelected: Bool) -> some View {
        Button {
            selectedIndex = index
            if step.kind == .output {
                toggleExpanded(step.id)
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.primary : Color(.tertiarySystemFill))
                        .frame(width: 22, height: 22)
                    Image(systemName: icon(for: step.kind))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isSelected ? Color(.systemBackground) : Color.secondary)
                }
                .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(step.title)
                            .font(.system(size: 15, weight: .semibold))
                        Spacer(minLength: 0)
                        Text(formatOffset(step.offsetFromStart))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    if let detail = step.detail {
                        Text(detail)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }

                    if step.kind == .approval || step.kind == .question {
                        approvalMeta(step)
                    }

                    if step.kind == .output, let preview = step.previewText {
                        outputPreview(step: step, preview: preview)
                    }

                    if step.duration > 0 {
                        Text(formatDuration(step.duration))
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func approvalMeta(_ step: FlightRecorderStep) -> some View {
        HStack(spacing: 8) {
            if let risk = step.risk {
                Text("Risk \(risk)")
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(Capsule())
            }
            if let decision = step.decision {
                Text(decision)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            if let latency = step.latency {
                Text(String(format: "%.1fs", latency))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func outputPreview(step: FlightRecorderStep, preview: String) -> some View {
        let expanded = expandedOutputIDs.contains(step.id)
        VStack(alignment: .leading, spacing: 4) {
            Text(expanded ? preview : collapsedPreview(preview))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            HStack(spacing: 6) {
                Text(expanded ? "Collapse" : "Expand")
                    .font(.system(size: 12, weight: .medium))
                if step.isPreviewTruncated {
                    Text("· capped 4KB")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(.secondary)
        }
    }

    private func collapsedPreview(_ text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        if lines.count <= 3, text.count <= 180 { return text }
        let head = lines.prefix(3).joined(separator: "\n")
        let clipped = head.count > 180 ? String(head.prefix(180)) : head
        return clipped + "…"
    }

    private func toggleExpanded(_ id: String) {
        if expandedOutputIDs.contains(id) {
            expandedOutputIDs.remove(id)
        } else {
            expandedOutputIDs.insert(id)
        }
    }

    private func icon(for kind: FlightRecorderStep.Kind) -> String {
        switch kind {
        case .dispatch: return "paperplane"
        case .output: return "text.alignleft"
        case .tool: return "wrench"
        case .approval: return "checkmark.shield"
        case .question: return "questionmark"
        case .receipt: return "doc.text"
        case .exit: return "flag"
        }
    }

    private func formatOffset(_ t: TimeInterval) -> String {
        if t < 60 { return String(format: "+%.1fs", t) }
        let m = Int(t) / 60
        let s = t.truncatingRemainder(dividingBy: 60)
        return String(format: "+%dm %.0fs", m, s)
    }

    private func formatDuration(_ t: TimeInterval) -> String {
        String(format: "%.1fs", t)
    }

    private func load() async {
        do {
            let db = try AppDatabase.openShared()
            let repo = ChatConversationRepository(db)
            let events = try await repo.events(conversationID: conversationID, sinceSeq: 0, limit: 10_000)
            timeline = FlightRecorderAssembler.assemble(
                events: events,
                turnID: turnID,
                runID: runID
            )
        } catch {
            loadError = "Couldn't load recording."
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
#endif
