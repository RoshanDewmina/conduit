#if os(iOS)
import Foundation

/// UI-independent relay-first run dispatch for App Intents. `AppRoot` registers
/// the live handler once the fleet/relay graph is ready.
public enum RunDispatchResult: Sendable {
    case started(runId: String, conversationId: String?, summary: String)
    case blocked(String)
    case unavailable(String)
}

@MainActor
public final class RunDispatchService {
    public static let shared = RunDispatchService()

    public typealias Handler = @MainActor @Sendable (
        _ machineID: String,
        _ vendor: String,
        _ cwd: String,
        _ prompt: String,
        _ budgetUSD: Double?,
        _ model: String?,
        _ onProgress: (@Sendable (String) -> Void)?
    ) async -> RunDispatchResult

    private var handler: Handler?
    private var inFlightTask: Task<Void, Never>?

    public init() {}

    public func setHandler(_ handler: Handler?) {
        self.handler = handler
    }

    public func startRun(
        machineID: String,
        vendor: String,
        cwd: String,
        prompt: String,
        budgetUSD: Double? = nil,
        model: String? = nil,
        onProgress: (@Sendable (String) -> Void)? = nil
    ) async -> RunDispatchResult {
        guard let handler else {
            return .unavailable("Open Lancer first, then try again.")
        }
        onProgress?("dispatching")
        return await handler(machineID, vendor, cwd, prompt, budgetUSD, model, onProgress)
    }

    public func cancelInFlight() {
        inFlightTask?.cancel()
        inFlightTask = nil
    }

    public func trackInFlight(_ task: Task<Void, Never>?) {
        inFlightTask = task
    }
}
#endif
