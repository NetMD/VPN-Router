import Foundation

nonisolated struct ProfileMetadata: Codable, Identifiable, Equatable {
    let id: UUID
    var displayName: String
    let createdAt: Date
    var updatedAt: Date
    var sanitizedConfiguration: String
    var summary: WireGuardConfigSummary

    init(
        id: UUID = UUID(),
        displayName: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        sanitizedConfiguration: String,
        summary: WireGuardConfigSummary
    ) {
        self.id = id
        self.displayName = displayName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sanitizedConfiguration = sanitizedConfiguration
        self.summary = summary
    }
}
