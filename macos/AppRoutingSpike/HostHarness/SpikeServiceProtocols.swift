import Foundation

public protocol SystemExtensionActivating: Sendable {
    func activate() async throws -> SystemExtensionActivationOutcome
}

public enum SystemExtensionActivationOutcome: Equatable, Sendable {
    case completed
    case willCompleteAfterReboot
}

public protocol TransparentProxyControlling: Sendable {
    func start() async throws
    func startAndWaitUntilConnected(timeout: Duration) async throws
    func stopProvider() async throws
    func stopAndWaitUntilDisconnected(timeout: Duration) async throws
    func removeOwnedConfiguration() async throws
    func removeAllOwnedConfigurations() async throws -> Int
    func ownedConfigurationCount() async throws -> Int
}

public extension TransparentProxyControlling {
    func startAndWaitUntilConnected(timeout: Duration) async throws { try await start() }
    func stopAndWaitUntilDisconnected(timeout: Duration) async throws { try await stopProvider() }
    func removeAllOwnedConfigurations() async throws -> Int { try await removeOwnedConfiguration(); return 1 }
    func ownedConfigurationCount() async throws -> Int { 0 }
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

/// 설계상 제어 경로 판정은 Host 자신이 만든 새 흐름 1건을 Provider가 directPass 하는지로 확인합니다.
/// 이 흐름이 없으면 signedMac 판정의 controlPlane 관찰이 비어 INCONCLUSIVE로 남습니다.
public protocol ControlPlaneFlowProbing: Sendable {
    func probeControlPlaneFlow() async
}

public struct LocalFlowControlPlaneProbe: ControlPlaneFlowProbing {
    private let trigger = LocalFlowTrigger()

    public init() {}

    public func probeControlPlaneFlow() async {
        _ = await trigger.trigger(.tcp)
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
