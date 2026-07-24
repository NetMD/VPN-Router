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
    let ipv6BypassDomains: [String]
    let generatedAt: Date
    let expiresAt: Date

    init(
        domains: [String],
        includedRoutes: [IPv4RouteDescriptor],
        unresolvedDomains: [String],
        ipv6BypassDomains: [String] = [],
        generatedAt: Date,
        expiresAt: Date
    ) {
        self.domains = domains
        self.includedRoutes = includedRoutes
        self.unresolvedDomains = unresolvedDomains
        self.ipv6BypassDomains = ipv6BypassDomains
        self.generatedAt = generatedAt
        self.expiresAt = expiresAt
    }

    private enum CodingKeys: String, CodingKey {
        case domains
        case includedRoutes
        case unresolvedDomains
        case ipv6BypassDomains
        case generatedAt
        case expiresAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        domains = try container.decode([String].self, forKey: .domains)
        includedRoutes = try container.decode([IPv4RouteDescriptor].self, forKey: .includedRoutes)
        unresolvedDomains = try container.decode([String].self, forKey: .unresolvedDomains)
        ipv6BypassDomains = try container.decodeIfPresent([String].self, forKey: .ipv6BypassDomains) ?? []

        let decodedGeneratedAt = try container.decodeIfPresent(Date.self, forKey: .generatedAt) ?? Date()
        generatedAt = decodedGeneratedAt
        expiresAt = try container.decodeIfPresent(Date.self, forKey: .expiresAt)
            ?? DomainRouteRefreshPolicy.standard.expirationDate(for: decodedGeneratedAt)
    }
}

enum DomainRoutePlanner {
    nonisolated static let defaultMaximumRouteCount = 512
    private nonisolated static let hostRouteSubnetMask = "255.255.255.255"

    nonisolated static func buildPlan(
        rules: [DomainRule],
        resolvedAddresses: [ResolvedDomainAddress],
        resolvedIPv6Domains: [String] = [],
        maximumRouteCount: Int = defaultMaximumRouteCount,
        generatedAt: Date = Date(),
        refreshPolicy: DomainRouteRefreshPolicy = .standard
    ) throws -> DomainRoutePlan {
        precondition(maximumRouteCount >= 0, "maximumRouteCount must not be negative")

        let expandedRules = DomainRuleExpander.expand(rules).filter(\.enabled)
        let normalizedRules = expandedRules.map { rule in
            NormalizedRule(
                domain: DomainRuleExpander.normalize(rule.domain),
                includeSubdomains: rule.includeSubdomains
            )
        }
        let plannedDomains = Array(Set(normalizedRules.map(\.domain))).sorted()
        let ipv6BypassDomains = Array(Set(resolvedIPv6Domains.compactMap { value -> String? in
            let domain = DomainRuleExpander.normalize(value)
            return normalizedRules.contains(where: { $0.matches(domain) }) ? domain : nil
        })).sorted()

        var sourceDomainsByAddress: [String: String] = [:]
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
            if let existingDomain = sourceDomainsByAddress[address.ipv4Address] {
                sourceDomainsByAddress[address.ipv4Address] = min(existingDomain, domain)
            } else {
                sourceDomainsByAddress[address.ipv4Address] = domain
            }
        }

        guard sourceDomainsByAddress.count <= maximumRouteCount else {
            throw DomainRoutePlannerError.routeLimitExceeded(
                limit: maximumRouteCount,
                actual: sourceDomainsByAddress.count
            )
        }

        let plannedRoutes = sourceDomainsByAddress.map { address, sourceDomain in
            IPv4RouteDescriptor(
                destinationAddress: address,
                subnetMask: hostRouteSubnetMask,
                sourceDomain: sourceDomain
            )
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
            },
            ipv6BypassDomains: ipv6BypassDomains,
            generatedAt: generatedAt,
            expiresAt: refreshPolicy.expirationDate(for: generatedAt)
        )
    }
}

enum DomainRoutePlannerError: LocalizedError, Equatable {
    case invalidIPv4Address(String)
    case routeLimitExceeded(limit: Int, actual: Int)

    var errorDescription: String? {
        switch self {
        case .invalidIPv4Address(let address):
            return "확인된 주소가 올바른 IPv4 주소가 아닙니다: \(address)"
        case .routeLimitExceeded(let limit, let actual):
            return "경로 계획에 IPv4 경로가 \(actual)개 있어 안전 제한 \(limit)개를 초과했습니다."
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
