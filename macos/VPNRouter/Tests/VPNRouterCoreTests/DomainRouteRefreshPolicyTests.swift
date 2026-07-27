import XCTest
@testable import VPNRouterCore

final class DomainRouteRefreshPolicyTests: XCTestCase {
    func testRefreshAndExpirationBoundaries() {
        let policy = DomainRouteRefreshPolicy(refreshInterval: 60, routeLifetime: 180)
        let plan = makePlan(generatedAt: Date(timeIntervalSince1970: 1_000), policy: policy)

        XCTAssertFalse(policy.needsRefresh(plan, at: Date(timeIntervalSince1970: 1_059)))
        XCTAssertTrue(policy.needsRefresh(plan, at: Date(timeIntervalSince1970: 1_060)))
        XCTAssertFalse(policy.isExpired(plan, at: Date(timeIntervalSince1970: 1_179)))
        XCTAssertTrue(policy.isExpired(plan, at: Date(timeIntervalSince1970: 1_180)))
    }

    func testLegacyPlanDecodeReceivesBoundedLifetime() throws {
        let legacyJSON = """
        {
          "domains": ["example.com"],
          "includedRoutes": [],
          "unresolvedDomains": ["example.com"]
        }
        """.data(using: .utf8)!

        let beforeDecode = Date()
        let plan = try JSONDecoder().decode(DomainRoutePlan.self, from: legacyJSON)
        let afterDecode = Date()

        XCTAssertGreaterThanOrEqual(plan.generatedAt, beforeDecode)
        XCTAssertLessThanOrEqual(plan.generatedAt, afterDecode)
        XCTAssertEqual(
            plan.expiresAt.timeIntervalSince(plan.generatedAt),
            DomainRouteRefreshPolicy.standard.routeLifetime,
            accuracy: 0.001
        )
    }

    func testCurrentPlanRoundTripsTimestamps() throws {
        let policy = DomainRouteRefreshPolicy(refreshInterval: 60, routeLifetime: 180)
        let original = makePlan(
            generatedAt: Date(timeIntervalSinceReferenceDate: 1_000),
            policy: policy
        )

        let decoded = try JSONDecoder().decode(
            DomainRoutePlan.self,
            from: JSONEncoder().encode(original)
        )

        XCTAssertEqual(decoded, original)
    }

    private func makePlan(generatedAt: Date, policy: DomainRouteRefreshPolicy) -> DomainRoutePlan {
        DomainRoutePlan(
            domains: ["example.com"],
            includedRoutes: [],
            unresolvedDomains: ["example.com"],
            generatedAt: generatedAt,
            expiresAt: policy.expirationDate(for: generatedAt)
        )
    }

    func testStaticHistoryRetainsRotatedAddressesUntilTheirOriginalExpiry() throws {
        let start = Date(timeIntervalSince1970: 1_000)
        var history = StaticRoutePlanHistory()
        let first = makePlan(
            address: "203.0.113.10",
            generatedAt: start
        )
        let second = makePlan(
            address: "203.0.113.20",
            generatedAt: start.addingTimeInterval(5 * 60)
        )

        _ = try history.merge(freshPlan: first, at: start)
        let rotated = try history.merge(
            freshPlan: second,
            at: start.addingTimeInterval(5 * 60)
        )
        XCTAssertEqual(
            Set(rotated.includedRoutes.map(\.destinationAddress)),
            ["203.0.113.10", "203.0.113.20"]
        )

        let expired = try history.merge(
            freshPlan: second,
            at: start.addingTimeInterval(15 * 60)
        )
        XCTAssertEqual(
            expired.includedRoutes.map(\.destinationAddress),
            ["203.0.113.20"]
        )
    }

    func testStaticHistoryResetsWhenExpandedDomainSetChanges() throws {
        let start = Date(timeIntervalSince1970: 1_000)
        var history = StaticRoutePlanHistory()
        _ = try history.merge(
            freshPlan: makePlan(address: "203.0.113.10", generatedAt: start),
            at: start
        )
        let replacement = DomainRoutePlan(
            domains: ["netflix.com"],
            includedRoutes: [
                IPv4RouteDescriptor(
                    destinationAddress: "203.0.113.20",
                    subnetMask: "255.255.255.255",
                    sourceDomain: "netflix.com"
                )
            ],
            unresolvedDomains: [],
            generatedAt: start.addingTimeInterval(60),
            expiresAt: start.addingTimeInterval(16 * 60)
        )

        let result = try history.merge(
            freshPlan: replacement,
            at: start.addingTimeInterval(60)
        )
        XCTAssertEqual(
            result.includedRoutes.map(\.destinationAddress),
            ["203.0.113.20"]
        )
    }

    private func makePlan(address: String, generatedAt: Date) -> DomainRoutePlan {
        DomainRoutePlan(
            domains: ["youtube.com"],
            includedRoutes: [
                IPv4RouteDescriptor(
                    destinationAddress: address,
                    subnetMask: "255.255.255.255",
                    sourceDomain: "youtube.com"
                )
            ],
            unresolvedDomains: [],
            generatedAt: generatedAt,
            expiresAt: generatedAt.addingTimeInterval(15 * 60)
        )
    }
}
