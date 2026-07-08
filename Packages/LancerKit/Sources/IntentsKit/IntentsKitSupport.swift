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
    let blocks = try await BlockRepository(db).recent(for: approval.sessionID, limit: 1)
    if let hostName = blocks.first?.prompt.hostName.trimmingCharacters(in: .whitespacesAndNewlines),
       !hostName.isEmpty
    {
      return hostName
    }
    let hosts = try await HostRepository(db).all()
    if let match = hosts.first(where: { $0.id.uuidString == approval.sessionID.uuidString }) {
      return match.name
    }
    return "unknown"
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
