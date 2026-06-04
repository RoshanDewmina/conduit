#if os(iOS)
import SwiftUI
import ConduitCore
import DesignSystem
import SSHTransport

/// Proactive-dispatch composer (WS-B2): start or schedule an agent run on the
/// resident bridge over your own infra. The daemon applies the same policy +
/// budget gate as approvals, so a dispatch can come back denied / needs-approval.
/// `channel == nil` renders a demo (gallery) without a live daemon.
public struct DispatchComposerView: View {
    private let channel: DaemonChannel?
    @State private var agent: String
    @State private var cwd: String
    @State private var prompt: String = ""
    @State private var budget: String = ""
    @State private var everyMinutes: String = ""
    @State private var status: String = ""
    @State private var statusTone: StatusTone = .neutral
    @State private var busy = false
    @Environment(\.conduitTokens) private var t

    enum StatusTone { case neutral, ok, warn, danger }

    public init(channel: DaemonChannel? = nil, agent: String = "claudeCode", cwd: String = "~") {
        self.channel = channel
        _agent = State(initialValue: agent)
        _cwd = State(initialValue: cwd)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                field("Agent") {
                    Picker("", selection: $agent) {
                        Text("Claude Code").tag("claudeCode")
                        Text("Codex").tag("codex")
                        Text("opencode").tag("opencode")
                    }
                    .pickerStyle(.segmented)
                }
                field("Working directory") { input($cwd, placeholder: "~/repos/project") }
                field("Task / prompt") {
                    TextField("Refactor the auth module and run tests", text: $prompt, axis: .vertical)
                        .lineLimit(3...6)
                        .font(.dsMonoPt(12))
                        .padding(10)
                        .background(t.surface, in: RoundedRectangle(cornerRadius: t.radiusMD))
                }
                field("Daily budget USD (optional)") { input($budget, placeholder: "25", numeric: true) }

                DSButton("Dispatch now", systemImage: "play.fill", variant: .primary, isLoading: busy, fullWidth: true) {
                    dispatch()
                }

                Rectangle().fill(t.border).frame(height: 1).padding(.vertical, 4)

                field("Schedule — every N minutes (optional)") { input($everyMinutes, placeholder: "60", numeric: true) }
                DSButton("Save schedule", systemImage: "clock", variant: .secondary, fullWidth: true) {
                    schedule()
                }

                if !status.isEmpty { statusBanner }
            }
            .padding(16)
        }
        .background(t.bg)
    }

    private var statusBanner: some View {
        let color: Color = {
            switch statusTone {
            case .ok: return t.ok
            case .warn: return t.warn
            case .danger: return t.danger
            case .neutral: return t.text2
            }
        }()
        return Text(status)
            .font(.dsMonoPt(12))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(t.surface, in: RoundedRectangle(cornerRadius: t.radiusMD))
    }

    private func field<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.dsSansPt(12, weight: .semibold)).foregroundStyle(t.text2)
            content()
        }
    }

    private func input(_ text: Binding<String>, placeholder: String, numeric: Bool = false) -> some View {
        TextField(placeholder, text: text)
            .font(.dsMonoPt(12))
            .keyboardType(numeric ? .decimalPad : .default)
            .autocorrectionDisabled()
            .padding(10)
            .background(t.surface, in: RoundedRectangle(cornerRadius: t.radiusMD))
    }

    private func dispatch() {
        guard let channel else {
            status = "demo · dispatched \(agent) → running (policy: allow)"
            statusTone = .ok
            return
        }
        busy = true
        Task {
            defer { busy = false }
            do {
                let r = try await channel.dispatchAgent(
                    agent: agent, cwd: cwd, prompt: prompt, budgetUSD: Double(budget) ?? 0
                )
                status = describe(r)
                statusTone = tone(for: r.status)
            } catch {
                status = "error: \(error.localizedDescription)"
                statusTone = .danger
            }
        }
    }

    private func schedule() {
        guard let minutes = Int(everyMinutes), minutes > 0 else {
            status = "enter a positive interval in minutes to schedule"
            statusTone = .warn
            return
        }
        guard let channel else {
            status = "demo · scheduled \(agent) every \(minutes)m"
            statusTone = .ok
            return
        }
        Task {
            do {
                let sc = BridgeSchedule(
                    agent: agent, cwd: cwd, prompt: prompt,
                    everySeconds: minutes * 60, budgetUSD: Double(budget) ?? 0
                )
                let saved = try await channel.addSchedule(sc)
                status = "scheduled · id \(saved.id.prefix(8)) every \(minutes)m"
                statusTone = .ok
            } catch {
                status = "error: \(error.localizedDescription)"
                statusTone = .danger
            }
        }
    }

    private func describe(_ r: DispatchResult) -> String {
        var s = r.status
        if let rule = r.rule { s += " · rule \(rule)" }
        if let msg = r.message { s += " · \(msg)" }
        if let id = r.runId { s += " · run \(id.prefix(8))" }
        return s
    }

    private func tone(for status: String) -> StatusTone {
        switch status {
        case "running": return .ok
        case "needs-approval": return .warn
        case "denied", "budget-exceeded", "error": return .danger
        default: return .neutral
        }
    }
}
#endif
