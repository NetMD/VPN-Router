import CryptoKit
import Foundation

public enum SpikeRunStateError: Error, Equatable {
    case runIDConflict
    case runMismatch
}

/// 실행 요청의 멱등성과 선택 식별자의 메모리 수명을 한 곳에서 관리합니다.
public final class SpikeRunState: @unchecked Sendable {
    private struct BeginRecord {
        let requestFingerprint: Data
        let response: SpikeCommandResponse
    }

    private let lock = NSLock()
    private var activeRequest: SpikeRunRequest?
    private var beginRecords: [UUID: BeginRecord] = [:]
    private var beginRecordOrder: [UUID] = []
    private var stopResponses: [UUID: SpikeCommandResponse] = [:]
    private var terminalFailures: [UUID: String] = [:]
    private var failedRunID: UUID?

    public init() {}

    public func begin(_ request: SpikeRunRequest, acceptedAt: Date) throws -> SpikeCommandResponse {
        let fingerprint = requestFingerprint(request)
        lock.lock()
        defer { lock.unlock() }
        if let existing = beginRecords[request.runId] {
            guard existing.requestFingerprint == fingerprint else {
                throw SpikeRunStateError.runIDConflict
            }
            return existing.response
        }
        guard activeRequest == nil, failedRunID == nil else {
            throw SpikeRunStateError.runIDConflict
        }
        let response = SpikeCommandResponse(
            runId: request.runId,
            command: .beginRun,
            acceptedAt: acceptedAt
        )
        insertBeginRecord(BeginRecord(requestFingerprint: fingerprint, response: response), runId: request.runId)
        activeRequest = request
        return response
    }

    public func stop(runId: UUID, acceptedAt: Date) throws -> SpikeCommandResponse {
        lock.lock()
        defer { lock.unlock() }
        if let response = stopResponses[runId] { return response }
        guard activeRequest?.runId == runId || failedRunID == runId else {
            throw SpikeRunStateError.runMismatch
        }
        let response = SpikeCommandResponse(runId: runId, command: .stopRun, acceptedAt: acceptedAt)
        stopResponses[runId] = response
        activeRequest = nil
        if failedRunID == runId { failedRunID = nil }
        trimStopResponses()
        return response
    }

    public func currentRequest() -> SpikeRunRequest? {
        lock.lock()
        defer { lock.unlock() }
        return activeRequest
    }

    public func recognizes(runId: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return beginRecords[runId] != nil
    }

    public func markFailed(runId: UUID, failureCode: String) {
        lock.lock()
        defer { lock.unlock() }
        guard activeRequest?.runId == runId else { return }
        activeRequest = nil
        terminalFailures[runId] = failureCode
        failedRunID = runId
    }

    public func failureCode(runId: UUID) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return terminalFailures[runId]
    }

    public func shouldRejectNewFlows() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return failedRunID != nil
    }

    public func retainedRecordCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return beginRecords.count
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        activeRequest = nil
        beginRecords.removeAll(keepingCapacity: false)
        beginRecordOrder.removeAll(keepingCapacity: false)
        stopResponses.removeAll(keepingCapacity: false)
        terminalFailures.removeAll(keepingCapacity: false)
        failedRunID = nil
    }

    private func requestFingerprint(_ request: SpikeRunRequest) -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let encoded = (try? encoder.encode(request)) ?? Data()
        return Data(SHA256.hash(data: encoded))
    }

    private func insertBeginRecord(_ record: BeginRecord, runId: UUID) {
        beginRecords[runId] = record
        beginRecordOrder.append(runId)
        while beginRecordOrder.count > SpikeLimits.maximumRunRecords {
            let evicted = beginRecordOrder.removeFirst()
            beginRecords.removeValue(forKey: evicted)
            stopResponses.removeValue(forKey: evicted)
            terminalFailures.removeValue(forKey: evicted)
            if failedRunID == evicted { failedRunID = nil }
        }
    }

    private func trimStopResponses() {
        let retained = Set(beginRecordOrder)
        stopResponses = stopResponses.filter { retained.contains($0.key) }
    }
}
