import Testing
import Foundation
@testable import LancerCore

// Tests for the governance wedge feature models (the testable, UI-free layers).
// The Go drift.remediate RPC is covered by daemon/lancerd/drift_test.go.

// MARK: - #2 BlastRadius.derive heuristic

@Suite("BlastRadius — command risk derivation")
struct BlastRadiusTests {
    @Test("rm -rf is high severity")
    func rmrf() {
        let b = BlastRadius.derive(fromCommand: "rm -rf build/")
        #expect(b.severity == .high)
    }

    @Test("read-only command is low severity")
    func readOnly() {
        let b = BlastRadius.derive(fromCommand: "git status")
        #expect(b.severity == .low)
        #expect(b.touchesProduction == false)
    }

    @Test("deploy flags production")
    func deploy() {
        let b = BlastRadius.derive(fromCommand: "npm run deploy")
        #expect(b.severity == .high)
        #expect(b.touchesProduction)
    }

    @Test("affectedPathCount mirrors the path list")
    func pathCount() {
        let b = BlastRadius(affectedPaths: ["a", "b", "c"], commands: [], severity: .low, touchesProduction: false)
        #expect(b.affectedPathCount == 3)
    }

    @Test("a derived blast radius round-trips through Codable")
    func codable() throws {
        let b = BlastRadius.derive(fromCommand: "rm -rf build/ && npm run deploy")
        let data = try JSONEncoder().encode(b)
        let back = try JSONDecoder().decode(BlastRadius.self, from: data)
        #expect(back == b)
    }
}

// MARK: - #5 NormalizedPolicy cross-provider mapping

@Suite("NormalizedPolicy — cross-provider mapping")
struct NormalizedPolicyTests {
    @Test("default policy has the four seeded rules")
    func defaultRules() {
        #expect(NormalizedPolicy.defaultPolicy.rules.count == 4)
    }

    @Test("Claude Code realizes every rule as a hook")
    func claudeAllHook() {
        let p = NormalizedPolicy.defaultPolicy
        for rule in p.rules {
            #expect(p.mapping(for: rule, provider: .claudeCode) == .hook)
        }
    }

    @Test("Codex realizes every rule as an approval gate")
    func codexAllApproval() {
        let p = NormalizedPolicy.defaultPolicy
        for rule in p.rules {
            #expect(p.mapping(for: rule, provider: .codex) == .approval)
        }
    }

    @Test("OpenCode cannot map scope-based rules")
    func openCodeScopeGaps() {
        let p = NormalizedPolicy.defaultPolicy
        let scopeRule = p.rules.first { $0.id == "escalate-prod-writes" }!
        let toolRule = p.rules.first { $0.id == "ask-network-installs" }!
        #expect(p.mapping(for: scopeRule, provider: .openCode) == .unsupported)
        #expect(p.mapping(for: toolRule, provider: .openCode) == .hook)
    }

    @Test("all three providers are enumerable")
    func providers() {
        #expect(AgentProvider.allCases.count == 3)
    }
}

// MARK: - #6 TeamRoles

@Suite("TeamRole — capabilities & approval")
struct TeamRoleTests {
    @Test("only owner and approver can approve")
    func canApprove() {
        #expect(TeamRole.owner.canApprove)
        #expect(TeamRole.approver.canApprove)
        #expect(TeamRole.viewer.canApprove == false)
    }

    @Test("owner has the full capability set")
    func ownerCaps() {
        #expect(TeamRole.owner.capabilities.contains("stop agent"))
        #expect(TeamRole.viewer.capabilities == ["read-only"])
    }
}

@Suite("TeamRoleStore — local persistence")
struct TeamRoleStoreTests {
    private func freshStore(_ name: String) -> (TeamRoleStore, UserDefaults) {
        let suite = "test.team.\(name)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return (TeamRoleStore(defaults: d), d)
    }

