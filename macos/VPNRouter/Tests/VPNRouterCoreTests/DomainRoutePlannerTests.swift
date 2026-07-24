import XCTest
@testable import VPNRouterCore

final class DomainRoutePlannerTests: XCTestCase {
    private let profileId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    func testBuildPlanDeduplicatesSameIPAddressAcrossDomains() throws {
        let plan = try DomainRoutePlanner.buildPlan(
            rules: [
                makeRule(domain: "example.com"),
                makeRule(domain: "media.example.com")
            ],
            resolvedAddresses: [
                ResolvedDomainAddress(domain: "example.com", ipv4Address: "203.0.113.10"),
                ResolvedDomainAddress(domain: "media.example.com", ipv4Address: "203.0.113.10"),
                ResolvedDomainAddress(domain: "example.com", ipv4Address: "203.0.113.10")
            ]
        )

        XCTAssertEqual(plan.includedRoutes, [
            IPv4RouteDescriptor(
                destinationAddress: "203.0.113.10",
                subnetMask: "255.255.255.255",
                sourceDomain: "example.com"
            )
        ])
        XCTAssertTrue(plan.unresolvedDomains.isEmpty)
    }

    func testBuildPlanIncludesMatchingSubdomainAndExcludesUnrelatedAddress() throws {
        let plan = try DomainRoutePlanner.buildPlan(
            rules: [makeRule(domain: "example.com")],
            resolvedAddresses: [
                ResolvedDomainAddress(domain: "cdn.example.com", ipv4Address: "203.0.113.11"),
                ResolvedDomainAddress(domain: "unrelated.test", ipv4Address: "198.51.100.20")
            ]
        )

        XCTAssertEqual(plan.includedRoutes.map(\.destinationAddress), ["203.0.113.11"])
    }

    func testBuildPlanRejectsInvalidMatchingIPv4Address() {
        XCTAssertThrowsError(try DomainRoutePlanner.buildPlan(
            rules: [makeRule(domain: "example.com")],
            resolvedAddresses: [
                ResolvedDomainAddress(domain: "example.com", ipv4Address: "not-an-address")
            ]
        )) { error in
            XCTAssertEqual(error as? DomainRoutePlannerError, .invalidIPv4Address("not-an-address"))
        }
    }

    func testBuildPlanRejectsRoutesOverConfiguredLimit() {
        XCTAssertThrowsError(try DomainRoutePlanner.buildPlan(
            rules: [makeRule(domain: "example.com")],
            resolvedAddresses: [
                ResolvedDomainAddress(domain: "example.com", ipv4Address: "203.0.113.1"),
                ResolvedDomainAddress(domain: "example.com", ipv4Address: "203.0.113.2")
            ],
            maximumRouteCount: 1
        )) { error in
            XCTAssertEqual(
                error as? DomainRoutePlannerError,
                .routeLimitExceeded(limit: 1, actual: 2)
            )
        }
    }

    func testBuildPlanRecordsDeterministicLifetime() throws {
        let generatedAt = Date(timeIntervalSince1970: 1_000)
        let policy = DomainRouteRefreshPolicy(refreshInterval: 60, routeLifetime: 180)

        let plan = try DomainRoutePlanner.buildPlan(
            rules: [makeRule(domain: "example.com")],
            resolvedAddresses: [
                ResolvedDomainAddress(domain: "example.com", ipv4Address: "203.0.113.1")
            ],
            generatedAt: generatedAt,
            refreshPolicy: policy
        )

        XCTAssertEqual(plan.generatedAt, generatedAt)
        XCTAssertEqual(plan.expiresAt, Date(timeIntervalSince1970: 1_180))
    }

    func testBuildPlanReportsOnlyMatchingIPv6BypassDomains() throws {
        let plan = try DomainRoutePlanner.buildPlan(
            rules: [makeRule(domain: "example.com")],
            resolvedAddresses: [
                ResolvedDomainAddress(domain: "example.com", ipv4Address: "203.0.113.1")
            ],
            resolvedIPv6Domains: [
                "EXAMPLE.COM",
                "cdn.example.com",
                "cdn.example.com",
                "unrelated.test"
            ]
        )

        XCTAssertEqual(plan.ipv6BypassDomains, ["cdn.example.com", "example.com"])
    }

    private func makeRule(domain: String) -> DomainRule {
        DomainRule(
            profileId: profileId,
            domain: domain,
            includeSubdomains: true,
            enabled: true,
            createdAt: Date(timeIntervalSince1970: 0)
        )
    }
}
