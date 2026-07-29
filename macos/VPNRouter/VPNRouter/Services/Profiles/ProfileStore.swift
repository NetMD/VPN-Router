import Foundation

nonisolated struct ProfileStore {
    private nonisolated let fileURL: URL

    init(
        fileURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws {
        self.fileURL = try fileURL ?? Self.defaultFileURL(fileManager: fileManager)
    }

    func loadProfiles() throws -> [ProfileMetadata] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ProfileMetadataFile.self, from: data).profiles
    }

    func saveProfiles(_ profiles: [ProfileMetadata]) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let payload = ProfileMetadataFile(schemaVersion: 1, profiles: profiles)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    func upsertProfile(_ profile: ProfileMetadata) throws -> [ProfileMetadata] {
        var profiles = try loadProfiles()
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }

        try saveProfiles(profiles)
        return profiles
    }

    func deleteProfile(id: UUID) throws -> [ProfileMetadata] {
        let profiles = try loadProfiles().filter { $0.id != id }
        try saveProfiles(profiles)
        return profiles
    }

    func renameProfile(
        id: UUID,
        displayName: String,
        updatedAt: Date = Date()
    ) throws -> [ProfileMetadata] {
        let normalizedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else {
            throw ProfileStoreError.emptyDisplayName
        }

        var profiles = try loadProfiles()
        guard let index = profiles.firstIndex(where: { $0.id == id }) else {
            throw ProfileStoreError.profileNotFound
        }

        profiles[index].displayName = normalizedName
        profiles[index].updatedAt = updatedAt
        try saveProfiles(profiles)
        return profiles
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
            .appendingPathComponent("Profiles", isDirectory: true)
            .appendingPathComponent("profiles.json", isDirectory: false)
    }
}

private enum ProfileStoreError: LocalizedError {
    case emptyDisplayName
    case profileNotFound

    var errorDescription: String? {
        switch self {
        case .emptyDisplayName:
            return "프로필 이름은 비워 둘 수 없습니다."
        case .profileNotFound:
            return "이름을 변경할 프로필을 찾지 못했습니다."
        }
    }
}

private nonisolated struct ProfileMetadataFile: Codable {
    let schemaVersion: Int
    let profiles: [ProfileMetadata]
}
