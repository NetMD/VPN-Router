import Foundation

public enum EvidenceRecordOutcome: Equatable, Sendable {
    case recorded
    case runFailed
}

/// 버퍼 포화를 실행 실패로 승격해 이후 흐름이 우회되지 않도록 합니다.
public struct SpikeEvidenceCoordinator: Sendable {
    private let recorder: SpikeEvidenceRecorder
    private let runState: SpikeRunState

    public init(recorder: SpikeEvidenceRecorder, runState: SpikeRunState) {
        self.recorder = recorder
        self.runState = runState
    }

    public func record(_ result: RedactedFlowResult) -> EvidenceRecordOutcome {
        guard recorder.append(result) else {
            runState.markFailed(
                runId: result.runId,
                failureCode: SpikeFailureCode.evidenceBufferFull.rawValue
            )
            return .runFailed
        }
        return .recorded
    }
}
