import Combine
import Foundation

@MainActor
public final class SpikeViewModel: ObservableObject {
    @Published public private(set) var displayState: SpikeDisplayState
    @Published public private(set) var redactedResults: [RedactedFlowResult]

    private let systemExtensionActivator: SystemExtensionActivating
    private let proxyController: TransparentProxyControlling
    private let xpcClient: SpikeXPCClientProtocol
    private let selectedTestAppSelector: SelectedTestAppSelecting
    private let controlConnectivityVerifier: ControlConnectivityVerifying
    private let controlPlaneFlowProbe: ControlPlaneFlowProbing
    private let exporter: RedactedResultExporter
    private var currentRunId: UUID?
    private var pendingStopHadXPCError = false
    private var baseline: (dns: Bool, ipv4: Bool, ipv6: Bool)?
    private var providerStopObserved = false
    private var managerCountAfterCleanup: Int?
    private var cleanupSummary: CleanupSummary?
    private var controlInternetReachable: Bool?
    private var controlPlaneRecursionCount: Int?

    public init(
        displayState: SpikeDisplayState = SpikeDisplayState(),
        redactedResults: [RedactedFlowResult] = [],
        systemExtensionActivator: SystemExtensionActivating,
        proxyController: TransparentProxyControlling,
        xpcClient: SpikeXPCClientProtocol,
        selectedTestAppSelector: SelectedTestAppSelecting,
        controlConnectivityVerifier: ControlConnectivityVerifying = ManualControlConnectivityVerifier(),
        controlPlaneFlowProbe: ControlPlaneFlowProbing = LocalFlowControlPlaneProbe(),
        configurationError: String? = nil,
        exporter: RedactedResultExporter = RedactedResultExporter()
    ) {
        self.displayState = displayState
        self.redactedResults = redactedResults
        self.systemExtensionActivator = systemExtensionActivator
        self.proxyController = proxyController
        self.xpcClient = xpcClient
        self.selectedTestAppSelector = selectedTestAppSelector
        self.controlConnectivityVerifier = controlConnectivityVerifier
        self.controlPlaneFlowProbe = controlPlaneFlowProbe
        self.exporter = exporter
        self.displayState.redactedResultCount = redactedResults.count
        if let configurationError {
            self.displayState.hasValidHostConfiguration = false
            self.displayState.lifecycle = .configurationInvalid
            self.displayState.userFacingError = configurationError
        }
    }

    public func setSanitizedFixtureReady(_ isReady: Bool) {
        guard displayState.canSelectTestApp else {
            return
        }
        displayState.hasSanitizedFixture = isReady
        updateReadiness()
    }

    public func setEntitlementEvidenceState(_ state: EntitlementEvidenceState) {
        displayState.entitlementEvidenceState = state
        if state != .confirmed { displayState.activationEvidenceState = .notObserved }
        updateReadiness()
    }

    public func setProvisioningEvidenceState(_ state: ProvisioningEvidenceState) {
        displayState.provisioningEvidenceState = state
        if state != .confirmed { displayState.activationEvidenceState = .notObserved }
        updateReadiness()
    }

    public func captureBaseline(dnsAvailable: Bool, ipv4Available: Bool, ipv6Available: Bool) {
        guard dnsAvailable, ipv4Available else {
            baseline = nil
            displayState.baselineState = .notCaptured
            displayState.signedMacSummary = ValidationAxisSummary(validationAxis: .signedMac,
                validationVerdict: .inconclusive, executedCount: 0, passedCount: 0, failedCount: 0, observedAt: Date())
            return
        }
        baseline = (dnsAvailable, ipv4Available, ipv6Available)
        displayState.baselineState = .captured
        updateReadiness()
    }

    public func selectTestApp() async {
        guard displayState.canSelectTestApp else {
            return
        }
        displayState.userFacingError = nil
        do {
            displayState.hasSelectedTestApp = try await selectedTestAppSelector
                .selectSignedApplication()
            updateReadiness()
        } catch {
            displayState.hasSelectedTestApp = false
            displayState.userFacingError = message(for: error)
            updateReadiness()
        }
    }

