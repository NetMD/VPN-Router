import Foundation

/// 동시에 처리 중인 선택 앱 흐름 수를 고정 상한 아래로 제한합니다.
public final class SelectedFlowCapacityGate: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    public init() {}

    public func acquire() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard count < SpikeLimits.maximumSelectedFlows else { return false }
        count += 1
        return true
    }

    public func release() {
        lock.lock()
        defer { lock.unlock() }
        count = max(0, count - 1)
    }

    public func currentCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}
