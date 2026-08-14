import Foundation
import XCTest
#if SWIFT_PACKAGE
@testable import AppRoutingSpikeNetworking
#endif

final class NetworkingTests: XCTestCase {
    private let runId = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    private let policyDate = Date(timeIntervalSince1970: 1_000)

    func testContractRawValuesAndJSONShape() throws {
        XCTAssertEqual(CandidateKind.transparentProxy.rawValue, "transparentProxy")
        XCTAssertEqual(EvidenceTier.signedMac.rawValue, "signedMac")
        XCTAssertEqual(FlowAge.preExistingFlow.rawValue, "preExistingFlow")
        let data = try isoEncoder().encode(runRequest())
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), [
            "schemaVersion", "runId", "candidateKind", "evidenceTier",
            "selectedSigningIdentifier", "selectedTeamIdentifier", "policyAppliedAt"
        ])
    }

    func testAppPriorityStateTableAllFourCases() {
        let table = AppPriorityStateTable()
        XCTAssertEqual(table.decision(activeAppRuleCount: 0, siteRuleCount: 0), .blockedNoFixture)
        XCTAssertEqual(table.decision(activeAppRuleCount: 0, siteRuleCount: 1), .preserveProductSiteMode)
        XCTAssertEqual(table.decision(activeAppRuleCount: 1, siteRuleCount: 0), .runAppPrioritySpike)
        XCTAssertEqual(table.decision(activeAppRuleCount: 1, siteRuleCount: 1), .runAppPrioritySpike)
    }

    func testSelectedFlowTransportIsUnsupported() {
        XCTAssertEqual(SelectedFlowTransport().forward(), .unsupported)
    }

    func testSelectedTransportFailureNeverBecomesDirectPass() {
        let decision = FlowPolicyEvaluator().evaluate(
            FlowPolicyInput(
                sourceSigningIdentifier: "com.example.selected",
                auditTokenIsValid: true,
                isControlPlane: false,
                isKnownHelper: false,
                observedAt: policyDate
            ),
            request: runRequest()
        )
        XCTAssertEqual(
            decision,
            .handledAndClosed(
                appRole: .selectedApp,
                flowAge: .newFlow,
                failureCode: "wireguard-transport-unavailable"
            )
        )
    }

    func testMissingIdentityIsNotTreatedAsSelectedApp() {
        let decision = FlowPolicyEvaluator().evaluate(
            FlowPolicyInput(
                sourceSigningIdentifier: nil,
                auditTokenIsValid: false,
                isControlPlane: false,
                isKnownHelper: false,
                observedAt: policyDate
            ),
            request: runRequest()
        )
        XCTAssertEqual(decision, .handledAndClosed(
            appRole: .selectedApp,
            flowAge: .newFlow,
            failureCode: "identity-metadata-missing"
        ))
    }

    func testControlAndHelperFlowsPassDirectly() {
        let evaluator = FlowPolicyEvaluator()
        let control = evaluator.evaluate(
            FlowPolicyInput(
                sourceSigningIdentifier: "com.example.control",
                auditTokenIsValid: true,
                isControlPlane: false,
                isKnownHelper: false,
                observedAt: policyDate
            ), request: runRequest()
        )
        let helper = evaluator.evaluate(
            FlowPolicyInput(
                sourceSigningIdentifier: "com.example.helper",
                auditTokenIsValid: true,
                isControlPlane: false,
                isKnownHelper: true,
                observedAt: policyDate
            ), request: runRequest()
        )
        XCTAssertEqual(control, .directPass(appRole: .controlApp, flowAge: .newFlow))
        XCTAssertEqual(helper, .directPass(appRole: .helper, flowAge: .newFlow))
    }

    func testInvalidAuditTokenNeverPassesMismatchedAppDirectly() {
        let decision = FlowPolicyEvaluator().evaluate(
            FlowPolicyInput(
                sourceSigningIdentifier: "com.example.other",
                auditTokenIsValid: false,
                isControlPlane: false,
                isKnownHelper: false,
                observedAt: policyDate
            ),
            request: runRequest()
        )
        XCTAssertEqual(decision, .handledAndClosed(
            appRole: .selectedApp,
            flowAge: .newFlow,
            failureCode: "identity-verification-failed"
        ))
    }

    func testProviderAdapterPassesValidControlAndHelperFromDifferentTeam() {
        let controlToken = Data([10])
        let helperToken = Data([11])
        let adapter = providerAdapter(identities: [
            controlToken: ("com.other.control", "OTHERTEAM1"),
            helperToken: ("com.other.helper", "HELPERTEAM")
        ])

        XCTAssertEqual(adapter.evaluate(
            sourceSigningIdentifier: "com.other.control",
            sourceAppAuditToken: controlToken,
            isControlPlane: false,
            isKnownHelper: false,
            observedAt: policyDate,
            request: runRequest(),
            controlPlaneTeamIdentifier: "HOSTTEAM01"
        ), .directPass(appRole: .controlApp, flowAge: .newFlow))
        XCTAssertEqual(adapter.evaluate(
            sourceSigningIdentifier: "com.other.helper",
            sourceAppAuditToken: helperToken,
            isControlPlane: false,
            isKnownHelper: true,
            observedAt: policyDate,
            request: runRequest(),
            controlPlaneTeamIdentifier: "HOSTTEAM01"
        ), .directPass(appRole: .helper, flowAge: .newFlow))
    }

    func testProviderAdapterClosesSelectedIdentifierWithWrongTeam() {
        let token = Data([12])
        let adapter = providerAdapter(identities: [
            token: ("com.example.selected", "WRONGTEAM1")
        ])
        XCTAssertEqual(adapter.evaluate(
            sourceSigningIdentifier: "com.example.selected",
            sourceAppAuditToken: token,
            isControlPlane: false,
            isKnownHelper: false,
            observedAt: policyDate,
            request: runRequest(),
            controlPlaneTeamIdentifier: "HOSTTEAM01"
        ), .handledAndClosed(
            appRole: .selectedApp,
            flowAge: .newFlow,
            failureCode: "identity-verification-failed"
        ))
    }

    func testProviderAdapterPassesVerifiedControlPlaneWithoutRecursion() {
        let token = Data([13])
        let adapter = providerAdapter(identities: [
            token: ("com.example.vpnrouter.approutingspike.proxy", "HOSTTEAM01")
        ])
        XCTAssertEqual(adapter.evaluate(
            sourceSigningIdentifier: "com.example.vpnrouter.approutingspike.proxy",
            sourceAppAuditToken: token,
            isControlPlane: true,
            isKnownHelper: false,
            observedAt: policyDate,
            request: runRequest(),
            controlPlaneTeamIdentifier: "HOSTTEAM01"
        ), .directPass(appRole: .controlPlane, flowAge: .newFlow))
    }

    func testControlPlaneWinsBeforeSelectedIdentity() {
        let decision = FlowPolicyEvaluator().evaluate(
            FlowPolicyInput(
                sourceSigningIdentifier: "com.example.selected",
                auditTokenIsValid: true,
                isControlPlane: true,
                isKnownHelper: false,
                observedAt: policyDate
            ), request: runRequest()
        )
        XCTAssertEqual(decision, .directPass(appRole: .controlPlane, flowAge: .newFlow))
    }

    func testFlowAgeBoundary() {
        let evaluator = FlowPolicyEvaluator()
        func age(at offset: TimeInterval) -> FlowAge {
            let decision = evaluator.evaluate(
                FlowPolicyInput(
                    sourceSigningIdentifier: "com.example.control",
                    auditTokenIsValid: true,
                    isControlPlane: false,
                    isKnownHelper: false,
                    observedAt: policyDate.addingTimeInterval(offset)
                ), request: runRequest()
            )
            guard case let .directPass(_, age) = decision else { return .newFlow }
            return age
        }
        XCTAssertEqual(age(at: -0.001), .preExistingFlow)
        XCTAssertEqual(age(at: 0), .newFlow)
        XCTAssertEqual(age(at: 0.001), .newFlow)
    }

    func testAuditTokenVerifierRequiresExactIdentifierAndToken() {
        let verifier = FlowIdentityVerifier(auditTokenValidator: StubAuditTokenValidator(isValid: true))
        XCTAssertTrue(verifier.verify(
            sourceSigningIdentifier: "com.example.selected",
            sourceAppAuditToken: Data([1]),
            expectedSigningIdentifier: "com.example.selected",
            expectedTeamIdentifier: "TEAMID1234"
        ))
        XCTAssertFalse(verifier.verify(
            sourceSigningIdentifier: "COM.EXAMPLE.SELECTED",
            sourceAppAuditToken: Data([1]),
            expectedSigningIdentifier: "com.example.selected",
            expectedTeamIdentifier: "TEAMID1234"
        ))
        XCTAssertFalse(verifier.verify(
            sourceSigningIdentifier: "com.example.selected",
            sourceAppAuditToken: nil,
            expectedSigningIdentifier: "com.example.selected",
            expectedTeamIdentifier: "TEAMID1234"
        ))
    }

    func testRequestPayloadAndIdentifierBoundaries() throws {
        let validator = SpikeRequestValidator()
        try validator.validate(payload: Data(count: 262_143), decoded: runRequest())
        try validator.validate(payload: Data(count: 262_144), decoded: runRequest())
        XCTAssertThrowsError(try validator.validate(payload: Data(count: 262_145), decoded: runRequest()))
        try validator.validate(payload: Data(), decoded: runRequest(identifier: String(repeating: "a", count: 255)))
        XCTAssertThrowsError(try validator.validate(
            payload: Data(), decoded: runRequest(identifier: String(repeating: "a", count: 256))
        ))
        try validator.validate(payload: Data(), decoded: runRequest(teamIdentifier: String(repeating: "A", count: 64)))
        XCTAssertThrowsError(try validator.validate(
            payload: Data(), decoded: runRequest(teamIdentifier: String(repeating: "A", count: 65))
        ))
    }

    func testSnapshotPaginationAndCursorBoundaries() throws {
        let recorder = SpikeEvidenceRecorder()
        for index in 0..<65 {
            XCTAssertTrue(recorder.append(result(durationMs: index)))
        }
        let first = try recorder.snapshot(SpikeSnapshotRequest(runId: runId, cursor: nil, limit: 64))
        XCTAssertEqual(first.items.count, 64)
        XCTAssertEqual(first.nextCursor, 64)
        XCTAssertTrue(first.hasMore)
        let second = try recorder.snapshot(SpikeSnapshotRequest(runId: runId, cursor: 64, limit: 64))
        XCTAssertEqual(second.items.map(\.cursor), [65])
        XCTAssertFalse(second.hasMore)
        XCTAssertThrowsError(try recorder.snapshot(
            SpikeSnapshotRequest(runId: runId, cursor: nil, limit: 65)
        ))
        XCTAssertThrowsError(try recorder.snapshot(
            SpikeSnapshotRequest(runId: runId, cursor: 66, limit: 1)
        ))
    }

    func testEvidenceBufferFailsWithoutDroppingOldResults() {
        let recorder = SpikeEvidenceRecorder()
        for index in 0..<SpikeLimits.resultBufferCapacity {
            XCTAssertTrue(recorder.append(result(durationMs: index)))
        }
        XCTAssertFalse(recorder.append(result(durationMs: SpikeLimits.resultBufferCapacity)))
        let lastPage = try? recorder.snapshot(
            SpikeSnapshotRequest(runId: runId, cursor: 1_999, limit: 1)
        )
        XCTAssertEqual(lastPage?.items.single?.cursor, 2_000)
    }

    func testRunCommandsAreIdempotentAndConflictsAreRejected() throws {
        let state = SpikeRunState()
        let request = runRequest()
        let first = try state.begin(request, acceptedAt: policyDate)
        let retry = try state.begin(request, acceptedAt: policyDate.addingTimeInterval(5))
        XCTAssertEqual(first, retry)
        XCTAssertThrowsError(try state.begin(
            runRequest(identifier: "com.example.other"), acceptedAt: policyDate
        ))
        let stopped = try state.stop(runId: runId, acceptedAt: policyDate)
        let stopRetry = try state.stop(runId: runId, acceptedAt: policyDate.addingTimeInterval(5))
        XCTAssertEqual(stopped, stopRetry)
        XCTAssertNil(state.currentRequest())
    }

    func testSelectedFlowCapacityBoundary() {
        let gate = SelectedFlowCapacityGate()
        for _ in 0..<255 { XCTAssertTrue(gate.acquire()) }
        XCTAssertEqual(gate.currentCount(), 255)
        XCTAssertTrue(gate.acquire())
        XCTAssertEqual(gate.currentCount(), 256)
        XCTAssertFalse(gate.acquire())
        for _ in 0..<256 { gate.release() }
        XCTAssertEqual(gate.currentCount(), 0)
    }

    func testEvidenceBufferFullFailsRunAndRejectsNewFlows() throws {
        let recorder = SpikeEvidenceRecorder()
        let state = SpikeRunState()
        _ = try state.begin(runRequest(), acceptedAt: policyDate)
        let coordinator = SpikeEvidenceCoordinator(recorder: recorder, runState: state)
        for index in 0..<SpikeLimits.resultBufferCapacity {
            XCTAssertEqual(coordinator.record(result(durationMs: index)), .recorded)
        }
        XCTAssertEqual(
            coordinator.record(result(durationMs: SpikeLimits.resultBufferCapacity)),
            .runFailed
        )
        XCTAssertEqual(state.failureCode(runId: runId), "evidence-buffer-full")
        XCTAssertTrue(state.shouldRejectNewFlows())
        XCTAssertNil(state.currentRequest())
    }

    func testRunStateClearsSensitiveRequestAndBoundsRecords() throws {
        let state = SpikeRunState()
        for index in 0..<(SpikeLimits.maximumRunRecords + 1) {
            let id = UUID()
            let request = SpikeRunRequest(
                runId: id,
                candidateKind: .transparentProxy,
                evidenceTier: .automated,
                selectedSigningIdentifier: "com.example.sensitive.\(index)",
                selectedTeamIdentifier: "TEAMID1234",
                policyAppliedAt: policyDate
            )
            _ = try state.begin(request, acceptedAt: policyDate)
            _ = try state.stop(runId: id, acceptedAt: policyDate)
            XCTAssertNil(state.currentRequest())
        }
        XCTAssertEqual(state.retainedRecordCount(), SpikeLimits.maximumRunRecords)
        state.clear()
        XCTAssertEqual(state.retainedRecordCount(), 0)
    }

    func testFailedRunCanStopAndRetainsFailureForSnapshotResponse() throws {
        let state = SpikeRunState()
        _ = try state.begin(runRequest(), acceptedAt: policyDate)
        state.markFailed(runId: runId, failureCode: "evidence-buffer-full")
        _ = try state.stop(runId: runId, acceptedAt: policyDate)
        XCTAssertEqual(state.failureCode(runId: runId), "evidence-buffer-full")
        XCTAssertTrue(state.shouldRejectNewFlows())

        let nextRequest = SpikeRunRequest(
            runId: UUID(),
            candidateKind: .transparentProxy,
            evidenceTier: .automated,
            selectedSigningIdentifier: "com.example.next",
            selectedTeamIdentifier: "TEAMID1234",
            policyAppliedAt: policyDate
        )
        XCTAssertNoThrow(try state.begin(nextRequest, acceptedAt: policyDate))
    }

    func testCleanupOrderIsFixed() {
        XCTAssertEqual(CleanupCoordinator().orderedSteps(), [
            .rejectNewFlows,
            .stopProvider,
            .removeOwnedConfiguration,
            .verifyControlConnectivity
        ])
    }

    func testRedactedResultContainsNoIdentityOrNetworkFields() throws {
        let data = try isoEncoder().encode(result(durationMs: 4))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let forbidden = Set([
            "selectedSigningIdentifier", "bundleIdentifier", "address",
            "domain", "port", "privateKey", "dnsPayload", "packet"
        ])
        XCTAssertTrue(Set(object.keys).isDisjoint(with: forbidden))
        XCTAssertFalse(object.values.contains { ($0 as? String) == "com.example.selected" })
    }

    static let allTests = [
        ("testContractRawValuesAndJSONShape", testContractRawValuesAndJSONShape),
        ("testAppPriorityStateTableAllFourCases", testAppPriorityStateTableAllFourCases),
        ("testSelectedFlowTransportIsUnsupported", testSelectedFlowTransportIsUnsupported),
        ("testSelectedTransportFailureNeverBecomesDirectPass", testSelectedTransportFailureNeverBecomesDirectPass),
        ("testMissingIdentityIsNotTreatedAsSelectedApp", testMissingIdentityIsNotTreatedAsSelectedApp),
        ("testControlAndHelperFlowsPassDirectly", testControlAndHelperFlowsPassDirectly),
        ("testInvalidAuditTokenNeverPassesMismatchedAppDirectly", testInvalidAuditTokenNeverPassesMismatchedAppDirectly),
        ("testProviderAdapterPassesValidControlAndHelperFromDifferentTeam", testProviderAdapterPassesValidControlAndHelperFromDifferentTeam),
        ("testProviderAdapterClosesSelectedIdentifierWithWrongTeam", testProviderAdapterClosesSelectedIdentifierWithWrongTeam),
        ("testProviderAdapterPassesVerifiedControlPlaneWithoutRecursion", testProviderAdapterPassesVerifiedControlPlaneWithoutRecursion),
        ("testControlPlaneWinsBeforeSelectedIdentity", testControlPlaneWinsBeforeSelectedIdentity),
        ("testFlowAgeBoundary", testFlowAgeBoundary),
        ("testAuditTokenVerifierRequiresExactIdentifierAndToken", testAuditTokenVerifierRequiresExactIdentifierAndToken),
        ("testRequestPayloadAndIdentifierBoundaries", testRequestPayloadAndIdentifierBoundaries),
        ("testSnapshotPaginationAndCursorBoundaries", testSnapshotPaginationAndCursorBoundaries),
        ("testEvidenceBufferFailsWithoutDroppingOldResults", testEvidenceBufferFailsWithoutDroppingOldResults),
        ("testRunCommandsAreIdempotentAndConflictsAreRejected", testRunCommandsAreIdempotentAndConflictsAreRejected),
        ("testSelectedFlowCapacityBoundary", testSelectedFlowCapacityBoundary),
        ("testEvidenceBufferFullFailsRunAndRejectsNewFlows", testEvidenceBufferFullFailsRunAndRejectsNewFlows),
        ("testRunStateClearsSensitiveRequestAndBoundsRecords", testRunStateClearsSensitiveRequestAndBoundsRecords),
        ("testFailedRunCanStopAndRetainsFailureForSnapshotResponse", testFailedRunCanStopAndRetainsFailureForSnapshotResponse),
        ("testCleanupOrderIsFixed", testCleanupOrderIsFixed),
        ("testRedactedResultContainsNoIdentityOrNetworkFields", testRedactedResultContainsNoIdentityOrNetworkFields)
    ]

    private func runRequest(
        identifier: String = "com.example.selected",
        teamIdentifier: String = "TEAMID1234"
    ) -> SpikeRunRequest {
        SpikeRunRequest(
            runId: runId,
            candidateKind: .transparentProxy,
            evidenceTier: .automated,
            selectedSigningIdentifier: identifier,
            selectedTeamIdentifier: teamIdentifier,
            policyAppliedAt: policyDate
        )
    }

    private func result(durationMs: Int) -> RedactedFlowResult {
        RedactedFlowResult(
            runId: runId,
            candidateKind: .transparentProxy,
            evidenceTier: .automated,
            flowKind: .tcpIPv4,
            appRole: .selectedApp,
            flowAge: .newFlow,
            spikeResult: .inconclusive,
            failureCode: "wireguard-transport-unavailable",
            observedAt: policyDate,
            durationMs: durationMs
        )
    }

    private func providerAdapter(
        identities: [Data: (signingIdentifier: String, teamIdentifier: String)]
    ) -> FlowIdentityPolicyAdapter {
        FlowIdentityPolicyAdapter(identityVerifier: FlowIdentityVerifier(
            auditTokenValidator: FixtureAuditTokenValidator(identities: identities)
        ))
    }

    private func isoEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private struct StubAuditTokenValidator: AuditTokenValidating {
    let isValid: Bool

    func validate(
        _ auditToken: Data,
        expectedSigningIdentifier: String,
        expectedTeamIdentifier: String?
    ) -> Bool {
        isValid
    }
}

private struct FixtureAuditTokenValidator: AuditTokenValidating {
    let identities: [Data: (signingIdentifier: String, teamIdentifier: String)]

    func validate(
        _ auditToken: Data,
        expectedSigningIdentifier: String,
        expectedTeamIdentifier: String?
    ) -> Bool {
        guard let identity = identities[auditToken],
              identity.signingIdentifier == expectedSigningIdentifier else {
            return false
        }
        return expectedTeamIdentifier == nil || identity.teamIdentifier == expectedTeamIdentifier
    }
}

private extension Array {
    var single: Element? { count == 1 ? first : nil }
}
