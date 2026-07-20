import Foundation

nonisolated struct DomainRule: Codable, Identifiable, Equatable {
    let id: UUID
    let profileId: UUID
    let domain: String
    let includeSubdomains: Bool
    let enabled: Bool
    let createdAt: Date

    init(
        id: UUID = UUID(),
        profileId: UUID,
        domain: String,
        includeSubdomains: Bool,
        enabled: Bool,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.profileId = profileId
        self.domain = domain
        self.includeSubdomains = includeSubdomains
        self.enabled = enabled
        self.createdAt = createdAt
    }
}
