import Foundation
import XCTest
@testable import AppRoutingSpikeHost

@MainActor
final class SpikeViewModelTests: XCTestCase {
    private final class EventRecorder: @unchecked Sendable {
        var events: [String] = []
    }

    private struct FakeActivator: SystemExtensionActivating {
        let recorder: EventRecorder

        func activate() async throws {
            recorder.events.append("activate")
        }
    }

    private struct FakeProxy: TransparentProxyControlling {
        let recorder: EventRecorder

        func start() async throws {
            recorder.events.append("proxy-start")
        }

        func stopProvider() async throws {
            recorder.events.append("proxy-stop")
        }

        func removeOwnedConfiguration() async throws {
            recorder.events.append("proxy-remove")
        }
    }

    private final class FakeSelector: SelectedTestAppSelecting {
        var pendingIdentity: SelectedTestAppIdentity? = SelectedTestAppIdentity(
            signingIdentifier: "local-only-test-app",
            teamIdentifier: "TEAMID1234"
        )

        func selectSignedApplication() async throws -> Bool {
            pendingIdentity != nil
        }

        func consumeIdentity() throws -> SelectedTestAppIdentity {
            guard let identity = pendingIdentity else {
                throw SpikeHostServiceError.selectedApplicationUnavailable
            }
            pendingIdentity = nil
            return identity
        }

        func clear() {
            pendingIdentity = nil
        }
    }

    private struct FakeConnectivityVerifier: ControlConnectivityVerifying {
        let recorder: EventRecorder

        func verifyAfterCleanup() async -> ControlConnectivityVerification {
            recorder.events.append("verify-control")
            return .requiresUserConfirmation
        }
    }

    private enum FakeError: Error {
        case stopped
    }

    private final class FakeXPCClient: SpikeXPCClientProtocol, @unchecked Sendable {
        let recorder: EventRecorder
        var beginRequest: SpikeRunRequest?
        var results: [RedactedFlowResult] = []
        var stopError: Error?

        init(recorder: EventRecorder) {
            self.recorder = recorder
        }

        func beginRun(_ request: SpikeRunRequest) async throws {
            beginRequest = request
            recorder.events.append("xpc-begin")
        }

        func snapshot(runId: UUID) async throws -> [RedactedFlowResult] {
            recorder.events.append("xpc-snapshot")
            return results
        }

        func stopRun(runId: UUID) async throws {
            recorder.events.append("xpc-stop")
            if let stopError {
                throw stopError
            }
        }

        func invalidate() {
            recorder.events.append("xpc-invalidate")
        }
    }

    func testInstallStartStopAndManualConnectivityConfirmationUseSafeOrder() async {
        let recorder = EventRecorder()
        let selector = FakeSelector()
        let xpc = FakeXPCClient(recorder: recorder)
        xpc.results = [makeResult()]
        let model = SpikeViewModel(
            systemExtensionActivator: FakeActivator(recorder: recorder),
            proxyController: FakeProxy(recorder: recorder),
            xpcClient: xpc,
            selectedTestAppSelector: selector,
            controlConnectivityVerifier: FakeConnectivityVerifier(recorder: recorder)
        )

        await model.selectTestApp()
        model.setSanitizedFixtureReady(true)
        await model.requestInstallation()
        XCTAssertTrue(model.displayState.canStart)

        await model.start()
        XCTAssertEqual(recorder.events, ["activate", "proxy-start", "xpc-begin"])
        XCTAssertEqual(xpc.beginRequest?.candidateKind, .transparentProxy)
        XCTAssertEqual(xpc.beginRequest?.evidenceTier, .signedMac)
        XCTAssertEqual(xpc.beginRequest?.selectedSigningIdentifier, "local-only-test-app")
        XCTAssertEqual(xpc.beginRequest?.selectedTeamIdentifier, "TEAMID1234")
        XCTAssertNil(selector.pendingIdentity)
        XCTAssertTrue(model.displayState.canStop)

        await model.stop()
        XCTAssertEqual(recorder.events, [
            "activate", "proxy-start", "xpc-begin", "xpc-stop", "xpc-snapshot",
            "proxy-stop", "proxy-remove", "verify-control",
        ])
        XCTAssertEqual(model.displayState.lifecycle, .awaitingControlVerification)
        XCTAssertNotEqual(model.displayState.statusText, "시험을 안전하게 중단했습니다")
        XCTAssertEqual(model.displayState.redactedResultCount, 1)

        model.completeControlConnectivityVerification(
            dnsAvailable: true,
            ipv4Available: true,
            ipv6Available: true
        )
        XCTAssertEqual(model.displayState.lifecycle, .stopped)
        XCTAssertEqual(model.displayState.spikeResult, .stopped)
        XCTAssertTrue(model.displayState.canExport)
    }

