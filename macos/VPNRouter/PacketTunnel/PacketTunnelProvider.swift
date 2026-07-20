import Foundation
import NetworkExtension
import OSLog
import Security
import WireGuardKit

final class PacketTunnelProvider: NEPacketTunnelProvider {
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "VPNRouter.PacketTunnel",
        category: "PacketTunnel"
    )
    private lazy var wireGuardAdapter = WireGuardAdapter(with: self) { [weak self] level, message in
        self?.wireGuardRuntimeMessage = "WireGuardKit: \(message)"
        self?.logger.log(level: level.osLogType, "WireGuardKit: \(message, privacy: .public)")
    }
    private var activeConfiguration = ProviderRuntimeConfiguration.phase0Stub
    private var wireGuardRuntimeMessage = "WireGuardKit has not started yet."

    override func startTunnel(
        options: [String: NSObject]?,
        completionHandler: @escaping (Error?) -> Void
    ) {
        activeConfiguration = ProviderRuntimeConfiguration.from(
            protocolConfiguration: protocolConfiguration,
            options: options
        )
        logger.info("Starting packet tunnel. Mode: \(self.activeConfiguration.mode, privacy: .public)")

        if activeConfiguration.mode == "phase1-wireguard" {
            startWireGuardTunnel(completionHandler: completionHandler)
            return
        }

        applyStubTunnelSettings(completionHandler: completionHandler)
    }

    override func stopTunnel(
        with reason: NEProviderStopReason,
        completionHandler: @escaping () -> Void
    ) {
        logger.info("Stopping packet tunnel. Reason: \(reason.rawValue)")
        wireGuardAdapter.stop { [logger] error in
            if let error {
                logger.error("WireGuardKit stop returned: \(String(describing: error), privacy: .public)")
            }
            completionHandler()
        }
    }

    override func handleAppMessage(
        _ messageData: Data,
        completionHandler: ((Data?) -> Void)?
    ) {
        let diagnostics = TunnelDiagnostics(
            schemaVersion: 1,
            providerState: activeConfiguration.mode,
            profileId: activeConfiguration.profileId,
            profileDisplayName: activeConfiguration.profileDisplayName,
            plannedRouteCount: activeConfiguration.includedRoutes.count,
            wireGuardKitLinked: true,
            message: activeConfiguration.mode == "phase1-wireguard" ? wireGuardRuntimeMessage : activeConfiguration.diagnosticMessage,
            updatedAt: Date()
        )

        completionHandler?(try? JSONEncoder().encode(diagnostics))
    }

    override func sleep(completionHandler: @escaping () -> Void) {
        completionHandler()
    }

    override func wake() {
        logger.info("Packet tunnel woke.")
    }

    private func startWireGuardTunnel(completionHandler: @escaping (Error?) -> Void) {
        do {
            guard let profileId = activeConfiguration.profileId.flatMap(UUID.init(uuidString:)) else {
                throw PacketTunnelRuntimeError.missingProfileId
            }
            guard let privateKey = try SharedKeychainSecretStore().loadPrivateKey(profileId: profileId) else {
                throw PacketTunnelRuntimeError.missingPrivateKey
            }

            let tunnelConfiguration = try WireGuardKitConfigurationBuilder.build(
                runtimeConfiguration: activeConfiguration,
                privateKey: privateKey
            )

            wireGuardRuntimeMessage = "WireGuardKit start requested."
            wireGuardAdapter.start(tunnelConfiguration: tunnelConfiguration) { [weak self] error in
                if let error {
                    self?.wireGuardRuntimeMessage = "WireGuardKit start failed: \(String(describing: error))"
                    self?.logger.error("WireGuardKit start failed: \(String(describing: error), privacy: .public)")
                    completionHandler(error)
                    return
                }

                self?.wireGuardRuntimeMessage = "WireGuardKit adapter start completed."
                self?.logger.info("WireGuardKit adapter started.")
                completionHandler(nil)
            }
        } catch {
            logger.error("Unable to start WireGuardKit adapter: \(error.localizedDescription, privacy: .public)")
            completionHandler(error)
        }
    }

    private func applyStubTunnelSettings(completionHandler: @escaping (Error?) -> Void) {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        settings.mtu = 1280
        settings.ipv4Settings = NEIPv4Settings(
            addresses: ["10.255.0.2"],
            subnetMasks: ["255.255.255.255"]
        )
        settings.ipv4Settings?.includedRoutes = activeConfiguration.includedRoutes.map { route in
            NEIPv4Route(destinationAddress: route.destinationAddress, subnetMask: route.subnetMask)
        }
        settings.ipv4Settings?.excludedRoutes = []

        setTunnelNetworkSettings(settings) { [logger, activeConfiguration] error in
            if let error {
                logger.error("Failed to apply tunnel settings: \(error.localizedDescription, privacy: .public)")
                completionHandler(error)
                return
            }

            logger.info("Packet tunnel settings applied. Mode: \(activeConfiguration.mode, privacy: .public)")
            completionHandler(nil)
        }
    }
}

