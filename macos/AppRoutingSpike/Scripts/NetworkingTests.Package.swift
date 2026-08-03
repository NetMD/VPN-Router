// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AppRoutingSpikeNetworking",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "AppRoutingSpikeNetworking", targets: ["AppRoutingSpikeNetworking"])
    ],
    targets: [
        .target(name: "AppRoutingSpikeNetworking", path: "Sources"),
        .testTarget(
            name: "AppRoutingSpikeNetworkingTests",
            dependencies: ["AppRoutingSpikeNetworking"],
            path: "Tests"
        )
    ]
)
