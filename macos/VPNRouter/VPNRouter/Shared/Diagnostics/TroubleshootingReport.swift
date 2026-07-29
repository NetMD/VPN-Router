import Foundation

nonisolated struct TroubleshootingReport: Codable, Equatable {
    static let currentSchemaVersion = 2

    let schemaVersion: Int
    let generatedAt: Date
    let app: AppSummary
    let system: SystemSummary
    let connection: ConnectionSummary
    let routing: RoutingSummary
    let storage: StorageSummary
    let protection: ProtectionSummary
    let lifecycle: LifecycleSummary

    init(
        generatedAt: Date = Date(),
        app: AppSummary,
        system: SystemSummary,
        connection: ConnectionSummary,
        routing: RoutingSummary,
        storage: StorageSummary,
        protection: ProtectionSummary,
        lifecycle: LifecycleSummary
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.generatedAt = generatedAt
        self.app = app
        self.system = system
        self.connection = connection
        self.routing = routing
        self.storage = storage
        self.protection = protection
        self.lifecycle = lifecycle
    }

    nonisolated struct AppSummary: Codable, Equatable {
        let version: String
        let build: String
    }

    nonisolated struct SystemSummary: Codable, Equatable {
        let operatingSystem: String
        let architecture: String
    }

    nonisolated struct ConnectionSummary: Codable, Equatable {
        let state: String
        let stage: String
        let failureCode: String?
        let configurationInstalled: Bool
        let packetTunnelSessionAvailable: Bool
    }

    nonisolated struct RoutingSummary: Codable, Equatable {
        let plannedRouteCount: Int
        let unresolvedDomainCount: Int
        let ipv6BypassRiskDomainCount: Int
        let generatedAt: Date?
        let expiresAt: Date?
    }

    nonisolated struct StorageSummary: Codable, Equatable {
        let profileCount: Int
        let selectedSiteCount: Int
    }

    nonisolated struct ProtectionSummary: Codable, Equatable {
        let routeExpiryDisconnectEnabled: Bool
        let stateOwnership: String
    }

    nonisolated struct LifecycleSummary: Codable, Equatable {
        let networkState: String
        let networkChangeCount: Int
        let sleepCount: Int
        let wakeCount: Int
    }
}

enum TroubleshootingReportEncoder {
    nonisolated static func encode(_ report: TroubleshootingReport) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(report)
    }
}
