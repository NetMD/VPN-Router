import Foundation

public enum CleanupStep: String, Codable, CaseIterable, Sendable {
    case rejectNewFlows
    case stopProvider
    case removeOwnedConfiguration
    case verifyControlConnectivity
}

/// 시제품이 소유한 상태만 설계 순서대로 정리합니다.
public struct CleanupCoordinator: Sendable {
    public init() {}

    public func orderedSteps() -> [CleanupStep] {
        CleanupStep.allCases
    }
}
