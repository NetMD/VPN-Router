import Foundation
import Network

nonisolated struct DynamicRouteObservation: Equatable {
    let domain: String
    let ipv4Address: String
    let observedAt: Date
    let expiresAt: Date
}

enum DynamicRoutePlanMerger {
    nonisolated static let minimumRemainingLifetime: TimeInterval = 60

    nonisolated static func merge(
        basePlan: DomainRoutePlan,
        observations: [DynamicRouteObservation],
        at now: Date = Date(),
        maximumRouteCount: Int = DomainRoutePlanner.defaultMaximumRouteCount,
        refreshPolicy: DomainRouteRefreshPolicy = .standard
    ) throws -> DomainRoutePlan {
        let usableObservations = observations.filter {
            $0.expiresAt.timeIntervalSince(now) >= minimumRemainingLifetime
        }
        guard usableObservations.allSatisfy({ IPv4Address($0.ipv4Address) != nil }) else {
            throw DynamicRoutePlanMergeError.invalidObservationAddress
        }
        let profileId = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        let rules = basePlan.domains.map {
            DomainRule(
                profileId: profileId,
                domain: $0,
                includeSubdomains: true,
                enabled: true,
                createdAt: now
            )
        }
        let observedPlan = try DomainRoutePlanner.buildPlan(
            rules: rules,
            resolvedAddresses: usableObservations.map {
                ResolvedDomainAddress(domain: $0.domain, ipv4Address: $0.ipv4Address)
            },
            maximumRouteCount: maximumRouteCount,
            generatedAt: now,
            refreshPolicy: refreshPolicy
        )

        var routesByAddress = Dictionary(
            uniqueKeysWithValues: basePlan.includedRoutes.map {
                ($0.destinationAddress, $0)
            }
        )
        for route in observedPlan.includedRoutes where routesByAddress[route.destinationAddress] == nil {
            routesByAddress[route.destinationAddress] = route
        }
        guard routesByAddress.count <= maximumRouteCount else {
            throw DomainRoutePlannerError.routeLimitExceeded(
                limit: maximumRouteCount,
                actual: routesByAddress.count
            )
        }

        let observedAddresses = Set(observedPlan.includedRoutes.map(\.destinationAddress))
        let observationExpiry = usableObservations
            .filter { observedAddresses.contains($0.ipv4Address) }
            .map(\.expiresAt)
            .min()
        let policyExpiry = refreshPolicy.expirationDate(for: now)
        let expiresAt = min(observationExpiry ?? policyExpiry, policyExpiry)

        return DomainRoutePlan(
            domains: basePlan.domains,
            includedRoutes: routesByAddress.values.sorted {
                if $0.destinationAddress != $1.destinationAddress {
                    return $0.destinationAddress < $1.destinationAddress
                }
                return $0.sourceDomain < $1.sourceDomain
            },
            unresolvedDomains: basePlan.unresolvedDomains,
            ipv6BypassDomains: basePlan.ipv6BypassDomains,
            generatedAt: now,
            expiresAt: expiresAt
        )
    }
}

enum DynamicRoutePlanMergeError: LocalizedError, Equatable {
    case invalidObservationAddress

    var errorDescription: String? {
        "DNS Proxy가 올바르지 않은 IPv4 관찰값을 반환했습니다."
    }
}
