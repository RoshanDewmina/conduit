import Foundation
import LancerCore
import AgentKit

/// Pure presentation + action logic for a persisted run proof receipt artifact.
public enum ReceiptCardModel {
    public struct CriterionRow: Equatable, Sendable {
        public let text: String
        public let status: ProofReceipt.Criterion.Status
        public let evidence: String?

        public init(text: String, status: ProofReceipt.Criterion.Status, evidence: String? = nil) {
            self.text = text
            self.status = status
            self.evidence = evidence
        }
    }

    public struct FileRow: Equatable, Sendable {
        public let path: String
        public let additions: Int
        public let deletions: Int

        public init(path: String, additions: Int, deletions: Int) {
            self.path = path
            self.additions = additions
            self.deletions = deletions
        }
    }

    public struct CommandRow: Equatable, Sendable {
        public let command: String
        public let exitCode: Int?

        public init(command: String, exitCode: Int? = nil) {
            self.command = command
            self.exitCode = exitCode
        }
    }

    // MARK: - Decode

    public static func decodeReceipt(from artifact: ChatArtifact) -> ProofReceipt? {
        guard artifact.kind == .receipt else { return nil }
        guard let data = artifact.payloadJSON.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ProofReceipt.self, from: data)
    }

    public static func acceptedAt(in payloadJSON: String) -> Date? {
        guard let data = payloadJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = object["acceptedAt"] as? String else { return nil }
        return iso8601Date(from: raw)
    }

    public static func isAccepted(payloadJSON: String) -> Bool {
        acceptedAt(in: payloadJSON) != nil
    }

    // MARK: - Mutations

    public static func mergeAcceptedAt(into payloadJSON: String, at date: Date = .now) -> String? {
        guard var object = jsonObject(from: payloadJSON) else { return nil }
        object["acceptedAt"] = iso8601String(from: date)
        return encodeJSONObject(object)
    }

    // MARK: - Derived display

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

    public static func criteriaRows(receipt: ProofReceipt) -> [CriterionRow] {
        if let criteria = receipt.criteria, !criteria.isEmpty {
            return criteria.map { CriterionRow(text: $0.text, status: $0.status, evidence: $0.evidence) }
        }
        return receipt.contract?.doneCriteria.map {
            CriterionRow(text: $0, status: .unknown, evidence: nil)
        } ?? []
    }

    public static func fileRows(receipt: ProofReceipt) -> [FileRow] {
        receipt.filesTouched?.map {
            FileRow(path: $0.path, additions: $0.additions, deletions: $0.deletions)
        } ?? []
    }

    public static func commandRows(receipt: ProofReceipt) -> [CommandRow] {
        receipt.commands?.map {
            CommandRow(command: $0.command, exitCode: $0.exitCode)
        } ?? []
    }

    public static func testsSummaryText(_ tests: ProofReceipt.TestsSummary?) -> String? {
        guard let tests else { return nil }
        guard tests.ran else { return "No tests recorded" }
        if tests.failed == 0 {
            return "\(tests.passed) passed"
        }
        return "\(tests.passed) passed · \(tests.failed) failed"
    }

    public static func confidenceCaption(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        switch value {
        case "complete": return "Complete capture"
        case "bestEffort": return "Best-effort capture"
        case "partial": return "Partial capture"
        default: return value.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
            .capitalized
        }
    }

    public static func anotherPassPrefill(receipt: ProofReceipt) -> String {
        let unmet = criteriaRows(receipt: receipt).filter { $0.status == .unmet }.map(\.text)
        if !unmet.isEmpty {
            return "Please address these unmet criteria:\n" + unmet.map { "• \($0)" }.joined(separator: "\n")
        }
        if let goal = receipt.contract?.goal, !goal.isEmpty {
            return "Please take another pass on: \(goal)"
        }
        return "Please take another pass on this run."
    }

    public static func resumeShellCommand(
        receipt: ProofReceipt,
        workingDirectory: String? = nil
    ) -> String? {
        guard let resume = receipt.resume else { return nil }
        let sessionID = resume.vendorSessionId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !sessionID.isEmpty else { return nil }
        guard let agent = AgentRegistry.defaults.registration(id: resume.agent) else { return nil }
        return AgentResumeBuilder.resumeShellCommand(
            agent: agent,
            sessionId: sessionID,
            workingDirectory: workingDirectory
        )
    }

    // MARK: - Helpers

    private static func jsonObject(from payloadJSON: String) -> [String: Any]? {
        guard let data = payloadJSON.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func encodeJSONObject(_ object: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func iso8601Date(from raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: raw) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }

    private static func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
