#if os(iOS)
import Foundation
import Observation
import LancerCore
import SessionFeature

/// Accumulates streamed output + lifecycle status for dispatched agent runs,
/// keyed by runId. Fed by `ApprovalIngest` from `agent.run.output` /
/// `agent.run.status` daemon notifications; read by `RunDetailView`.
@MainActor @Observable
public final class RunOutputStore {

    public struct Run: Identifiable, Sendable {
        public let runId: String
        public var chunks: [Chunk]
        public var blocks: [ToolBlock]
        public var status: String
        public var exitCode: Int?

        public var id: String { runId }

        public var text: String {
            chunks.sorted { $0.seq < $1.seq }.map(\.chunk).joined()
        }

        public var isTerminal: Bool {
            status == "exited" || status == "failed"
        }
    }

    public struct Chunk: Sendable, Hashable {
        public let seq: Int
        public let stream: String
        public let chunk: String
    }

    public struct ToolBlock: Identifiable, Sendable {
        public let id: String
        public let toolName: String
        public let inputJSON: String
        public var status: ToolStatus
        public enum ToolStatus: Sendable { case running, done }
    }

    public private(set) var runs: [String: Run] = [:]

    public init() {}

    /// Pre-register a freshly dispatched run so the detail view has a slot to
    /// stream into before the first `agent.run.output` arrives. Also marks the
    /// run active in `ActiveRunRegistry` so the Lancer app target's `PauseRunIntent`/
    /// `StopRunIntent` (which cannot see this AppFeature-only store) know it exists.
    public func register(runId: String, status: String = "running") {
        if runs[runId] == nil {
            runs[runId] = Run(runId: runId, chunks: [], blocks: [], status: status, exitCode: nil)
        }
        ActiveRunRegistry.shared.markActive(runId: runId)
    }

    public func appendOutput(_ params: RunOutputParams) {
        guard !params.runId.isEmpty else { return }
        var run = runs[params.runId] ?? Run(runId: params.runId, chunks: [], blocks: [], status: "running", exitCode: nil)
        // Dedupe on seq so a retried/duplicated notification doesn't double-print.
        if !run.chunks.contains(where: { $0.seq == params.seq }) {
            run.chunks.append(Chunk(seq: params.seq, stream: params.stream, chunk: params.chunk))
        }
        runs[params.runId] = run
    }

    public func updateStatus(_ params: RunStatusParams) {
        guard !params.runId.isEmpty else { return }
        var run = runs[params.runId] ?? Run(runId: params.runId, chunks: [], blocks: [], status: params.status, exitCode: nil)
        run.status = params.status
        if let code = params.exitCode { run.exitCode = code }
        runs[params.runId] = run
        if run.isTerminal {
            ActiveRunRegistry.shared.markTerminal(runId: params.runId)
        }
    }

    public func appendToolStart(_ params: ToolStartParams) {
        guard !params.runId.isEmpty else { return }
        var run = runs[params.runId] ?? Run(runId: params.runId, chunks: [], blocks: [], status: "running", exitCode: nil)
        if !run.blocks.contains(where: { $0.id == params.toolId }) {
            run.blocks.append(ToolBlock(id: params.toolId, toolName: params.toolName, inputJSON: params.inputJSON, status: .running))
        }
        runs[params.runId] = run
    }

    public func markToolDone(runId: String, toolId: String) {
        guard var run = runs[runId] else { return }
        if let idx = run.blocks.firstIndex(where: { $0.id == toolId }) {
            run.blocks[idx].status = .done
        }
        runs[runId] = run
    }

    public func run(_ runId: String) -> Run? { runs[runId] }

    public func clear(_ runId: String) {
        runs[runId] = nil
        ActiveRunRegistry.shared.markTerminal(runId: runId)
    }
}
#endif
