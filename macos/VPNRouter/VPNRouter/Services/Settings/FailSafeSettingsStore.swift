import Foundation
import Security

struct FailSafeSettingsStore {
    static let settingKey = "routePlanExpirationFailSafeEnabled"

    private let defaults: UserDefaults

    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults
            ?? Self.appGroupIdentifier().flatMap(UserDefaults.init(suiteName:))
            ?? .standard
    }

    var isEnabled: Bool {
        guard defaults.object(forKey: Self.settingKey) != nil else {
            return true
        }
        return defaults.bool(forKey: Self.settingKey)
    }

    func setEnabled(_ isEnabled: Bool) {
        defaults.set(isEnabled, forKey: Self.settingKey)
    }

    private static func appGroupIdentifier() -> String? {
        guard
            let task = SecTaskCreateFromSelf(nil),
            let value = SecTaskCopyValueForEntitlement(
                task,
                "com.apple.security.application-groups" as CFString,
                nil
            ),
            let groups = value as? [String]
        else {
            return nil
        }

        return groups.first
    }
}
