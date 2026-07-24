// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "VPNRouterCore",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "VPNRouterCore", targets: ["VPNRouterCore"]),
        .library(name: "VPNRouterSettings", targets: ["VPNRouterSettings"]),
        .library(name: "VPNRouterDNSObservation", targets: ["VPNRouterDNSObservation"]),
        .library(name: "VPNRouterDNSProxyControl", targets: ["VPNRouterDNSProxyControl"])
    ],
    targets: [
        .target(
            name: "VPNRouterCore",
            path: "VPNRouter/Shared",
            exclude: ["Profiles", "WireGuard"],
            sources: [
                "Rules/DomainRule.swift",
                "Rules/DomainRuleExpander.swift",
                "Rules/DynamicRoutePlanMerger.swift",
                "Rules/DomainRoutePlanner.swift",
                "Rules/DomainRouteRefreshPolicy.swift"
            ]
        ),
        .target(
            name: "VPNRouterSettings",
            path: "VPNRouter/Services/Settings"
        ),
        .target(
            name: "VPNRouterDNSObservation",
            path: "DNSProxyExtension",
            exclude: [
                "DNSFlowSessions.swift",
                "DNSObservationStore.swift",
                "DNSProxyExtension.entitlements",
                "DNSProxyProvider.swift",
                "DNSProxyXPCService.swift",
                "Info.plist",
                "main.swift"
            ],
            sources: ["DNSMessageParser.swift"]
        ),
        .target(
            name: "VPNRouterDNSProxyControl",
            path: "VPNRouter/Services/DNSProxy",
            exclude: [
                "DNSProxyCapabilityProbe.swift",
                "DNSProxyConfigurationController.swift",
                "DNSProxyObservationSettingsStore.swift",
                "DNSProxySystemExtensionController.swift"
            ],
            sources: ["DNSProxyConfigurationPolicy.swift"]
        ),
        .testTarget(
            name: "VPNRouterCoreTests",
            dependencies: [
                "VPNRouterCore",
                "VPNRouterSettings",
                "VPNRouterDNSObservation",
                "VPNRouterDNSProxyControl"
            ]
        )
    ]
)
