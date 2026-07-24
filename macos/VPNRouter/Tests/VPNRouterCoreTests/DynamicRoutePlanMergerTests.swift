import XCTest
@testable import VPNRouterCore

final class DynamicRoutePlanMergerTests: XCTestCase {
    func testMergesActiveObservedRoutesAndUsesEarliestTTL() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let basePlan = makeBasePlan(now: now)

        let merged = try DynamicRoutePlanMerger.merge(
            basePlan: basePlan,
            observations: [
                makeObservation(address: "203.0.113.20", expiresAt: now.addingTimeInterval(120)),
                makeObservation(address: "203.0.113.21", expiresAt: now.addingTimeInterval(60))
            ],
            at: now
        )

        XCTAssertEqual(
            merged.includedRoutes.map(\.destinationAddress),
            ["203.0.113.10", "203.0.113.20", "203.0.113.21"]
        )
        XCTAssertEqual(merged.expiresAt, now.addingTimeInterval(60))
    }

    func testExcludesExpiredAndNearlyExpiredObservations() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let merged = try DynamicRoutePlanMerger.merge(
            basePlan: makeBasePlan(now: now),
            observations: [
                makeObservation(address: "203.0.113.20", expiresAt: now),
                makeObservation(address: "203.0.113.21", expiresAt: now.addingTimeInterval(59))
            ],
            at: now
        )

        XCTAssertEqual(merged.includedRoutes.map(\.destinationAddress), ["203.0.113.10"])
        XCTAssertEqual(
            merged.expiresAt,
            DomainRouteRefreshPolicy.standard.expirationDate(for: now)
        )
    }

    func testStaticRouteWinsWhenObservationUsesSameAddress() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let merged = try DynamicRoutePlanMerger.merge(
            basePlan: makeBasePlan(now: now),
            observations: [
                makeObservation(address: "203.0.113.10", expiresAt: now.addingTimeInterval(60))
            ],
            at: now
        )

        XCTAssertEqual(merged.includedRoutes.count, 1)
        XCTAssertEqual(merged.includedRoutes[0].sourceDomain, "example.com")
    }

    func testRejectsCombinedRoutesOverLimit() {
        let now = Date(timeIntervalSince1970: 1_000)

        XCTAssertThrowsError(try DynamicRoutePlanMerger.merge(
            basePlan: makeBasePlan(now: now),
            observations: [
                makeObservation(address: "203.0.113.20", expiresAt: now.addingTimeInterval(60))
            ],
            at: now,
            maximumRouteCount: 1
        )) { error in
            XCTAssertEqual(
                error as? DomainRoutePlannerError,
                .routeLimitExceeded(limit: 1, actual: 2)
            )
        }
    }

    func testRejectsInvalidObservationWithoutEchoingAddress() {
        let now = Date(timeIntervalSince1970: 1_000)

        XCTAssertThrowsError(try DynamicRoutePlanMerger.merge(
            basePlan: makeBasePlan(now: now),
            observations: [
                makeObservation(address: "not-an-address", expiresAt: now.addingTimeInterval(60))
            ],
            at: now
        )) { error in
            XCTAssertEqual(
                error as? DynamicRoutePlanMergeError,
                .invalidObservationAddress
            )
            XCTAssertFalse(error.localizedDescription.contains("not-an-address"))
        }
    }

    private func makeBasePlan(now: Date) -> DomainRoutePlan {
        DomainRoutePlan(
            domains: ["example.com"],
            includedRoutes: [
                IPv4RouteDescriptor(
                    destinationAddress: "203.0.113.10",
                    subnetMask: "255.255.255.255",
                    sourceDomain: "example.com"
                )
            ],
            unresolvedDomains: [],
            generatedAt: now,
            expiresAt: DomainRouteRefreshPolicy.standard.expirationDate(for: now)
        )
    }

    private func makeObservation(address: String, expiresAt: Date) -> DynamicRouteObservation {
        DynamicRouteObservation(
            domain: "cdn.example.com",
            ipv4Address: address,
            observedAt: expiresAt.addingTimeInterval(-30),
            expiresAt: expiresAt
        )
    }
}
