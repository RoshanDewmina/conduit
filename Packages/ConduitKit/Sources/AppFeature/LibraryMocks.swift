#if os(iOS)
import Foundation

// TODO: back with real workflow + agent services

struct MockWorkflow: Identifiable {
    let id = UUID()
    let name: String
    let stepCount: Int
    let lastRun: String
}

struct MockAgent: Identifiable {
    let id = UUID()
    let name: String
    let model: String
    let isActive: Bool
    let monthlyCost: String
}

enum LibraryMocks {
    static let workflows: [MockWorkflow] = [
        MockWorkflow(name: "deploy --prod", stepCount: 4, lastRun: "2 days ago"),
        MockWorkflow(name: "db backup", stepCount: 3, lastRun: "1 week ago"),
        MockWorkflow(name: "restart services", stepCount: 2, lastRun: "3 days ago"),
        MockWorkflow(name: "tail logs", stepCount: 1, lastRun: "yesterday"),
    ]

    static let agents: [MockAgent] = [
        MockAgent(name: "claude", model: "claude-sonnet-4-6", isActive: true, monthlyCost: "$4.32"),
        MockAgent(name: "codex", model: "gpt-4o", isActive: false, monthlyCost: "$1.08"),
    ]
}
#endif