private struct ProviderRuntimeConfiguration {
    static let phase0Stub = ProviderRuntimeConfiguration(
        mode: "phase0-stub",
        profileId: nil,
        profileDisplayName: nil,
        sanitizedConfiguration: "",
        includedRoutes: []
    )

    let mode: String
    let profileId: String?
    let profileDisplayName: String?
    let sanitizedConfiguration: String
    let includedRoutes: [ProviderRouteDescriptor]

    var diagnosticMessage: String {
        if mode == "phase1-wireguard" {
            return "WireGuardKit is linked and configured for selected IPv4 routes."
        }

        return "PacketTunnelProvider is reachable."
    }

    static func from(
        protocolConfiguration: NEVPNProtocol,
        options: [String: NSObject]?
    ) -> ProviderRuntimeConfiguration {
        let providerConfiguration = (protocolConfiguration as? NETunnelProviderProtocol)?.providerConfiguration ?? [:]
        let mode = options?["mode"] as? String
            ?? providerConfiguration["mode"] as? String
            ?? phase0Stub.mode
        let payload = payload(from: providerConfiguration["payload"])

        return ProviderRuntimeConfiguration(
            mode: mode,
            profileId: providerConfiguration["profileId"] as? String ?? payload?.profileId.uuidString,
            profileDisplayName: providerConfiguration["profileDisplayName"] as? String ?? payload?.profileDisplayName,
            sanitizedConfiguration: payload?.sanitizedConfiguration ?? "",
            includedRoutes: payload?.routePlan.includedRoutes ?? []
        )
    }

    private static func payload(from value: Any?) -> ProviderConfigurationPayload? {
        guard let data = value as? Data else {
            return nil
        }

        return try? JSONDecoder().decode(ProviderConfigurationPayload.self, from: data)
    }
}

private struct ProviderConfigurationPayload: Decodable {
    let profileId: UUID
    let profileDisplayName: String
    let sanitizedConfiguration: String
    let routePlan: ProviderRoutePlan
}

private struct ProviderRoutePlan: Decodable {
    let includedRoutes: [ProviderRouteDescriptor]
}

private struct ProviderRouteDescriptor: Decodable {
    let destinationAddress: String
    let subnetMask: String
    let sourceDomain: String

    var cidr: String {
        "\(destinationAddress)/32"
    }
}

private enum WireGuardKitConfigurationBuilder {
    static func build(
        runtimeConfiguration: ProviderRuntimeConfiguration,
        privateKey: String
    ) throws -> TunnelConfiguration {
        guard !runtimeConfiguration.includedRoutes.isEmpty else {
            throw PacketTunnelRuntimeError.emptyRoutePlan
        }

        let restoredConfiguration = runtimeConfiguration.sanitizedConfiguration
            .replacingOccurrences(of: "PrivateKey = <stored securely>", with: "PrivateKey = \(privateKey)")
        let parsedConfig = try ParsedWireGuardConfiguration.parse(restoredConfiguration)

        guard let interfacePrivateKey = PrivateKey(base64Key: parsedConfig.interface.privateKey) else {
            throw PacketTunnelRuntimeError.invalidWireGuardConfig("Invalid interface private key.")
        }

        var interface = InterfaceConfiguration(privateKey: interfacePrivateKey)
        interface.addresses = try parsedConfig.interface.addresses.map { address in
            guard let range = IPAddressRange(from: address) else {
                throw PacketTunnelRuntimeError.invalidWireGuardConfig("Invalid interface address: \(address)")
            }
            return range
        }
        // Phase 1 installs pre-resolved split routes only. Applying the profile DNS
        // globally can send unrelated lookups into a tunnel that does not route them.
        interface.listenPort = parsedConfig.interface.listenPort.flatMap(UInt16.init)

        let selectedAllowedIPs = runtimeConfiguration.includedRoutes.map(\.cidr)
        let peers = try parsedConfig.peers.map { peerConfig in
            guard let publicKey = PublicKey(base64Key: peerConfig.publicKey) else {
                throw PacketTunnelRuntimeError.invalidWireGuardConfig("Invalid peer public key.")
            }

            var peer = PeerConfiguration(publicKey: publicKey)
            if let presharedKey = peerConfig.presharedKey, !presharedKey.isEmpty {
                guard let key = PreSharedKey(base64Key: presharedKey) else {
                    throw PacketTunnelRuntimeError.invalidWireGuardConfig("Invalid peer preshared key.")
                }
                peer.preSharedKey = key
            }
            peer.allowedIPs = try selectedAllowedIPs.map { allowedIP in
                guard let range = IPAddressRange(from: allowedIP) else {
                    throw PacketTunnelRuntimeError.invalidWireGuardConfig("Invalid route plan address: \(allowedIP)")
                }
                return range
            }
            if let endpoint = peerConfig.endpoint, !endpoint.isEmpty {
                guard let parsedEndpoint = Endpoint(from: endpoint) else {
                    throw PacketTunnelRuntimeError.invalidWireGuardConfig("Invalid peer endpoint: \(endpoint)")
                }
                peer.endpoint = parsedEndpoint
            }
            peer.persistentKeepAlive = peerConfig.persistentKeepalive.flatMap(UInt16.init)
            return peer
        }

        guard !peers.isEmpty else {
            throw PacketTunnelRuntimeError.invalidWireGuardConfig("WireGuard config must contain at least one peer.")
        }

        return TunnelConfiguration(
            name: runtimeConfiguration.profileDisplayName,
            interface: interface,
            peers: peers
        )
    }
}

