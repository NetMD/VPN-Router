import Foundation

nonisolated struct DomainRouteRefreshPolicy: Equatable {
    static let standard = DomainRouteRefreshPolicy(
        refreshInterval: 5 * 60,
        routeLifetime: 15 * 60
    )

    let refreshInterval: TimeInterval
    let routeLifetime: TimeInterval

    init(refreshInterval: TimeInterval, routeLifetime: TimeInterval) {
        precondition(refreshInterval > 0, "refreshInterval must be positive")
        precondition(routeLifetime >= refreshInterval, "routeLifetime must cover at least one refresh interval")
        self.refreshInterval = refreshInterval
        self.routeLifetime = routeLifetime
    }

    func expirationDate(for generatedAt: Date) -> Date {
        generatedAt.addingTimeInterval(routeLifetime)
    }

    func needsRefresh(_ plan: DomainRoutePlan, at now: Date = Date()) -> Bool {
        now >= plan.generatedAt.addingTimeInterval(refreshInterval)
    }

    func isExpired(_ plan: DomainRoutePlan, at now: Date = Date()) -> Bool {
        now >= plan.expiresAt
    }
}
