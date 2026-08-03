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
