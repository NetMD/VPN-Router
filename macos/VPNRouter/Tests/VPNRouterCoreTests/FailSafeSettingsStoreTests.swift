import Foundation
import XCTest
@testable import VPNRouterSettings

final class FailSafeSettingsStoreTests: XCTestCase {
    func testMandatoryProtectionIgnoresLegacyDisabledSetting() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(false, forKey: FailSafeSettingsStore.settingKey)
        XCTAssertTrue(FailSafeSettingsStore(defaults: defaults).isEnabled)
    }

    func testEnforceEnabledRemovesLegacyOverride() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = FailSafeSettingsStore(defaults: defaults)

        defaults.set(false, forKey: FailSafeSettingsStore.settingKey)
        XCTAssertTrue(store.enforceEnabled())

        XCTAssertTrue(store.isEnabled)
        XCTAssertNil(defaults.object(forKey: FailSafeSettingsStore.settingKey))
    }

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suiteName = "VPNRouterTests.FailSafe.\(UUID().uuidString)"
        return (try XCTUnwrap(UserDefaults(suiteName: suiteName)), suiteName)
    }
}
