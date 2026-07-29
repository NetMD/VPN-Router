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
    private lazy var wireGuardAdapter = WireGuardAdapter(with: self) { [weak self] level, _ in
        self?.updateWireGuardRuntimeMessage("WireGuard 런타임 이벤트를 확인했습니다.")
        self?.logger.log(level: level.osLogType, "WireGuardKit emitted a runtime event.")
    }
    private var activeConfiguration = ProviderRuntimeConfiguration.phase0Stub
    private let wireGuardRuntimeMessageLock = NSLock()
    private var storedWireGuardRuntimeMessage = "WireGuard가 아직 시작되지 않았습니다."
    private var routeExpirationTimer: DispatchSourceTimer?

    override func startTunnel(
        options: [String: NSObject]?,
        completionHandler: @escaping (Error?) -> Void
    ) {
        SharedFailSafeSettingsStore().enforceEnabled()
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
        cancelRouteExpirationTimer()
        wireGuardAdapter.stop { [logger] error in
            if error != nil {
                logger.error("WireGuardKit stop returned an error.")
            }
            completionHandler()
        }
    }

    override func handleAppMessage(
        _ messageData: Data,
        completionHandler: ((Data?) -> Void)?
    ) {
        if !messageData.isEmpty {
            handleRouteUpdate(messageData, completionHandler: completionHandler)
            return
        }

        let diagnostics = TunnelDiagnostics(
            schemaVersion: 2,
            providerState: activeConfiguration.mode,
            profileId: activeConfiguration.profileId,
            profileDisplayName: activeConfiguration.profileDisplayName,
            plannedRouteCount: activeConfiguration.includedRoutes.count,
            ipv6BypassDomainCount: activeConfiguration.ipv6BypassDomains.count,
            routePlanExpiresAt: activeConfiguration.routePlanExpiresAt,
            failSafeEnabled: true,
            wireGuardKitLinked: true,
            message: activeConfiguration.mode == "phase1-wireguard"
                ? currentWireGuardRuntimeMessage()
                : activeConfiguration.diagnosticMessage,
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

            updateWireGuardRuntimeMessage("WireGuard 시작을 요청했습니다.")
            wireGuardAdapter.start(tunnelConfiguration: tunnelConfiguration) { [weak self] error in
                if let error {
                    self?.updateWireGuardRuntimeMessage("WireGuard를 시작하지 못했습니다.")
                    self?.logger.error("WireGuardKit start failed.")
                    completionHandler(error)
                    return
                }

                self?.updateWireGuardRuntimeMessage("WireGuard 연결을 시작했습니다.")
                self?.logger.info("WireGuardKit adapter started.")
                self?.scheduleRouteExpiration()
                completionHandler(nil)
            }
        } catch {
            logger.error("Unable to start WireGuardKit adapter.")
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

    private func handleRouteUpdate(
        _ messageData: Data,
        completionHandler: ((Data?) -> Void)?
    ) {
        do {
            let request = try JSONDecoder().decode(ProviderAppRequest.self, from: messageData)
            guard request.schemaVersion == 1 else {
                throw PacketTunnelRuntimeError.unsupportedProviderMessage
            }

            if request.command == "update-fail-safe" {
                guard request.failSafeEnabled == true else {
                    throw PacketTunnelRuntimeError.unsupportedProviderMessage
                }
                SharedFailSafeSettingsStore().enforceEnabled()
                scheduleRouteExpiration()
                completeRouteUpdate(
                    success: true,
                    message: "필수 만료 보호를 적용했습니다.",
                    completionHandler: completionHandler
                )
                return
            }

            guard
                request.command == "replace-routes",
                let profileId = request.profileId,
                let routePlan = request.routePlan
            else {
                throw PacketTunnelRuntimeError.unsupportedProviderMessage
            }
            guard profileId.uuidString == activeConfiguration.profileId else {
                throw PacketTunnelRuntimeError.routeUpdateProfileMismatch
            }
            guard !routePlan.includedRoutes.isEmpty else {
                throw PacketTunnelRuntimeError.emptyRoutePlan
            }
            guard routePlan.includedRoutes.count <= ProviderRuntimeConfiguration.maximumRouteCount else {
                throw PacketTunnelRuntimeError.routeLimitExceeded(
                    routePlan.includedRoutes.count
                )
            }
            let now = Date()
            guard
                let generatedAt = routePlan.generatedAt,
                let expiresAt = routePlan.expiresAt,
                generatedAt <= now.addingTimeInterval(60),
                expiresAt > now,
                expiresAt.timeIntervalSince(generatedAt) <= ProviderRuntimeConfiguration.routeLifetime
            else {
                throw PacketTunnelRuntimeError.routePlanExpired
            }

            let replacement = try activeConfiguration.replacingRoutes(
                routePlan.includedRoutes,
                ipv6BypassDomains: routePlan.ipv6BypassDomains ?? [],
                generatedAt: generatedAt,
                expiresAt: expiresAt
            )
            guard let profileId = replacement.profileId.flatMap(UUID.init(uuidString:)) else {
                throw PacketTunnelRuntimeError.missingProfileId
            }
            guard let privateKey = try SharedKeychainSecretStore().loadPrivateKey(profileId: profileId) else {
                throw PacketTunnelRuntimeError.missingPrivateKey
            }

            let tunnelConfiguration = try WireGuardKitConfigurationBuilder.build(
                runtimeConfiguration: replacement,
                privateKey: privateKey
            )
            wireGuardAdapter.update(tunnelConfiguration: tunnelConfiguration) { [weak self] error in
                guard let self else {
                    completionHandler?(nil)
                    return
                }
                if error != nil {
                    self.updateWireGuardRuntimeMessage("WireGuard 경로를 새로고치지 못했습니다.")
                    self.logger.error("WireGuardKit route update failed.")
                    self.completeRouteUpdate(
                        success: false,
                        message: "WireGuardKit이 새 경로 계획을 적용하지 못했습니다.",
                        completionHandler: completionHandler
                    )
                    return
                }

                self.activeConfiguration = replacement
                self.updateWireGuardRuntimeMessage("WireGuard에 새 분할 경로를 적용했습니다.")
                self.scheduleRouteExpiration()
                self.logger.info("Applied refreshed split-route plan with \(replacement.includedRoutes.count) route(s).")
                self.completeRouteUpdate(
                    success: true,
                    message: "새 경로 계획을 적용했습니다.",
                    completionHandler: completionHandler
                )
            }
        } catch {
            logger.error("Rejected provider route update.")
            completeRouteUpdate(
                success: false,
                message: error.localizedDescription,
                completionHandler: completionHandler
            )
        }
    }

    private func completeRouteUpdate(
        success: Bool,
        message: String,
        completionHandler: ((Data?) -> Void)?
    ) {
        let response = ProviderRouteUpdateResponse(
            schemaVersion: 1,
            success: success,
            message: message,
            plannedRouteCount: activeConfiguration.includedRoutes.count,
            routePlanExpiresAt: activeConfiguration.routePlanExpiresAt
        )
        completionHandler?(try? JSONEncoder().encode(response))
    }

    private func scheduleRouteExpiration() {
        cancelRouteExpirationTimer()
        guard let expiresAt = activeConfiguration.routePlanExpiresAt else {
            return
        }

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + max(0, expiresAt.timeIntervalSinceNow))
        timer.setEventHandler { [weak self] in
            guard let self else {
                return
            }
            self.logger.error("Split-route plan expired before a successful refresh; cancelling tunnel.")
            self.updateWireGuardRuntimeMessage("경로 계획이 만료되어 VPN 연결 해제를 요청했습니다.")
            self.cancelTunnelWithError(PacketTunnelRuntimeError.routePlanExpired)
        }
        routeExpirationTimer = timer
        timer.resume()
    }

    private func cancelRouteExpirationTimer() {
        routeExpirationTimer?.cancel()
        routeExpirationTimer = nil
    }

    private func currentWireGuardRuntimeMessage() -> String {
        wireGuardRuntimeMessageLock.lock()
        defer { wireGuardRuntimeMessageLock.unlock() }
        return storedWireGuardRuntimeMessage
    }

    private func updateWireGuardRuntimeMessage(_ message: String) {
        wireGuardRuntimeMessageLock.lock()
        storedWireGuardRuntimeMessage = message
        wireGuardRuntimeMessageLock.unlock()
    }
}

