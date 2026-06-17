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

    // P0.8: Coalescing buffer
    private let coalesceInterval: Duration = .milliseconds(50)
    private var pendingText = ""
    private var flushTask: Task<Void, Never>?

    public init(blockRenderer: BlockRenderer, runControl: RunControlStore) {
        self.blockRenderer = blockRenderer
        self.runControl = runControl
    }

    // MARK: - P0.8: Stream coalescing buffer (50ms flush)

    public func enqueueDelta(_ text: String, blockID: BlockID) {
        pendingText += text
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: self?.coalesceInterval ?? .milliseconds(50))
            await MainActor.run { [weak self] in
                guard let self else { return }
                if !self.pendingText.isEmpty {
                    self.appendCoalesced(self.pendingText, blockID: blockID)
                    self.pendingText = ""
                }
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

    // MARK: - P0.3: SpectrumBar mode mapping

    public func spectrumMode(
        runStatus: RunControlStatus,
        agentState: AgentState,
        blocks: [Block]
    ) -> SpectrumMode {
        switch runStatus {
        case .stopped, .budgetExceeded: return .idle
        case .paused: return .idle
        case .running:
            switch agentState {
            case .thinking: return .loading
            case .streaming: return .working
            case .approval: return .working
            case .done: return .idle
            case .error: return .scan
            case .offline: return .scan
            }
        }
    }
}
#endif
