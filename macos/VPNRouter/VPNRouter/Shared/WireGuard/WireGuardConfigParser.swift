import Foundation
import Network

enum WireGuardConfigParser {
    private nonisolated static let interfaceSection = "Interface"
    private nonisolated static let peerSection = "Peer"

    nonisolated static func parse(_ configText: String) throws -> WireGuardConfig {
        guard !configText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WireGuardConfigError.invalid("WireGuard 설정 파일이 비어 있습니다.")
        }

        let sections = try parseSections(configText)
        let interfaceValues = try requiredSection(sections, named: interfaceSection)
        let peers = try sections
            .filter { $0.name.caseInsensitiveCompare(peerSection) == .orderedSame }
            .map(parsePeer)

        guard !peers.isEmpty else {
            throw WireGuardConfigError.invalid("WireGuard 설정에 [Peer] 항목이 하나 이상 필요합니다.")
        }

        let config = WireGuardConfig(
            interface: try parseInterface(interfaceValues),
            peers: peers
        )
        try validate(config)
        return config
    }

    nonisolated static func prepareImport(_ configText: String) throws -> WireGuardImportResult {
        let config = try parse(configText)

        return WireGuardImportResult(
            config: config,
            sanitizedConfiguration: sanitize(configText),
            privateKey: config.interface.privateKey,
            summary: createSummary(config)
        )
    }

    nonisolated static func sanitize(_ configText: String) -> String {
        guard !configText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ""
        }

        return normalizeLineEndings(configText)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { rawLine in
                let line = String(rawLine).trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

                if trimmed.hasCaseInsensitivePrefix("PrivateKey"), let split = splitKeyValue(trimmed) {
                    return "\(split.key) = <stored securely>"
                }

                return line
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated static func createSummary(_ config: WireGuardConfig) -> WireGuardConfigSummary {
        WireGuardConfigSummary(
            hasInterfaceSection: true,
            hasPeerSection: !config.peers.isEmpty,
            hasPrivateKey: !config.interface.privateKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            interfaceAddresses: config.interface.addresses,
            dnsServers: config.interface.dnsServers,
            peerCount: config.peers.count,
            allowedIPs: Array(Set(config.peers.flatMap(\.allowedIPs))).sorted(),
            endpoints: config.peers.compactMap(\.endpoint)
        )
    }

    private nonisolated static func parseInterface(_ section: ParsedSection) throws -> WireGuardInterfaceConfig {
        let values = section.values

        return WireGuardInterfaceConfig(
            privateKey: try requiredValue(values, key: "PrivateKey", sectionName: interfaceSection),
            addresses: splitCSV(values["address"]),
            dnsServers: splitCSV(values["dns"]),
            listenPort: try parseNullableInt(values["listenport"], key: "ListenPort")
        )
    }

    private nonisolated static func parsePeer(_ section: ParsedSection) throws -> WireGuardPeerConfig {
        let values = section.values

        return WireGuardPeerConfig(
            publicKey: try requiredValue(values, key: "PublicKey", sectionName: peerSection),
            presharedKey: values["presharedkey"],
            endpoint: values["endpoint"],
            allowedIPs: splitCSV(values["allowedips"]),
            persistentKeepalive: try parseNullableInt(values["persistentkeepalive"], key: "PersistentKeepalive")
        )
    }

    private nonisolated static func validate(_ config: WireGuardConfig) throws {
        guard !config.interface.addresses.isEmpty else {
            throw WireGuardConfigError.invalid("[Interface]에 Address가 하나 이상 필요합니다.")
        }

        try validateBase64LikeKey(config.interface.privateKey, key: "PrivateKey")

        for address in config.interface.addresses {
            try validateCIDR(address, key: "Address")
        }

        for dnsServer in config.interface.dnsServers where IPv4Address(dnsServer) == nil && IPv6Address(dnsServer) == nil {
            throw WireGuardConfigError.invalid("DNS 값이 올바른 IP 주소가 아닙니다: \(dnsServer)")
        }

        for peer in config.peers {
            try validateBase64LikeKey(peer.publicKey, key: "PublicKey")

            if let presharedKey = peer.presharedKey, !presharedKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try validateBase64LikeKey(presharedKey, key: "PresharedKey")
            }

            guard !peer.allowedIPs.isEmpty else {
                throw WireGuardConfigError.invalid("[Peer]에 AllowedIPs 값이 하나 이상 필요합니다.")
            }

            for allowedIP in peer.allowedIPs {
                try validateCIDR(allowedIP, key: "AllowedIPs")
            }
        }
    }

    private nonisolated static func parseSections(_ configText: String) throws -> [ParsedSection] {
        var sections: [ParsedSection] = []
        var currentSection: ParsedSection?

        for (offset, rawLine) in normalizeLineEndings(configText).split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let lineNumber = offset + 1
            let line = stripComment(String(rawLine)).trimmingCharacters(in: .whitespacesAndNewlines)

            guard !line.isEmpty else {
                continue
            }

            if line.hasPrefix("["), line.hasSuffix("]") {
                let sectionName = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !sectionName.isEmpty else {
                    throw WireGuardConfigError.invalid("\(lineNumber)번째 줄의 섹션 이름이 비어 있습니다.")
                }

                currentSection = ParsedSection(name: sectionName)
                sections.append(currentSection!)
                continue
            }

            guard currentSection != nil else {
                throw WireGuardConfigError.invalid("\(lineNumber)번째 줄의 키/값이 섹션보다 먼저 나왔습니다.")
            }

            guard let split = splitKeyValue(line) else {
                throw WireGuardConfigError.invalid("\(lineNumber)번째 줄의 키/값 형식이 올바르지 않습니다.")
            }

            currentSection?.values[split.key.lowercased()] = split.value
            sections[sections.count - 1] = currentSection!
        }

        return sections
    }

    private nonisolated static func requiredSection(_ sections: [ParsedSection], named name: String) throws -> ParsedSection {
        guard let section = sections.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
            throw WireGuardConfigError.invalid("WireGuard 설정에 [\(name)] 섹션이 필요합니다.")
        }

        return section
    }

    private nonisolated static func requiredValue(_ values: [String: String], key: String, sectionName: String) throws -> String {
        guard let value = values[key.lowercased()], !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WireGuardConfigError.invalid("[\(sectionName)]에 \(key) 값이 필요합니다.")
        }

        return value
    }

    private nonisolated static func splitKeyValue(_ line: String) -> (key: String, value: String)? {
        guard let equalsIndex = line.firstIndex(of: "="), equalsIndex != line.startIndex else {
            return nil
        }

        let key = line[..<equalsIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        let value = line[line.index(after: equalsIndex)...].trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? nil : (key, value)
    }

    private nonisolated static func splitCSV(_ value: String?) -> [String] {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        return value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private nonisolated static func parseNullableInt(_ value: String?, key: String) throws -> Int? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        guard let parsed = Int(value), parsed >= 0, parsed <= 65_535 else {
            throw WireGuardConfigError.invalid("\(key) 값은 올바른 포트 또는 간격 정수여야 합니다.")
        }

        return parsed
    }

    private nonisolated static func validateBase64LikeKey(_ value: String, key: String) throws {
        guard value.count >= 32 else {
            throw WireGuardConfigError.invalid("\(key) 값이 올바른 WireGuard 키로 사용하기에 너무 짧습니다.")
        }
    }

    private nonisolated static func validateCIDR(_ value: String, key: String) throws {
        let parts = value.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, let prefix = Int(parts[1]) else {
            throw WireGuardConfigError.invalid("\(key) 값은 CIDR 형식이어야 합니다: \(value)")
        }

        let address = String(parts[0])
        let maxPrefix: Int
        if IPv4Address(address) != nil {
            maxPrefix = 32
        } else if IPv6Address(address) != nil {
            maxPrefix = 128
        } else {
            throw WireGuardConfigError.invalid("\(key) 값은 CIDR 형식이어야 합니다: \(value)")
        }

        guard prefix >= 0, prefix <= maxPrefix else {
            throw WireGuardConfigError.invalid("\(key) 접두사 범위를 벗어났습니다: \(value)")
        }
    }

    private nonisolated static func stripComment(_ line: String) -> String {
        guard let hashIndex = line.firstIndex(of: "#") else {
            return line
        }

        return String(line[..<hashIndex])
    }

    private nonisolated static func normalizeLineEndings(_ value: String) -> String {
        value.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }
}

private struct ParsedSection {
    let name: String
    var values: [String: String] = [:]
}

private extension String {
    nonisolated func hasCaseInsensitivePrefix(_ prefix: String) -> Bool {
        range(of: prefix, options: [.caseInsensitive, .anchored]) != nil
    }
}
