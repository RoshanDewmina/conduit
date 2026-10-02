import Foundation

/// Pure helpers for Needs-You thread promotion (Phase 1 P1.6).
///
/// Relay approvals are machine-scoped (`RelayApprovalIngest`), not run-scoped.
/// The only honest thread signal available without a daemon wire change is the
/// approval's `cwd` — when empty, we do **not** invent a match.
public enum NeedsYouOrdering {
    /// True when `rowCwd` is the same path as, under, or a parent of any
    /// non-empty pending-approval cwd (normalized via `WorkspaceRepoCatalog`).
    public static func cwdNeedsAttention(
        rowCwd: String,
        pendingApprovalCwds: [String]
    ) -> Bool {
        let row = WorkspaceRepoCatalog.normalizeCwd(rowCwd)
        guard !row.isEmpty else { return false }
        for raw in pendingApprovalCwds {
            let pending = WorkspaceRepoCatalog.normalizeCwd(raw)
            guard !pending.isEmpty else { continue }
            if WorkspaceRepoCatalog.pathsMatch(row, pending) { return true }
            if WorkspaceRepoCatalog.isEqualOrUnder(cwd: row, repoPath: pending) { return true }
            if WorkspaceRepoCatalog.isEqualOrUnder(cwd: pending, repoPath: row) { return true }
        }
        return false
    }

    /// Needs-you rows first (newest among themselves), then remaining by date desc.
    public static func sortedNeedsYouFirst<T>(
        _ items: [T],
        needsYou: (T) -> Bool,
        sortDate: (T) -> Date
    ) -> [T] {
        items.sorted { a, b in
            let aNeeds = needsYou(a)
            let bNeeds = needsYou(b)
            if aNeeds != bNeeds { return aNeeds && !bNeeds }
            return sortDate(a) > sortDate(b)
        }
    }

    /// Recency buckets with a leading "Needs you" section when any row matches.
    /// Rows already in Needs you are excluded from Today/Yesterday/… so they
    /// are not duplicated.
    public static func groupNeedsYouFirstThenRecency<T>(
        _ items: [T],
        needsYou: (T) -> Bool,
        date: KeyPath<T, Date>,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [(title: String, items: [T])] {
        let needs = items.filter(needsYou)
            .sorted { $0[keyPath: date] > $1[keyPath: date] }
        let rest = items.filter { !needsYou($0) }
        var groups: [(title: String, items: [T])] = []
        if !needs.isEmpty {
            groups.append((title: "Needs you", items: needs))
        }
        groups += WorkspaceRepoCatalog.groupByRecency(
            rest,
            date: date,
            now: now,
            calendar: calendar
        )
        return groups
    }
}
