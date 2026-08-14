import Foundation
import XCTest
@testable import AppRoutingSpikeHost

@MainActor
final class SpikeViewModelStartCleanupSecurityTests: XCTestCase {
    private enum TestError: Error { case beginFailed }

    private actor CleanupProbe: TransparentProxyControlling {
        private var events: [String] = []

        func start() async throws { events.append("start") }
        func startAndWaitUntilConnected(timeout: Duration) async throws {
            events.append("startAndWait")
        }
        func stopProvider() async throws { events.append("stop") }
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

    private struct Activator: SystemExtensionActivating {
        func activate() async throws -> SystemExtensionActivationOutcome { .completed }
    }

    private final class Selector: SelectedTestAppSelecting {
        func selectSignedApplication() async throws -> Bool { true }
        func consumeIdentity() throws -> SelectedTestAppIdentity {
            SelectedTestAppIdentity(signingIdentifier: "com.example.selected", teamIdentifier: "EXAMPLETEAM")
        }
        func clear() {}
    }

    private final class FailingXPC: SpikeXPCClientProtocol {
        func beginRun(_ request: SpikeRunRequest) async throws { throw TestError.beginFailed }
        func snapshot(runId: UUID) async throws -> [RedactedFlowResult] { [] }
        func stopRun(runId: UUID) async throws {}
        func invalidate() {}
    }

    func testStartFailureRemovesAllOwnedManagersAndRequeriesZero() async {
        let proxy = CleanupProbe()
        let model = SpikeViewModel(
            systemExtensionActivator: Activator(),
            proxyController: proxy,
            xpcClient: FailingXPC(),
            selectedTestAppSelector: Selector()
        )
        await model.selectTestApp()
        model.setSanitizedFixtureReady(true)
        model.setEntitlementEvidenceState(.confirmed)
        model.setProvisioningEvidenceState(.confirmed)
        model.captureBaseline(dnsAvailable: true, ipv4Available: true, ipv6Available: false)
        await model.requestInstallation()

        await model.start()

        let events = await proxy.recordedEvents()
        XCTAssertEqual(events, ["startAndWait", "stop", "removeAll", "ownedCount"])
        XCTAssertEqual(model.displayState.lifecycle, .stoppedWithError)
        XCTAssertEqual(model.displayState.cleanupPhase, .managerCountVerifiedZero)
    }
}
