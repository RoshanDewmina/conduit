#if os(iOS)
import Foundation

// MARK: - Mock VM / workspace data

struct MockVM: Identifiable {
    let id = UUID()
    let name: String
    let status: String       // "running" | "sleeping" | "stopped"
    let vcpu: Int
    let memGB: Int
    let ratePerHour: Double?
    let cpuPercent: Double
    let memUsedGB: Double
    let gpuPercent: Double
    let costToday: Double
}

// MARK: - Mock Agent (M2a/M2b)

struct MockAgent: Identifiable {
    let id = UUID()
    let name: String
    let model: String
    let provider: String
    let status: String       // "working" | "idle" | "off"
    let costMonth: Double?
    let byok: Bool
}

// MARK: - Mock Port Forward

struct MockPortForward: Identifiable {
    let id = UUID()
    let local: Int
    let remote: Int
    let description: String
}

// MARK: - Mock Workflow Step

struct MockWorkflowStep: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
}

// MARK: - Mock Diagnostic Check

struct MockDiagnosticCheck: Identifiable {
    let id = UUID()
    let label: String
    let status: String
    let timingMS: Int?
    let tone: String  // "ok" | "warn" | "danger"
}

enum ManagementMocks {
    // VMs
    static let vms: [MockVM] = [
        MockVM(name: "gpu-box", status: "running", vcpu: 4, memGB: 16, ratePerHour: 0.06,
               cpuPercent: 38, memUsedGB: 6.2, gpuPercent: 71, costToday: 0.78),
        MockVM(name: "build-runner", status: "sleeping", vcpu: 2, memGB: 8, ratePerHour: nil,
               cpuPercent: 0, memUsedGB: 0, gpuPercent: 0, costToday: 0),
        MockVM(name: "scratch", status: "stopped", vcpu: 1, memGB: 4, ratePerHour: nil,
               cpuPercent: 0, memUsedGB: 0, gpuPercent: 0, costToday: 0),
    ]

    // Agents
    static let agents: [MockAgent] = [
        MockAgent(name: "claude sonnet-4.5", model: "anthropic/claude-sonnet-4-5",
                  provider: "Anthropic", status: "working", costMonth: 2.10, byok: false),
        MockAgent(name: "codex", model: "openai/codex-mini",
                  provider: "OpenAI", status: "idle", costMonth: 0.84, byok: true),
        MockAgent(name: "gemini", model: "google/gemini-2.0-flash",
                  provider: "Google", status: "off", costMonth: nil, byok: false),
    ]

    // Port forwards
    static let portForwards: [MockPortForward] = [
        MockPortForward(local: 3000, remote: 3000, description: "dev server"),
        MockPortForward(local: 5432, remote: 5432, description: "postgres"),
    ]

    // Workflow steps (for "deploy --prod")
    static let workflowSteps: [MockWorkflowStep] = [
        MockWorkflowStep(title: "ssh prod", subtitle: "connect to production"),
        MockWorkflowStep(title: "git pull", subtitle: "fetch latest"),
        MockWorkflowStep(title: "npm build", subtitle: "compile assets"),
        MockWorkflowStep(title: "pm2 restart", subtitle: "reload server"),
    ]

    // Diagnostics
    static let diagnostics: [MockDiagnosticCheck] = [
        MockDiagnosticCheck(label: "DNS resolve",    status: "ok",      timingMS: 12,  tone: "ok"),
        MockDiagnosticCheck(label: "TCP:22",         status: "ok",      timingMS: 38,  tone: "ok"),
        MockDiagnosticCheck(label: "SSH handshake",  status: "ok",      timingMS: 120, tone: "ok"),
        MockDiagnosticCheck(label: "Host key",       status: "trusted", timingMS: nil, tone: "ok"),
        MockDiagnosticCheck(label: "tmux reachable", status: "ok",      timingMS: nil, tone: "ok"),
        MockDiagnosticCheck(label: "Latency",        status: "42 ms",   timingMS: 42,  tone: "warn"),
    ]

    // CPU sparkline (60 values)
    static let cpuSparkline: [Double] = (0..<60).map { i in
        let base = 38.0
        let noise = sin(Double(i) * 0.73) * 8.0
        return min(100, max(0, base + noise))
    }
}
#endif