    func testXPCStopFailureDoesNotSkipOwnedCleanup() async {
        let recorder = EventRecorder()
        let xpc = FakeXPCClient(recorder: recorder)
        xpc.stopError = FakeError.stopped
        let model = SpikeViewModel(
            systemExtensionActivator: FakeActivator(recorder: recorder),
            proxyController: FakeProxy(recorder: recorder),
            xpcClient: xpc,
            selectedTestAppSelector: FakeSelector(),
            controlConnectivityVerifier: FakeConnectivityVerifier(recorder: recorder)
        )

        await model.selectTestApp()
        model.setSanitizedFixtureReady(true)
        await model.requestInstallation()
        await model.start()
        await model.stop()

        XCTAssertTrue(recorder.events.contains("proxy-stop"))
        XCTAssertTrue(recorder.events.contains("proxy-remove"))
        XCTAssertEqual(model.displayState.lifecycle, .awaitingControlVerification)

        model.completeControlConnectivityVerification(
            dnsAvailable: true,
            ipv4Available: true,
            ipv6Available: true
        )
        XCTAssertEqual(model.displayState.lifecycle, .stoppedWithError)
        XCTAssertEqual(model.displayState.spikeResult, .fail)
    }

    func testMissingConfigurationBlocksEveryAction() async {
        let recorder = EventRecorder()
        let model = SpikeViewModel(
            systemExtensionActivator: FakeActivator(recorder: recorder),
            proxyController: FakeProxy(recorder: recorder),
            xpcClient: FakeXPCClient(recorder: recorder),
            selectedTestAppSelector: FakeSelector(),
            configurationError: "시험 앱 구성을 확인하지 못했습니다."
        )

        await model.selectTestApp()
        await model.requestInstallation()
        await model.start()

        XCTAssertTrue(recorder.events.isEmpty)
        XCTAssertFalse(model.displayState.canStart)
        XCTAssertEqual(model.displayState.lifecycle, .configurationInvalid)
    }

    func testStartDoesNothingUntilEveryReadinessConditionIsMet() async {
        let recorder = EventRecorder()
        let selector = FakeSelector()
        selector.pendingIdentity = nil
        let model = SpikeViewModel(
            systemExtensionActivator: FakeActivator(recorder: recorder),
            proxyController: FakeProxy(recorder: recorder),
            xpcClient: FakeXPCClient(recorder: recorder),
            selectedTestAppSelector: selector
        )

        await model.start()

        XCTAssertTrue(recorder.events.isEmpty)
        XCTAssertEqual(model.displayState.userFacingError, "시험 앱을 지정해 주세요")
    }

    private func makeResult() -> RedactedFlowResult {
        RedactedFlowResult(
            runId: UUID(),
            candidateKind: .transparentProxy,
            evidenceTier: .signedMac,
            flowKind: .tcpIPv4,
            appRole: .selectedApp,
            flowAge: .newFlow,
            spikeResult: .inconclusive,
            failureCode: "wireguard-transport-unavailable",
            observedAt: Date(),
            durationMs: 1
        )
    }
}
