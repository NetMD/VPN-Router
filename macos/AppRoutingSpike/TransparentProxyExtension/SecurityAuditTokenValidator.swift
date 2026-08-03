import Foundation
import Security

final class SecurityAuditTokenValidator: AuditTokenValidating, @unchecked Sendable {
    func validate(
        _ auditToken: Data,
        expectedSigningIdentifier: String,
        expectedTeamIdentifier: String?
    ) -> Bool {
        let attributes = [kSecGuestAttributeAudit as String: auditToken] as CFDictionary
        var code: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess,
              let code,
              SecCodeCheckValidity(code, [], nil) == errSecSuccess else {
            return false
        }

        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-")
        guard !expectedSigningIdentifier.isEmpty,
              expectedSigningIdentifier.unicodeScalars.allSatisfy(allowed.contains) else {
            return false
        }
        var requirement: SecRequirement?
        let teamClause: String
        if let expectedTeamIdentifier {
            guard expectedTeamIdentifier.unicodeScalars.allSatisfy(allowed.contains) else { return false }
            teamClause = " and certificate leaf[subject.OU] = \"\(expectedTeamIdentifier)\""
        } else {
            teamClause = ""
        }
        let requirementText = "anchor apple generic and identifier \"\(expectedSigningIdentifier)\"\(teamClause)" as CFString
        guard SecRequirementCreateWithString(requirementText, [], &requirement) == errSecSuccess,
              let requirement else {
            return false
        }
        return SecCodeCheckValidity(code, [], requirement) == errSecSuccess
    }
}
