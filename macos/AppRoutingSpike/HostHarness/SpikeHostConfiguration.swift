import Foundation

public struct SpikeHostConfiguration: Equatable, Sendable {
    public static let extensionIdentifierKey = "AppRoutingSpikeExtensionIdentifier"
    public static let machServiceNameKey = "AppRoutingSpikeMachServiceName"

    public let extensionIdentifier: String
    public let machServiceName: String

    public init(bundle: Bundle = .main) throws {
        extensionIdentifier = try Self.requiredValue(
            forKey: Self.extensionIdentifierKey,
            bundle: bundle
        )
        machServiceName = try Self.requiredValue(
            forKey: Self.machServiceNameKey,
            bundle: bundle
        )
    }

    public init(extensionIdentifier: String, machServiceName: String) throws {
        guard Self.isValid(extensionIdentifier), Self.isValid(machServiceName) else {
            throw SpikeHostServiceError.missingHostConfiguration
        }
        self.extensionIdentifier = extensionIdentifier
        self.machServiceName = machServiceName
    }

    private static func requiredValue(forKey key: String, bundle: Bundle) throws -> String {
        guard let value = bundle.object(forInfoDictionaryKey: key) as? String,
              isValid(value) else {
            throw SpikeHostServiceError.missingHostConfiguration
        }
        return value
    }

    private static func isValid(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !trimmed.contains("$(")
    }
}

public struct UnavailableSystemExtensionActivator: SystemExtensionActivating {
    public init() {}

    public func activate() async throws -> SystemExtensionActivationOutcome {
        throw SpikeHostServiceError.missingHostConfiguration
    }
}

public struct UnavailableTransparentProxyController: TransparentProxyControlling {
    public init() {}

    public func start() async throws {
        throw SpikeHostServiceError.missingHostConfiguration
    }

    public func stopProvider() async throws {}
    public func removeOwnedConfiguration() async throws {}
}

public struct UnavailableSpikeXPCClient: SpikeXPCClientProtocol {
    public init() {}

    public func beginRun(_ request: SpikeRunRequest) async throws {
        throw SpikeHostServiceError.missingHostConfiguration
    }

    public func snapshot(runId: UUID) async throws -> [RedactedFlowResult] {
        throw SpikeHostServiceError.missingHostConfiguration
    }

    public func stopRun(runId: UUID) async throws {
        throw SpikeHostServiceError.missingHostConfiguration
    }

    public func invalidate() {}
}
