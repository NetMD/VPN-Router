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
        expectedBundleIdentifier: String
    ) -> DNSProxyConfigurationOwnership {
        guard hasConfiguration else {
            return .none
        }
        if providerBundleIdentifier == expectedBundleIdentifier {
            return .vpnRouter
        }

        let hasDescription = localizedDescription?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty == false
        if providerBundleIdentifier == nil,
           hasDescription == false,
           !hasProviderConfiguration,
           !isEnabled {
            return .none
        }

        return .other
    }
}
