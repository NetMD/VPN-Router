import Foundation
import XCTest
@testable import VPNRouterCore

final class TroubleshootingReportTests: XCTestCase {
    func testExportContainsOnlyBoundedStatusAndCounts() throws {
        let report = TroubleshootingReport(
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            app: .init(version: "0.1.0", build: "12"),
            system: .init(operatingSystem: "macOS", architecture: "arm64"),
            connection: .init(
                state: "disconnected",
                stage: "verifyingDNSProxy",
                failureCode: "dns-proxy-xpc-unready",
                configurationInstalled: true,
                packetTunnelSessionAvailable: false
            ),
            routing: .init(
                plannedRouteCount: 27,
                unresolvedDomainCount: 3,
                ipv6BypassRiskDomainCount: 7,
                generatedAt: nil,
                expiresAt: nil
            ),
            storage: .init(profileCount: 1, selectedSiteCount: 2),
            protection: .init(
                routeExpiryDisconnectEnabled: true,
                stateOwnership: "vpn-router-only"
            ),
            lifecycle: .init(
                networkState: "available",
                networkChangeCount: 1,
                sleepCount: 0,
                wakeCount: 0
            )
        )

        let data = try TroubleshootingReportEncoder.encode(report)
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(text.contains("\"schemaVersion\" : 2"))
        XCTAssertTrue(text.contains("\"plannedRouteCount\" : 27"))
        XCTAssertTrue(text.contains("\"stage\" : \"verifyingDNSProxy\""))
        XCTAssertTrue(text.contains("\"failureCode\" : \"dns-proxy-xpc-unready\""))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("privatekey"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("sanitizedconfiguration"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("dnspayload"))
        XCTAssertFalse(text.contains("[Interface]"))
        XCTAssertFalse(text.contains("example.com"))
        XCTAssertFalse(text.contains("203.0.113.10"))
    }

    func testExportRoundTripsSchema() throws {
        let report = TroubleshootingReport(
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            app: .init(version: "0.1.0", build: "12"),
            system: .init(operatingSystem: "macOS", architecture: "arm64"),
            connection: .init(
                state: "connected",
                stage: "ready",
                failureCode: nil,
                configurationInstalled: true,
                packetTunnelSessionAvailable: true
            ),
            routing: .init(
                plannedRouteCount: 8,
                unresolvedDomainCount: 0,
                ipv6BypassRiskDomainCount: 1,
                generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
                expiresAt: Date(timeIntervalSince1970: 1_700_000_900)
            ),
            storage: .init(profileCount: 2, selectedSiteCount: 4),
            protection: .init(
                routeExpiryDisconnectEnabled: true,
                stateOwnership: "vpn-router-only"
            ),
            lifecycle: .init(
                networkState: "available",
                networkChangeCount: 2,
                sleepCount: 1,
                wakeCount: 1
            )
        )

        let data = try TroubleshootingReportEncoder.encode(report)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(TroubleshootingReport.self, from: data)

        XCTAssertEqual(decoded, report)
        XCTAssertEqual(decoded.schemaVersion, TroubleshootingReport.currentSchemaVersion)
    }
}