private struct ParsedWireGuardConfiguration {
    let interface: ParsedInterface
    let peers: [ParsedPeer]

    static func parse(_ configText: String) throws -> ParsedWireGuardConfiguration {
        var currentSection = ""
        var interfaceValues: [String: String] = [:]
        var peerValues: [[String: String]] = []

        func commitPeer(_ values: [String: String]) {
            if !values.isEmpty {
                peerValues.append(values)
            }
        }

        var pendingPeer: [String: String] = [:]
        for rawLine in configText.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
                .split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
                .first
                .map(String.init)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !line.isEmpty else {
                continue
            }

            if line.caseInsensitiveCompare("[Interface]") == .orderedSame {
                commitPeer(pendingPeer)
                pendingPeer = [:]
                currentSection = "interface"
                continue
            }
            if line.caseInsensitiveCompare("[Peer]") == .orderedSame {
                commitPeer(pendingPeer)
                pendingPeer = [:]
                currentSection = "peer"
                continue
            }

            guard let equals = line.firstIndex(of: "=") else {
                throw PacketTunnelRuntimeError.invalidWireGuardConfig("Invalid config line: \(line)")
            }
            let key = line[..<equals].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespacesAndNewlines)

            if currentSection == "interface" {
                interfaceValues[key] = value
            } else if currentSection == "peer" {
                pendingPeer[key] = value
            }
        }
        commitPeer(pendingPeer)

        guard let privateKey = interfaceValues["privatekey"] else {
            throw PacketTunnelRuntimeError.invalidWireGuardConfig("Missing interface private key.")
        }

        return ParsedWireGuardConfiguration(
            interface: ParsedInterface(
                privateKey: privateKey,
                addresses: splitCSV(interfaceValues["address"]),
                dnsServers: splitCSV(interfaceValues["dns"]),
                listenPort: interfaceValues["listenport"].flatMap(Int.init)
            ),
            peers: peerValues.map { values in
                ParsedPeer(
                    publicKey: values["publickey"] ?? "",
                    presharedKey: values["presharedkey"],
                    endpoint: values["endpoint"],
                    persistentKeepalive: values["persistentkeepalive"].flatMap(Int.init)
                )
            }
        )
    }

    private static func splitCSV(_ value: String?) -> [String] {
        guard let value else {
            return []
        }

        return value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

private struct ParsedInterface {
    let privateKey: String
    let addresses: [String]
    let dnsServers: [String]
    let listenPort: Int?
}

private struct ParsedPeer {
    let publicKey: String
    let presharedKey: String?
    let endpoint: String?
    let persistentKeepalive: Int?
}

private struct SharedKeychainSecretStore {
    private let service = "VPNRouter.WireGuardPrivateKeys"
    private let accessGroup = KeychainEntitlements.defaultAccessGroup()

    func loadPrivateKey(profileId: UUID) throws -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "wireguard.privateKey.\(profileId.uuidString)",
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true
        ]

        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw PacketTunnelRuntimeError.keychainStatus(status)
        }
        guard
            let data = result as? Data,
            let privateKey = String(data: data, encoding: .utf8)
        else {
            throw PacketTunnelRuntimeError.invalidKeychainData
        }

        return privateKey
    }
}

private enum KeychainEntitlements {
    static func defaultAccessGroup() -> String? {
        guard
            let task = SecTaskCreateFromSelf(nil),
            let value = SecTaskCopyValueForEntitlement(task, "keychain-access-groups" as CFString, nil),
            let groups = value as? [String]
        else {
            return nil
        }

        return groups.first
    }
}

private enum PacketTunnelRuntimeError: LocalizedError {
    case emptyRoutePlan
    case invalidKeychainData
    case invalidWireGuardConfig(String)
    case keychainStatus(OSStatus)
    case missingPrivateKey
    case missingProfileId

    var errorDescription: String? {
        switch self {
        case .emptyRoutePlan:
            return "Route plan is empty; refusing to start a full-tunnel WireGuard session."
        case .invalidKeychainData:
            return "Stored private key data is not valid UTF-8."
        case .invalidWireGuardConfig(let message):
            return message
        case .keychainStatus(let status):
            return "Keychain read failed with status \(status)."
        case .missingPrivateKey:
            return "No private key was found for the selected profile."
        case .missingProfileId:
            return "Provider configuration is missing a profile id."
        }
    }
}

private struct TunnelDiagnostics: Codable {
    let schemaVersion: Int
    let providerState: String
    let profileId: String?
    let profileDisplayName: String?
    let plannedRouteCount: Int
    let wireGuardKitLinked: Bool
    let message: String
    let updatedAt: Date
}

private extension WireGuardLogLevel {
    var osLogType: OSLogType {
        switch self {
        case .verbose:
            return .debug
        case .error:
            return .error
        }
    }
}
