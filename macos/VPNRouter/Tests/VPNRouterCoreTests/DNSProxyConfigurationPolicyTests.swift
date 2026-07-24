import Testing
@testable import VPNRouterDNSProxyControl

struct DNSProxyConfigurationPolicyTests {
    private let expectedBundleIdentifier = "com.example.VPNRouter.DNSProxyExtension"

    @Test
    func missingConfigurationIsSafeToCreate() {
        let ownership = DNSProxyConfigurationPolicy.ownership(
            hasConfiguration: false,
            providerBundleIdentifier: nil,
            localizedDescription: nil,
            hasProviderConfiguration: false,
            isEnabled: false,
            expectedBundleIdentifier: expectedBundleIdentifier
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
            expectedBundleIdentifier: expectedBundleIdentifier
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
            expectedBundleIdentifier: expectedBundleIdentifier
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
            expectedBundleIdentifier: expectedBundleIdentifier
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
            expectedBundleIdentifier: expectedBundleIdentifier
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
            expectedBundleIdentifier: expectedBundleIdentifier
        )

        #expect(ownership == .other)
    }
}
