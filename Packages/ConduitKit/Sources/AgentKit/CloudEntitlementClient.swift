import Foundation

/// Stripe subscription entitlement returned by push-backend.
public struct CloudEntitlement: Codable, Sendable, Equatable {
    public let customerId: String?
    public let subscriptionId: String?
    public let status: String
    public let active: Bool
    public let priceId: String?
    public let appAccountToken: String?
    public let currentPeriodEnd: Int64?
    public let updatedAt: String?
    /// Provisioned OpenRouter sub-key when the user is on the managed AI tier.
    public let openRouterAPIKey: String?
    /// Server-issued bearer token for control-plane /agents and /runs endpoints.
    public let clientToken: String?
    /// Team org id when the subscription is org-scoped (Phase 3 stub).
    public let orgId: String?
    public let orgName: String?

    public init(
        customerId: String? = nil,
        subscriptionId: String? = nil,
        status: String = "not_found",
        active: Bool = false,
        priceId: String? = nil,
        appAccountToken: String? = nil,
        currentPeriodEnd: Int64? = nil,
        updatedAt: String? = nil,
        openRouterAPIKey: String? = nil,
        clientToken: String? = nil,
        orgId: String? = nil,
        orgName: String? = nil
    ) {
        self.customerId = customerId
        self.subscriptionId = subscriptionId
        self.status = status
        self.active = active
        self.priceId = priceId
        self.appAccountToken = appAccountToken
        self.currentPeriodEnd = currentPeriodEnd
        self.updatedAt = updatedAt
        self.openRouterAPIKey = openRouterAPIKey
        self.clientToken = clientToken
        self.orgId = orgId
        self.orgName = orgName
    }

    public var teamOrg: TeamOrgInfo? {
        guard let orgId, !orgId.isEmpty else { return nil }
        let name = orgName?.isEmpty == false ? orgName! : orgId
        return TeamOrgInfo(orgId: orgId, displayName: name)
    }
}

public enum CloudEntitlementError: Error, Sendable, Equatable {
    case unavailable(status: Int?)
    case notConfigured
}

/// Policy helper — keeps Apple IAP (`isPro`) separate from Stripe cloud entitlement.
public enum CloudEntitlementPolicy {
    public static func hasCloudEntitlement(
        _ entitlement: CloudEntitlement?,
        backendURLConfigured: Bool,
        debugBypass: Bool = false
    ) -> Bool {
        #if DEBUG
        if debugBypass { return true }
        if !backendURLConfigured { return true }
        #endif
        return entitlement?.active == true
    }
}

/// Fetches cloud subscription entitlement from push-backend.
public struct CloudEntitlementClient: Sendable {
    public let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    public var isConfigured: Bool {
        !baseURL.absoluteString.isEmpty
    }

    /// GET /billing/entitlement — falls back to /billing/subscription-status.
    public func fetch(
        customerId: String?,
        appAccountToken: String? = nil,
        checkoutSessionId: String? = nil
    ) async throws -> CloudEntitlement {
        var components = URLComponents(url: baseURL.appendingPathComponent("billing/entitlement"), resolvingAgainstBaseURL: false)!
        var query: [URLQueryItem] = []
        if let customerId, !customerId.isEmpty {
            query.append(URLQueryItem(name: "customerId", value: customerId))
        }
        if let appAccountToken, !appAccountToken.isEmpty {
            query.append(URLQueryItem(name: "appAccountToken", value: appAccountToken))
        }
        if let checkoutSessionId, !checkoutSessionId.isEmpty {
            query.append(URLQueryItem(name: "checkoutSessionId", value: checkoutSessionId))
        }
        if !query.isEmpty {
            components.queryItems = query
        }

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 404 {
            return try await fetchLegacyStatus(customerId: customerId, checkoutSessionId: checkoutSessionId)
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode
            throw CloudEntitlementError.unavailable(status: code)
        }
        return try JSONDecoder().decode(CloudEntitlement.self, from: data)
    }

    private func fetchLegacyStatus(customerId: String?, checkoutSessionId: String?) async throws -> CloudEntitlement {
        var components = URLComponents(url: baseURL.appendingPathComponent("billing/subscription-status"), resolvingAgainstBaseURL: false)!
        var query: [URLQueryItem] = []
        if let customerId, !customerId.isEmpty {
            query.append(URLQueryItem(name: "customerId", value: customerId))
        }
        if let checkoutSessionId, !checkoutSessionId.isEmpty {
            query.append(URLQueryItem(name: "checkoutSessionId", value: checkoutSessionId))
        }
        components.queryItems = query.isEmpty ? nil : query

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode
            throw CloudEntitlementError.unavailable(status: code)
        }
        return try JSONDecoder().decode(CloudEntitlement.self, from: data)
    }
}