    public func requestInstallation() async {
        guard displayState.canRequestInstallation else {
            return
        }
        displayState.lifecycle = .awaitingApproval
        displayState.userFacingError = nil
        do {
            let outcome = try await systemExtensionActivator.activate()
            displayState.activationEvidenceState = outcome == .completed ? .confirmed : .rebootRequired
            updateReadiness()
        } catch {
            displayState.activationEvidenceState = .failed
            displayState.lifecycle = .stopped
            displayState.spikeResult = .inconclusive
            displayState.userFacingError = message(for: error)
        }
    }

    public func start() async {
        guard displayState.canStart else {
            displayState.userFacingError = displayState.hasSelectedTestApp
                ? nil
                : "시험 앱을 지정해 주세요"
            return
        }

        displayState.userFacingError = nil
        let identity: SelectedTestAppIdentity
        do {
            identity = try selectedTestAppSelector.consumeIdentity()
            displayState.hasSelectedTestApp = false
        } catch {
            displayState.hasSelectedTestApp = false
            displayState.userFacingError = message(for: error)
            updateReadiness()
            return
        }
        let runId = UUID()
        let request = SpikeRunRequest(
            schemaVersion: SpikeLimits.schemaVersion,
            runId: runId,
            candidateKind: .transparentProxy,
            evidenceTier: .signedMac,
            selectedSigningIdentifier: identity.signingIdentifier,
            selectedTeamIdentifier: identity.teamIdentifier,
            policyAppliedAt: Date()
        )

        do {
            try await proxyController.startAndWaitUntilConnected(timeout: .seconds(10))
            try await xpcClient.beginRun(request)
            providerStopObserved = false
            managerCountAfterCleanup = nil
            cleanupSummary = nil
            controlInternetReachable = nil
            controlPlaneRecursionCount = nil
            currentRunId = runId
            displayState.lifecycle = .running
            displayState.evidenceTier = .signedMac
            displayState.spikeResult = .notRun
            // 설계대로 Host가 새 흐름을 한 번 만들어 Provider의 제어 경로 directPass를 확인합니다.
            await controlPlaneFlowProbe.probeControlPlaneFlow()
        } catch {
            let startError = error
            try? await proxyController.stopProvider()
            var cleanupFailed = false
            do {
                _ = try await proxyController.removeAllOwnedConfigurations()
                cleanupFailed = try await proxyController.ownedConfigurationCount() != 0
            } catch {
                cleanupFailed = true
            }
            currentRunId = nil
            displayState.lifecycle = cleanupFailed ? .cleanupFailed : .stoppedWithError
            displayState.cleanupPhase = cleanupFailed ? .failed : .managerCountVerifiedZero
            displayState.spikeResult = .fail
            displayState.userFacingError = cleanupFailed
                ? message(for: SpikeHostServiceError.proxyCleanupFailed)
                : message(for: startError)
        }
    }

