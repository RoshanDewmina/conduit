import Foundation
import LancerCore

/// One grouped step on a turn's flight-recorder timeline.
public struct FlightRecorderStep: Identifiable, Sendable, Hashable {
    public enum Kind: String, Sendable, Hashable {
        case dispatch
        case output
        case approval
        case question
        case receipt
        case exit
    }

    public let id: String
    public let kind: Kind
    public let title: String
    public let detail: String?
    public let offsetFromStart: TimeInterval
    public let duration: TimeInterval
    public let previewText: String?
    public let isPreviewTruncated: Bool
    public let risk: String?
    public let decision: String?
    public let latency: TimeInterval?
    public let seqStart: Int
    public let seqEnd: Int

    public init(
        id: String,
        kind: Kind,
        title: String,
        detail: String? = nil,
        offsetFromStart: TimeInterval,
        duration: TimeInterval,
        previewText: String? = nil,
        isPreviewTruncated: Bool = false,
        risk: String? = nil,
        decision: String? = nil,
        latency: TimeInterval? = nil,
        seqStart: Int,
        seqEnd: Int
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.offsetFromStart = offsetFromStart
        self.duration = duration
        self.previewText = previewText
        self.isPreviewTruncated = isPreviewTruncated
        self.risk = risk
        self.decision = decision
        self.latency = latency
        self.seqStart = seqStart
        self.seqEnd = seqEnd
    }
}

/// Assembled step timeline for one turn — never invents missing ledger rows.
public struct FlightRecorderTimeline: Sendable, Hashable {
    public let turnID: String?
    public let runID: String?
    public let turnStartedAt: Date?
    public let steps: [FlightRecorderStep]
    public let isIncomplete: Bool
    public let incompleteReason: String?
    public let totalDuration: TimeInterval

    public init(
        turnID: String?,
        runID: String?,
        turnStartedAt: Date?,
        steps: [FlightRecorderStep],
        isIncomplete: Bool,
        incompleteReason: String?,
        totalDuration: TimeInterval
    ) {
        self.turnID = turnID
        self.runID = runID
        self.turnStartedAt = turnStartedAt
        self.steps = steps
        self.isIncomplete = isIncomplete
        self.incompleteReason = incompleteReason
        self.totalDuration = totalDuration
    }
}

/// Pure events → steps assembly for Pocket Trace Review / Flight Recorder.
public enum FlightRecorderAssembler: Sendable {
    /// Matches Orca `native-chat-tool-fold` / tool-summary 4 KB result cap.
    public static let outputPreviewByteCap = 4096

    private static let terminalStatuses: Set<String> = [
        "completed", "exited", "failed", "cancelled", "error", "denied", "budgetExceeded",
    ]

    public static func assemble(
        events: [ChatEvent],
        turnID: String? = nil,
        runID: String? = nil
    ) -> FlightRecorderTimeline {
        let scoped = events.filter { event in
            if let turnID {
                return event.turnID == turnID
            }
            if let runID {
                return event.runID == runID
            }
            return true
        }
        .sorted { $0.seq < $1.seq }

        guard !scoped.isEmpty else {
            return FlightRecorderTimeline(
                turnID: turnID,
                runID: runID,
                turnStartedAt: nil,
                steps: [],
                isIncomplete: true,
                incompleteReason: "recording incomplete",
                totalDuration: 0
            )
        }

        let hasDispatch = scoped.contains { $0.kind == "turn_started" }
        let turnStartedAt = scoped.first(where: { $0.kind == "turn_started" })?.createdAt
            ?? scoped.first?.createdAt
        let start = turnStartedAt ?? scoped[0].createdAt

        var drafts: [StepDraft] = []
        var index = 0
        while index < scoped.count {
            let event = scoped[index]
            switch event.kind {
            case "turn_started":
                drafts.append(.init(
                    kind: .dispatch,
                    title: "Dispatch",
                    detail: event.runID.map { "run \($0)" },
                    events: [event]
                ))
                index += 1

            case "output":
                var burst: [ChatEvent] = [event]
                index += 1
                while index < scoped.count, scoped[index].kind == "output" {
                    burst.append(scoped[index])
                    index += 1
                }
                let joined = burst.compactMap(\.text).joined()
                let (preview, truncated) = cappedPreview(joined)
                let streams = Set(burst.compactMap(\.stream)).sorted()
                let streamLabel = streams.isEmpty ? "Output" : streams.joined(separator: "+")
                drafts.append(.init(
                    kind: .output,
                    title: streamLabel,
                    detail: "\(burst.count) chunk\(burst.count == 1 ? "" : "s")",
                    events: burst,
                    previewText: preview,
                    isPreviewTruncated: truncated
                ))

            case "approval":
                let meta = parseDecisionPayload(event.payloadJSON, eventCreatedAt: event.createdAt)
                drafts.append(.init(
                    kind: .approval,
                    title: "Approval",
                    detail: meta.detail,
                    events: [event],
                    risk: meta.risk,
                    decision: meta.decision,
                    latency: meta.latency
                ))
                index += 1

            case "question":
                let meta = parseDecisionPayload(event.payloadJSON, eventCreatedAt: event.createdAt)
                drafts.append(.init(
                    kind: .question,
                    title: "Question",
                    detail: meta.detail,
                    events: [event],
                    decision: meta.decision,
                    latency: meta.latency
                ))
                index += 1

            case "receipt":
                drafts.append(.init(
                    kind: .receipt,
                    title: "Receipt",
                    detail: receiptDetail(event.payloadJSON),
                    events: [event]
                ))
                index += 1

            case "status":
                let status = statusValue(event.payloadJSON) ?? "status"
                if terminalStatuses.contains(status) {
                    let exitCode = exitCodeValue(event.payloadJSON)
                    var detail = status
                    if let exitCode {
                        detail += " · exit \(exitCode)"
                    }
                    drafts.append(.init(
                        kind: .exit,
                        title: "Exit",
                        detail: detail,
                        events: [event]
                    ))
                }
                // Non-terminal status events are ledger noise for the step timeline.
                index += 1

            default:
                // Unknown kinds: do not invent steps.
                index += 1
            }
        }

        let endTimes = drafts.enumerated().map { i, draft -> Date in
            if i + 1 < drafts.count {
                return drafts[i + 1].events[0].createdAt
            }
            return draft.events.last?.createdAt ?? draft.events[0].createdAt
        }

        let steps: [FlightRecorderStep] = drafts.enumerated().map { i, draft in
            let first = draft.events[0]
            let last = draft.events.last ?? first
            let offset = first.createdAt.timeIntervalSince(start)
            let duration = max(0, endTimes[i].timeIntervalSince(first.createdAt))
            // Prefer intra-burst span when the next step shares the same timestamp.
            let burstSpan = max(0, last.createdAt.timeIntervalSince(first.createdAt))
            let resolvedDuration = duration > 0 ? duration : burstSpan
            return FlightRecorderStep(
                id: "\(draft.kind.rawValue)-\(first.seq)",
                kind: draft.kind,
                title: draft.title,
                detail: draft.detail,
                offsetFromStart: offset,
                duration: resolvedDuration,
                previewText: draft.previewText,
                isPreviewTruncated: draft.isPreviewTruncated,
                risk: draft.risk,
                decision: draft.decision,
                latency: draft.latency,
                seqStart: first.seq,
                seqEnd: last.seq
            )
        }

        let hasReceipt = steps.contains { $0.kind == .receipt }
        let hasExit = steps.contains { $0.kind == .exit }
        let incompleteReason: String?
        if !hasDispatch {
            incompleteReason = "recording incomplete"
        } else if hasExit && !hasReceipt {
            incompleteReason = "recording incomplete"
        } else {
            incompleteReason = nil
        }

        let totalDuration: TimeInterval = {
            guard let last = scoped.last else { return 0 }
            return max(0, last.createdAt.timeIntervalSince(start))
        }()

        return FlightRecorderTimeline(
            turnID: turnID ?? scoped.compactMap(\.turnID).first,
            runID: runID ?? scoped.compactMap(\.runID).first,
            turnStartedAt: turnStartedAt,
            steps: steps,
            isIncomplete: incompleteReason != nil,
            incompleteReason: incompleteReason,
            totalDuration: totalDuration
        )
    }

