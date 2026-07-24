import Foundation
import NetworkExtension

nonisolated struct TunnelProfileProviderConfiguration: Codable, Equatable {
    let schemaVersion: Int
    let mode: String
    let profileId: UUID
    let profileDisplayName: String
    let sanitizedConfiguration: String
    let routePlan: DomainRoutePlan
}

nonisolated struct TunnelRouteUpdateRequest: Codable, Equatable {
    let schemaVersion: Int
    let command: String
    let profileId: UUID
    let routePlan: DomainRoutePlan

    init(profileId: UUID, routePlan: DomainRoutePlan) {
        schemaVersion = 1
        command = "replace-routes"
        self.profileId = profileId
        self.routePlan = routePlan
    }
}

nonisolated struct TunnelRouteUpdateResponse: Codable, Equatable {
    let schemaVersion: Int
    let success: Bool
    let message: String
    let plannedRouteCount: Int
    let routePlanExpiresAt: Date?
}

nonisolated struct TunnelFailSafeUpdateRequest: Codable, Equatable {
    let schemaVersion: Int
    let command: String
    let failSafeEnabled: Bool

    init(failSafeEnabled: Bool) {
        schemaVersion = 1
        command = "update-fail-safe"
        self.failSafeEnabled = failSafeEnabled
    }
}

enum TunnelProfileConfigurationFactory {
    nonisolated static func makeProtocol(
        profile: ProfileMetadata,
        routePlan: DomainRoutePlan
    ) throws -> NETunnelProviderProtocol {
        let tunnelProtocol = NETunnelProviderProtocol()
        tunnelProtocol.providerBundleIdentifier = TunnelIdentifiers.packetTunnelBundleIdentifier
        tunnelProtocol.serverAddress = profile.displayName
        tunnelProtocol.providerConfiguration = try makeProviderConfiguration(
            profile: profile,
            routePlan: routePlan
        )
        return tunnelProtocol
    }

    nonisolated static func makeProviderConfiguration(
        profile: ProfileMetadata,
        routePlan: DomainRoutePlan
    ) throws -> [String: Any] {
        let payload = TunnelProfileProviderConfiguration(
            schemaVersion: 1,
            mode: TunnelProviderModes.phase1WireGuard,
            profileId: profile.id,
            profileDisplayName: profile.displayName,
            sanitizedConfiguration: profile.sanitizedConfiguration,
            routePlan: routePlan
        )
        let data = try JSONEncoder().encode(payload)

        return [
            TunnelProviderConfigurationKeys.schemaVersion: payload.schemaVersion,
            TunnelProviderConfigurationKeys.mode: payload.mode,
            TunnelProviderConfigurationKeys.profileId: profile.id.uuidString,
            TunnelProviderConfigurationKeys.profileDisplayName: profile.displayName,
            TunnelProviderConfigurationKeys.payload: data
        ]
    }
}
