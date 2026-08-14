import Foundation

/// Host Harness와 Provider 사이의 로컬 XPC 경계입니다.
/// 요청과 응답은 크기 제한 및 가림 검사를 거치는 UTF-8 JSON `Data`만 사용합니다.
@objc public protocol SpikeXPCProtocol {
    func beginRun(_ request: Data, withReply reply: @escaping (Data) -> Void)
    func snapshot(_ request: Data, withReply reply: @escaping (Data) -> Void)
    func stopRun(_ request: Data, withReply reply: @escaping (Data) -> Void)
}

public enum SpikeCommandKind: String, Codable, Sendable {
    case beginRun
    case stopRun
}

public struct SpikeCommandResponse: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let runId: UUID
    public let command: SpikeCommandKind
    public let accepted: Bool
    public let acceptedAt: Date

    public init(
        schemaVersion: Int = 2,
        runId: UUID,
        command: SpikeCommandKind,
        accepted: Bool = true,
        acceptedAt: Date
    ) {
        self.schemaVersion = schemaVersion
        self.runId = runId
        self.command = command
        self.accepted = accepted
        self.acceptedAt = acceptedAt
    }
}

public struct SpikeSnapshotRequest: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let runId: UUID
    public let cursor: UInt64?
    public let limit: Int

    public init(schemaVersion: Int = 2, runId: UUID, cursor: UInt64?, limit: Int) {
        self.schemaVersion = schemaVersion
        self.runId = runId
        self.cursor = cursor
        self.limit = limit
    }
}

public struct SpikeSnapshotItem: Codable, Equatable, Sendable {
    public let cursor: UInt64
    public let result: RedactedFlowResult

    public init(cursor: UInt64, result: RedactedFlowResult) {
        self.cursor = cursor
        self.result = result
    }
}

public struct SpikeSnapshotPage: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let runId: UUID
    public let items: [SpikeSnapshotItem]
    public let nextCursor: UInt64?
    public let hasMore: Bool

    public init(
        schemaVersion: Int = 2,
        runId: UUID,
        items: [SpikeSnapshotItem],
        nextCursor: UInt64?,
        hasMore: Bool
    ) {
        self.schemaVersion = schemaVersion
        self.runId = runId
        self.items = items
        self.nextCursor = nextCursor
        self.hasMore = hasMore
    }
}

public struct SpikeErrorResponse: Codable, Equatable, Sendable {
    public struct ErrorBody: Codable, Equatable, Sendable {
        public let code: String
        public let message: String

        public init(code: String, message: String) {
            self.code = code
            self.message = message
        }
    }

    public let error: ErrorBody

    public init(code: String, message: String) {
        error = ErrorBody(code: code, message: message)
    }
}

/// 기술 스파이크에서 비교하는 Apple 네트워크 후보입니다.
public enum CandidateKind: String, Codable, CaseIterable, Sendable {
    case managedPerAppVPN
    case appProxy
    case transparentProxy
    case contentFilter
    case packetTunnelOnly
}

/// 결과가 자동 검사인지 실제 서명 Mac 시험인지 구분합니다.
public enum EvidenceTier: String, Codable, CaseIterable, Sendable {
    case automated
    case signedMac
}

public enum ValidationAxis: String, Codable, CaseIterable, Sendable {
    case automated
    case signedMac
    case p3ProductIntegration
}

public enum ValidationVerdict: String, Codable, CaseIterable, Sendable {
    case notRun, pass, fail, inconclusive, noGo
}

public enum HandlingOutcome: String, Codable, CaseIterable, Sendable {
    case directPass
    case ownedAndClosed
}

public enum SpikeFailureCode: String, Codable, CaseIterable, Sendable {
    case identityVerificationFailed = "identity-verification-failed"
    case identityMetadataMissing = "identity-metadata-missing"
    case wireGuardTransportUnavailable = "wireguard-transport-unavailable"
    case selectedFlowLimitExceeded = "selected-flow-limit-exceeded"
    case evidenceBufferFull = "evidence-buffer-full"
    case xpcPayloadTooLarge = "xpc-payload-too-large"
    case invalidRequest = "invalid-request"
    case runMismatch = "run-mismatch"
    case runIDConflict = "run-id-conflict"
    case stoppingNewFlowRejected = "stopping-new-flow-rejected"
}

public struct ValidationAxisSummary: Codable, Equatable, Sendable {
    public let validationAxis: ValidationAxis
    public let validationVerdict: ValidationVerdict
    public let executedCount: Int
    public let passedCount: Int
    public let failedCount: Int
    public let observedAt: Date

