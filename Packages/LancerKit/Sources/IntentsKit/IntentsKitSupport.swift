#if canImport(AppIntents)
import Foundation
import LancerCore
import PersistenceKit

@available(iOS 17.0, *)
enum IntentsKitSupport {
  static func riskLabel(_ risk: Approval.Risk) -> String {
    switch risk {
    case .low: "low"
    case .medium: "medium"
    case .high: "high"
    case .critical: "critical"
    }
  }

  static func approvalActionSummary(_ approval: Approval) -> String {
    if let command = approval.command?.trimmingCharacters(in: .whitespacesAndNewlines), !command.isEmpty {
      return command
    }
    if let question = approval.question?.trimmingCharacters(in: .whitespacesAndNewlines), !question.isEmpty {
      return question
    }
    return ApprovalSummary.derive(from: approval).headline
  }

  static func approvalDisplayTitle(actionSummary: String, risk: Approval.Risk, hostName: String) -> String {
    let quoted = "'\(actionSummary)'"
    return "\(quoted) · \(riskLabel(risk)) · \(hostName)"
  }

  static func hostName(for approval: Approval, db: AppDatabase) async throws -> String {
    try await hostIdentity(for: approval, db: db).name
  }

  /// Resolves the approval's originating host to (display name, host UUID string).
  /// The UUID is what `ApprovalRelay.enqueue` audits under — passing it fixes the
  /// empty-hostID audit rows the pre-D2 deny intent wrote. `id` stays nil when
  /// the approval's session can't be tied to a known Host row.
  static func hostIdentity(for approval: Approval, db: AppDatabase) async throws -> (name: String, id: String?) {
    let hosts = try await HostRepository(db).all()
    let blocks = try await BlockRepository(db).recent(for: approval.sessionID, limit: 1)
    if let hostName = blocks.first?.prompt.hostName.trimmingCharacters(in: .whitespacesAndNewlines),
       !hostName.isEmpty
    {
      let match = hosts.first(where: { $0.name == hostName })
      return (hostName, match?.id.uuidString)
    }
    if let match = hosts.first(where: { $0.id.uuidString == approval.sessionID.uuidString }) {
      return (match.name, match.id.uuidString)
    }
    return ("unknown", nil)
  }

  static func normalizedQuery(_ string: String) -> String {
    string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }

  static func matchesFuzzy(_ haystack: String, query: String) -> Bool {
    let q = normalizedQuery(query)
    guard !q.isEmpty else { return true }
    return haystack.lowercased().contains(q)
  }
}

#endif