    // MARK: - Helpers

    private struct StepDraft {
        var kind: FlightRecorderStep.Kind
        var title: String
        var detail: String?
        var events: [ChatEvent]
        var previewText: String? = nil
        var isPreviewTruncated: Bool = false
        var risk: String? = nil
        var decision: String? = nil
        var latency: TimeInterval? = nil
    }

    private struct DecisionMeta {
        var risk: String?
        var decision: String?
        var latency: TimeInterval?
        var detail: String?
    }

    static func cappedPreview(_ text: String) -> (String, Bool) {
        let utf8 = Array(text.utf8)
        guard utf8.count > outputPreviewByteCap else { return (text, false) }
        var end = outputPreviewByteCap
        while end > 0 && (utf8[end] & 0b1100_0000) == 0b1000_0000 {
            end -= 1
        }
        let sliced = String(decoding: utf8[..<end], as: UTF8.self)
        return (sliced, true)
    }

    private static func parseDecisionPayload(_ payloadJSON: String?, eventCreatedAt: Date) -> DecisionMeta {
        guard let payloadJSON,
              let data = payloadJSON.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return DecisionMeta(risk: nil, decision: nil, latency: nil, detail: nil)
        }

        let risk: String? = {
            if let s = obj["risk"] as? String { return s }
            if let n = obj["risk"] as? NSNumber { return n.stringValue }
            if let i = obj["risk"] as? Int { return String(i) }
            return nil
        }()
        let decision = obj["decision"] as? String

        let latency: TimeInterval? = {
            if let n = obj["latencySeconds"] as? Double { return n }
            if let n = obj["latencySeconds"] as? Int { return TimeInterval(n) }
            if let n = obj["latency"] as? Double { return n }
            if let n = obj["decidedAtOffset"] as? Double { return n }
            if let n = obj["decidedAtOffset"] as? Int { return TimeInterval(n) }
            if let decidedAt = obj["decidedAt"] as? String,
               let date = ISO8601DateFormatter().date(from: decidedAt) {
                return date.timeIntervalSince(eventCreatedAt)
            }
            return nil
        }()

        var parts: [String] = []
        if let risk { parts.append("risk \(risk)") }
        if let decision { parts.append(decision) }
        if let latency {
            parts.append(String(format: "%.1fs", latency))
        }

        return DecisionMeta(
            risk: risk,
            decision: decision,
            latency: latency,
            detail: parts.isEmpty ? nil : parts.joined(separator: " · ")
        )
    }

    private static func statusValue(_ payloadJSON: String?) -> String? {
        guard let payloadJSON,
              let data = payloadJSON.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = obj["status"] as? String
        else { return nil }
        return status
    }

    private static func exitCodeValue(_ payloadJSON: String?) -> Int? {
        guard let payloadJSON,
              let data = payloadJSON.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        if let i = obj["exitCode"] as? Int { return i }
        if let n = obj["exitCode"] as? NSNumber { return n.intValue }
        return nil
    }

    private static func receiptDetail(_ payloadJSON: String?) -> String? {
        guard let payloadJSON,
              let data = payloadJSON.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        if let schema = obj["schema"] as? String { return schema }
        if let status = obj["status"] as? String { return status }
        return nil
    }
}
