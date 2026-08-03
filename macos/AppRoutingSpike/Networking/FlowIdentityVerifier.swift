import Foundation

public protocol AuditTokenValidating: Sendable {
    func validate(
        _ auditToken: Data,
        expectedSigningIdentifier: String,
        expectedTeamIdentifier: String?
    ) -> Bool
}

/// metadata 식별자와 audit token 서명 식별자가 모두 정확히 같을 때만 신원을 인정합니다.
public struct FlowIdentityVerifier: Sendable {
    private let auditTokenValidator: any AuditTokenValidating

    public init(auditTokenValidator: any AuditTokenValidating) {
        self.auditTokenValidator = auditTokenValidator
    }

    public func verify(
        sourceSigningIdentifier: String?,
        sourceAppAuditToken: Data?,
        expectedSigningIdentifier: String,
        expectedTeamIdentifier: String?
    ) -> Bool {
        guard sourceSigningIdentifier == expectedSigningIdentifier,
              let sourceAppAuditToken else {
            return false
        }
        return auditTokenValidator.validate(
            sourceAppAuditToken,
            expectedSigningIdentifier: expectedSigningIdentifier,
            expectedTeamIdentifier: expectedTeamIdentifier
        )
    }
}

public struct ControlPlaneExclusionPolicy: Sendable {
    private let signingIdentifiers: Set<String>

    public init(signingIdentifiers: Set<String>) {
        self.signingIdentifiers = signingIdentifiers
    }

    public func contains(signingIdentifier: String?) -> Bool {
        guard let signingIdentifier else { return false }
        return signingIdentifiers.contains(signingIdentifier)
    }
}
