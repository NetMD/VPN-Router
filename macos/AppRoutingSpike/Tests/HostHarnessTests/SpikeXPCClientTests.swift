import Foundation
import XCTest
@testable import AppRoutingSpikeHost

final class SpikeXPCClientTests: XCTestCase {
    private final class FakeTransport: SpikeXPCTransport, @unchecked Sendable {
        private let lock = NSLock()
        private var replies: [Data]
        private(set) var requests: [(SpikeXPCOperation, Data)] = []

        init(replies: [Data]) {
            self.replies = replies
        }

        func send(_ operation: SpikeXPCOperation, data: Data) async throws -> Data {
            takeReply(operation: operation, data: data)
        }

        func invalidate() {}

        private func takeReply(operation: SpikeXPCOperation, data: Data) -> Data {
            lock.lock()
            defer { lock.unlock() }
            requests.append((operation, data))
            return replies.removeFirst()
        }
    }

    private struct SlowTransport: SpikeXPCTransport {
        func send(_ operation: SpikeXPCOperation, data: Data) async throws -> Data {
            try await Task.sleep(for: .seconds(1))
            return Data()
        }

        func invalidate() {}
    }

    func testReplyTimeoutReturnsWithoutWaitingForTheRemoteReply() async throws {
        let runId = UUID()
        let client = SpikeXPCClient(
            transport: SlowTransport(),
            replyTimeoutSeconds: 0.01
        )
        let request = SpikeRunRequest(
            runId: runId,
            candidateKind: .transparentProxy,
            evidenceTier: .signedMac,
            selectedSigningIdentifier: "local-only-test-app",
            selectedTeamIdentifier: "TEAMID1234",
            policyAppliedAt: Date()
        )

        do {
            try await client.beginRun(request)
            XCTFail("응답이 없는 XPC 요청은 성공할 수 없습니다.")
        } catch {
            XCTAssertEqual(error as? SpikeXPCClientError, .replyTimedOut)
        }
    }

    func testBeginRunRequiresTheExactCommandResponse() async throws {
        let runId = UUID()
        let transport = FakeTransport(replies: [try encode(SpikeCommandResponse(
            runId: runId,
            command: .beginRun,
            acceptedAt: Date(timeIntervalSince1970: 0)
        ))])
        let client = SpikeXPCClient(transport: transport)
        let request = SpikeRunRequest(
            runId: runId,
            candidateKind: .transparentProxy,
            evidenceTier: .signedMac,
            selectedSigningIdentifier: "local-only-test-app",
            selectedTeamIdentifier: "TEAMID1234",
            policyAppliedAt: Date(timeIntervalSince1970: 0)
        )

        try await client.beginRun(request)

        let sent = try XCTUnwrap(transport.requests.first)
        let decoded = try decoder().decode(SpikeRunRequest.self, from: sent.1)
        XCTAssertEqual(decoded, request)
    }

    func testBeginRunRejectsAcceptedFalse() async throws {
        let runId = UUID()
        let transport = FakeTransport(replies: [try encode(SpikeCommandResponse(
            runId: runId,
            command: .beginRun,
            accepted: false,
            acceptedAt: Date()
        ))])
        let client = SpikeXPCClient(transport: transport)
        let request = SpikeRunRequest(
            runId: runId,
            candidateKind: .transparentProxy,
            evidenceTier: .signedMac,
            selectedSigningIdentifier: "local-only-test-app",
            selectedTeamIdentifier: "TEAMID1234",
            policyAppliedAt: Date()
        )

        do {
            try await client.beginRun(request)
            XCTFail("accepted=false 응답은 성공할 수 없습니다.")
        } catch {
            XCTAssertEqual(error as? SpikeXPCClientError, .invalidResponse)
        }
    }

    func testSnapshotCollectsEveryCursorPageInOrder() async throws {
        let runId = UUID()
        let firstResult = makeResult(runId: runId, flowKind: .tcpIPv4)
        let secondResult = makeResult(runId: runId, flowKind: .udpIPv6)
        let transport = FakeTransport(replies: [
            try encode(SpikeSnapshotPage(
                runId: runId,
                items: [SpikeSnapshotItem(cursor: 1, result: firstResult)],
                nextCursor: 1,
                hasMore: true
            )),
            try encode(SpikeSnapshotPage(
                runId: runId,
                items: [SpikeSnapshotItem(cursor: 2, result: secondResult)],
                nextCursor: 2,
                hasMore: false
            )),
        ])
        let client = SpikeXPCClient(transport: transport)

        let results = try await client.snapshot(runId: runId)

        XCTAssertEqual(results, [firstResult, secondResult])
        XCTAssertEqual(transport.requests.count, 2)
        let firstRequest = try decoder().decode(SpikeSnapshotRequest.self, from: transport.requests[0].1)
        let secondRequest = try decoder().decode(SpikeSnapshotRequest.self, from: transport.requests[1].1)
        XCTAssertNil(firstRequest.cursor)
        XCTAssertEqual(secondRequest.cursor, 1)
        XCTAssertEqual(firstRequest.limit, SpikeLimits.snapshotBatchSize)
    }

    func testSnapshotRejectsARepeatedCursor() async throws {
        let runId = UUID()
        let transport = FakeTransport(replies: [try encode(SpikeSnapshotPage(
            runId: runId,
            items: [SpikeSnapshotItem(
                cursor: 1,
                result: makeResult(runId: runId, flowKind: .tcpIPv4)
            )],
            nextCursor: 2,
            hasMore: false
        ))])
        let client = SpikeXPCClient(transport: transport)

        do {
            _ = try await client.snapshot(runId: runId)
            XCTFail("마지막 항목과 다른 nextCursor는 성공할 수 없습니다.")
        } catch {
            XCTAssertEqual(error as? SpikeXPCClientError, .invalidResponse)
        }
    }

