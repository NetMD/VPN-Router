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

        let data = try RedactedResultExporter().encodedData(for: makeReport(results: [result]))
        let report = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let array = try XCTUnwrap(report["results"] as? [[String: Any]])
        let keys = Set(try XCTUnwrap(array.first).keys)
        XCTAssertEqual(Set(report.keys), ["schemaVersion", "validationSummaries", "results"])

        XCTAssertEqual(keys, [
            "schemaVersion", "runId", "candidateKind", "evidenceTier", "flowKind",
            "appRole", "flowAge", "handlingOutcome", "spikeResult", "failureCode", "observedAt", "durationMs",
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

        XCTAssertThrowsError(try RedactedResultExporter().encodedData(for: makeReport(results: [result]))) { error in
            XCTAssertEqual(error as? RedactedResultExportError, .invalidFailureCode)
        }
    }

    func testExportRejectsKebabCaseValueOutsideFailureCodeAllowlist() {
        let result = RedactedFlowResult(
            runId: UUID(),
            candidateKind: .transparentProxy,
            evidenceTier: .automated,
            flowKind: .tcpIPv4,
            appRole: .controlApp,
            flowAge: .newFlow,
            spikeResult: .fail,
            failureCode: "com-example-sensitive-app",
            observedAt: Date(),
            durationMs: 1
        )

        XCTAssertThrowsError(try RedactedResultExporter().encodedData(for: makeReport(results: [result]))) { error in
            XCTAssertEqual(error as? RedactedResultExportError, .invalidFailureCode)
        }
    }

    func testExportRejectsEmptyResults() {
        XCTAssertThrowsError(try RedactedResultExporter().encodedData(for: makeReport(results: []))) { error in
            XCTAssertEqual(error as? RedactedResultExportError, .emptyResults)
        }
    }

    func testExporterPreservesPassFailAndInconclusiveVerdicts() throws {
        let cleanup = CleanupSummary(
            providerStopObserved: true,
            managerCountAfterCleanup: 0,
            dnsMatchedBaseline: true,
            ipv4MatchedBaseline: true,
            ipv6MatchedBaseline: true
        )
        for verdict in [ValidationVerdict.pass, .fail, .inconclusive] {
            let report = makeReport(
                results: [makeResult()],
                signedVerdict: verdict,
                cleanupSummary: verdict == .inconclusive ? nil : cleanup
            )
            let data = try RedactedResultExporter().encodedData(for: report)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let summaries = try XCTUnwrap(json["validationSummaries"] as? [[String: Any]])
            let signed = try XCTUnwrap(summaries.first { $0["validationAxis"] as? String == "signedMac" })
            XCTAssertEqual(signed["validationVerdict"] as? String, verdict.rawValue)
            XCTAssertEqual(json["cleanupSummary"] != nil, verdict != .inconclusive)
        }
    }

    func testExportWritesTheProvidedAxesAndCleanupWithoutRecomputingThem() throws {
        let cleanup = CleanupSummary(
            providerStopObserved: true,
            managerCountAfterCleanup: 0,
            dnsMatchedBaseline: true,
            ipv4MatchedBaseline: false,
            ipv6MatchedBaseline: true
        )
        let report = makeReport(
            results: [makeResult()],
            signedVerdict: .fail,
            cleanupSummary: cleanup
        )
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vpn-router-report-preservation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appendingPathComponent("report.json")

        try RedactedResultExporter().export(report, to: destination)

        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: destination)) as? [String: Any]
        )
        let summaries = try XCTUnwrap(json["validationSummaries"] as? [[String: Any]])
        XCTAssertEqual(summaries.count, 3)
        XCTAssertEqual(
            summaries.first { $0["validationAxis"] as? String == "signedMac" }?["validationVerdict"] as? String,
            "fail"
        )
        let writtenCleanup = try XCTUnwrap(json["cleanupSummary"] as? [String: Any])
        XCTAssertEqual(writtenCleanup["managerCountAfterCleanup"] as? Int, 0)
        XCTAssertEqual(writtenCleanup["ipv4MatchedBaseline"] as? Bool, false)
    }

    func testExporterRejectsDuplicateAndMissingValidationAxes() {
        let now = Date(timeIntervalSince1970: 0)
        let invalid = RedactedValidationReport(
            validationSummaries: [
                ValidationAxisSummary(validationAxis: .automated, validationVerdict: .pass,
                                      executedCount: 1, passedCount: 1, failedCount: 0, observedAt: now),
                ValidationAxisSummary(validationAxis: .signedMac, validationVerdict: .inconclusive,
                                      executedCount: 0, passedCount: 0, failedCount: 0, observedAt: now),
                ValidationAxisSummary(validationAxis: .signedMac, validationVerdict: .pass,
                                      executedCount: 1, passedCount: 1, failedCount: 0, observedAt: now),
            ],
            cleanupSummary: nil,
            results: [makeResult()]
        )

        XCTAssertThrowsError(try RedactedResultExporter().encodedData(for: invalid)) { error in
            XCTAssertEqual(error as? RedactedResultExportError, .invalidReport)
        }
    }

    func testExportRejectsSymbolicLinkDestinationWithoutChangingTarget() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vpn-router-export-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("target.json")
        let destination = root.appendingPathComponent("report.json")
        try Data("unchanged".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: destination, withDestinationURL: target)

        XCTAssertThrowsError(try RedactedResultExporter().export(makeReport(results: [makeResult()]), to: destination)) { error in
            XCTAssertEqual(error as? RedactedResultExportError, .unsafeDestination)
        }
        XCTAssertEqual(try Data(contentsOf: target), Data("unchanged".utf8))
    }

    func testExportRejectsSymbolicLinkParentDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vpn-router-export-\(UUID().uuidString)")
        let realParent = root.appendingPathComponent("real")
        let linkedParent = root.appendingPathComponent("linked")
        try FileManager.default.createDirectory(at: realParent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createSymbolicLink(at: linkedParent, withDestinationURL: realParent)

        XCTAssertThrowsError(
            try RedactedResultExporter().export(makeReport(results: [makeResult()]), to: linkedParent.appendingPathComponent("report.json"))
        ) { error in
            XCTAssertEqual(error as? RedactedResultExportError, .unsafeDestination)
        }
    }

    private func makeResult() -> RedactedFlowResult {
        RedactedFlowResult(
            runId: UUID(),
            candidateKind: .transparentProxy,
            evidenceTier: .automated,
            flowKind: .tcpIPv4,
            appRole: .controlApp,
            flowAge: .newFlow,
            handlingOutcome: .directPass,
            spikeResult: .pass,
            failureCode: nil,
            observedAt: Date(),
            durationMs: 0
        )
    }

    private func makeReport(
        results: [RedactedFlowResult],
        signedVerdict: ValidationVerdict = .inconclusive,
        cleanupSummary: CleanupSummary? = nil
    ) -> RedactedValidationReport {
        let now = Date(timeIntervalSince1970: 0)
        return RedactedValidationReport(
            validationSummaries: [
                ValidationAxisSummary(validationAxis: .automated, validationVerdict: .pass,
                                      executedCount: 1, passedCount: 1, failedCount: 0, observedAt: now),
                ValidationAxisSummary(validationAxis: .signedMac, validationVerdict: signedVerdict,
                                      executedCount: 0, passedCount: 0, failedCount: 0, observedAt: now),
                ValidationAxisSummary(validationAxis: .p3ProductIntegration, validationVerdict: .noGo,
                                      executedCount: 0, passedCount: 0, failedCount: 0, observedAt: now),
            ],
            cleanupSummary: cleanupSummary,
            results: results
        )
    }
}
