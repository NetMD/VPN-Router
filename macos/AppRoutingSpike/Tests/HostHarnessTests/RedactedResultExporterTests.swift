import Foundation
import XCTest
@testable import AppRoutingSpikeHost

final class RedactedResultExporterTests: XCTestCase {
    func testExportContainsOnlyTheContractAllowlist() throws {
        let result = RedactedFlowResult(
            runId: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!,
            candidateKind: .transparentProxy,
            evidenceTier: .signedMac,
            flowKind: .udpIPv6,
            appRole: .selectedApp,
            flowAge: .newFlow,
            spikeResult: .inconclusive,
            failureCode: "wireguard-transport-unavailable",
            observedAt: Date(timeIntervalSince1970: 0),
            durationMs: 12
        )

        let data = try RedactedResultExporter().encodedData(for: [result])
        let array = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        let keys = Set(try XCTUnwrap(array.first).keys)

        XCTAssertEqual(keys, [
            "schemaVersion", "runId", "candidateKind", "evidenceTier", "flowKind",
            "appRole", "flowAge", "spikeResult", "failureCode", "observedAt", "durationMs",
        ])

        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(text.contains("selectedSigningIdentifier"))
        XCTAssertFalse(text.contains("privateKey"))
        XCTAssertFalse(text.contains("destination"))
        XCTAssertLessThanOrEqual(data.count, SpikeLimits.maximumExportBytes)
    }

    func testExportRejectsNonKebabCaseFailureCode() {
        let result = RedactedFlowResult(
            runId: UUID(),
            candidateKind: .transparentProxy,
            evidenceTier: .automated,
            flowKind: .tcpIPv4,
            appRole: .controlApp,
            flowAge: .newFlow,
            spikeResult: .fail,
            failureCode: "원본 오류 전문",
            observedAt: Date(),
            durationMs: 1
        )

        XCTAssertThrowsError(try RedactedResultExporter().encodedData(for: [result])) { error in
            XCTAssertEqual(error as? RedactedResultExportError, .invalidFailureCode)
        }
    }

    func testExportRejectsEmptyResults() {
        XCTAssertThrowsError(try RedactedResultExporter().encodedData(for: [])) { error in
            XCTAssertEqual(error as? RedactedResultExportError, .emptyResults)
        }
    }
}
