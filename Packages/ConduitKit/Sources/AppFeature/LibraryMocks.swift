#if os(iOS)
import Foundation

// TODO: back with real workflow service

struct MockWorkflow: Identifiable {
    let id = UUID()
    let name: String
    let stepCount: Int
    let lastRun: String
}

enum LibraryMocks {
    static let workflows: [MockWorkflow] = [
        MockWorkflow(name: "deploy --prod", stepCount: 4, lastRun: "2 days ago"),
        MockWorkflow(name: "db backup", stepCount: 3, lastRun: "1 week ago"),
        MockWorkflow(name: "restart services", stepCount: 2, lastRun: "3 days ago"),
        MockWorkflow(name: "tail logs", stepCount: 1, lastRun: "yesterday"),
    ]
}
#endif
