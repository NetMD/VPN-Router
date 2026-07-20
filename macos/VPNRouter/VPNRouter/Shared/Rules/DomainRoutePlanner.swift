import Foundation
import Network

nonisolated struct ResolvedDomainAddress: Equatable {
    let domain: String
    let ipv4Address: String

    init(domain: String, ipv4Address: String) {
        self.domain = domain
        self.ipv4Address = ipv4Address
    }
}

nonisolated struct IPv4RouteDescriptor: Codable, Equatable {
    let destinationAddress: String
    let subnetMask: String
    let sourceDomain: String
}

nonisolated struct DomainRoutePlan: Codable, Equatable {
    let domains: [String]
    let includedRoutes: [IPv4RouteDescriptor]
    let unresolvedDomains: [String]
}

enum DomainRoutePlanner {
    private nonisolated static let hostRouteSubnetMask = "255.255.255.255"

    nonisolated static func buildPlan(
        rules: [DomainRule],
        resolvedAddresses: [ResolvedDomainAddress]
    ) throws -> DomainRoutePlan {
        let expandedRules = DomainRuleExpander.expand(rules).filter(\.enabled)
        let normalizedRules = expandedRules.map { rule in
            NormalizedRule(
                domain: DomainRuleExpander.normalize(rule.domain),
                includeSubdomains: rule.includeSubdomains
            )
        }
        let plannedDomains = Array(Set(normalizedRules.map(\.domain))).sorted()

        var plannedRoutes: [IPv4RouteDescriptor] = []
        var routeKeys = Set<String>()
        var resolvedDomains = Set<String>()

        for address in resolvedAddresses {
            let domain = DomainRuleExpander.normalize(address.domain)
            guard normalizedRules.contains(where: { $0.matches(domain) }) else {
                continue
            }

            guard IPv4Address(address.ipv4Address) != nil else {
                throw DomainRoutePlannerError.invalidIPv4Address(address.ipv4Address)
            }

            resolvedDomains.insert(domain)
            let routeKey = "\(address.ipv4Address)|\(domain)"
            guard routeKeys.insert(routeKey).inserted else {
                continue
            }

            plannedRoutes.append(IPv4RouteDescriptor(
                destinationAddress: address.ipv4Address,
                subnetMask: hostRouteSubnetMask,
                sourceDomain: domain
            ))
        }

        return DomainRoutePlan(
            domains: plannedDomains,
            includedRoutes: plannedRoutes.sorted { lhs, rhs in
                if lhs.destinationAddress == rhs.destinationAddress {
                    return lhs.sourceDomain < rhs.sourceDomain
                }
                return lhs.destinationAddress < rhs.destinationAddress
            },
            unresolvedDomains: plannedDomains.filter { domain in
                !resolvedDomains.contains(domain)
            }
        )
    }
}

enum DomainRoutePlannerError: LocalizedError, Equatable {
    case invalidIPv4Address(String)

    var errorDescription: String? {
        switch self {
        case .invalidIPv4Address(let address):
            return "Resolved address is not a valid IPv4 address: \(address)"
        }
    }
}

private nonisolated struct NormalizedRule: Equatable {
    let domain: String
    let includeSubdomains: Bool

    func matches(_ resolvedDomain: String) -> Bool {
        resolvedDomain == domain || (includeSubdomains && resolvedDomain.hasSuffix(".\(domain)"))
    }
}
