#if os(iOS)
import SwiftUI
import DesignSystem
import AgentKit
import SettingsFeature

/// Interactive one-shot command console against an agent's ssh-host. Streams
/// stdout/stderr live via `store.execStream`. ssh-host runtime only.
struct AgentExecView: View {
    let store: AgentStore
    let agent: HostedAgent

    @Environment(\.conduitTokens) private var t
    @Environment(\.dismiss) private var dismiss

    @State private var command = ""
    @State private var output = ""
    @State private var running = false
    @State private var execTask: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .top) {
            t.termBg.ignoresSafeArea()
            VStack(spacing: 0) {
                DSDetailHeader("exec — \(agent.name)", onBack: { dismiss() })
                outputView
                inputBar
            }
        }
        .navigationBarHidden(true)
        .onDisappear { execTask?.cancel() }
    }

    private var outputView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(output.isEmpty ? "Run a command on \(agent.hostID ?? "the host")…" : output)
                    .font(.dsMonoPt(12))
                    .foregroundStyle(output.isEmpty ? t.termText.opacity(0.5) : t.termText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(12)
                    .id("bottom")
            }
            .onChange(of: output) { _, _ in
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            Text("$")
                .font(.dsMonoPt(13, weight: .bold))
                .foregroundStyle(t.termPrompt)
            TextField("command", text: $command)
                .font(.dsMonoPt(13))
                .foregroundStyle(t.termText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .submitLabel(.send)
                .onSubmit { run() }
            if running {
                DSButton("Stop", variant: .destructive, size: .sm, mono: true) { stop() }
            } else {
                DSButton("Run", variant: .accent, size: .sm, mono: true) { run() }
                    .disabled(command.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(12)
        .background(t.termSurface)
    }

    private func run() {
        let cmd = command.trimmingCharacters(in: .whitespaces)
        guard !cmd.isEmpty, !running else { return }
        output += "\n$ \(cmd)\n"
        command = ""
        running = true
        execTask = Task {
            do {
                for try await chunk in store.execStream(agent: agent, command: cmd) {
                    output += chunk
                }
            } catch {
                output += "\n[error] \(error.localizedDescription)\n"
            }
            running = false
        }
    }

    private func stop() {
        execTask?.cancel()
        running = false
        output += "\n[cancelled]\n"
    }
}
#endif