private struct ProviderRuntimeConfiguration {
    static let maximumRouteCount = 512
    static let routeLifetime: TimeInterval = 15 * 60
    static let phase0Stub = ProviderRuntimeConfiguration(
        mode: "phase0-stub",
        profileId: nil,
        profileDisplayName: nil,
        sanitizedConfiguration: "",
        includedRoutes: [],
        ipv6BypassDomains: [],
        routePlanGeneratedAt: nil,
        routePlanExpiresAt: nil
    )

    let mode: String
    let profileId: String?
    let profileDisplayName: String?
    let sanitizedConfiguration: String
    let includedRoutes: [ProviderRouteDescriptor]
    let ipv6BypassDomains: [String]
    let routePlanGeneratedAt: Date?
    let routePlanExpiresAt: Date?

    var diagnosticMessage: String {
        if mode == "phase1-wireguard" {
            return "선택한 IPv4 경로에 WireGuard를 사용하도록 구성했습니다."
        }

        return "Packet Tunnel이 응답했습니다."
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
        let loadedAt = Date()
        let generatedAt = payload?.routePlan.generatedAt ?? loadedAt
        let requestedExpiresAt = payload?.routePlan.expiresAt
            ?? generatedAt.addingTimeInterval(routeLifetime)
        let boundedExpiresAt = min(
            requestedExpiresAt,
            loadedAt.addingTimeInterval(routeLifetime)
        )

        return ProviderRuntimeConfiguration(
            mode: mode,
            profileId: providerConfiguration["profileId"] as? String ?? payload?.profileId.uuidString,
            profileDisplayName: providerConfiguration["profileDisplayName"] as? String ?? payload?.profileDisplayName,
            sanitizedConfiguration: payload?.sanitizedConfiguration ?? "",
            includedRoutes: payload?.routePlan.includedRoutes ?? [],
            ipv6BypassDomains: payload?.routePlan.ipv6BypassDomains ?? [],
            routePlanGeneratedAt: payload == nil ? nil : generatedAt,
            routePlanExpiresAt: payload == nil
                ? nil
                : boundedExpiresAt
        )
    }

