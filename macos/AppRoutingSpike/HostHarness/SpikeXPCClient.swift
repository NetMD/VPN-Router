import Foundation

public protocol SpikeXPCClientProtocol: Sendable {
    func beginRun(_ request: SpikeRunRequest) async throws
    func snapshot(runId: UUID) async throws -> [RedactedFlowResult]
    func stopRun(runId: UUID) async throws
    func invalidate()
}

public enum SpikeXPCClientError: Error, Equatable, LocalizedError {
    case connectionUnavailable
    case replyTimedOut
    case invalidResponse
    case rejected(code: String, message: String)

    public var errorDescription: String? {
        switch self {
        case .connectionUnavailable:
            return "시험 확장과 연결하지 못했습니다."
        case .replyTimedOut:
            return "시험 확장의 응답 시간이 초과됐습니다."
        case .invalidResponse:
            return "시험 확장의 가려진 응답을 확인하지 못했습니다."
        case let .rejected(_, message):
            return message
        }
    }
}

public enum SpikeXPCOperation: Sendable {
    case beginRun
    case snapshot
    case stopRun
}

public protocol SpikeXPCTransport: Sendable {
    func send(_ operation: SpikeXPCOperation, data: Data) async throws -> Data
    func invalidate()
}

public final class NSXPCSpikeTransport: SpikeXPCTransport, @unchecked Sendable {
    private final class ReplyGate: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Data, Error>?

        init(continuation: CheckedContinuation<Data, Error>) {
            self.continuation = continuation
        }

        @discardableResult
        func resume(with result: Result<Data, Error>) -> Bool {
            lock.lock()
            let current = continuation
            continuation = nil
            lock.unlock()
            current?.resume(with: result)
            return current != nil
        }
    }

    private let slot: XPCConnectionSlot<NSXPCConnection>

    public init(machServiceName: String) {
        slot = XPCConnectionSlot(
            make: { _, onLost in
                let connection = NSXPCConnection(machServiceName: machServiceName, options: [])
                connection.remoteObjectInterface = NSXPCInterface(with: SpikeXPCProtocol.self)
                connection.invalidationHandler = onLost
                connection.interruptionHandler = onLost
                connection.resume()
                return connection
            },
            tearDown: { $0.invalidate() }
        )
    }

    public func send(_ operation: SpikeXPCOperation, data: Data) async throws -> Data {
        try await invoke { remote, callback in
            switch operation {
            case .beginRun:
                remote.beginRun(data, withReply: callback)
            case .snapshot:
                remote.snapshot(data, withReply: callback)
            case .stopRun:
                remote.stopRun(data, withReply: callback)
            }
        }
    }

    public func invalidate() {
        slot.reset()
    }

    private func invoke(
        _ operation: @escaping (SpikeXPCProtocol, @escaping (Data) -> Void) -> Void
    ) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let gate = ReplyGate(continuation: continuation)
            let lease = slot.acquire()
            let proxy = lease.connection.remoteObjectProxyWithErrorHandler { [slot] _ in
                slot.discard(lease.token)
                gate.resume(with: .failure(SpikeXPCClientError.connectionUnavailable))
            }
            guard let remote = proxy as? SpikeXPCProtocol else {
                slot.discard(lease.token)
                gate.resume(with: .failure(SpikeXPCClientError.connectionUnavailable))
                return
            }
            operation(remote) { data in
                gate.resume(with: .success(data))
            }
        }
    }
}

/// Provider는 시험을 시작한 뒤에야 Mach 서비스를 등록합니다. 연결을 앱 실행 시점에 미리 만들면
/// 이름 조회가 실패해 그 연결이 영구히 무효가 되고, Provider가 뒤늦게 떠도 되살아나지 않습니다.
/// 그래서 연결은 첫 요청 때 만들고, 끊기거나 무효가 되면 다음 요청에서 새로 만듭니다.
final class XPCConnectionSlot<Connection: AnyObject>: @unchecked Sendable {
    struct Lease {
        let connection: Connection
        let token: UInt64
    }

