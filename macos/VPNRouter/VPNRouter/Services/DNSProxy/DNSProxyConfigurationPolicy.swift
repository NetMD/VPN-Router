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
        expectedBundleIdentifier: String
    ) -> DNSProxyConfigurationOwnership {
        guard hasConfiguration else {
            return .none
        }
        return providerBundleIdentifier == expectedBundleIdentifier
            ? .vpnRouter
            : .other
    }
}
