import Foundation

struct ProfileImportService {
    private let profileStore: ProfileStore
    private let secretStore: KeychainSecretStore

    init(profileStore: ProfileStore, secretStore: KeychainSecretStore = KeychainSecretStore()) {
        self.profileStore = profileStore
        self.secretStore = secretStore
    }

    func importProfile(
        displayName: String,
        configText: String,
        id: UUID = UUID(),
        importedAt: Date = Date()
    ) throws -> ProfileMetadata {
        let importResult = try WireGuardConfigParser.prepareImport(configText)
        let safeDisplayName = Self.normalizedDisplayName(displayName)
        let metadata = ProfileMetadata(
            id: id,
            displayName: safeDisplayName,
            createdAt: importedAt,
            updatedAt: importedAt,
            sanitizedConfiguration: importResult.sanitizedConfiguration,
            summary: importResult.summary
        )

        try secretStore.savePrivateKey(importResult.privateKey, profileId: id)

        do {
            _ = try profileStore.upsertProfile(metadata)
        } catch {
            try? secretStore.deletePrivateKey(profileId: id)
            throw error
        }

        return metadata
    }

    private static func normalizedDisplayName(_ displayName: String) -> String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "가져온 WireGuard 프로필" : trimmed
    }
}
