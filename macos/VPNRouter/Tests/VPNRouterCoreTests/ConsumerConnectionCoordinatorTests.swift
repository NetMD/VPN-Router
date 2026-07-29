import Testing
@testable import VPNRouterConnection

@MainActor
struct ConsumerConnectionCoordinatorTests {
    @Test
    func successfulConnectionReachesReadyInOrderWithoutCleanup() async {
        let recorder = Recorder()
        let coordinator = ConsumerConnectionCoordinator()

        await coordinator.connect(using: recorder.operations())

        #expect(coordinator.state == .ready)
        #expect(
            recorder.events == [
                "preflight",
                "activate-extension",
                "prepare",
                "start",
                "enable",
                "publish",
                "verify",
                "arm"
            ]
        )
    }

    @Test(arguments: [
        FailureCase(step: .preflight, expectedStage: .preflighting, expectedCleanup: []),
        FailureCase(step: .activateExtension, expectedStage: .activatingDNSProxyExtension, expectedCleanup: []),
        FailureCase(step: .prepare, expectedStage: .preparingPacketTunnel, expectedCleanup: []),
        FailureCase(step: .start, expectedStage: .startingPacketTunnel, expectedCleanup: ["stop"]),
        FailureCase(step: .enable, expectedStage: .enablingDNSProxy, expectedCleanup: ["disable", "stop"]),
        FailureCase(step: .publish, expectedStage: .publishingTargets, expectedCleanup: ["disable", "stop"]),
        FailureCase(step: .verify, expectedStage: .verifyingDNSProxy, expectedCleanup: ["disable", "stop"]),
        FailureCase(step: .arm, expectedStage: .armingSafetyMonitor, expectedCleanup: ["disable", "stop"])
    ])
    func failureRecordsStableStageAndCleansUpOwnedStateInReverseOrder(
        testCase: FailureCase
    ) async {
        let recorder = Recorder(failingStep: testCase.step)
        let coordinator = ConsumerConnectionCoordinator()

        await coordinator.connect(using: recorder.operations())

        #expect(
            coordinator.state == .failed(
                stage: testCase.expectedStage,
                code: "injected-\(testCase.step.rawValue)"
            )
        )
        #expect(Array(recorder.events.suffix(testCase.expectedCleanup.count)) == testCase.expectedCleanup)
    }

    @Test
    func disconnectAlwaysDisablesOwnedDNSProxyBeforeStoppingPacketTunnel() async {
        let recorder = Recorder()
        let coordinator = ConsumerConnectionCoordinator()
        coordinator.restoreReadyState()

        await coordinator.disconnect(
            disableOwnedDNSProxy: { recorder.events.append("disable") },
            stopPacketTunnel: { recorder.events.append("stop") }
        )

        #expect(coordinator.state == .idle)
        #expect(recorder.events == ["disable", "stop"])
    }
}

struct FailureCase: Sendable {
    let step: Step
    let expectedStage: ConsumerConnectionStage
    let expectedCleanup: [String]
}

enum Step: String, Sendable {
    case preflight
    case activateExtension = "activate-extension"
    case prepare
    case start
    case enable
    case publish
    case verify
    case arm
}

@MainActor
private final class Recorder {
    var events: [String] = []
    private let failingStep: Step?

    init(failingStep: Step? = nil) {
        self.failingStep = failingStep
    }

    func operations() -> ConsumerConnectionCoordinator.Operations {
        .init(
            preflight: { try self.perform(.preflight) },
            activateDNSProxyExtension: { try self.perform(.activateExtension) },
            preparePacketTunnel: { try self.perform(.prepare) },
            startPacketTunnel: { try self.perform(.start) },
            enableDNSProxy: { try self.perform(.enable) },
            publishTargets: { try self.perform(.publish) },
            verifyDNSProxy: { try self.perform(.verify) },
            armSafetyMonitor: { try self.perform(.arm) },
            disableOwnedDNSProxy: { self.events.append("disable") },
            stopPacketTunnel: { self.events.append("stop") }
        )
    }

    private func perform(_ step: Step) throws {
        events.append(step.rawValue)
        guard failingStep == step else {
            return
        }
        throw ConsumerConnectionStepError(
            code: "injected-\(step.rawValue)",
            message: "Injected test failure"
        )
    }
}
