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
}
