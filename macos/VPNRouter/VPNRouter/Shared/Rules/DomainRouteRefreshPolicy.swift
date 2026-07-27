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

nonisolated struct StaticRoutePlanHistory {
    private struct Entry {
        let route: IPv4RouteDescriptor
        let expiresAt: Date
    }

    private var domains: [String] = []
    private var entriesByAddress: [String: Entry] = [:]

    mutating func merge(
        freshPlan: DomainRoutePlan,
        at now: Date = Date(),
        maximumRouteCount: Int = DomainRoutePlanner.defaultMaximumRouteCount
    ) throws -> DomainRoutePlan {
        if domains != freshPlan.domains {
            domains = freshPlan.domains
            entriesByAddress.removeAll()
        }

        entriesByAddress = entriesByAddress.filter { $0.value.expiresAt > now }
        for route in freshPlan.includedRoutes {
            entriesByAddress[route.destinationAddress] = Entry(
                route: route,
                expiresAt: freshPlan.expiresAt
            )
        }

        guard entriesByAddress.count <= maximumRouteCount else {
            throw DomainRoutePlannerError.routeLimitExceeded(
                limit: maximumRouteCount,
                actual: entriesByAddress.count
            )
        }

        let routes = entriesByAddress.values.map(\.route).sorted {
            if $0.destinationAddress != $1.destinationAddress {
                return $0.destinationAddress < $1.destinationAddress
            }
            return $0.sourceDomain < $1.sourceDomain
        }
        let domainsWithRoutes = Set(routes.map(\.sourceDomain))

        return DomainRoutePlan(
            domains: freshPlan.domains,
            includedRoutes: routes,
            unresolvedDomains: freshPlan.unresolvedDomains.filter {
                !domainsWithRoutes.contains($0)
            },
            ipv6BypassDomains: freshPlan.ipv6BypassDomains,
            generatedAt: freshPlan.generatedAt,
            expiresAt: freshPlan.expiresAt
        )
    }

    mutating func reset() {
        domains.removeAll()
        entriesByAddress.removeAll()
    }
}
