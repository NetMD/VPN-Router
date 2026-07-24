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
        .library(name: "VPNRouterDNSObservation", targets: ["VPNRouterDNSObservation"])
    ],
    targets: [
        .target(
            name: "VPNRouterCore",
            path: "VPNRouter/Shared",
            exclude: ["Profiles", "WireGuard"],
            sources: [
                "Rules/DomainRule.swift",
                "Rules/DomainRuleExpander.swift",
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
                "Info.plist",
                "main.swift"
            ],
            sources: ["DNSMessageParser.swift"]
        ),
        .testTarget(
            name: "VPNRouterCoreTests",
            dependencies: [
                "VPNRouterCore",
                "VPNRouterSettings",
                "VPNRouterDNSObservation"
            ]
        )
    ]
)
