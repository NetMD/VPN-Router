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

public enum EntitlementEvidenceState: String, Codable, Sendable { case notProvided, confirmed, declined }
public enum ProvisioningEvidenceState: String, Codable, Sendable { case notProvided, confirmed, declined }
public enum ActivationEvidenceState: String, Codable, Sendable { case notObserved, confirmed, rebootRequired, failed }
public enum BaselineState: String, Codable, Sendable { case notCaptured, captured }
public enum CleanupPhase: String, Codable, Sendable {
    case idle, running, rejectingNewFlows, providerStopRequested, providerStopped
    case ownedManagersRemoved, managerCountVerifiedZero, dnsCompared, ipv4Compared, ipv6Compared
    case complete, failed
}

public struct SpikeDisplayState: Equatable, Sendable {
    public var entitlementEvidenceState: EntitlementEvidenceState
    public var provisioningEvidenceState: ProvisioningEvidenceState
    public var activationEvidenceState: ActivationEvidenceState
    public var baselineState: BaselineState
    public var cleanupPhase: CleanupPhase
    public var automatedSummary: ValidationAxisSummary
    public var signedMacSummary: ValidationAxisSummary
    public var p3ProductIntegrationSummary: ValidationAxisSummary
    public var hasValidHostConfiguration: Bool
    public var hasSelectedTestApp: Bool
    public var hasSanitizedFixture: Bool
    public var lifecycle: SpikeLifecycleState
    public var evidenceTier: EvidenceTier
    public var spikeResult: SpikeResult
    public var redactedResultCount: Int
    public var userFacingError: String?

    public init(
        entitlementEvidenceState: EntitlementEvidenceState = .notProvided,
        provisioningEvidenceState: ProvisioningEvidenceState = .notProvided,
        activationEvidenceState: ActivationEvidenceState = .notObserved,
        baselineState: BaselineState = .notCaptured,
        cleanupPhase: CleanupPhase = .idle,
        hasValidHostConfiguration: Bool = true,
        hasSelectedTestApp: Bool = false,
        hasSanitizedFixture: Bool = false,
        lifecycle: SpikeLifecycleState = .notReady,
        evidenceTier: EvidenceTier = .signedMac,
        spikeResult: SpikeResult = .notRun,
        redactedResultCount: Int = 0,
        userFacingError: String? = nil
    ) {
        self.entitlementEvidenceState = entitlementEvidenceState
        self.provisioningEvidenceState = provisioningEvidenceState
        self.activationEvidenceState = activationEvidenceState
        self.baselineState = baselineState
        self.cleanupPhase = cleanupPhase
        let now = Date(timeIntervalSince1970: 0)
        automatedSummary = ValidationAxisSummary(validationAxis: .automated, validationVerdict: .notRun, executedCount: 0, passedCount: 0, failedCount: 0, observedAt: now)
        signedMacSummary = ValidationAxisSummary(validationAxis: .signedMac, validationVerdict: .inconclusive, executedCount: 0, passedCount: 0, failedCount: 0, observedAt: now)
        p3ProductIntegrationSummary = ValidationAxisSummary(validationAxis: .p3ProductIntegration, validationVerdict: .noGo, executedCount: 0, passedCount: 0, failedCount: 0, observedAt: now)
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
        entitlementEvidenceState == .confirmed
            && provisioningEvidenceState == .confirmed
            && !isBusy
    }

    public var hasAllReadinessConditions: Bool {
        hasValidHostConfiguration
            && activationEvidenceState == .confirmed
            && hasSelectedTestApp
            && hasSanitizedFixture
            && baselineState == .captured
    }

    public var canStart: Bool {
        hasAllReadinessConditions && !isRunning && !isStopping
    }

    public var isBusy: Bool {
        isRunning || isStopping || lifecycle == .awaitingApproval
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
