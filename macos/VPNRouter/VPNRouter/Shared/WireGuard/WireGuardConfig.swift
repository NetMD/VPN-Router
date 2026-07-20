import Foundation

struct WireGuardConfig: Equatable {
    let interface: WireGuardInterfaceConfig
    let peers: [WireGuardPeerConfig]
}

struct WireGuardInterfaceConfig: Equatable {
    let privateKey: String
    let addresses: [String]
    let dnsServers: [String]
    let listenPort: Int?
}

struct WireGuardPeerConfig: Equatable {
    let publicKey: String
    let presharedKey: String?
    let endpoint: String?
    let allowedIPs: [String]
    let persistentKeepalive: Int?
}

nonisolated struct WireGuardConfigSummary: Codable, Equatable {
    let hasInterfaceSection: Bool
    let hasPeerSection: Bool
    let hasPrivateKey: Bool
    let interfaceAddresses: [String]
    let dnsServers: [String]
    let peerCount: Int
    let allowedIPs: [String]
    let endpoints: [String]
}

struct WireGuardImportResult: Equatable {
    let config: WireGuardConfig
    let sanitizedConfiguration: String
    let privateKey: String
    let summary: WireGuardConfigSummary
}

enum WireGuardConfigError: LocalizedError, Equatable {
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .invalid(let message):
            return message
        }
    }
}