    func testServerErrorMessageIsReplacedWithAnAllowedMessage() async throws {
        let runId = UUID()
        let transport = FakeTransport(replies: [try encode(SpikeErrorResponse(
            code: "identity-verification-failed",
            message: "공유하면 안 되는 원본 오류"
        ))])
        let client = SpikeXPCClient(transport: transport)
        let request = SpikeRunRequest(
            runId: runId,
            candidateKind: .transparentProxy,
            evidenceTier: .signedMac,
            selectedSigningIdentifier: "local-only-test-app",
            selectedTeamIdentifier: "TEAMID1234",
            policyAppliedAt: Date()
        )

        do {
            try await client.beginRun(request)
            XCTFail("오류 응답은 성공할 수 없습니다.")
        } catch {
            XCTAssertEqual(
                error as? SpikeXPCClientError,
                .rejected(
                    code: "identity-verification-failed",
                    message: "앱 신원을 확인하지 못했습니다."
                )
            )
        }
    }

    private func makeResult(runId: UUID, flowKind: FlowKind) -> RedactedFlowResult {
        RedactedFlowResult(
            runId: runId,
            candidateKind: .transparentProxy,
            evidenceTier: .signedMac,
            flowKind: flowKind,
            appRole: .selectedApp,
            flowAge: .newFlow,
            spikeResult: .inconclusive,
            failureCode: nil,
            observedAt: Date(timeIntervalSince1970: 0),
            durationMs: 1
        )
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }

    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// Provider가 Mach 서비스를 늦게 등록해도 호스트가 붙을 수 있어야 합니다.
/// 실기에서 앱 실행 때 만든 연결이 이름 조회 실패로 영구 무효가 되어
/// 시험 시작이 계속 실패했던 결함의 회귀 시험입니다.
final class XPCConnectionSlotTests: XCTestCase {
    private final class FakeConnection {
        let serial: Int
        var isTornDown = false

        init(serial: Int) {
            self.serial = serial
        }
    }

    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var madeCount = 0
        private(set) var lostHandlers: [@Sendable () -> Void] = []
        private(set) var tornDown: [Int] = []

        func nextSerial() -> Int {
            lock.lock()
            defer { lock.unlock() }
            madeCount += 1
            return madeCount
        }

        var count: Int {
            lock.lock()
            defer { lock.unlock() }
            return madeCount
        }

        func remember(_ handler: @escaping @Sendable () -> Void) {
            lock.lock()
            lostHandlers.append(handler)
            lock.unlock()
        }

        func rememberTearDown(_ serial: Int) {
            lock.lock()
            tornDown.append(serial)
            lock.unlock()
        }
    }

    private func makeSlot() -> (XPCConnectionSlot<FakeConnection>, Recorder) {
        let recorder = Recorder()
        let slot = XPCConnectionSlot<FakeConnection>(
            make: { _, onLost in
                recorder.remember(onLost)
                return FakeConnection(serial: recorder.nextSerial())
            },
            tearDown: { connection in
                connection.isTornDown = true
                recorder.rememberTearDown(connection.serial)
            }
        )
        return (slot, recorder)
    }

    func testDoesNotCreateAConnectionBeforeTheFirstRequest() {
        let (slot, recorder) = makeSlot()
        _ = slot
        XCTAssertEqual(recorder.count, 0, "요청 전에 연결을 미리 만들면 안 됩니다.")
    }

    func testReusesTheSameConnectionAcrossRequests() {
        let (slot, recorder) = makeSlot()

        let first = slot.acquire()
        let second = slot.acquire()

        XCTAssertEqual(recorder.count, 1)
        XCTAssertTrue(first.connection === second.connection)
        XCTAssertEqual(first.token, second.token)
    }

    func testCreatesANewConnectionAfterTheCurrentOneIsLost() {
        let (slot, recorder) = makeSlot()

        let first = slot.acquire()
        slot.discard(first.token)
        let second = slot.acquire()

        XCTAssertEqual(recorder.count, 2)
        XCTAssertFalse(first.connection === second.connection)
        XCTAssertNotEqual(first.token, second.token)
        XCTAssertEqual(recorder.tornDown, [first.connection.serial])
    }

    func testInvalidationHandlerFromTheConnectionTriggersReconnect() {
        let (slot, recorder) = makeSlot()

        let first = slot.acquire()
        recorder.lostHandlers.last?()
        let second = slot.acquire()

        XCTAssertEqual(recorder.count, 2)
        XCTAssertFalse(first.connection === second.connection)
    }

    func testStaleTokenDoesNotDiscardTheCurrentConnection() {
        let (slot, recorder) = makeSlot()

        let first = slot.acquire()
        slot.discard(first.token)
        let second = slot.acquire()
        slot.discard(first.token)
        let third = slot.acquire()

        XCTAssertEqual(recorder.count, 2, "지난 연결의 token으로 현재 연결을 버리면 안 됩니다.")
        XCTAssertTrue(second.connection === third.connection)
    }

    func testResetAllowsAFreshConnectionForTheNextRequest() {
        let (slot, recorder) = makeSlot()

        let first = slot.acquire()
        slot.reset()
        let second = slot.acquire()

        XCTAssertEqual(recorder.count, 2)
        XCTAssertTrue(first.connection.isTornDown)
        XCTAssertFalse(second.connection.isTornDown)
    }
}
