import Foundation
import LancerCore

/// Pure presentation logic for the phone→desktop Return-to-Desk packet.
public enum ReturnPacketModel {
    public static func unmetCriteria(receipt: ProofReceipt) -> [ReceiptCardModel.CriterionRow] {
        ReceiptCardModel.criteriaRows(receipt: receipt).filter { $0.status == .unmet }
    }

    /// Best-effort branch label from the receipt git snapshot.
    public static func gitBranchLabel(receipt: ProofReceipt) -> String? {
        let ref = receipt.git?.endRef ?? receipt.git?.startRef
        guard let ref, !ref.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return ref
    }

    /// Prefers the receipt's recorded worktree path over the live thread cwd.
    public static func worktreePath(receipt: ProofReceipt, workingDirectory: String?) -> String? {
        let fromReceipt = receipt.git?.worktreePath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !fromReceipt.isEmpty { return fromReceipt }
        let fallback = workingDirectory?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return fallback.isEmpty ? nil : fallback
    }

    public static func dirtyAtStart(receipt: ProofReceipt) -> Bool? {
        receipt.git?.dirtyAtStart
    }

    /// Runnable shell command to resume the agent session on desktop.
    public static func continuationCommand(
        receipt: ProofReceipt,
        workingDirectory: String? = nil
    ) -> String? {
        ReceiptCardModel.resumeShellCommand(
            receipt: receipt,
            workingDirectory: worktreePath(receipt: receipt, workingDirectory: workingDirectory)
        )
    }
}
