import XCTest
@testable import AppRoutingSpikeHost

final class TransparentProxyControllerProtocolDispatchTests: XCTestCase {
    private actor DispatchProbe: TransparentProxyControlling {
        private var events: [String] = []

        func start() async throws { events.append("start") }
        func startAndWaitUntilConnected(timeout: Duration) async throws {
            events.append("startAndWait")
        }
        func stopProvider() async throws { events.append("stop") }
        func stopAndWaitUntilDisconnected(timeout: Duration) async throws {
            events.append("stopAndWait")
        }
        func removeOwnedConfiguration() async throws { events.append("removeOne") }
        func removeAllOwnedConfigurations() async throws -> Int {
            events.append("removeAll")
            return 2
        }
        func ownedConfigurationCount() async throws -> Int {
            events.append("ownedCount")
            return 0
        }

        func recordedEvents() -> [String] { events }
    }

    func testExistentialDispatchUsesSafetyCriticalImplementations() async throws {
        let probe = DispatchProbe()
        let controller: any TransparentProxyControlling = probe

        try await controller.startAndWaitUntilConnected(timeout: .seconds(10))
        try await controller.stopAndWaitUntilDisconnected(timeout: .seconds(10))
        let removedCount = try await controller.removeAllOwnedConfigurations()
        let remainingCount = try await controller.ownedConfigurationCount()
        XCTAssertEqual(removedCount, 2)
        XCTAssertEqual(remainingCount, 0)

        let events = await probe.recordedEvents()
        XCTAssertEqual(events, ["startAndWait", "stopAndWait", "removeAll", "ownedCount"])
    }
}
