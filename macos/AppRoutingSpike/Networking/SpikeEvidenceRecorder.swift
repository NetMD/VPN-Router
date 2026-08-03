import Foundation

public enum EvidenceSnapshotError: Error, Equatable {
    case invalidPageLimit
    case invalidCursor
}

/// 원문 흐름 정보 없이 가려진 결과만 보유하는 고정 크기 메모리 버퍼입니다.
public final class SpikeEvidenceRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var itemsByRun: [UUID: [SpikeSnapshotItem]] = [:]
    private var totalCount = 0

    public init() {}

    @discardableResult
    public func append(_ result: RedactedFlowResult) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard totalCount < SpikeLimits.resultBufferCapacity else { return false }
        var items = itemsByRun[result.runId, default: []]
        let cursor = UInt64(items.count) + 1
        items.append(SpikeSnapshotItem(cursor: cursor, result: result))
        itemsByRun[result.runId] = items
        totalCount += 1
        return true
    }

    public func snapshot(_ request: SpikeSnapshotRequest) throws -> SpikeSnapshotPage {
        lock.lock()
        defer { lock.unlock() }
        guard (1...SpikeLimits.snapshotBatchSize).contains(request.limit) else {
            throw EvidenceSnapshotError.invalidPageLimit
        }

        let allItems = itemsByRun[request.runId, default: []]
        if let cursor = request.cursor,
           cursor == 0 || cursor > UInt64(allItems.count) {
            throw EvidenceSnapshotError.invalidCursor
        }

        let start = Int(request.cursor ?? 0)
        let end = min(start + request.limit, allItems.count)
        let items = Array(allItems[start..<end])
        let nextCursor = items.last?.cursor ?? request.cursor
        return SpikeSnapshotPage(
            runId: request.runId,
            items: items,
            nextCursor: nextCursor,
            hasMore: end < allItems.count
        )
    }

    public func removeAll(runId: UUID) {
        lock.lock()
        defer { lock.unlock() }
        totalCount -= itemsByRun.removeValue(forKey: runId)?.count ?? 0
    }
}
