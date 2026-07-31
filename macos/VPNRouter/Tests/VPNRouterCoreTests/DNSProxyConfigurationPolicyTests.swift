import Foundation
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

    @Test
    func runtimeStateSeparatesOwnedEnabledFromOtherConfigurations() {
        #expect(
            DNSProxyConfigurationPolicy.runtimeState(
                ownership: .vpnRouter,
                isEnabled: true
            ) == .ownedEnabled
        )
        #expect(
            DNSProxyConfigurationPolicy.runtimeState(
                ownership: .vpnRouter,
                isEnabled: false
            ) == .ownedDisabled
        )
        #expect(
            DNSProxyConfigurationPolicy.runtimeState(
                ownership: .other,
                isEnabled: true
            ) == .other
        )
    }

    @Test
    func monitorFailsSafeImmediatelyWhenOwnershipOrEnablementIsLost() {
        for state in [
            DNSProxyRuntimeState.absent,
            .ownedDisabled,
            .other,
            .unreadable
        ] {
            #expect(
                DNSProxyConfigurationPolicy.monitorDecision(
                    runtimeState: state,
                    consecutiveHealthFailures: 0
                ) == .failSafe
            )
        }
    }

    @Test
    func monitorAllowsTwoTransientHealthFailuresButNotThree() {
        #expect(
            DNSProxyConfigurationPolicy.monitorDecision(
                runtimeState: .ownedEnabled,
                consecutiveHealthFailures: 0
            ) == .healthy
        )
        #expect(
            DNSProxyConfigurationPolicy.monitorDecision(
                runtimeState: .ownedEnabled,
                consecutiveHealthFailures: 2
            ) == .waitForHealthRetry
        )
        #expect(
            DNSProxyConfigurationPolicy.monitorDecision(
                runtimeState: .ownedEnabled,
                consecutiveHealthFailures: 3
            ) == .failSafe
        )
    }

    @Test
    func monitorFailsSafeImmediatelyWhenTunnelInterfaceSetChanges() {
        #expect(
            DNSProxyConfigurationPolicy.monitorDecision(
                runtimeState: .ownedEnabled,
                consecutiveHealthFailures: 0,
                tunnelInterfaceSetChanged: true
            ) == .failSafe
        )
    }

    @Test
    func encryptedDNSPreflightAllowsExplicitlyDisabledBrowserDoH() {
        let result = EncryptedDNSPreflightPolicy.evaluate(
            browserStates: [
                BrowserSecureDNSState(
                    displayName: "Chrome",
                    isInstalled: true,
                    mode: .off
                ),
                BrowserSecureDNSState(
                    displayName: "Edge",
                    isInstalled: false,
                    mode: .unset
                )
            ]
        )

        #expect(result.disposition == .compatible)
        #expect(result.allowsDNSProxyActivation)
    }

    @Test
    func encryptedDNSPreflightRequiresManualCheckWhenPolicyIsUnset() {
        let result = EncryptedDNSPreflightPolicy.evaluate(
            browserStates: [
                BrowserSecureDNSState(
                    displayName: "Chrome",
                    isInstalled: true,
                    mode: .unset
                )
            ]
        )

        #expect(result.disposition == .needsManualVerification)
        #expect(result.allowsDNSProxyActivation)
    }

    @Test
    func encryptedDNSPreflightBlocksEnabledOrUnknownBrowserDoH() {
        for mode in [
            BrowserSecureDNSMode.automatic,
            .secure,
            .unsupported("future-mode")
        ] {
            let result = EncryptedDNSPreflightPolicy.evaluate(
                browserStates: [
                    BrowserSecureDNSState(
                        displayName: "Chrome",
                        isInstalled: true,
                        mode: mode
                    )
                ]
            )

            #expect(result.disposition == .blocked)
            #expect(!result.allowsDNSProxyActivation)
        }
    }

    @Test
    func browserSecureDNSModeNormalizesPolicyValues() {
        #expect(BrowserSecureDNSMode(rawValue: " OFF ") == .off)
        #expect(BrowserSecureDNSMode(rawValue: "Automatic") == .automatic)
        #expect(BrowserSecureDNSMode(rawValue: "secure") == .secure)
        #expect(BrowserSecureDNSMode(rawValue: nil) == .unset)
        #expect(
            BrowserSecureDNSMode(rawValue: "future-mode")
                == .unsupported("future-mode")
        )
    }

    @Test
    func systemExtensionActivationRequiresApplicationsFolder() {
        #expect(
            SystemExtensionInstallLocationPolicy.allowsActivation(
                for: URL(fileURLWithPath: "/Applications/VPNRouter.app")
            )
        )
        #expect(
            !SystemExtensionInstallLocationPolicy.allowsActivation(
                for: URL(
                    fileURLWithPath:
                        "/Users/test/Library/Developer/Xcode/DerivedData/VPNRouter/Build/Products/Debug/VPNRouter.app"
                )
            )
        )
        #expect(
            !SystemExtensionInstallLocationPolicy.allowsActivation(
                for: URL(fileURLWithPath: "/Applications/VPNRouter")
            )
        )
    }

}
