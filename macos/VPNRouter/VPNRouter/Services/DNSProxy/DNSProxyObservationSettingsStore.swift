import Foundation
import Security

struct DNSProxyObservationSettingsStore {
    static let targetDomainsKey = "dnsProxyTargetDomainsV1"
    static let maximumTargetCount = 256

    private let defaults: UserDefaults

    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults
            ?? Self.appGroupIdentifier().flatMap(UserDefaults.init(suiteName:))
            ?? .standard
    }

    func publish(domains: [String]) {
        let profileId = DomainRuleStore.sharedSiteRulesProfileId
        let rules = domains.map {
            DomainRule(
                profileId: profileId,
                domain: DomainRuleExpander.normalize($0),
                includeSubdomains: true,
                enabled: true
            )
        }
        let expandedDomains = DomainRuleExpander.expand(rules)
            .filter(\.enabled)
            .map { DomainRuleExpander.normalize($0.domain) }
            .filter { !$0.isEmpty }
        let boundedDomains = Array(
            Set(expandedDomains)
                .sorted()
                .prefix(Self.maximumTargetCount)
        )
        defaults.set(boundedDomains, forKey: Self.targetDomainsKey)
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