    public func stop() async {
        guard displayState.canStop, let runId = currentRunId else {
            return
        }
        displayState.lifecycle = .stopping
        displayState.cleanupPhase = .rejectingNewFlows
        displayState.userFacingError = nil
        selectedTestAppSelector.clear()

        var xpcError: Error?
        do {
            try await xpcClient.stopRun(runId: runId)
            redactedResults = try await xpcClient.snapshot(runId: runId)
            displayState.redactedResultCount = redactedResults.count
        } catch {
            xpcError = error
        }

        var cleanupError: Error?
        do {
            displayState.cleanupPhase = .providerStopRequested
            try await proxyController.stopAndWaitUntilDisconnected(timeout: .seconds(10))
            providerStopObserved = true
            displayState.cleanupPhase = .providerStopped
        } catch {
            cleanupError = error
        }
        do {
            _ = try await proxyController.removeAllOwnedConfigurations()
            displayState.cleanupPhase = .ownedManagersRemoved
            let remainingManagerCount = try await proxyController.ownedConfigurationCount()
            managerCountAfterCleanup = remainingManagerCount
            guard remainingManagerCount == 0 else {
                throw SpikeHostServiceError.proxyCleanupFailed
            }
            displayState.cleanupPhase = .managerCountVerifiedZero
        } catch {
            cleanupError = cleanupError ?? error
        }

        currentRunId = nil
        if let cleanupError {
            displayState.lifecycle = .cleanupFailed
            displayState.cleanupPhase = .failed
            displayState.spikeResult = .fail
            displayState.userFacingError = message(for: cleanupError)
            return
        }

        pendingStopHadXPCError = xpcError != nil
        _ = await controlConnectivityVerifier.verifyAfterCleanup()
        displayState.lifecycle = .awaitingControlVerification
        displayState.spikeResult = .inconclusive
        if let xpcError {
            displayState.userFacingError = message(for: xpcError)
        }
    }

    public func completeCleanupComparison(
        dnsAvailable: Bool,
        ipv4Available: Bool,
        ipv6Available: Bool,
        controlInternetReachable: Bool? = nil,
        controlPlaneRecursionCount: Int? = nil
    ) {
        guard displayState.lifecycle == .awaitingControlVerification else {
            return
        }
        guard let baseline else {
            displayState.lifecycle = .cleanupFailed
            displayState.cleanupPhase = .failed
            displayState.userFacingError = "DNS·IPv4·IPv6 회복 확인이 필요합니다."
            return
        }
        displayState.cleanupPhase = .dnsCompared
        let dnsMatched = dnsAvailable == baseline.dns
        displayState.cleanupPhase = .ipv4Compared
        let ipv4Matched = ipv4Available == baseline.ipv4
        displayState.cleanupPhase = .ipv6Compared
        let ipv6Matched = ipv6Available == baseline.ipv6
        self.controlInternetReachable = controlInternetReachable
        self.controlPlaneRecursionCount = controlPlaneRecursionCount
        let summary = CleanupSummary(
            providerStopObserved: providerStopObserved,
            managerCountAfterCleanup: managerCountAfterCleanup,
            dnsMatchedBaseline: dnsMatched,
            ipv4MatchedBaseline: ipv4Matched,
            ipv6MatchedBaseline: ipv6Matched
        )
        cleanupSummary = summary
        updateSignedMacVerdict(cleanup: summary)
        guard dnsMatched, ipv4Matched, ipv6Matched else {
            displayState.lifecycle = .cleanupFailed
            displayState.cleanupPhase = .failed
            displayState.spikeResult = .fail
            displayState.userFacingError = "일반 인터넷 보존 검사에 실패했습니다."
            return
        }

        if pendingStopHadXPCError {
            displayState.lifecycle = .stoppedWithError
            displayState.spikeResult = .fail
        } else {
            displayState.lifecycle = .stopped
            displayState.cleanupPhase = .complete
            switch displayState.signedMacSummary.validationVerdict {
            case .pass:
                displayState.spikeResult = .pass
            case .fail:
                displayState.spikeResult = .fail
            default:
                displayState.spikeResult = .inconclusive
            }
            displayState.userFacingError = nil
        }
        pendingStopHadXPCError = false
    }

    public func completeControlConnectivityVerification(dnsAvailable: Bool, ipv4Available: Bool, ipv6Available: Bool) {
        completeCleanupComparison(dnsAvailable: dnsAvailable, ipv4Available: ipv4Available, ipv6Available: ipv6Available)
    }

    public func export(to destination: URL) {
        guard displayState.canExport else {
            return
        }
        do {
            try exporter.export(redactedValidationReport(), to: destination)
            displayState.userFacingError = nil
        } catch {
            displayState.userFacingError = message(for: error)
        }
    }

