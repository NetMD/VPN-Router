import XCTest
@testable import AppRoutingSpikeHost

final class SpikeDisplayStateTests: XCTestCase {
    func testStartRequiresAllReadinessConditionsAndIdleLifecycle() {
        let cases: [(Bool, Bool, Bool, SpikeLifecycleState, Bool)] = [
            (false, false, false, .notReady, false),
            (true, false, true, .notReady, false),
            (true, true, false, .notReady, false),
            (true, true, true, .ready, true),
            (true, true, true, .running, false),
            (true, true, true, .stopping, false),
        ]

        for (entitlement, selectedApp, fixture, lifecycle, expected) in cases {
            let state = SpikeDisplayState(
                hasSignedEntitlement: entitlement,
                hasSelectedTestApp: selectedApp,
                hasSanitizedFixture: fixture,
                lifecycle: lifecycle
            )
            XCTAssertEqual(state.canStart, expected)
        }
    }

    func testControlsFollowTheSpecifiedLifecycleMatrix() {
        var state = SpikeDisplayState(lifecycle: .running, redactedResultCount: 1)
        XCTAssertFalse(state.canSelectTestApp)
        XCTAssertTrue(state.canStop)
        XCTAssertFalse(state.canExport)

        state.lifecycle = .stopping
        XCTAssertFalse(state.canSelectTestApp)
        XCTAssertFalse(state.canStop)
        XCTAssertFalse(state.canExport)

        state.lifecycle = .stopped
        XCTAssertTrue(state.canSelectTestApp)
        XCTAssertFalse(state.canStop)
        XCTAssertTrue(state.canExport)
    }

    func testCleanupIsNotReportedCompleteBeforeControlVerification() {
        let awaiting = SpikeDisplayState(lifecycle: .awaitingControlVerification)
        XCTAssertEqual(awaiting.statusText, "통제 인터넷 확인이 필요합니다")
        XCTAssertNotEqual(awaiting.statusText, "시험을 안전하게 중단했습니다")

        let invalid = SpikeDisplayState(
            hasValidHostConfiguration: false,
            lifecycle: .configurationInvalid
        )
        XCTAssertFalse(invalid.canRequestInstallation)
        XCTAssertFalse(invalid.canStart)
    }

    func testResultAndEvidenceDoNotReplaceLifecycle() {
        let state = SpikeDisplayState(
            lifecycle: .running,
            evidenceTier: .automated,
            spikeResult: .pass
        )

        XCTAssertTrue(state.isRunning)
        XCTAssertEqual(state.evidenceTier, .automated)
        XCTAssertEqual(state.spikeResult, .pass)
        XCTAssertEqual(state.statusText, "시험 중")
    }
}
