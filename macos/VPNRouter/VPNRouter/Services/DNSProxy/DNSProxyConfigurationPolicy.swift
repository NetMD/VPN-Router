import Foundation

enum DNSProxyConfigurationOwnership: Equatable {
    case none
    case vpnRouter
    case other
}

enum DNSProxyConfigurationPolicy {
    static func ownership(
        hasConfiguration: Bool,
        providerBundleIdentifier: String?,
        localizedDescription: String?,
        hasProviderConfiguration: Bool,
        isEnabled: Bool,
        expectedBundleIdentifier: String,
        expectedLegacyDescription: String?
    ) -> DNSProxyConfigurationOwnership {
        guard hasConfiguration else {
            return .none
        }
        if providerBundleIdentifier == expectedBundleIdentifier {
            return .vpnRouter
        }

        let normalizedDescription = localizedDescription?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let hasDescription = normalizedDescription?.isEmpty == false
        if providerBundleIdentifier == nil,
           !hasProviderConfiguration,
           !isEnabled {
            if hasDescription == false || normalizedDescription == expectedLegacyDescription {
                return .none
            }
        }

        return .other
    }
}