    public init(validationAxis: ValidationAxis, validationVerdict: ValidationVerdict,
                executedCount: Int, passedCount: Int, failedCount: Int, observedAt: Date) {
        self.validationAxis = validationAxis
        self.validationVerdict = validationVerdict
        self.executedCount = executedCount
        self.passedCount = passedCount
        self.failedCount = failedCount
        self.observedAt = observedAt
    }
}

public struct CleanupSummary: Codable, Equatable, Sendable {
    public let providerStopObserved: Bool
    public let managerCountAfterCleanup: Int?
    public let dnsMatchedBaseline: Bool?
    public let ipv4MatchedBaseline: Bool?
    public let ipv6MatchedBaseline: Bool?
}

public struct RedactedValidationReport: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let validationSummaries: [ValidationAxisSummary]
    public let cleanupSummary: CleanupSummary?
    public let results: [RedactedFlowResult]

    public init(schemaVersion: Int = 2, validationSummaries: [ValidationAxisSummary],
                cleanupSummary: CleanupSummary?, results: [RedactedFlowResult]) {
        self.schemaVersion = schemaVersion
        self.validationSummaries = validationSummaries
        self.cleanupSummary = cleanupSummary
        self.results = results
    }
}

/// 서로 섞어 해석하면 안 되는 스파이크 판정입니다.
public enum SpikeResult: String, Codable, CaseIterable, Sendable {
    case notRun
    case pass
    case fail
    case inconclusive
    case stopped
}

/// 관찰 대상으로 합의된 흐름 종류입니다.
public enum FlowKind: String, Codable, CaseIterable, Sendable {
    case tcpIPv4
    case tcpIPv6
    case udpIPv4
    case udpIPv6
    case quic
    case dnsA
    case dnsAAAA
}

/// 원본 앱 정보를 결과에 남기지 않고 역할만 기록합니다.
public enum AppRole: String, Codable, CaseIterable, Sendable {
    case selectedApp
    case controlApp
    case helper
    case controlPlane
}

/// 정책 적용 시각을 기준으로 기존 연결과 새 연결을 구분합니다.
public enum FlowAge: String, Codable, CaseIterable, Sendable {
    case newFlow
    case preExistingFlow
}

/// 선택 앱 식별자는 Provider 메모리에서만 보유하며 결과에는 포함하지 않습니다.
public struct SpikeRunRequest: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let runId: UUID
    public let candidateKind: CandidateKind
    public let evidenceTier: EvidenceTier
    public let selectedSigningIdentifier: String
    public let selectedTeamIdentifier: String
    public let policyAppliedAt: Date

    public init(
        schemaVersion: Int = 2,
        runId: UUID,
        candidateKind: CandidateKind,
        evidenceTier: EvidenceTier,
        selectedSigningIdentifier: String,
        selectedTeamIdentifier: String,
        policyAppliedAt: Date
    ) {
        self.schemaVersion = schemaVersion
        self.runId = runId
        self.candidateKind = candidateKind
        self.evidenceTier = evidenceTier
        self.selectedSigningIdentifier = selectedSigningIdentifier
        self.selectedTeamIdentifier = selectedTeamIdentifier
        self.policyAppliedAt = policyAppliedAt
    }
}

/// 공유 가능한 최소 관찰 결과입니다. 앱·주소·도메인 원문은 저장하지 않습니다.
public struct RedactedFlowResult: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let runId: UUID
    public let candidateKind: CandidateKind
    public let evidenceTier: EvidenceTier
    public let flowKind: FlowKind
    public let appRole: AppRole
    public let flowAge: FlowAge
    public let handlingOutcome: HandlingOutcome
    public let spikeResult: SpikeResult
    public let failureCode: String?
    public let observedAt: Date
    public let durationMs: Int

    public init(
        schemaVersion: Int = 2,
        runId: UUID,
        candidateKind: CandidateKind,
        evidenceTier: EvidenceTier,
        flowKind: FlowKind,
        appRole: AppRole,
        flowAge: FlowAge,
        handlingOutcome: HandlingOutcome = .ownedAndClosed,
        spikeResult: SpikeResult,
        failureCode: String?,
        observedAt: Date,
        durationMs: Int
    ) {
        self.schemaVersion = schemaVersion
        self.runId = runId
        self.candidateKind = candidateKind
        self.evidenceTier = evidenceTier
        self.flowKind = flowKind
        self.appRole = appRole
        self.flowAge = flowAge
        self.handlingOutcome = handlingOutcome
        self.spikeResult = spikeResult
        self.failureCode = failureCode
        self.observedAt = observedAt
        self.durationMs = durationMs
    }
}
