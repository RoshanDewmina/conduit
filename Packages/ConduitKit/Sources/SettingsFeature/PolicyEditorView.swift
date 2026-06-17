#if os(iOS)
import SwiftUI
import ConduitCore
import DesignSystem

public struct PolicyEditorView: View {
    @State private var yamlText: String
    @State private var preset: AutonomyPreset
    @State private var statusMessage: String?
    @State private var isSaving = false
    @State private var activeAllowRules: [ActiveAllowRule] = []
    private let cwd: String
    private let onReload: () async -> Void
    private let onSave: ((String) async throws -> Void)?
    private let simulate: (@Sendable (_ yaml: String, _ periodDays: Int) async throws -> PolicySimulation)?

    @Environment(\.conduitTokens) private var t

    public init(
        cwd: String,
        initialYAML: String,
        onReload: @escaping () async -> Void,
        onSave: ((String) async throws -> Void)? = nil,
        simulate: (@Sendable (_ yaml: String, _ periodDays: Int) async throws -> PolicySimulation)? = nil
    ) {
        self.cwd = cwd
        _yamlText = State(initialValue: initialYAML)
        _preset = State(initialValue: Self.detectPreset(from: initialYAML))
        self.onReload = onReload
        self.onSave = onSave
        self.simulate = simulate
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                allowAlwaysRulesSection
                presetSection
                rulesSection
                yamlSection
                actionsSection
            }
        }
        .background(t.bg)
        .navigationTitle("Agent policy")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadActiveAllowRules()
        }
    }

    // MARK: - Active allow-always rules

    private var allowAlwaysRulesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("ACTIVE ALLOW-ALWAYS RULES")
                .font(.dsMonoPt(10, weight: .semibold))
                .tracking(10 * 0.12)
                .foregroundStyle(t.text3)
                .padding(.horizontal, 18)
                .padding(.top, 22)
                .padding(.bottom, 8)

            if activeAllowRules.isEmpty {
                VStack(spacing: 6) {
                    Text("No active allow-always rules")
                        .font(.dsSansPt(13))
                        .foregroundStyle(t.text3)
                    Text("Rules created from the inbox will appear here.")
                        .font(.dsSansPt(11))
                        .foregroundStyle(t.text4)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(t.surface)
                .clipShape(RoundedRectangle(cornerRadius: t.r1, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: t.r1, style: .continuous)
                        .strokeBorder(t.border, lineWidth: 1)
                )
                .padding(.horizontal, 18)
                .padding(.bottom, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(activeAllowRules.enumerated()), id: \.element.id) { idx, rule in
                        if idx > 0 {
                            Rectangle()
                                .fill(t.divider)
                                .frame(height: 1)
                                .padding(.leading, 18)
                        }
                        allowAlwaysRuleRow(rule)
                    }
                }
                .background(t.surface)
                .clipShape(RoundedRectangle(cornerRadius: t.r1, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: t.r1, style: .continuous)
                        .strokeBorder(t.border, lineWidth: 1)
                )
                .padding(.horizontal, 18)
                .padding(.bottom, 8)
            }
        }
    }

    private func allowAlwaysRuleRow(_ rule: ActiveAllowRule) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(rule.description)
                    .font(.dsMonoPt(12))
                    .foregroundStyle(t.text)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    if let scope = rule.scopeLabel {
                        DSChip(scope, tone: .accent, variant: .soft, size: .sm)
                    }
                    if let timeLeft = rule.timeRemaining {
                        DSChip(timeLeft, tone: rule.isExpired ? .danger : .ok, variant: .soft, size: .sm)
                    }
                }
            }
            Spacer()
            Button {
                revokeRule(rule)
                Haptics.selection()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(t.danger)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func loadActiveAllowRules() {
        let key = "inbox.allowAlwaysRules"
        guard let entries = UserDefaults.standard.array(forKey: key) as? [[String: String]] else {
            activeAllowRules = []
            return
        }

        activeAllowRules = entries.compactMap { entry in
            let id = entry["command", default: ""] + entry["toolName", default: ""]
            let description = entry["command"] ?? entry["toolName"] ?? "Unknown rule"
            let scopeLabel: String? = {
                if let scope = entry["scope"] {
                    switch scope {
                    case "thisCommandInRepo": return "in repo"
                    case "thisCommandMatchingPath": return "path"
                    case "thisKindFromAgent": return "all actions"
                    default: return nil
                    }
                }
                return nil
            }()

            let timeRemaining: String? = {
                guard let expiresAt = entry["expiresAt"] else { return nil }
                guard let expiry = ISO8601DateFormatter().date(from: expiresAt) else { return nil }
                let now = Date()
                if now > expiry { return "expired" }
                let interval = expiry.timeIntervalSince(now)
                if interval < 3600 {
                    return "\(Int(interval / 60))m left"
                } else if interval < 86400 {
                    return "\(Int(interval / 3600))h left"
                } else {
                    return "\(Int(interval / 86400))d left"
                }
            }()

            let isExpired: Bool = {
                guard let expiresAt = entry["expiresAt"],
                      let expiry = ISO8601DateFormatter().date(from: expiresAt) else {
                    return false
                }
                return Date() > expiry
            }()

            return ActiveAllowRule(
                id: id,
                description: description,
                scopeLabel: scopeLabel,
                timeRemaining: timeRemaining,
                isExpired: isExpired,
                entry: entry
            )
        }.filter { !$0.isExpired }
    }

    private func revokeRule(_ rule: ActiveAllowRule) {
        let key = "inbox.allowAlwaysRules"
        guard var entries = UserDefaults.standard.array(forKey: key) as? [[String: String]] else { return }
        entries.removeAll { $0["command"] == rule.entry["command"] && $0["toolName"] == rule.entry["toolName"] }
        UserDefaults.standard.set(entries, forKey: key)
        loadActiveAllowRules()
    }

    // MARK: - Preset bar

    private var presetSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("SAFE PRESETS")
                .font(.dsMonoPt(10, weight: .semibold))
                .tracking(10 * 0.12)
                .foregroundStyle(t.text3)
                .padding(.horizontal, 18)
                .padding(.top, 22)
                .padding(.bottom, 8)

            DSAutonomyPresetBar(preset: $preset)
                .onChange(of: preset) { _, newValue in
                    Task { await applyPreset(yamlForPreset(newValue)) }
                }
        }
    }

    // MARK: - Rules list

    private var rulesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("RULES")
                .font(.dsMonoPt(10, weight: .semibold))
                .tracking(10 * 0.12)
                .foregroundStyle(t.text3)
                .padding(.horizontal, 18)
                .padding(.top, 22)
                .padding(.bottom, 2)

            VStack(spacing: 0) {
                ForEach(Array(parsedRules.enumerated()), id: \.offset) { idx, rule in
                    if idx > 0 {
                        Rectangle()
                            .fill(t.divider)
                            .frame(height: 1)
                            .padding(.leading, 18)
                    }
                    ruleRow(rule)
                }

                Rectangle()
                    .fill(t.divider)
                    .frame(height: 1)
                    .padding(.leading, 18)

                failSafeRow
            }
            .background(t.surface)
            .overlay(
                RoundedRectangle(cornerRadius: t.r1, style: .continuous)
                    .strokeBorder(t.border, lineWidth: 1)
            )
            .padding(.horizontal, 18)
            .padding(.top, 6)
        }
    }

    private func ruleRow(_ rule: PolicyRule) -> some View {
        HStack(spacing: 12) {
            Text(rule.matcher)
                .font(.dsMonoPt(12))
                .foregroundStyle(t.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            DSChip(rule.effectLabel, tone: rule.effectTone, variant: .soft, size: .sm)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var failSafeRow: some View {
        HStack(spacing: 8) {
            Text("unmatched")
                .font(.dsMonoPt(12))
                .foregroundStyle(t.text3)
            Text("→")
                .font(.dsMonoPt(12))
                .foregroundStyle(t.text4)
            Text("asks")
                .font(.dsMonoPt(12))
                .foregroundStyle(t.text3)
            Text("(fail-safe)")
                .font(.dsSansPt(11))
                .foregroundStyle(t.text4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - YAML editor

    private var yamlSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("POLICY YAML")
                .font(.dsMonoPt(10, weight: .semibold))
                .tracking(10 * 0.12)
                .foregroundStyle(t.text3)
                .padding(.horizontal, 18)
                .padding(.top, 22)
                .padding(.bottom, 8)

            Text("Edit on the bridge host at ~/.conduit/policy.yaml — reload after external edits.")
                .font(.dsSansPt(12))
                .foregroundStyle(t.text3)
                .padding(.horizontal, 18)
                .padding(.bottom, 8)

            TextEditor(text: $yamlText)
                .font(.dsMonoPt(12))
                .foregroundStyle(t.termText)
                .scrollContentBackground(.hidden)
                .background(t.termSurface)
                .frame(minHeight: 220)
                .clipShape(RoundedRectangle(cornerRadius: t.r1, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: t.r1, style: .continuous)
                        .strokeBorder(t.termBorder, lineWidth: 1)
                )
                .padding(.horizontal, 18)
        }
    }

    // MARK: - Actions

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            NavigationLink {
                PolicySimulatorView(yaml: yamlText, simulate: simulate)
            } label: {
                DSButton(
                    "Simulate policy",
                    variant: .accent,
                    size: .md,
                    mono: true,
                    fullWidth: true
                ) {}
            }

            DSButton(
                "Reload policy on bridge",
                variant: .secondary,
                size: .md,
                mono: true,
                fullWidth: true
            ) {
                Task {
                    await onReload()
                    statusMessage = "Reloaded on bridge."
                }
            }

            if let onSave {
                DSButton(
                    isSaving ? "Saving…" : "Save to bridge",
                    variant: .primary,
                    size: .md,
                    mono: true,
                    isLoading: isSaving,
                    fullWidth: true
                ) {
                    Task {
                        isSaving = true
                        defer { isSaving = false }
                        do {
                            try await onSave(yamlText)
                            statusMessage = "Saved to bridge."
                        } catch {
                            statusMessage = error.localizedDescription
                        }
                    }
                }
                .disabled(isSaving)
            } else {
                Text("Connect an SSH session to edit policy on the bridge.")
                    .font(.dsSansPt(12))
                    .foregroundStyle(t.text3)
            }

            if let msg = statusMessage {
                Text(msg)
                    .font(.dsMonoPt(11))
                    .foregroundStyle(t.text2)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 32)
    }

    // MARK: - Preset application

    private func applyPreset(_ yaml: String) async {
        yamlText = yaml
        guard let onSave else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await onSave(yaml)
            statusMessage = "Preset applied to bridge."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func yamlForPreset(_ p: AutonomyPreset) -> String {
        switch p {
        case .alwaysAsk:      return Self.strictPreset
        case .autoReads:      return Self.balancedPreset
        case .autoSafeWrites: return Self.balancedPreset
        case .agentDecides:   return Self.permissivePreset
        }
    }

    // MARK: - Rule parsing

    private var parsedRules: [PolicyRule] {
        Self.parseRules(from: yamlText)
    }

    // MARK: - Preset detection

    static func detectPreset(from yaml: String) -> AutonomyPreset {
        let trimmed = yaml.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == strictPreset.trimmingCharacters(in: .whitespacesAndNewlines) {
            return .alwaysAsk
        } else if trimmed == balancedPreset.trimmingCharacters(in: .whitespacesAndNewlines) {
            return .autoReads
        } else if trimmed == permissivePreset.trimmingCharacters(in: .whitespacesAndNewlines) {
            return .agentDecides
        }
        return .alwaysAsk
    }

    // Minimal line-by-line YAML rule parser — reads `effect:`, `kind:`, `maxRisk:` fields.
    static func parseRules(from yaml: String) -> [PolicyRule] {
        var rules: [PolicyRule] = []
        var currentEffect: String?
        var matchers: [String] = []

        func flush() {
            guard let effect = currentEffect else { return }
            let matcher = matchers.isEmpty ? "all actions" : matchers.joined(separator: ", ")
            rules.append(PolicyRule(matcher: matcher, effect: effect))
        }

        for rawLine in yaml.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("- effect:") {
                flush()
                currentEffect = line.replacingOccurrences(of: "- effect:", with: "").trimmingCharacters(in: .whitespaces)
                matchers = []
            } else if line.hasPrefix("kind:") {
                let value = line.replacingOccurrences(of: "kind:", with: "").trimmingCharacters(in: .whitespaces)
                matchers.append("kind=\(value)")
            } else if line.hasPrefix("maxRisk:") {
                let value = line.replacingOccurrences(of: "maxRisk:", with: "").trimmingCharacters(in: .whitespaces)
                matchers.append("maxRisk=\(value)")
            }
        }
        flush()
        return rules
    }

    // MARK: - Preset YAML strings

    static let balancedPreset = """
default: ask
rules:
  - effect: deny
    kind: credential
  - effect: deny
    kind: network
  - effect: deny
    maxRisk: critical
  - effect: allow
    maxRisk: low
    kind: command
  - effect: ask
    kind: patch
"""

    static let strictPreset = """
default: ask
rules:
  - effect: deny
    kind: credential
  - effect: deny
    kind: network
  - effect: deny
    maxRisk: critical
  - effect: deny
    maxRisk: high
  - effect: ask
"""

    static let permissivePreset = """
default: ask
rules:
  - effect: deny
    kind: credential
  - effect: allow
    maxRisk: low
  - effect: ask
"""
}

// MARK: - PolicyRule

struct PolicyRule {
    let matcher: String
    let effect: String

    var effectLabel: String { effect }

    var effectTone: DSChipTone {
        switch effect {
        case "allow": return .ok
        case "ask":   return .warn
        case "deny":  return .danger
        default:      return .neutral
        }
    }
}

// MARK: - ActiveAllowRule

struct ActiveAllowRule: Identifiable {
    let id: String
    let description: String
    let scopeLabel: String?
    let timeRemaining: String?
    let isExpired: Bool
    let entry: [String: String]
}

#endif
