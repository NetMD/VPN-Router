import Foundation

public enum SpikeRequestValidationError: Error, Equatable {
    case payloadTooLarge
    case unsupportedSchema
    case invalidCandidate
    case invalidEvidenceTier
    case missingSigningIdentifier
    case signingIdentifierTooLong
    case missingTeamIdentifier
    case invalidTeamIdentifier
}

public struct SpikeRequestValidator: Sendable {
    public init() {}

    public func validate(payload: Data, decoded request: SpikeRunRequest) throws {
        guard payload.count <= SpikeLimits.maximumXPCPayloadBytes else {
            throw SpikeRequestValidationError.payloadTooLarge
        }
        guard request.schemaVersion == SpikeLimits.schemaVersion else {
            throw SpikeRequestValidationError.unsupportedSchema
        }
        guard request.candidateKind == .transparentProxy else {
            throw SpikeRequestValidationError.invalidCandidate
        }
        guard request.evidenceTier == .automated || request.evidenceTier == .signedMac else {
            throw SpikeRequestValidationError.invalidEvidenceTier
        }
        guard !request.selectedSigningIdentifier.isEmpty else {
            throw SpikeRequestValidationError.missingSigningIdentifier
        }
        guard request.selectedSigningIdentifier.utf8.count <= SpikeLimits.maximumSigningIdentifierBytes else {
            throw SpikeRequestValidationError.signingIdentifierTooLong
        }
        guard !request.selectedTeamIdentifier.isEmpty else {
            throw SpikeRequestValidationError.missingTeamIdentifier
        }
        let allowedTeamCharacters = CharacterSet.alphanumerics
        guard request.selectedTeamIdentifier.utf8.count <= SpikeLimits.maximumTeamIdentifierBytes,
              request.selectedTeamIdentifier.unicodeScalars.allSatisfy(allowedTeamCharacters.contains) else {
            throw SpikeRequestValidationError.invalidTeamIdentifier
        }
    }
}
