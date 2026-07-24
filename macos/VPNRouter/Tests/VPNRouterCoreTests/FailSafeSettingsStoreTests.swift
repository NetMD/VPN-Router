import Foundation
import XCTest
@testable import VPNRouterSettings

final class FailSafeSettingsStoreTests: XCTestCase {
    func testDefaultsToEnabledWhenSettingDoesNotExist() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertTrue(FailSafeSettingsStore(defaults: defaults).isEnabled)
    }

    func testPersistsEnabledAndDisabledValues() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = FailSafeSettingsStore(defaults: defaults)

        store.setEnabled(false)
        XCTAssertFalse(store.isEnabled)

        store.setEnabled(true)
        XCTAssertTrue(store.isEnabled)
    }

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suiteName = "VPNRouterTests.FailSafe.\(UUID().uuidString)"
        return (try XCTUnwrap(UserDefaults(suiteName: suiteName)), suiteName)
    }
}
