import Foundation

public protocol SystemExtensionActivating: Sendable {
    func activate() async throws
}

public protocol TransparentProxyControlling: Sendable {
    func start() async throws
    func stopProvider() async throws
    func removeOwnedConfiguration() async throws
}

@MainActor
public protocol SelectedTestAppSelecting: Sendable {
    func selectSignedApplication() async throws -> Bool
    func consumeIdentity() throws -> SelectedTestAppIdentity
    func clear()
}

public struct SelectedTestAppIdentity: Equatable, Sendable {
    public let signingIdentifier: String
    public let teamIdentifier: String

    public init(signingIdentifier: String, teamIdentifier: String) {
        self.signingIdentifier = signingIdentifier
        self.teamIdentifier = teamIdentifier
    }
}

public enum ControlConnectivityVerification: Equatable, Sendable {
    case requiresUserConfirmation
}

public protocol ControlConnectivityVerifying: Sendable {
    func verifyAfterCleanup() async -> ControlConnectivityVerification
}

public struct ManualControlConnectivityVerifier: ControlConnectivityVerifying {
    public init() {}

    public func verifyAfterCleanup() async -> ControlConnectivityVerification {
        .requiresUserConfirmation
    }
}

public enum SpikeHostServiceError: Error, Equatable, LocalizedError {
    case entitlementUnavailable
    case extensionActivationFailed
    case proxyConfigurationFailed
    case proxyStartFailed
    case proxyCleanupFailed
    case missingHostConfiguration
    case invalidSelectedApplication
    case selectedApplicationUnavailable

    public var errorDescription: String? {
        switch self {
        case .entitlementUnavailable:
            return "필요한 개발 권한을 확인하지 못했습니다."
        case .extensionActivationFailed:
            return "시스템 확장 승인이 필요합니다."
        case .proxyConfigurationFailed, .proxyStartFailed:
            return "시험 확장을 시작하지 못했습니다."
        case .proxyCleanupFailed:
            return "시험 상태 정리를 확인하지 못했습니다."
        case .missingHostConfiguration:
            return "시험 앱 구성을 확인하지 못했습니다."
        case .invalidSelectedApplication:
            return "서명된 시험 앱을 확인하지 못했습니다."
        case .selectedApplicationUnavailable:
            return "시험 앱을 다시 지정해 주세요."
        }
    }
}
