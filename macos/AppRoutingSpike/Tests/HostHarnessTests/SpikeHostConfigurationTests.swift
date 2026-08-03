import XCTest
@testable import AppRoutingSpikeHost

final class SpikeHostConfigurationTests: XCTestCase {
    func testValidConfigurationKeepsBothIdentifiers() throws {
        let configuration = try SpikeHostConfiguration(
            extensionIdentifier: "com.example.vpnrouter.approutingspike.proxy",
            machServiceName: "group.com.example.vpnrouter.approutingspike.proxy"
        )

        XCTAssertEqual(
            configuration.extensionIdentifier,
            "com.example.vpnrouter.approutingspike.proxy"
        )
        XCTAssertEqual(
            configuration.machServiceName,
            "group.com.example.vpnrouter.approutingspike.proxy"
        )
    }

    func testEmptyOrUnexpandedConfigurationIsRejectedBeforeXPCInitialization() {
        XCTAssertThrowsError(try SpikeHostConfiguration(
            extensionIdentifier: "",
            machServiceName: ""
        ))
        XCTAssertThrowsError(try SpikeHostConfiguration(
            extensionIdentifier: "$(SPIKE_PROXY_BUNDLE_IDENTIFIER)",
            machServiceName: "$(SPIKE_MACH_SERVICE_NAME)"
        ))
    }
}
