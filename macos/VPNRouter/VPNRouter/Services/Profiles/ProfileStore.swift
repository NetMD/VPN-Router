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
        let profiles = try ProfileRenamePolicy.renaming(
            loadProfiles(),
            id: id,
            displayName: displayName,
            updatedAt: updatedAt
        )
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

nonisolated extension ProfileMetadata: ProfileRenameRecord {}

private nonisolated struct ProfileMetadataFile: Codable {
    let schemaVersion: Int
    let profiles: [ProfileMetadata]
}