    @Test("seeds 'you' as owner and on-call on first run")
    func seedsOwner() {
        let (store, _) = freshStore(#function)
        let members = store.all()
        #expect(members.count == 1)
        #expect(members.first?.role == .owner)
        #expect(store.onCallMember()?.id == members.first?.id)
        #expect(store.currentUserCanApprove())
    }

    @Test("add, role change, and remove a teammate")
    func mutate() {
        let (store, _) = freshStore(#function)
        store.add(name: "Dana", role: .viewer)
        let dana = store.all().first { $0.name == "Dana" }!
        #expect(dana.role == .viewer)
        store.setRole(dana.id, role: .approver)
        #expect(store.all().first { $0.id == dana.id }?.role == .approver)
        store.remove(id: dana.id)
        #expect(store.all().contains { $0.id == dana.id } == false)
    }

    @Test("on-call assignment persists")
    func onCall() {
        let (store, _) = freshStore(#function)
        store.add(name: "Dana", role: .approver)
        let dana = store.all().first { $0.name == "Dana" }!
        store.setOnCall(dana.id)
        #expect(store.onCallMember()?.id == dana.id)
    }
}

// MARK: - #1 PolicyPreset store

@Suite("PolicyPresetStore — presets & JSON round-trip")
struct PolicyPresetStoreTests {
    private func freshStore(_ name: String) -> PolicyPresetStore {
        let suite = "test.preset.\(name)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return PolicyPresetStore(defaults: d)
    }

    @Test("seeds prod-strict and dev-relaxed builtins")
    func seeds() {
        let store = freshStore(#function)
        let names = store.all().map(\.name)
        #expect(store.all().count >= 2)
        #expect(names.contains { $0.localizedCaseInsensitiveContains("strict") })
        #expect(names.contains { $0.localizedCaseInsensitiveContains("relaxed") })
    }

    @Test("save then delete a custom preset")
    func saveDelete() {
        let store = freshStore(#function)
        let before = store.all().count
        let p = PolicyPreset(id: "custom-1", name: "custom", description: "d", ruleYAML: "rules: []")
        store.save(p)
        #expect(store.all().count == before + 1)
        store.delete(id: "custom-1")
        #expect(store.all().count == before)
    }

    @Test("export then import is idempotent on ids")
    func exportImport() throws {
        let store = freshStore(#function)
        let data = try store.exportJSON()
        let countBefore = store.all().count
        try store.importJSON(data)   // same ids → upsert, no duplication
        #expect(store.all().count == countBefore)
    }
}

// MARK: - #4 Drift remediation decoding (forward-compat)

@Suite("DriftFinding — remediation decoding")
struct DriftRemediationTests {
    @Test("missing remediation field decodes to .manual (never an unsafe auto-fix)")
    func missingDefaultsManual() throws {
        let json = #"{"file":"CLAUDE.md","line":3,"kind":"dead-link","ref":"x","message":"m"}"#
        let f = try JSONDecoder().decode(DriftFinding.self, from: Data(json.utf8))
        #expect(f.remediation == .manual)
    }

    @Test("unknown remediation value decodes to .manual")
    func unknownDefaultsManual() throws {
        let json = #"{"file":"CLAUDE.md","line":3,"kind":"dead-link","ref":"x","message":"m","remediation":"future-thing"}"#
        let f = try JSONDecoder().decode(DriftFinding.self, from: Data(json.utf8))
        #expect(f.remediation == .manual)
    }

    @Test("explicit apply-fix decodes")
    func applyFix() throws {
        let json = #"{"file":"CLAUDE.md","line":3,"kind":"dead-link","ref":"x","message":"m","remediation":"apply-fix"}"#
        let f = try JSONDecoder().decode(DriftFinding.self, from: Data(json.utf8))
        #expect(f.remediation == .applyFix)
    }
}

// #3 audit-chain verification is iOS-gated UI code (AuditVerifyExportModel lives
// behind #if os(iOS)) and is a client-side ORDERING/COUNT recompute, not a real
// tamper detector — AuditEvent carries no stored hash to compare against, so the
// authoritative chain check is daemon-side. Covered by the app-target build +
// the daemon hash-chain tests; intentionally not duplicated as a macOS unit test.