    private let make: (UInt64, @escaping @Sendable () -> Void) -> Connection
    private let tearDown: (Connection) -> Void
    private let lock = NSRecursiveLock()
    private var current: Connection?
    private var currentToken: UInt64 = 0

    init(
        make: @escaping (UInt64, @escaping @Sendable () -> Void) -> Connection,
        tearDown: @escaping (Connection) -> Void
    ) {
        self.make = make
        self.tearDown = tearDown
    }

    func acquire() -> Lease {
        lock.lock()
        defer { lock.unlock() }
        if let current {
            return Lease(connection: current, token: currentToken)
        }
        currentToken &+= 1
        let issued = currentToken
        let created = make(issued) { [weak self] in
            self?.discard(issued)
        }
        // make 도중에 이미 끊겼다면 보관하지 않습니다. 이 요청은 실패하고
        // 다음 요청이 새 연결을 만듭니다.
        guard currentToken == issued else {
            tearDown(created)
            return Lease(connection: created, token: issued)
        }
        current = created
        return Lease(connection: created, token: issued)
    }

    /// 이 token으로 빌려준 연결만 버립니다. 이미 새 연결로 바뀐 뒤라면 아무것도 하지 않습니다.
    func discard(_ token: UInt64) {
        lock.lock()
        guard currentToken == token else {
            lock.unlock()
            return
        }
        let lost = current
        current = nil
        currentToken &+= 1
        lock.unlock()
        if let lost {
            tearDown(lost)
        }
    }

    func reset() {
        lock.lock()
        let lost = current
        current = nil
        currentToken &+= 1
        lock.unlock()
        if let lost {
            tearDown(lost)
        }
    }
}

public final class SpikeXPCClient: SpikeXPCClientProtocol, @unchecked Sendable {
    private final class TimedReplyGate: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Data, Error>?

        init(continuation: CheckedContinuation<Data, Error>) {
            self.continuation = continuation
        }

