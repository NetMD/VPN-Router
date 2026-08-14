import Foundation

public struct ProviderFlowProjection: Sendable {
    public let sourceSigningIdentifier: String?
    public let sourceAppAuditToken: Data?
    public let flowKind: FlowKind
    public let observedAt: Date
}

public struct ProviderHandlingPlan: Equatable, Sendable {
    public let providerReturnValue: Bool
    public let shouldClose: Bool
    public let redactedResult: RedactedFlowResult?
}

public struct ProviderFlowBridge: Sendable {
    private let adapter: FlowIdentityPolicyAdapter

    public init(identityVerifier: FlowIdentityVerifier) {
        adapter = FlowIdentityPolicyAdapter(identityVerifier: identityVerifier)
    }

    public func evaluate(_ projection: ProviderFlowProjection, request: SpikeRunRequest,
                         isControlPlane: Bool, isKnownHelper: Bool,
                         controlPlaneTeamIdentifier: String) -> ProviderHandlingPlan {
        let decision = adapter.evaluate(sourceSigningIdentifier: projection.sourceSigningIdentifier,
                                        sourceAppAuditToken: projection.sourceAppAuditToken,
                                        isControlPlane: isControlPlane, isKnownHelper: isKnownHelper,
                                        observedAt: projection.observedAt, request: request,
                                        controlPlaneTeamIdentifier: controlPlaneTeamIdentifier)
        switch decision {
        case let .directPass(appRole, flowAge):
            return plan(request, projection, appRole, flowAge, .directPass, .pass, nil, false)
        case let .handledAndClosed(appRole, flowAge, failureCode):
            let verdict: SpikeResult = failureCode == SpikeFailureCode.wireGuardTransportUnavailable.rawValue ? .inconclusive : .fail
            return plan(request, projection, appRole, flowAge, .ownedAndClosed, verdict, failureCode, true)
        }
    }

    private func plan(_ request: SpikeRunRequest, _ projection: ProviderFlowProjection,
                      _ appRole: AppRole, _ flowAge: FlowAge, _ outcome: HandlingOutcome,
                      _ verdict: SpikeResult, _ failureCode: String?, _ close: Bool) -> ProviderHandlingPlan {
        let result = RedactedFlowResult(runId: request.runId, candidateKind: request.candidateKind,
                                        evidenceTier: request.evidenceTier, flowKind: projection.flowKind,
                                        appRole: appRole, flowAge: flowAge, handlingOutcome: outcome,
                                        spikeResult: verdict, failureCode: failureCode,
                                        observedAt: projection.observedAt, durationMs: 0)
        return ProviderHandlingPlan(providerReturnValue: close, shouldClose: close, redactedResult: result)
    }
}
