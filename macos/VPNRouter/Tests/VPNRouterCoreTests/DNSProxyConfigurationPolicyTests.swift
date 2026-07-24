import Testing
@testable import VPNRouterDNSProxyControl

struct DNSProxyConfigurationPolicyTests {
    private let expectedBundleIdentifier = "com.example.VPNRouter.DNSProxyExtension"

    @Test
    func missingConfigurationIsSafeToCreate() {
        let ownership = DNSProxyConfigurationPolicy.ownership(
            hasConfiguration: false,
            providerBundleIdentifier: nil,
            expectedBundleIdentifier: expectedBundleIdentifier
        )

        #expect(ownership == .none)
    }

    @Test
    func matchingProviderIsOwnedByVPNRouter() {
        let ownership = DNSProxyConfigurationPolicy.ownership(
            hasConfiguration: true,
            providerBundleIdentifier: expectedBundleIdentifier,
            expectedBundleIdentifier: expectedBundleIdentifier
        )

        #expect(ownership == .vpnRouter)
    }

    @Test
    func differentProviderIsNeverTreatedAsOwned() {
        let ownership = DNSProxyConfigurationPolicy.ownership(
            hasConfiguration: true,
            providerBundleIdentifier: "com.example.SecurityDNS",
            expectedBundleIdentifier: expectedBundleIdentifier
        )

        #expect(ownership == .other)
    }

    @Test
    func unidentifiedExistingConfigurationIsNeverTreatedAsOwned() {
        let ownership = DNSProxyConfigurationPolicy.ownership(
            hasConfiguration: true,
            providerBundleIdentifier: nil,
            expectedBundleIdentifier: expectedBundleIdentifier
        )

        #expect(ownership == .other)
    }
}