        @discardableResult
        func resume(with result: Result<Data, Error>) -> Bool {
            lock.lock()
            let current = continuation
            continuation = nil
            lock.unlock()
            current?.resume(with: result)
            return current != nil
        }
    }


    private struct RunIdentifierRequest: Codable {
        let schemaVersion: Int
        let runId: UUID

        init(runId: UUID) {
            schemaVersion = SpikeLimits.schemaVersion
            self.runId = runId
        }
    }

    private let transport: SpikeXPCTransport
    private let replyTimeoutSeconds: TimeInterval
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        transport: SpikeXPCTransport,
        replyTimeoutSeconds: TimeInterval = SpikeLimits.xpcReplyTimeoutSeconds
    ) {
        self.transport = transport
        self.replyTimeoutSeconds = replyTimeoutSeconds
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    public convenience init(machServiceName: String) {
        self.init(transport: NSXPCSpikeTransport(machServiceName: machServiceName))
    }

    public func beginRun(_ request: SpikeRunRequest) async throws {
        let data = try encoder.encode(request)
        try validatePayloadSize(data)
        let reply = try await sendWithTimeout(.beginRun, data: data)
        try validateCommandReply(reply, runId: request.runId, command: .beginRun)
    }

    public func snapshot(runId: UUID) async throws -> [RedactedFlowResult] {
        var cursor: UInt64?
        var results: [RedactedFlowResult] = []

        repeat {
            let request = SpikeSnapshotRequest(
                schemaVersion: SpikeLimits.schemaVersion,
                runId: runId,
                cursor: cursor,
                limit: SpikeLimits.snapshotBatchSize
            )
            let data = try encoder.encode(request)
            try validatePayloadSize(data)
            let reply = try await sendWithTimeout(.snapshot, data: data)
            let page = try decodeSnapshotPage(
                reply,
                runId: runId,
                requestCursor: cursor,
                limit: request.limit
            )
            results.append(contentsOf: page.items.map(\.result))
            guard results.count <= SpikeLimits.resultBufferCapacity else {
                throw SpikeXPCClientError.invalidResponse
            }
            cursor = page.nextCursor
            if !page.hasMore {
                return results
            }
        } while true
    }

    public func stopRun(runId: UUID) async throws {
        let data = try encoder.encode(RunIdentifierRequest(runId: runId))
        try validatePayloadSize(data)
        let reply = try await sendWithTimeout(.stopRun, data: data)
        try validateCommandReply(reply, runId: runId, command: .stopRun)
    }

    public func invalidate() {
        transport.invalidate()
    }

    private func sendWithTimeout(
        _ operation: SpikeXPCOperation,
        data: Data
    ) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let gate = TimedReplyGate(continuation: continuation)
            Task {
                do {
                    let reply = try await transport.send(operation, data: data)
                    gate.resume(with: .success(reply))
                } catch {
                    gate.resume(with: .failure(error))
                }
            }
            Task {
                try? await Task.sleep(for: .seconds(replyTimeoutSeconds))
                if gate.resume(with: .failure(SpikeXPCClientError.replyTimedOut)) {
                    transport.invalidate()
                }
            }
        }
    }

    private func validateCommandReply(
        _ data: Data,
        runId: UUID,
        command: SpikeCommandKind
    ) throws {
        try validatePayloadSize(data)
        if let error = try? decoder.decode(SpikeErrorResponse.self, from: data) {
            throw SpikeXPCClientError.rejected(
                code: error.error.code,
                message: allowedMessage(for: error.error.code)
            )
        }
        guard let response = try? decoder.decode(SpikeCommandResponse.self, from: data),
              response.schemaVersion == SpikeLimits.schemaVersion,
              response.runId == runId,
              response.command == command,
              response.accepted else {
            throw SpikeXPCClientError.invalidResponse
        }
    }

    private func decodeSnapshotPage(
        _ data: Data,
        runId: UUID,
        requestCursor: UInt64?,
        limit: Int
    ) throws -> SpikeSnapshotPage {
        try validatePayloadSize(data)
        if let error = try? decoder.decode(SpikeErrorResponse.self, from: data) {
            throw SpikeXPCClientError.rejected(
                code: error.error.code,
                message: allowedMessage(for: error.error.code)
            )
        }
        guard let page = try? decoder.decode(SpikeSnapshotPage.self, from: data),
              page.schemaVersion == SpikeLimits.schemaVersion,
              page.runId == runId,
              page.items.count <= limit,
              page.items.allSatisfy({ item in
                  item.result.schemaVersion == SpikeLimits.schemaVersion
                      && item.result.runId == runId
              }) else {
            throw SpikeXPCClientError.invalidResponse
        }

        var previousCursor = requestCursor ?? 0
        for item in page.items {
            guard item.cursor > previousCursor else {
                throw SpikeXPCClientError.invalidResponse
            }
            previousCursor = item.cursor
        }

        if let last = page.items.last {
            guard page.nextCursor == last.cursor else {
                throw SpikeXPCClientError.invalidResponse
            }
        } else {
            guard page.nextCursor == requestCursor, !page.hasMore else {
                throw SpikeXPCClientError.invalidResponse
            }
        }
        return page
    }

    private func validatePayloadSize(_ data: Data) throws {
        guard data.count <= SpikeLimits.maximumXPCPayloadBytes else {
            throw SpikeXPCClientError.rejected(
                code: "xpc-payload-too-large",
                message: "시험 요청 크기가 허용 범위를 넘었습니다."
            )
        }
    }

    private func allowedMessage(for code: String) -> String {
        switch code {
        case "identity-verification-failed":
            return "앱 신원을 확인하지 못했습니다."
        case "selected-flow-transport-failed", "wireguard-transport-unavailable":
            return "선택 앱의 보호 경로를 만들지 못했습니다."
        case "control-flow-damaged":
            return "일반 인터넷 보존 검사에 실패했습니다."
        case "xpc-payload-too-large":
            return "시험 요청 크기가 허용 범위를 넘었습니다."
        default:
            return "시험 확장이 요청을 처리하지 못했습니다."
        }
    }
}