    public func shutdown() async {
        if displayState.canStop {
            await stop()
        }
        selectedTestAppSelector.clear()
        xpcClient.invalidate()
    }

    private func updateReadiness() {
        displayState.lifecycle = displayState.hasAllReadinessConditions
            ? .ready
            : .notReady
    }

    private func updateSignedMacVerdict(cleanup: CleanupSummary) {
        let observations: [Bool?] = [
            displayState.activationEvidenceState == .confirmed,
            flowObservation(role: .selectedApp, kind: .tcpIPv4, outcome: .ownedAndClosed,
                            result: .inconclusive,
                            failureCode: SpikeFailureCode.wireGuardTransportUnavailable.rawValue),
            flowObservation(role: .selectedApp, kind: .udpIPv4, outcome: .ownedAndClosed,
                            result: .inconclusive,
                            failureCode: SpikeFailureCode.wireGuardTransportUnavailable.rawValue),
            flowObservation(role: .controlApp, kind: .tcpIPv4, outcome: .directPass,
                            result: .pass, failureCode: nil),
            flowObservation(role: .controlApp, kind: .udpIPv4, outcome: .directPass,
                            result: .pass, failureCode: nil),
            roleObservation(role: .controlPlane, outcome: .directPass,
                            result: .pass, failureCode: nil),
            controlInternetReachable,
            controlPlaneRecursionCount.map { $0 == 0 },
            cleanup.providerStopObserved && cleanup.managerCountAfterCleanup == 0,
            cleanupNetworkObservation(cleanup),
            pendingStopHadXPCError ? false : true,
        ]
        let executed = observations.compactMap { $0 }
        let verdict: ValidationVerdict
        if executed.contains(false) {
            verdict = .fail
        } else if executed.count == observations.count {
            verdict = .pass
        } else {
            verdict = .inconclusive
        }
        displayState.signedMacSummary = ValidationAxisSummary(
            validationAxis: .signedMac,
            validationVerdict: verdict,
            executedCount: executed.count,
            passedCount: executed.filter { $0 }.count,
            failedCount: executed.filter { !$0 }.count,
            observedAt: Date()
        )
    }

    private func flowObservation(
        role: AppRole,
        kind: FlowKind,
        outcome: HandlingOutcome,
        result: SpikeResult,
        failureCode: String?
    ) -> Bool? {
        let matches = redactedResults.filter {
            $0.appRole == role && $0.flowKind == kind && $0.flowAge == .newFlow
        }
        guard !matches.isEmpty else { return nil }
        return matches.allSatisfy {
            $0.handlingOutcome == outcome
                && $0.spikeResult == result
                && $0.failureCode == failureCode
        }
    }

    private func roleObservation(
        role: AppRole,
        outcome: HandlingOutcome,
        result: SpikeResult,
        failureCode: String?
    ) -> Bool? {
        let matches = redactedResults.filter { $0.appRole == role && $0.flowAge == .newFlow }
        guard !matches.isEmpty else { return nil }
        return matches.allSatisfy {
            $0.handlingOutcome == outcome
                && $0.spikeResult == result
                && $0.failureCode == failureCode
        }
    }

    private func cleanupNetworkObservation(_ cleanup: CleanupSummary) -> Bool? {
        guard let dns = cleanup.dnsMatchedBaseline,
              let ipv4 = cleanup.ipv4MatchedBaseline,
              let ipv6 = cleanup.ipv6MatchedBaseline else { return nil }
        return dns && ipv4 && ipv6
    }

    func redactedValidationReport() -> RedactedValidationReport {
        RedactedValidationReport(
            validationSummaries: [
                displayState.automatedSummary,
                displayState.signedMacSummary,
                displayState.p3ProductIntegrationSummary,
            ],
            cleanupSummary: cleanupSummary,
            results: redactedResults
        )
    }

    private func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription
            ?? "시험 요청을 안전하게 완료하지 못했습니다."
    }
}
