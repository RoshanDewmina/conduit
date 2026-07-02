import AgentKit
import AppIntents
import Foundation
import LancerCore
import PersistenceKit

// Lives in the `Lancer` app target — see StatusQueryIntents.swift's header
// comment for why (dual-target AppIntent compilation breaks runtime execution
// lookup even though static Shortcuts discovery still works).

/// Wraps a pending `Approval.id`. `EntityStringQuery`, not `IndexedEntity`:
/// pending approvals are short-lived (resolved or expired within minutes),
/// so there is nothing worth indexing into Spotlight — resolve fresh against
/// `ApprovalRepository` every time, per the audit's volatile/durable split.
@available(iOS 17.0, *)
public struct ApprovalEntity: AppEntity {
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Approval")
    public static let defaultQuery = ApprovalEntityQuery()

    public let id: String
    let summary: String
    let risk: Approval.Risk

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(summary)", subtitle: "\(riskLabel)")
    }

    private var riskLabel: LocalizedStringResource {
        switch risk {
        case .low: "Low risk"
        case .medium: "Medium risk"
        case .high: "High risk"
        case .critical: "Critical risk"
        }
    }

    /// The redacted command/tool-input/question text an approval is actually
    /// about — same field-precedence + redaction the in-app approval cards
    /// already use (`NewChatTabView.swift`, `LancerHomeView.swift`), so Siri
    /// never reads a secret out loud.
    static func summaryText(for approval: Approval) -> String {
        let raw = approval.command ?? approval.toolInput ?? approval.question ?? approval.toolName ?? "Approval"
        return Redactor.shared.redact(raw).redacted
    }

    init(approval: Approval) {
        self.id = approval.id.uuidString
        self.summary = Self.summaryText(for: approval)
        self.risk = approval.risk
    }
}

@available(iOS 17.0, *)
public struct ApprovalEntityQuery: EntityStringQuery {
    public init() {}

    public func entities(for identifiers: [String]) async throws -> [ApprovalEntity] {
        guard let db = try? AppDatabase.openShared() else { return [] }
        let repo = ApprovalRepository(db)
        var results: [ApprovalEntity] = []
        for identifier in identifiers {
            guard let uuid = UUID(uuidString: identifier),
                  let approval = try? await repo.find(id: ApprovalID(uuid))
            else { continue }
            results.append(ApprovalEntity(approval: approval))
        }
        return results
    }

    public func entities(matching string: String) async throws -> [ApprovalEntity] {
        try await suggestedEntities().filter {
            $0.summary.localizedCaseInsensitiveContains(string)
        }
    }

    public func suggestedEntities() async throws -> [ApprovalEntity] {
        guard let db = try? AppDatabase.openShared(),
              let pending = try? await ApprovalRepository(db).pending()
        else { return [] }
        return pending.map(ApprovalEntity.init)
    }
}
