import Foundation
import XCTest
@testable import AppRoutingSpikeHost

/// 제어 경로 판정은 Host가 만든 새 흐름 1건이 있어야 채워집니다.
/// 이 흐름을 만들지 않아 실기 signedMac 판정이 계속 INCONCLUSIVE로 남았던 결함의 회귀 시험입니다.
@MainActor
final class SpikeViewModelControlPlaneProbeTests: XCTestCase {
    private final class ProbeCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0

        func increment() {
            lock.lock()
            value += 1
            lock.unlock()
        }

        var count: Int {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
    }

    private struct CountingProbe: ControlPlaneFlowProbing {
        let counter: ProbeCounter

        func probeControlPlaneFlow() async {
            counter.increment()
        }
    }

    private struct StubActivator: SystemExtensionActivating {
        func activate() async throws -> SystemExtensionActivationOutcome { .completed }
    }

    private struct StubProxy: TransparentProxyControlling {
        let startError: Error?

        func start() async throws {
            if let startError {
                throw startError
            }
        }

        func stopProvider() async throws {}
        func removeOwnedConfiguration() async throws {}
        func removeAllOwnedConfigurations() async throws -> Int { 0 }
        func ownedConfigurationCount() async throws -> Int { 0 }
    }

    private final class StubSelector: SelectedTestAppSelecting {
        private var pendingIdentity: SelectedTestAppIdentity? = SelectedTestAppIdentity(
            signingIdentifier: "local-only-test-app",
            teamIdentifier: "TEAMID1234"
        )

        func selectSignedApplication() async throws -> Bool { pendingIdentity != nil }

        func consumeIdentity() throws -> SelectedTestAppIdentity {
            guard let identity = pendingIdentity else {
                throw SpikeHostServiceError.selectedApplicationUnavailable
            }
            pendingIdentity = nil
            return identity
        }

        func clear() { pendingIdentity = nil }
    }

    private struct StubXPCClient: SpikeXPCClientProtocol {
        let beginError: Error?

        func beginRun(_ request: SpikeRunRequest) async throws {
            if let beginError {
                throw beginError
            }
        }

        func snapshot(runId: UUID) async throws -> [RedactedFlowResult] { [] }
        func stopRun(runId: UUID) async throws {}
        func invalidate() {}
    }

    private enum StubError: Error {
        case failed
    }

    private func makeReadyModel(
        counter: ProbeCounter,
        proxyStartError: Error? = nil,
        beginError: Error? = nil
    ) async -> SpikeViewModel {
        let model = SpikeViewModel(
            systemExtensionActivator: StubActivator(),
            proxyController: StubProxy(startError: proxyStartError),
            xpcClient: StubXPCClient(beginError: beginError),
            selectedTestAppSelector: StubSelector(),
            controlPlaneFlowProbe: CountingProbe(counter: counter)
        )
        await model.selectTestApp()
        model.setSanitizedFixtureReady(true)
        model.setEntitlementEvidenceState(.confirmed)
        model.setProvisioningEvidenceState(.confirmed)
        model.captureBaseline(dnsAvailable: true, ipv4Available: true, ipv6Available: false)
        await model.requestInstallation()
        return model
    }

    func testStartMakesExactlyOneControlPlaneFlow() async {
        let counter = ProbeCounter()
        let model = await makeReadyModel(counter: counter)

        XCTAssertEqual(counter.count, 0, "시작 전에는 제어 경로 흐름을 만들지 않습니다.")
        await model.start()

        XCTAssertEqual(model.displayState.lifecycle, .running)
        XCTAssertEqual(counter.count, 1, "시작 뒤 제어 경로 흐름을 정확히 한 번 만들어야 합니다.")
    }

    func testDoesNotMakeAControlPlaneFlowWhenTheProxyFailsToStart() async {
        let counter = ProbeCounter()
        let model = await makeReadyModel(counter: counter, proxyStartError: StubError.failed)

        await model.start()

        XCTAssertNotEqual(model.displayState.lifecycle, .running)
        XCTAssertEqual(counter.count, 0, "Provider가 뜨지 않으면 흐름을 만들지 않습니다.")
    }

    func testDoesNotMakeAControlPlaneFlowWhenTheRunIsRejected() async {
        let counter = ProbeCounter()
        let model = await makeReadyModel(counter: counter, beginError: StubError.failed)

        await model.start()

        XCTAssertNotEqual(model.displayState.lifecycle, .running)
        XCTAssertEqual(counter.count, 0, "시험 실행이 거절되면 흐름을 만들지 않습니다.")
    }
}
