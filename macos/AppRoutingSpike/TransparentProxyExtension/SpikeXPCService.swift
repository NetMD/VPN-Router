import Foundation
import Security

final class SpikeXPCService: NSObject, SpikeXPCProtocol, NSXPCListenerDelegate {
    private struct RunIdentifierRequest: Codable {
        let schemaVersion: Int
        let runId: UUID
    }

    private let runState: SpikeRunState
    private let recorder: SpikeEvidenceRecorder
    private let listener: NSXPCListener
    private let expectedHostIdentifier: String
    private let expectedHostTeamIdentifier: String
    private let validator = SpikeRequestValidator()

    init(
        machServiceName: String,
        expectedHostIdentifier: String,
        expectedHostTeamIdentifier: String,
        runState: SpikeRunState,
        recorder: SpikeEvidenceRecorder
    ) {
        self.runState = runState
        self.recorder = recorder
        self.expectedHostIdentifier = expectedHostIdentifier
        self.expectedHostTeamIdentifier = expectedHostTeamIdentifier
        listener = NSXPCListener(machServiceName: machServiceName)
        super.init()
        listener.delegate = self
    }

    func start() {
        listener.resume()
    }

    func stop() {
        listener.invalidate()
    }

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection connection: NSXPCConnection
    ) -> Bool {
        let authorizer = ProcessCodeSigningAuthorizer()
        guard connection.effectiveUserIdentifier == geteuid(),
              let requirement = authorizer.requirement(
                  expectedSigningIdentifier: expectedHostIdentifier,
                  expectedTeamIdentifier: expectedHostTeamIdentifier
              ),
              authorizer.isAuthorized(
            processIdentifier: connection.processIdentifier,
            expectedSigningIdentifier: expectedHostIdentifier,
            expectedTeamIdentifier: expectedHostTeamIdentifier
        ) else {
            return false
        }
        connection.setCodeSigningRequirement(requirement)
        connection.exportedInterface = NSXPCInterface(with: SpikeXPCProtocol.self)
        connection.exportedObject = self
        connection.activate()
        return true
    }

    func beginRun(_ request: Data, withReply reply: @escaping (Data) -> Void) {
        guard request.count <= SpikeLimits.maximumXPCPayloadBytes,
              let decoded = try? decoder().decode(SpikeRunRequest.self, from: request) else {
            reply(errorData(code: request.count > SpikeLimits.maximumXPCPayloadBytes
                ? .xpcPayloadTooLarge : .invalidRequest))
            return
        }
        do {
            try validator.validate(payload: request, decoded: decoded)
            reply(encode(try runState.begin(decoded, acceptedAt: Date())))
        } catch SpikeRunStateError.runIDConflict {
            reply(errorData(code: .runIDConflict))
        } catch {
            reply(errorData(code: .invalidRequest))
        }
    }

    func snapshot(_ request: Data, withReply reply: @escaping (Data) -> Void) {
        guard request.count <= SpikeLimits.maximumXPCPayloadBytes,
              let decoded = try? decoder().decode(SpikeSnapshotRequest.self, from: request),
              decoded.schemaVersion == SpikeLimits.schemaVersion else {
            reply(errorData(code: request.count > SpikeLimits.maximumXPCPayloadBytes
                ? .xpcPayloadTooLarge : .invalidRequest))
            return
        }
        guard runState.recognizes(runId: decoded.runId) else {
            reply(errorData(code: .runMismatch))
            return
        }
        if let failureCode = runState.failureCode(runId: decoded.runId) {
            reply(errorData(code: failureCode, message: "시험 실행이 안전 제한에 따라 중단되었습니다."))
            return
        }
        do {
            reply(encode(try recorder.snapshot(decoded)))
        } catch EvidenceSnapshotError.invalidPageLimit {
            reply(errorData(code: .invalidPageLimit))
        } catch EvidenceSnapshotError.invalidCursor {
            reply(errorData(code: .invalidSnapshotCursor))
        } catch {
            reply(errorData(code: .invalidRequest))
        }
    }

    func stopRun(_ request: Data, withReply reply: @escaping (Data) -> Void) {
        guard request.count <= SpikeLimits.maximumXPCPayloadBytes,
              let decoded = try? decoder().decode(RunIdentifierRequest.self, from: request),
              decoded.schemaVersion == SpikeLimits.schemaVersion else {
            reply(errorData(code: request.count > SpikeLimits.maximumXPCPayloadBytes
                ? .xpcPayloadTooLarge : .invalidRequest))
            return
        }
        do {
            reply(encode(try runState.stop(runId: decoded.runId, acceptedAt: Date())))
        } catch {
            reply(errorData(code: .runMismatch))
        }
    }

    private func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func encode<T: Encodable>(_ value: T) -> Data {
        (try? encoder().encode(value)) ?? errorData(code: .invalidRequest)
    }

    private func errorData(code: XPCFailureCode) -> Data {
        let response = SpikeErrorResponse(code: code.rawValue, message: code.message)
        return (try? encoder().encode(response)) ?? Data()
    }

    private func errorData(code: String, message: String) -> Data {
        let response = SpikeErrorResponse(code: code, message: message)
        return (try? encoder().encode(response)) ?? Data()
    }
}

private enum XPCFailureCode: String {
    case xpcPayloadTooLarge = "xpc-payload-too-large"
    case invalidRequest = "invalid-request"
    case invalidPageLimit = "invalid-page-limit"
    case invalidSnapshotCursor = "invalid-snapshot-cursor"
    case runIDConflict = "run-id-conflict"
    case runMismatch = "run-mismatch"

    var message: String {
        switch self {
        case .xpcPayloadTooLarge: return "시험 요청 크기가 허용 범위를 넘었습니다."
        case .invalidPageLimit, .invalidSnapshotCursor: return "결과 조회 범위를 확인해 주세요."
        case .runIDConflict, .runMismatch: return "시험 실행 상태가 요청과 일치하지 않습니다."
        case .invalidRequest: return "시험 확장이 요청을 처리하지 못했습니다."
        }
    }
}

private struct ProcessCodeSigningAuthorizer {
    func requirement(expectedSigningIdentifier: String, expectedTeamIdentifier: String) -> String? {
        let identifierCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        let teamCharacters = CharacterSet.alphanumerics
        guard !expectedSigningIdentifier.isEmpty,
              !expectedTeamIdentifier.isEmpty,
              expectedSigningIdentifier.unicodeScalars.allSatisfy(identifierCharacters.contains),
              expectedTeamIdentifier.unicodeScalars.allSatisfy(teamCharacters.contains) else {
            return nil
        }
        return "anchor apple generic and identifier \"\(expectedSigningIdentifier)\" "
            + "and certificate leaf[subject.OU] = \"\(expectedTeamIdentifier)\""
    }

    func isAuthorized(
        processIdentifier: pid_t,
        expectedSigningIdentifier: String,
        expectedTeamIdentifier: String
    ) -> Bool {
        guard let requirementText = requirement(
            expectedSigningIdentifier: expectedSigningIdentifier,
            expectedTeamIdentifier: expectedTeamIdentifier
        ) else { return false }
        let attributes = [kSecGuestAttributePid as String: NSNumber(value: processIdentifier)] as CFDictionary
        var code: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess,
              let code else {
            return false
        }
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(requirementText as CFString, [], &requirement) == errSecSuccess,
              let requirement else {
            return false
        }
        return SecCodeCheckValidity(code, [], requirement) == errSecSuccess
    }
}
