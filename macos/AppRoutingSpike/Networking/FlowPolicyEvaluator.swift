import Foundation

public enum SpikeStartDecision: Equatable, Sendable {
    case blockedNoFixture
    case preserveProductSiteMode
    case runAppPrioritySpike
}

public struct AppPriorityStateTable: Sendable {
    public init() {}

    public func decision(activeAppRuleCount: Int, siteRuleCount: Int) -> SpikeStartDecision {
        guard activeAppRuleCount > 0 else {
            return siteRuleCount > 0 ? .preserveProductSiteMode : .blockedNoFixture
        }
        return .runAppPrioritySpike
    }
}

public struct FlowPolicyInput: Equatable, Sendable {
    public let sourceSigningIdentifier: String?
    public let auditTokenIsValid: Bool
    public let isControlPlane: Bool
    public let isKnownHelper: Bool
    public let observedAt: Date

    public init(
        sourceSigningIdentifier: String?,
        auditTokenIsValid: Bool,
        isControlPlane: Bool,
        isKnownHelper: Bool,
        observedAt: Date
    ) {
        self.sourceSigningIdentifier = sourceSigningIdentifier
        self.auditTokenIsValid = auditTokenIsValid
        self.isControlPlane = isControlPlane
        self.isKnownHelper = isKnownHelper
        self.observedAt = observedAt
    }
}

public enum FlowHandlingDecision: Equatable, Sendable {
    case directPass(appRole: AppRole, flowAge: FlowAge)
    case handledAndClosed(appRole: AppRole, flowAge: FlowAge, failureCode: String)
}

/// 앱 신원과 정책 적용 시각만으로 Provider의 안전한 처리 방향을 결정합니다.
public struct FlowPolicyEvaluator: Sendable {
    public init() {}

    public func evaluate(_ input: FlowPolicyInput, request: SpikeRunRequest) -> FlowHandlingDecision {
        let flowAge: FlowAge = input.observedAt < request.policyAppliedAt ? .preExistingFlow : .newFlow

        if input.isControlPlane && input.auditTokenIsValid {
            return .directPass(appRole: .controlPlane, flowAge: flowAge)
        }

        guard let sourceSigningIdentifier = input.sourceSigningIdentifier else {
            return .handledAndClosed(
                appRole: .selectedApp,
                flowAge: flowAge,
                failureCode: SpikeFailureCode.identityMetadataMissing.rawValue
            )
        }

        guard input.auditTokenIsValid else {
            return .handledAndClosed(
                appRole: .selectedApp,
                flowAge: flowAge,
                failureCode: SpikeFailureCode.identityVerificationFailed.rawValue
            )
        }

        guard sourceSigningIdentifier == request.selectedSigningIdentifier else {
            let role: AppRole = input.isKnownHelper ? .helper : .controlApp
            return .directPass(appRole: role, flowAge: flowAge)
        }

        return .handledAndClosed(
            appRole: .selectedApp,
            flowAge: flowAge,
            failureCode: SpikeFailureCode.wireGuardTransportUnavailable.rawValue
        )
    }
}
