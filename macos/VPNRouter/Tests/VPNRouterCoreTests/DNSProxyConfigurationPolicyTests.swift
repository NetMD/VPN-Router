import Testing
@testable import VPNRouterDNSProxyControl

struct DNSProxyConfigurationPolicyTests {
    private let expectedBundleIdentifier = "com.example.VPNRouter.DNSProxyExtension"
    private let expectedLegacyDescription = "com.example.VPNRouter"

    @Test
    func missingConfigurationIsSafeToCreate() {
        let ownership = DNSProxyConfigurationPolicy.ownership(
            hasConfiguration: false,
            providerBundleIdentifier: nil,
            localizedDescription: nil,
            hasProviderConfiguration: false,
            isEnabled: false,
            expectedBundleIdentifier: expectedBundleIdentifier,
            expectedLegacyDescription: expectedLegacyDescription
        )

        #expect(ownership == .none)
    }

    @Test
    func matchingProviderIsOwnedByVPNRouter() {
        let ownership = DNSProxyConfigurationPolicy.ownership(
            hasConfiguration: true,
            providerBundleIdentifier: expectedBundleIdentifier,
            localizedDescription: "VPN Router",
            hasProviderConfiguration: true,
            isEnabled: true,
            expectedBundleIdentifier: expectedBundleIdentifier,
            expectedLegacyDescription: expectedLegacyDescription
        )

        #expect(ownership == .vpnRouter)
    }

    @Test
    func differentProviderIsNeverTreatedAsOwned() {
        let ownership = DNSProxyConfigurationPolicy.ownership(
            hasConfiguration: true,
            providerBundleIdentifier: "com.example.SecurityDNS",
            localizedDescription: "Security DNS",
            hasProviderConfiguration: true,
            isEnabled: false,
            expectedBundleIdentifier: expectedBundleIdentifier,
            expectedLegacyDescription: expectedLegacyDescription
        )

        #expect(ownership == .other)
    }

    @Test
    func emptyInactivePlaceholderIsSafeToConfigure() {
        let ownership = DNSProxyConfigurationPolicy.ownership(
            hasConfiguration: true,
            providerBundleIdentifier: nil,
            localizedDescription: nil,
            hasProviderConfiguration: false,
            isEnabled: false,
            expectedBundleIdentifier: expectedBundleIdentifier,
            expectedLegacyDescription: expectedLegacyDescription
        )

        #expect(ownership == .none)
    }

    @Test
    func unidentifiedConfiguredProviderIsNeverTreatedAsOwned() {
        let ownership = DNSProxyConfigurationPolicy.ownership(
            hasConfiguration: true,
            providerBundleIdentifier: nil,
            localizedDescription: "Existing DNS",
            hasProviderConfiguration: false,
            isEnabled: false,
            expectedBundleIdentifier: expectedBundleIdentifier,
            expectedLegacyDescription: expectedLegacyDescription
        )

        #expect(ownership == .other)
    }

    @Test
    func enabledUnidentifiedProviderIsNeverTreatedAsPlaceholder() {
        let ownership = DNSProxyConfigurationPolicy.ownership(
            hasConfiguration: true,
            providerBundleIdentifier: nil,
            localizedDescription: nil,
            hasProviderConfiguration: false,
            isEnabled: true,
            expectedBundleIdentifier: expectedBundleIdentifier,
            expectedLegacyDescription: expectedLegacyDescription
        )

        #expect(ownership == .other)
    }

    @Test
    func inactiveHostNamedPlaceholderIsSafeToConfigure() {
        let ownership = DNSProxyConfigurationPolicy.ownership(
            hasConfiguration: true,
            providerBundleIdentifier: nil,
            localizedDescription: expectedLegacyDescription,
            hasProviderConfiguration: false,
            isEnabled: false,
            expectedBundleIdentifier: expectedBundleIdentifier,
            expectedLegacyDescription: expectedLegacyDescription
        )

        #expect(ownership == .none)
    }

    @Test
    func differentlyNamedPlaceholderIsNeverClaimed() {
        let ownership = DNSProxyConfigurationPolicy.ownership(
            hasConfiguration: true,
            providerBundleIdentifier: nil,
            localizedDescription: "com.example.SecurityDNS",
            hasProviderConfiguration: false,
            isEnabled: false,
            expectedBundleIdentifier: expectedBundleIdentifier,
            expectedLegacyDescription: expectedLegacyDescription
        )

        #expect(ownership == .other)
    }
}
