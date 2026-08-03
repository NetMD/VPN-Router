import Foundation

/// Provider metadata 검증과 정책 평가 사이의 역할별 서명 요구 조건을 한 곳에서 연결합니다.
public struct FlowIdentityPolicyAdapter: Sendable {
    private let identityVerifier: FlowIdentityVerifier
    private let policyEvaluator: FlowPolicyEvaluator

    public init(
        identityVerifier: FlowIdentityVerifier,
        policyEvaluator: FlowPolicyEvaluator = FlowPolicyEvaluator()
    ) {
        self.identityVerifier = identityVerifier
        self.policyEvaluator = policyEvaluator
    }

    public func evaluate(
        sourceSigningIdentifier: String?,
        sourceAppAuditToken: Data?,
        isControlPlane: Bool,
        isKnownHelper: Bool,
        observedAt: Date,
        request: SpikeRunRequest,
        controlPlaneTeamIdentifier: String
    ) -> FlowHandlingDecision {
        let expectedSigningIdentifier: String
        let expectedTeamIdentifier: String?

        if isControlPlane {
            expectedSigningIdentifier = sourceSigningIdentifier ?? ""
            expectedTeamIdentifier = controlPlaneTeamIdentifier
        } else if sourceSigningIdentifier == request.selectedSigningIdentifier {
            expectedSigningIdentifier = request.selectedSigningIdentifier
            expectedTeamIdentifier = request.selectedTeamIdentifier
        } else {
            expectedSigningIdentifier = sourceSigningIdentifier ?? ""
            expectedTeamIdentifier = nil
        }

        let auditTokenIsValid = identityVerifier.verify(
            sourceSigningIdentifier: sourceSigningIdentifier,
            sourceAppAuditToken: sourceAppAuditToken,
            expectedSigningIdentifier: expectedSigningIdentifier,
            expectedTeamIdentifier: expectedTeamIdentifier
        )
        return policyEvaluator.evaluate(
            FlowPolicyInput(
                sourceSigningIdentifier: sourceSigningIdentifier,
                auditTokenIsValid: auditTokenIsValid,
                isControlPlane: isControlPlane,
                isKnownHelper: isKnownHelper,
                observedAt: observedAt
            ),
            request: request
        )
    }
}
