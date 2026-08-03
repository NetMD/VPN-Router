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
    private let exporter: RedactedResultExporter
    private var currentRunId: UUID?
    private var pendingStopHadXPCError = false

    public init(
        displayState: SpikeDisplayState = SpikeDisplayState(),
        redactedResults: [RedactedFlowResult] = [],
        systemExtensionActivator: SystemExtensionActivating,
        proxyController: TransparentProxyControlling,
        xpcClient: SpikeXPCClientProtocol,
        selectedTestAppSelector: SelectedTestAppSelecting,
        controlConnectivityVerifier: ControlConnectivityVerifying = ManualControlConnectivityVerifier(),
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
            try await systemExtensionActivator.activate()
            displayState.hasSignedEntitlement = true
            updateReadiness()
        } catch {
            displayState.hasSignedEntitlement = false
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
            try await proxyController.start()
            try await xpcClient.beginRun(request)
            currentRunId = runId
            displayState.lifecycle = .running
            displayState.evidenceTier = .signedMac
            displayState.spikeResult = .notRun
        } catch {
            try? await proxyController.stopProvider()
            try? await proxyController.removeOwnedConfiguration()
            currentRunId = nil
            displayState.lifecycle = .stoppedWithError
            displayState.spikeResult = .fail
            displayState.userFacingError = message(for: error)
        }
    }

    public func stop() async {
        guard displayState.canStop, let runId = currentRunId else {
            return
        }
        displayState.lifecycle = .stopping
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
            try await proxyController.stopProvider()
        } catch {
            cleanupError = error
        }
        do {
            try await proxyController.removeOwnedConfiguration()
        } catch {
            cleanupError = cleanupError ?? error
        }

        currentRunId = nil
        if let cleanupError {
            displayState.lifecycle = .cleanupFailed
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

    public func completeControlConnectivityVerification(
        dnsAvailable: Bool,
        ipv4Available: Bool,
        ipv6Available: Bool
    ) {
        guard displayState.lifecycle == .awaitingControlVerification else {
            return
        }
        guard dnsAvailable, ipv4Available, ipv6Available else {
            displayState.lifecycle = .cleanupFailed
            displayState.spikeResult = .fail
            displayState.userFacingError = "일반 인터넷 보존 검사에 실패했습니다."
            return
        }

        if pendingStopHadXPCError {
            displayState.lifecycle = .stoppedWithError
            displayState.spikeResult = .fail
        } else {
            displayState.lifecycle = .stopped
            displayState.spikeResult = .stopped
            displayState.userFacingError = nil
        }
        pendingStopHadXPCError = false
    }

    public func export(to destination: URL) {
        guard displayState.canExport else {
            return
        }
        do {
            try exporter.export(redactedResults, to: destination)
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

    private func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription
            ?? "시험 요청을 안전하게 완료하지 못했습니다."
    }
}
