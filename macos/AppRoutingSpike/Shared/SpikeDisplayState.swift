import Foundation

public enum SpikeLifecycleState: Equatable, Sendable {
    case notReady
    case configurationInvalid
    case ready
    case awaitingApproval
    case running
    case stopping
    case awaitingControlVerification
    case stopped
    case stoppedWithError
    case cleanupFailed
}

public struct SpikeDisplayState: Equatable, Sendable {
    public var hasSignedEntitlement: Bool
    public var hasValidHostConfiguration: Bool
    public var hasSelectedTestApp: Bool
    public var hasSanitizedFixture: Bool
    public var lifecycle: SpikeLifecycleState
    public var evidenceTier: EvidenceTier
    public var spikeResult: SpikeResult
    public var redactedResultCount: Int
    public var userFacingError: String?

    public init(
        hasSignedEntitlement: Bool = false,
        hasValidHostConfiguration: Bool = true,
        hasSelectedTestApp: Bool = false,
        hasSanitizedFixture: Bool = false,
        lifecycle: SpikeLifecycleState = .notReady,
        evidenceTier: EvidenceTier = .signedMac,
        spikeResult: SpikeResult = .notRun,
        redactedResultCount: Int = 0,
        userFacingError: String? = nil
    ) {
        self.hasSignedEntitlement = hasSignedEntitlement
        self.hasValidHostConfiguration = hasValidHostConfiguration
        self.hasSelectedTestApp = hasSelectedTestApp
        self.hasSanitizedFixture = hasSanitizedFixture
        self.lifecycle = lifecycle
        self.evidenceTier = evidenceTier
        self.spikeResult = spikeResult
        self.redactedResultCount = redactedResultCount
        self.userFacingError = userFacingError
    }

    public var isRunning: Bool {
        lifecycle == .running
    }

    public var isStopping: Bool {
        lifecycle == .stopping
    }

    public var canSelectTestApp: Bool {
        hasValidHostConfiguration
            && !isRunning
            && !isStopping
            && lifecycle != .awaitingControlVerification
    }

    public var canRequestInstallation: Bool {
        canSelectTestApp
    }

    public var hasAllReadinessConditions: Bool {
        hasValidHostConfiguration
            && hasSignedEntitlement
            && hasSelectedTestApp
            && hasSanitizedFixture
    }

    public var canStart: Bool {
        hasAllReadinessConditions && !isRunning && !isStopping
    }

    public var canStop: Bool {
        isRunning && !isStopping
    }

    public var canExport: Bool {
        !isRunning && !isStopping && redactedResultCount > 0
    }

    public var statusText: String {
        switch lifecycle {
        case .notReady, .ready:
            return "시험 준비 전"
        case .configurationInvalid:
            return "시험 앱 구성을 확인하지 못했습니다"
        case .awaitingApproval:
            return "사용자 승인을 기다리는 중"
        case .running:
            return "시험 중"
        case .stopping:
            return "시험을 안전하게 중단하는 중"
        case .awaitingControlVerification:
            return "통제 인터넷 확인이 필요합니다"
        case .stopped:
            return "시험을 안전하게 중단했습니다"
        case .stoppedWithError:
            return "시험을 중단했지만 일부 결과를 확인하지 못했습니다"
        case .cleanupFailed:
            return "시험 상태 정리를 확인하지 못했습니다"
        }
    }

    public var resultCountText: String {
        "결과 \(redactedResultCount)건"
    }
}
