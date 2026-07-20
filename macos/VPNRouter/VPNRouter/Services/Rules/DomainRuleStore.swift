import Foundation

nonisolated struct DomainRuleStore {
    static nonisolated let sharedSiteRulesProfileId = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    private nonisolated let fileURL: URL

    init(
        fileURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws {
        self.fileURL = try fileURL ?? Self.defaultFileURL(fileManager: fileManager)
    }

    func loadRules() throws -> [DomainRule] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(DomainRuleFile.self, from: data).rules
    }

    func loadRules(profileId: UUID) throws -> [DomainRule] {
        try loadRules().filter { $0.profileId == profileId }
    }

    func saveRules(_ rules: [DomainRule]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let payload = DomainRuleFile(schemaVersion: 1, rules: rules)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    func upsertRule(_ rule: DomainRule) throws -> [DomainRule] {
        var rules = try loadRules()
        if let index = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[index] = rule
        } else {
            rules.append(rule)
        }

        try saveRules(rules)
        return rules
    }

    func deleteRule(id: UUID) throws -> [DomainRule] {
        let rules = try loadRules().filter { $0.id != id }
        try saveRules(rules)
        return rules
    }

    func deleteRules(profileId: UUID) throws -> [DomainRule] {
        let rules = try loadRules().filter { $0.profileId != profileId }
        try saveRules(rules)
        return rules
    }

    private nonisolated static func defaultFileURL(fileManager: FileManager) throws -> URL {
        let applicationSupportURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        return applicationSupportURL
            .appendingPathComponent("VPNRouter", isDirectory: true)
            .appendingPathComponent("Rules", isDirectory: true)
            .appendingPathComponent("domain-rules.json", isDirectory: false)
    }
}

private nonisolated struct DomainRuleFile: Codable {
    let schemaVersion: Int
    let rules: [DomainRule]
}
