#if os(iOS)
import SwiftUI
import ConduitCore
import DesignSystem

// MARK: - AllowAlwaysScopeSheet

// Scope sheet shown when the user taps "Allow always..." on an approval card.
// Lets the user configure what scope and time window the allow-always rule should have.

public struct AllowAlwaysScopeSheet: View {
    let approval: Approval
    let onConfirm: (ScopedAllowRule) -> Void

    @Environment(\.conduitTokens) private var t
    @Environment(\.dismiss) private var dismiss

    @State private var scope: Scope = .thisCommand
    @State private var pathPattern: String = ""
    @State private var timeWindow: TimeWindow = .untilRevoke
    @State private var customDays: String = ""
    @State private var repoPattern: String = ""

    public init(
        approval: Approval,
        onConfirm: @escaping (ScopedAllowRule) -> Void
    ) {
        self.approval = approval
        self.onConfirm = onConfirm
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerSection
                    scopeSection
                    if scope == .thisCommandMatchingPath {
                        pathInputSection
                    }
                    if scope == .thisCommandInRepo {
                        repoInputSection
                    }
                    timeWindowSection
                    confirmButton
                }
                .padding(18)
            }
            .background(t.bg)
            .navigationTitle("Allow always")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(.dsSansPt(14))
                    .foregroundStyle(t.text2)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Configure allow-always rule")
                .font(.dsSansPt(17, weight: .semibold))
                .foregroundStyle(t.text)

            Text("Choose what to allow and for how long. You can revoke this rule at any time from the policy editor.")
                .font(.dsSansPt(13))
                .foregroundStyle(t.text2)
                .lineSpacing(3)
        }
    }

    // MARK: - Scope selection

    private var scopeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("WHAT TO ALLOW")
                .font(.dsMonoPt(10, weight: .semibold))
                .tracking(10 * 0.12)
                .foregroundStyle(t.text3)

            VStack(spacing: 0) {
                ForEach(Scope.allCases, id: \.self) { option in
                    if option != Scope.allCases.first {
                        Rectangle()
                            .fill(t.divider)
                            .frame(height: 1)
                            .padding(.leading, 14)
                    }
                    scopeRow(option)
                }
            }
            .background(t.surface)
            .clipShape(RoundedRectangle(cornerRadius: t.r1, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: t.r1, style: .continuous)
                    .strokeBorder(t.border, lineWidth: 1)
            )
        }
    }

    private func scopeRow(_ option: Scope) -> some View {
        Button {
            scope = option
            Haptics.selection()
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .strokeBorder(scope == option ? t.accent : t.borderStrong, lineWidth: 1.5)
                    .frame(width: 18, height: 18)
                    .overlay(
                        Circle()
                            .fill(t.accent)
                            .frame(width: 10, height: 10)
                            .opacity(scope == option ? 1 : 0)
                    )
                Text(option.label)
                    .font(.dsSansPt(14))
                    .foregroundStyle(scope == option ? t.text : t.text2)
                Spacer()
                if let icon = option.icon {
                    Image(systemName: icon)
                        .font(.system(size: 12))
                        .foregroundStyle(t.text3)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Path pattern input

    private var pathInputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PATH PATTERN")
                .font(.dsMonoPt(10, weight: .semibold))
                .tracking(10 * 0.12)
                .foregroundStyle(t.text3)

            TextField("e.g. **/*.swift, src/**/*.ts", text: $pathPattern)
                .font(.dsMonoPt(13))
                .foregroundStyle(t.text)
                .padding(10)
                .background(t.surface)
                .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: t.r3, style: .continuous)
                        .strokeBorder(t.border, lineWidth: 1)
                )

            Text("Use * or ** for wildcards. Example: **/*.swift matches all Swift files.")
                .font(.dsSansPt(11))
                .foregroundStyle(t.text3)
        }
    }

    // MARK: - Repo pattern input

    private var repoInputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("REPO PATTERN")
                .font(.dsMonoPt(10, weight: .semibold))
                .tracking(10 * 0.12)
                .foregroundStyle(t.text3)

            TextField("e.g. my-app, **/backend/**", text: $repoPattern)
                .font(.dsMonoPt(13))
                .foregroundStyle(t.text)
                .padding(10)
                .background(t.surface)
                .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: t.r3, style: .continuous)
                        .strokeBorder(t.border, lineWidth: 1)
                )

            Text("Match by repo name or path pattern.")
                .font(.dsSansPt(11))
                .foregroundStyle(t.text3)
        }
    }

    // MARK: - Time window selection

    private var timeWindowSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("HOW LONG")
                .font(.dsMonoPt(10, weight: .semibold))
                .tracking(10 * 0.12)
                .foregroundStyle(t.text3)

            VStack(spacing: 0) {
                ForEach(TimeWindow.allCases, id: \.self) { option in
                    if option != TimeWindow.allCases.first {
                        Rectangle()
                            .fill(t.divider)
                            .frame(height: 1)
                            .padding(.leading, 14)
                    }
                    timeWindowRow(option)
                }

                if timeWindow == .custom {
                    Rectangle()
                        .fill(t.divider)
                        .frame(height: 1)
                        .padding(.leading, 14)
                    customDaysInput
                }
            }
            .background(t.surface)
            .clipShape(RoundedRectangle(cornerRadius: t.r1, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: t.r1, style: .continuous)
                    .strokeBorder(t.border, lineWidth: 1)
            )
        }
    }

    private func timeWindowRow(_ option: TimeWindow) -> some View {
        Button {
            timeWindow = option
            Haptics.selection()
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .strokeBorder(timeWindow == option ? t.accent : t.borderStrong, lineWidth: 1.5)
                    .frame(width: 18, height: 18)
                    .overlay(
                        Circle()
                            .fill(t.accent)
                            .frame(width: 10, height: 10)
                            .opacity(timeWindow == option ? 1 : 0)
                    )
                Text(option.label)
                    .font(.dsSansPt(14))
                    .foregroundStyle(timeWindow == option ? t.text : t.text2)
                Spacer()
                if let icon = option.icon {
                    Image(systemName: icon)
                        .font(.system(size: 12))
                        .foregroundStyle(t.text3)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
    }

    private var customDaysInput: some View {
        HStack(spacing: 8) {
            TextField("days", text: $customDays)
                .keyboardType(.numberPad)
                .font(.dsMonoPt(13))
                .foregroundStyle(t.text)
                .padding(10)
                .frame(width: 80)
                .background(t.bg)
                .clipShape(RoundedRectangle(cornerRadius: t.r3, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: t.r3, style: .continuous)
                        .strokeBorder(t.border, lineWidth: 1)
                )

            Text("days")
                .font(.dsSansPt(13))
                .foregroundStyle(t.text2)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Confirm button

    private var confirmButton: some View {
        DSButton(
            "Allow Always",
            variant: .primary,
            size: .md,
            mono: true,
            fullWidth: true
        ) {
            let rule = ScopedAllowRule(
                scope: ScopedAllowRule.Scope(rawValue: scope.rawValue) ?? .thisCommand,
                pathPattern: scope == .thisCommandMatchingPath ? pathPattern : nil,
                repoPattern: scope == .thisCommandInRepo ? repoPattern : nil,
                timeWindow: computedTimeWindow
            )
            onConfirm(rule)
            dismiss()
        }
        .disabled(scope == .thisCommandMatchingPath && pathPattern.trimmingCharacters(in: .whitespaces).isEmpty)
        .disabled(scope == .thisCommandInRepo && repoPattern.trimmingCharacters(in: .whitespaces).isEmpty)
        .disabled(timeWindow == .custom && (Int(customDays) ?? 0) <= 0)
    }

    // MARK: - Computed

    private var computedTimeWindow: ScopedAllowRule.TimeWindowValue {
        switch timeWindow {
        case .untilRevoke:
            return .untilRevoke
        case .hours24:
            return .hours(24)
        case .days7:
            return .days(7)
        case .custom:
            let days = Int(customDays) ?? 1
            return .days(days)
        }
    }
}

// MARK: - ScopedAllowRule

public struct ScopedAllowRule: Sendable {
    public enum Scope: String, CaseIterable, Sendable {
        case thisCommand = "thisCommand"
        case thisCommandInRepo = "thisCommandInRepo"
        case thisCommandMatchingPath = "thisCommandMatchingPath"
        case thisKindFromAgent = "thisKindFromAgent"

        public var label: String {
            switch self {
            case .thisCommand: return "This command only"
            case .thisCommandInRepo: return "This command in this repo"
            case .thisCommandMatchingPath: return "This command matching a path"
            case .thisKindFromAgent: return "All actions from this agent"
            }
        }

        public var icon: String? {
            switch self {
            case .thisCommand: return "terminal"
            case .thisCommandInRepo: return "folder"
            case .thisCommandMatchingPath: return "doc.text.magnifyingglass"
            case .thisKindFromAgent: return "person.2"
            }
        }
    }

    public enum TimeWindowValue: Sendable {
        case untilRevoke
        case hours(Int)
        case days(Int)
    }

    public let scope: Scope
    public let pathPattern: String?
    public let repoPattern: String?
    public let timeWindow: TimeWindowValue
}

// MARK: - Scope

extension AllowAlwaysScopeSheet {
    enum Scope: String, CaseIterable {
        case thisCommand = "thisCommand"
        case thisCommandInRepo = "thisCommandInRepo"
        case thisCommandMatchingPath = "thisCommandMatchingPath"
        case thisKindFromAgent = "thisKindFromAgent"

        var label: String {
            switch self {
            case .thisCommand: return "This command only"
            case .thisCommandInRepo: return "This command in this repo"
            case .thisCommandMatchingPath: return "This command matching a path"
            case .thisKindFromAgent: return "All actions from this agent"
            }
        }

        var icon: String? {
            switch self {
            case .thisCommand: return "terminal"
            case .thisCommandInRepo: return "folder"
            case .thisCommandMatchingPath: return "doc.text.magnifyingglass"
            case .thisKindFromAgent: return "person.2"
            }
        }
    }

    enum TimeWindow: String, CaseIterable {
        case untilRevoke = "untilRevoke"
        case hours24 = "hours24"
        case days7 = "days7"
        case custom = "custom"

        var label: String {
            switch self {
            case .untilRevoke: return "Until I revoke"
            case .hours24: return "24 hours"
            case .days7: return "7 days"
            case .custom: return "Custom"
            }
        }

        var icon: String? {
            switch self {
            case .untilRevoke: return "infinity"
            case .hours24: return "clock"
            case .days7: return "calendar"
            case .custom: return "slider.horizontal.3"
            }
        }
    }
}

#endif
