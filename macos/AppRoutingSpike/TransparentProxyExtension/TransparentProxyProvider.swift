import Foundation
import Network
import NetworkExtension

final class TransparentProxyProvider: NETransparentProxyProvider, NEAppProxyUDPFlowHandling, @unchecked Sendable {
    private let transport = SelectedFlowTransport()
    private let evidenceRecorder = SpikeEvidenceRecorder()
    private let runState = SpikeRunState()
    private let selectedFlowCapacity = SelectedFlowCapacityGate()
    private var xpcService: SpikeXPCService?
    private var acceptingNewFlows = false

    override func startProxy(
        options: [String: Any]? = nil,
        completionHandler: @escaping @Sendable (Error?) -> Void
    ) {
        guard let address = IPv4Address("192.0.2.1") else {
            completionHandler(ProviderSetupError.invalidFixtureAddress)
            return
        }
        let settings = NETransparentProxyNetworkSettings(tunnelRemoteAddress: "192.0.2.1")
        settings.includedNetworkRules = [
            NENetworkRule(
                destinationNetworkEndpoint: .hostPort(host: .ipv4(address), port: 443),
                prefix: 32,
                protocol: .any
            )
        ]
        setTunnelNetworkSettings(settings) { [weak self] error in
            guard let self, error == nil else {
                completionHandler(error)
                return
            }
            let machServiceName = Bundle.main.object(forInfoDictionaryKey: "SpikeMachServiceName") as? String ?? ""
            let hostIdentifier = Bundle.main.object(forInfoDictionaryKey: "SpikeHostBundleIdentifier") as? String ?? ""
            let hostTeamIdentifier = Bundle.main.object(forInfoDictionaryKey: "SpikeExpectedTeamIdentifier") as? String ?? ""
            guard !machServiceName.isEmpty, !hostIdentifier.isEmpty, !hostTeamIdentifier.isEmpty else {
                completionHandler(ProviderSetupError.missingXPCConfiguration)
                return
            }
            let service = SpikeXPCService(
                machServiceName: machServiceName,
                expectedHostIdentifier: hostIdentifier,
                expectedHostTeamIdentifier: hostTeamIdentifier,
                runState: self.runState,
                recorder: self.evidenceRecorder
            )
            service.start()
            self.xpcService = service
            self.acceptingNewFlows = true
            completionHandler(nil)
        }
    }

    override func stopProxy(
        with reason: NEProviderStopReason,
        completionHandler: @escaping @Sendable () -> Void
    ) {
        acceptingNewFlows = false
        runState.clear()
        xpcService?.stop()
        xpcService = nil
        completionHandler()
    }

    override func handleNewFlow(_ flow: NEAppProxyFlow) -> Bool {
        handle(flow: flow, kind: flowKind(for: flow))
    }

    func handleNewUDPFlow(
        _ flow: NEAppProxyUDPFlow,
        initialRemoteFlowEndpoint remoteEndpoint: Network.NWEndpoint
    ) -> Bool {
        handle(flow: flow, kind: flowKind(for: remoteEndpoint, udp: true))
    }

    private func handle(flow: NEAppProxyFlow, kind: FlowKind) -> Bool {
        guard acceptingNewFlows else { return false }
        if runState.shouldRejectNewFlows() {
            close(flow)
            return true
        }
        guard let request = runState.currentRequest() else { return false }
        let observedAt = Date()
        let sourceSigningIdentifier = flow.metaData.sourceAppSigningIdentifier
        let hostIdentifier = Bundle.main.object(forInfoDictionaryKey: "SpikeHostBundleIdentifier") as? String
        let controlPlanePolicy = ControlPlaneExclusionPolicy(
            signingIdentifiers: Set([hostIdentifier, Bundle.main.bundleIdentifier].compactMap { $0 })
        )
        let hostTeamIdentifier = Bundle.main.object(forInfoDictionaryKey: "SpikeExpectedTeamIdentifier") as? String ?? ""
        let decision = FlowIdentityPolicyAdapter(
            identityVerifier: FlowIdentityVerifier(
                auditTokenValidator: SecurityAuditTokenValidator()
            )
        ).evaluate(
            sourceSigningIdentifier: sourceSigningIdentifier,
            sourceAppAuditToken: flow.metaData.sourceAppAuditToken,
            isControlPlane: controlPlanePolicy.contains(signingIdentifier: sourceSigningIdentifier),
            isKnownHelper: false,
            observedAt: observedAt,
            request: request,
            controlPlaneTeamIdentifier: hostTeamIdentifier
        )

        switch decision {
        case .directPass:
            return false
        case let .handledAndClosed(appRole, flowAge, failureCode):
            guard selectedFlowCapacity.acquire() else {
                close(flow)
                runState.markFailed(
                    runId: request.runId,
                    failureCode: SpikeFailureCode.selectedFlowLimitExceeded.rawValue
                )
                return true
            }
            defer { selectedFlowCapacity.release() }
            guard transport.forward() == .unsupported else { return true }
            close(flow)
            let result =
                RedactedFlowResult(
                    runId: request.runId,
                    candidateKind: request.candidateKind,
                    evidenceTier: request.evidenceTier,
                    flowKind: kind,
                    appRole: appRole,
                    flowAge: flowAge,
                    spikeResult: failureCode == SpikeFailureCode.wireGuardTransportUnavailable.rawValue
                        ? .inconclusive : .fail,
                    failureCode: failureCode,
                    observedAt: observedAt,
                    durationMs: 0
                )
            _ = SpikeEvidenceCoordinator(recorder: evidenceRecorder, runState: runState).record(result)
            if failureCode == SpikeFailureCode.identityMetadataMissing.rawValue
                || failureCode == SpikeFailureCode.identityVerificationFailed.rawValue {
                runState.markFailed(runId: request.runId, failureCode: failureCode)
            }
            return true
        }
    }

    private func close(_ flow: NEAppProxyFlow) {
        flow.closeReadWithError(nil)
        flow.closeWriteWithError(nil)
    }

    private func flowKind(for flow: NEAppProxyFlow) -> FlowKind {
        if let tcp = flow as? NEAppProxyTCPFlow {
            return flowKind(for: tcp.remoteFlowEndpoint, udp: false)
        }
        return .tcpIPv4
    }

    private func flowKind(for endpoint: Network.NWEndpoint, udp: Bool) -> FlowKind {
        guard case let .hostPort(host, _) = endpoint else {
            return udp ? .udpIPv4 : .tcpIPv4
        }
        let isIPv6: Bool
        switch host {
        case .ipv6: isIPv6 = true
        default: isIPv6 = false
        }
        if udp { return isIPv6 ? .udpIPv6 : .udpIPv4 }
        return isIPv6 ? .tcpIPv6 : .tcpIPv4
    }
}

private enum ProviderSetupError: Error {
    case invalidFixtureAddress
    case missingXPCConfiguration
}
