#if os(iOS)
import SwiftUI
import Observation
import ConduitCore
import TerminalEngine
import DesignSystem

@MainActor @Observable
public class RelayChatViewModel {
    private let blockRenderer: BlockRenderer
    private let runControl: RunControlStore

    // P0.8: Coalescing buffer — per-block to avoid cross-block bleed
    private let coalesceInterval: Duration = .milliseconds(50)
    private var pendingTextByBlock: [BlockID: String] = [:]
    private var flushTask: Task<Void, Never>?

    public init(blockRenderer: BlockRenderer, runControl: RunControlStore) {
        self.blockRenderer = blockRenderer
        self.runControl = runControl
    }

    // MARK: - P0.8: Stream coalescing buffer (50ms flush)

    public func enqueueDelta(_ text: String, blockID: BlockID) {
        pendingTextByBlock[blockID, default: ""] += text
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: self?.coalesceInterval ?? .milliseconds(50))
            await MainActor.run { [weak self] in
                guard let self else { return }
                for (id, text) in self.pendingTextByBlock where !text.isEmpty {
                    self.appendCoalesced(text, blockID: id)
                }
                self.pendingTextByBlock.removeAll()
                self.flushTask = nil
            }
        }
    }

    private func appendCoalesced(_ text: String, blockID: BlockID) {
        guard let data = text.data(using: .utf8) else { return }
        blockRenderer.append(data, stream: .stdout, to: blockID)
    }

    // MARK: - P1.7: Haptic feedback map

    public func hapticForFirstToken() {
        Haptics.light()
    }

    public func hapticForBlockComplete() {
        Haptics.selection()
    }

    public func hapticForBlockError() {
        Haptics.warning()
    }

    public func hapticForMessageSent() {
        Haptics.light()
    }

    public func hapticForRunStop() {
        Haptics.medium()
    }

    public func hapticForApprovalNeeded() {
        Haptics.selection()
    }

    // MARK: - P2.4: Budget burn display

    /// Estimates budget burn from blocks. Uses a rough heuristic: each block
    /// with output contributes ~$0.01–0.05 based on output length.
    public func budgetBurn(blocks: [Block]) -> Double {
        var total: Double = 0
        for block in blocks {
            let outputLen = block.joinedOutput.count
            // Rough heuristic: ~$0.0001 per character of output, min $0.01 per block
            total += max(0.01, Double(outputLen) * 0.0001)
        }
        return min(total, 99.99)
    }

    /// Formats budget as a compact string like "$0.04" or "$1.23"
    public func formatBudget(_ amount: Double) -> String {
        if amount < 1.0 {
            return String(format: "$%.2f", amount)
        }
        return String(format: "$%.2f", amount)
    }

    /// Run duration in seconds from the first block's start to now or last block's end.
    public func runDuration(blocks: [Block]) -> TimeInterval {
        guard let first = blocks.first else { return 0 }
        let end = blocks.last?.finishedAt ?? Date()
        return end.timeIntervalSince(first.startedAt)
    }

    /// Formats duration as compact string like "12.4s" or "2m 15s"
    public func formatDuration(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return String(format: "%.1fs", seconds)
        }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return "\(mins)m \(secs)s"
    }

}
#endif
