import Foundation
import XCTest

final class ProviderFlowBridgeTests: XCTestCase {
    private struct Validator: AuditTokenValidating {
        let valid: Bool
        func validate(_ auditToken: Data, expectedSigningIdentifier: String,
                      expectedTeamIdentifier: String?) -> Bool { valid }
    }

    func testSelectedTCPAndUDPRemainOwnedAndClosedWithoutP3() {
        for kind in [FlowKind.tcpIPv4, .udpIPv4] {
            let plan = bridge(valid: true).evaluate(
                projection(identifier: "selected", token: Data([1]), kind: kind),
                request: request(), isControlPlane: false, isKnownHelper: false,
                controlPlaneTeamIdentifier: "host-team")
            XCTAssertTrue(plan.providerReturnValue)
            XCTAssertTrue(plan.shouldClose)
            XCTAssertEqual(plan.redactedResult?.handlingOutcome, .ownedAndClosed)
            XCTAssertEqual(plan.redactedResult?.failureCode, "wireguard-transport-unavailable")
        }
    }

    func testMissingIdentityFailsClosed() {
        let plan = bridge(valid: false).evaluate(
            projection(identifier: nil, token: nil, kind: .tcpIPv4), request: request(),
            isControlPlane: false, isKnownHelper: false, controlPlaneTeamIdentifier: "host-team")
        XCTAssertTrue(plan.providerReturnValue)
        XCTAssertTrue(plan.shouldClose)
        XCTAssertEqual(plan.redactedResult?.failureCode, "identity-metadata-missing")
    }

    func testSelectedAppSpoofWithInvalidAuditTokenFailsClosed() {
        let plan = bridge(valid: false).evaluate(
            projection(identifier: "selected", token: Data([1]), kind: .tcpIPv4), request: request(),
            isControlPlane: false, isKnownHelper: false, controlPlaneTeamIdentifier: "host-team")
        XCTAssertTrue(plan.providerReturnValue)
        XCTAssertTrue(plan.shouldClose)
        XCTAssertEqual(plan.redactedResult?.appRole, .selectedApp)
        XCTAssertEqual(plan.redactedResult?.handlingOutcome, .ownedAndClosed)
        XCTAssertEqual(plan.redactedResult?.failureCode, "identity-verification-failed")
    }

    func testSelectedAppTeamMismatchFailsClosed() {
        let plan = bridge(valid: false).evaluate(
            projection(identifier: "selected", token: Data([2]), kind: .udpIPv4), request: request(),
            isControlPlane: false, isKnownHelper: false, controlPlaneTeamIdentifier: "host-team")
        XCTAssertTrue(plan.providerReturnValue)
        XCTAssertTrue(plan.shouldClose)
        XCTAssertEqual(plan.redactedResult?.appRole, .selectedApp)
        XCTAssertEqual(plan.redactedResult?.handlingOutcome, .ownedAndClosed)
        XCTAssertEqual(plan.redactedResult?.failureCode, "identity-verification-failed")
    }

    func testAuditTokenMissingFailsClosed() {
        let plan = bridge(valid: false).evaluate(
            projection(identifier: "selected", token: nil, kind: .tcpIPv4), request: request(),
            isControlPlane: false, isKnownHelper: false, controlPlaneTeamIdentifier: "host-team")
        XCTAssertTrue(plan.providerReturnValue)
        XCTAssertTrue(plan.shouldClose)
        XCTAssertEqual(plan.redactedResult?.failureCode, "identity-verification-failed")
    }

    func testControlAppDirectPassIsRecordedBeforeFalseReturn() {
        let plan = bridge(valid: true).evaluate(
            projection(identifier: "control", token: Data([1]), kind: .tcpIPv4), request: request(),
            isControlPlane: false, isKnownHelper: false, controlPlaneTeamIdentifier: "host-team")
        XCTAssertFalse(plan.providerReturnValue)
        XCTAssertFalse(plan.shouldClose)
        XCTAssertEqual(plan.redactedResult?.appRole, .controlApp)
        XCTAssertEqual(plan.redactedResult?.handlingOutcome, .directPass)
        XCTAssertEqual(plan.redactedResult?.spikeResult, .pass)
    }

    func testStopRunRejectsNewFlowsAfterRawIdentityIsErased() throws {
        let state = SpikeRunState()
        let request = request()
        _ = try state.begin(request, acceptedAt: Date())
        _ = try state.stop(runId: request.runId, acceptedAt: Date())
        XCTAssertNil(state.currentRequest())
        XCTAssertNotNil(state.rejectingRunContext())
        XCTAssertTrue(state.shouldRejectNewFlows())
    }

    private func bridge(valid: Bool) -> ProviderFlowBridge {
        ProviderFlowBridge(identityVerifier: FlowIdentityVerifier(auditTokenValidator: Validator(valid: valid)))
    }
    private func request() -> SpikeRunRequest {
        SpikeRunRequest(runId: UUID(), candidateKind: .transparentProxy, evidenceTier: .automated,
                        selectedSigningIdentifier: "selected", selectedTeamIdentifier: "selected-team",
                        policyAppliedAt: Date(timeIntervalSince1970: 0))
    }
    private func projection(identifier: String?, token: Data?, kind: FlowKind) -> ProviderFlowProjection {
        ProviderFlowProjection(sourceSigningIdentifier: identifier, sourceAppAuditToken: token,
                               flowKind: kind, observedAt: Date(timeIntervalSince1970: 1))
    }
}
