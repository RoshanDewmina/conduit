#if os(iOS)
import Foundation
import Observation
import LancerCore
import SSHTransport

/// Manages per-provider quota status and spend guardrails.
@MainActor @Observable
public final class QuotaGuardStore {
    public var providers: [QuotaGuard.ProviderQuota] = []
    public var alerts: [QuotaGuard.SpendAlert] = []
    public var isLoading = false

    private var channel: DaemonChannel?

    public init() {}

    /// Attach or replace the daemon channel for live updates.
    public func setChannel(_ channel: DaemonChannel) {
        self.channel = channel
    }

    /// Total spend across all providers today.
    public var totalSpendToday: Double {
        providers.reduce(0) { $0 + $1.spentTodayUSD }
    }

    /// Whether any provider is over its daily cap.
    public var hasOverLimit: Bool {
        providers.contains { $0.isOverLimit }
    }

    /// Whether any provider is near (>=80%) its daily cap.
    public var hasNearLimit: Bool {
        providers.contains { $0.isNearLimit }
    }

    /// Reload quota status from the daemon.
    public func refresh() async {
        guard let channel else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await channel.getQuotaStatus()
            providers = result.providers
            alerts = result.alerts
        } catch {
            // Silently swallow — UI stays on stale data.
        }
    }

    /// Set daily and/or monthly USD caps for a provider.
    public func setCap(provider: String, dailyUSD: Double, monthlyUSD: Double) async throws {
        guard let channel else { return }
        _ = try await channel.setProviderCap(provider: provider, dailyUSD: dailyUSD, monthlyUSD: monthlyUSD)
        await refresh()
    }
}
#endif
