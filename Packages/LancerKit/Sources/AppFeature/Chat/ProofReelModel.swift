import Foundation
import LancerCore
import os

/// Derives a chronologically ordered scrub timeline from a `ProofReceipt`.
///
/// Also decodes receipt payloads from the shapes `ChatConversationRepository`
/// stores: `.receipt` artifacts and mirrored `chat_events` rows (`kind == "receipt"`).
public enum ProofReelModel {
    private static let logger = Logger(subsystem: "dev.lancer.mobile", category: "ProofReel")

    public enum StopKind: Equatable, Sendable {
        case command(ProofReceipt.Command)
        case file(ProofReceipt.FileTouched)
        case criterion(ProofReceipt.Criterion)
        // Reserved for Lane E question-ladder answers once `answersReserved` is typed.
        // case answer(key: String, value: String)
    }

    public struct Stop: Equatable, Sendable, Identifiable {
        public let id: Int
        public let kind: StopKind
        /// Stable ordering key for tests — lower sorts earlier.
        public let orderKey: Int

        public init(id: Int, kind: StopKind, orderKey: Int) {
            self.id = id
            self.kind = kind
            self.orderKey = orderKey
        }
    }

    public struct ScrubState: Equatable, Sendable {
        public let index: Int
        public let stop: Stop
        public let stopCount: Int
        public let progress: Double

        public var isAtStart: Bool { index == 0 }
        public var isAtEnd: Bool { index >= stopCount - 1 }
    }

    // MARK: - Decode (artifact / event shapes)

    public static func decodeReceipt(from artifact: ChatArtifact) -> ProofReceipt? {
        guard artifact.kind == .receipt else { return nil }
        return decodeReceiptPayload(artifact.payloadJSON)
    }

    /// Host ledger mirrors receipts as `conversation_events` kind `"receipt"`;
    /// the phone stores the same row via `appendEventsMirror`.
    public static func decodeReceipt(from event: ChatEvent) -> ProofReceipt? {
        guard event.kind == "receipt" else { return nil }
        guard let payload = event.payloadJSON else { return nil }
        return decodeReceiptPayload(payload)
    }

    public static func decodeReceiptPayload(_ payloadJSON: String) -> ProofReceipt? {
        guard let data = payloadJSON.data(using: .utf8) else {
            logger.error("Receipt payload is not valid UTF-8")
            return nil
        }
        do {
            return try JSONDecoder().decode(ProofReceipt.self, from: data)
        } catch {
            logger.error("Receipt decode failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Stops

    /// Builds the proof-reel stop sequence for `receipt`.
    ///
    /// Ordering heuristic (raw receipt data lacks a single global event clock):
    /// 1. **Commands** — those with `startedAt` sort by parsed timestamp ascending;
    ///    ties and commands missing `startedAt` keep receipt-array order after all
    ///    timestamped commands.
    /// 2. **Files touched** — no per-file timestamps; appended in receipt order after
    ///    all commands (files represent work product produced during command execution).
    /// 3. **Criteria** — no timestamps; appended in receipt order after files (criteria
    ///    are evaluated at run completion).
    /// 4. **`answersReserved`** — not rendered until Lane E defines question/answer shape.
    public static func stops(from receipt: ProofReceipt) -> [Stop] {
        var entries: [(orderKey: Int, kind: StopKind)] = []
        var orderKey = 0

        let commands = receipt.commands ?? []
        let dated = commands.enumerated().compactMap { index, command -> (Int, Int, ProofReceipt.Command)? in
            guard let startedAt = command.startedAt,
                  let date = iso8601Date(from: startedAt) else { return nil }
            return (index, Int(date.timeIntervalSince1970), command)
        }
        let undated = commands.enumerated().filter {
            $0.element.startedAt == nil || iso8601Date(from: $0.element.startedAt) == nil
        }

        for item in dated.sorted(by: { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
            return lhs.0 < rhs.0
        }) {
            entries.append((orderKey, .command(item.2)))
            orderKey += 1
        }
        for item in undated.sorted(by: { $0.offset < $1.offset }) {
            entries.append((orderKey, .command(item.element)))
            orderKey += 1
        }

        for file in receipt.filesTouched ?? [] {
            entries.append((orderKey, .file(file)))
            orderKey += 1
        }

        for criterion in receipt.criteria ?? [] {
            entries.append((orderKey, .criterion(criterion)))
            orderKey += 1
        }

        return entries.enumerated().map { index, entry in
            Stop(id: index, kind: entry.kind, orderKey: entry.orderKey)
        }
    }

    public static func scrubState(stops: [Stop], index: Int) -> ScrubState? {
        guard !stops.isEmpty, index >= 0, index < stops.count else { return nil }
        let clamped = max(0, min(index, stops.count - 1))
        let progress = stops.count == 1 ? 1.0 : Double(clamped) / Double(stops.count - 1)
        return ScrubState(
            index: clamped,
            stop: stops[clamped],
            stopCount: stops.count,
            progress: progress
        )
    }

    public static func scrubState(stops: [Stop], progress: Double) -> ScrubState? {
        guard !stops.isEmpty else { return nil }
        let clampedProgress = max(0, min(progress, 1))
        let index = Int((clampedProgress * Double(stops.count - 1)).rounded())
        return scrubState(stops: stops, index: index)
    }

    public static func stopLabel(for stop: Stop) -> String {
        switch stop.kind {
        case .command:
            return "Command"
        case .file:
            return "File"
        case .criterion:
            return "Criterion"
        }
    }

    /// Observed duration between receipt timestamps — never claims wall-clock accuracy.
    public static func durationText(startedAt: String?, endedAt: String?) -> String? {
        guard let start = iso8601Date(from: startedAt),
              let end = iso8601Date(from: endedAt) else { return nil }
        let seconds = max(0, end.timeIntervalSince(start))
        if seconds < 60 {
            return String(format: "%.1fs", seconds)
        }
        let minutes = Int(seconds) / 60
        let remainder = Int(seconds) % 60
        return "\(minutes)m \(remainder)s"
    }

    public static func shortGitRef(_ ref: String?) -> String? {
        guard let ref, !ref.isEmpty else { return nil }
        if ref.count <= 7 { return ref }
        return String(ref.prefix(7))
    }

    /// Localized display for a receipt/command ISO8601 timestamp; nil if unparseable.
    public static func localizedTimestamp(_ raw: String?) -> String? {
        guard let date = iso8601Date(from: raw) else { return nil }
        return localizedTimestampFormatter.string(from: date)
    }

    static func iso8601Date(from raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: raw) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }

    private static let localizedTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()
}