    func replacingRoutes(
        _ routes: [ProviderRouteDescriptor],
        ipv6BypassDomains: [String],
        generatedAt: Date?,
        expiresAt: Date
    ) throws -> ProviderRuntimeConfiguration {
        var addresses = Set<String>()
        for route in routes {
            guard route.subnetMask == "255.255.255.255", IPAddressRange(from: route.cidr) != nil else {
                throw PacketTunnelRuntimeError.invalidRoutePlanAddress(route.destinationAddress)
            }
            guard addresses.insert(route.destinationAddress).inserted else {
                throw PacketTunnelRuntimeError.duplicateRoutePlanAddress(route.destinationAddress)
            }
        }

        return ProviderRuntimeConfiguration(
            mode: mode,
            profileId: profileId,
            profileDisplayName: profileDisplayName,
            sanitizedConfiguration: sanitizedConfiguration,
            includedRoutes: routes,
            ipv6BypassDomains: Array(Set(ipv6BypassDomains)).sorted(),
            routePlanGeneratedAt: generatedAt ?? Date(),
            routePlanExpiresAt: expiresAt
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
    let ipv6BypassDomains: [String]?
    let generatedAt: Date?
    let expiresAt: Date?
}

private struct ProviderRouteDescriptor: Decodable {
    let destinationAddress: String
    let subnetMask: String
    let sourceDomain: String

    var cidr: String {
        "\(destinationAddress)/32"
    }
}

private struct ProviderAppRequest: Decodable {
    let schemaVersion: Int
    let command: String
    let profileId: UUID?
    let routePlan: ProviderRoutePlan?
    let failSafeEnabled: Bool?
}

private struct ProviderRouteUpdateResponse: Encodable {
    let schemaVersion: Int
    let success: Bool
    let message: String
    let plannedRouteCount: Int
    let routePlanExpiresAt: Date?
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
            throw PacketTunnelRuntimeError.invalidWireGuardConfig("인터페이스 개인 키가 올바르지 않습니다.")
        }

        var interface = InterfaceConfiguration(privateKey: interfacePrivateKey)
        interface.addresses = try parsedConfig.interface.addresses.map { address in
            guard let range = IPAddressRange(from: address) else {
                throw PacketTunnelRuntimeError.invalidWireGuardConfig("인터페이스 주소가 올바르지 않습니다: \(address)")
            }
            return range
        }
        // Phase 1 installs pre-resolved split routes only. Applying the profile DNS
        // globally can send unrelated lookups into a tunnel that does not route them.
        interface.listenPort = parsedConfig.interface.listenPort.flatMap(UInt16.init)

        let selectedAllowedIPs = runtimeConfiguration.includedRoutes.map(\.cidr)
        let peers = try parsedConfig.peers.map { peerConfig in
            guard let publicKey = PublicKey(base64Key: peerConfig.publicKey) else {
                throw PacketTunnelRuntimeError.invalidWireGuardConfig("피어 공개 키가 올바르지 않습니다.")
            }

            var peer = PeerConfiguration(publicKey: publicKey)
            if let presharedKey = peerConfig.presharedKey, !presharedKey.isEmpty {
                guard let key = PreSharedKey(base64Key: presharedKey) else {
                    throw PacketTunnelRuntimeError.invalidWireGuardConfig("피어 사전 공유 키가 올바르지 않습니다.")
                }
                peer.preSharedKey = key
            }
            peer.allowedIPs = try selectedAllowedIPs.map { allowedIP in
                guard let range = IPAddressRange(from: allowedIP) else {
                    throw PacketTunnelRuntimeError.invalidWireGuardConfig("경로 계획 주소가 올바르지 않습니다: \(allowedIP)")
                }
                return range
            }
            if let endpoint = peerConfig.endpoint, !endpoint.isEmpty {
                guard let parsedEndpoint = Endpoint(from: endpoint) else {
                    throw PacketTunnelRuntimeError.invalidWireGuardConfig("피어 엔드포인트가 올바르지 않습니다: \(endpoint)")
                }
                peer.endpoint = parsedEndpoint
            }
            peer.persistentKeepAlive = peerConfig.persistentKeepalive.flatMap(UInt16.init)
            return peer
        }

        guard !peers.isEmpty else {
            throw PacketTunnelRuntimeError.invalidWireGuardConfig("WireGuard 설정에 피어가 하나 이상 필요합니다.")
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
                throw PacketTunnelRuntimeError.invalidWireGuardConfig("설정 줄 형식이 올바르지 않습니다: \(line)")
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
            throw PacketTunnelRuntimeError.invalidWireGuardConfig("인터페이스 개인 키가 없습니다.")
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

private struct SharedFailSafeSettingsStore {
    private static let settingKey = "routePlanExpirationFailSafeEnabled"
    private let defaults: UserDefaults

    init() {
        defaults = Self.appGroupIdentifier().flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    func enforceEnabled() {
        defaults.removeObject(forKey: Self.settingKey)
    }

    private static func appGroupIdentifier() -> String? {
        guard
            let task = SecTaskCreateFromSelf(nil),
            let value = SecTaskCopyValueForEntitlement(
                task,
                "com.apple.security.application-groups" as CFString,
                nil
            ),
            let groups = value as? [String]
        else {
            return nil
        }

        return groups.first
    }
}

private enum PacketTunnelRuntimeError: LocalizedError {
    case duplicateRoutePlanAddress(String)
    case emptyRoutePlan
    case invalidRoutePlanAddress(String)
    case invalidKeychainData
    case invalidWireGuardConfig(String)
    case keychainStatus(OSStatus)
    case missingPrivateKey
    case missingProfileId
    case routeLimitExceeded(Int)
    case routePlanExpired
    case routeUpdateProfileMismatch
    case unsupportedProviderMessage

    var errorDescription: String? {
        switch self {
        case .duplicateRoutePlanAddress(let address):
            return "경로 새로고침에 중복된 IPv4 목적지가 있습니다: \(address)"
        case .emptyRoutePlan:
            return "경로 계획이 비어 있어 전체 트래픽 VPN 연결을 시작하지 않습니다."
        case .invalidRoutePlanAddress(let address):
            return "경로 새로고침에 올바르지 않은 IPv4 /32 목적지가 있습니다: \(address)"
        case .invalidKeychainData:
            return "저장된 개인 키 데이터를 읽지 못했습니다."
        case .invalidWireGuardConfig(let message):
            return message
        case .keychainStatus(let status):
            return "키체인에서 개인 키를 읽지 못했습니다. 상태 코드: \(status)"
        case .missingPrivateKey:
            return "선택한 프로필의 개인 키를 찾지 못했습니다."
        case .missingProfileId:
            return "Packet Tunnel 구성에 프로필 ID가 없습니다."
        case .routeLimitExceeded(let count):
            return "경로 \(count)개가 안전 제한을 초과했습니다."
        case .routePlanExpired:
            return "분할 경로 계획을 새로고치기 전에 만료되었습니다."
        case .routeUpdateProfileMismatch:
            return "새 경로의 프로필이 현재 VPN 연결과 일치하지 않습니다."
        case .unsupportedProviderMessage:
            return "지원하지 않는 Packet Tunnel 요청입니다."
        }
    }
}

private struct TunnelDiagnostics: Codable {
    let schemaVersion: Int
    let providerState: String
    let profileId: String?
    let profileDisplayName: String?
    let plannedRouteCount: Int
    let ipv6BypassDomainCount: Int
    let routePlanExpiresAt: Date?
    let failSafeEnabled: Bool
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
