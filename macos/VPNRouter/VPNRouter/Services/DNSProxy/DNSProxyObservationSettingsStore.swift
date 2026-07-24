import Foundation
import Security

struct DNSProxyObservationSettingsStore {
    static let targetDomainsKey = "dnsProxyTargetDomainsV1"
    static let observationsKey = "dnsProxyRouteObservationsV1"
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

    func prepareForDiagnosticRun(domains: [String]) {
        defaults.removeObject(forKey: Self.observationsKey)
        publish(domains: domains)
    }

    func summary(at date: Date = Date()) throws -> DNSProxyObservationSummary {
        guard let data = defaults.data(forKey: Self.observationsKey) else {
            return DNSProxyObservationSummary(
                activeCount: 0,
                expiredCount: 0,
                latestObservationAt: nil
            )
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(DNSProxyRouteObservationSnapshot.self, from: data)
        guard snapshot.schemaVersion == 1 else {
            throw DNSProxyObservationSettingsError.unsupportedSchema(snapshot.schemaVersion)
        }

        let activeCount = snapshot.routes.lazy.filter { $0.expiresAt > date }.count
        let latestObservationAt = snapshot.routes.map(\.observedAt).max()
        return DNSProxyObservationSummary(
            activeCount: activeCount,
            expiredCount: snapshot.routes.count - activeCount,
            latestObservationAt: latestObservationAt
        )
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

struct DNSProxyObservationSummary {
    let activeCount: Int
    let expiredCount: Int
    let latestObservationAt: Date?
}

private struct DNSProxyRouteObservationSnapshot: Decodable {
    let schemaVersion: Int
    let routes: [DNSProxyRouteObservation]
}

private struct DNSProxyRouteObservation: Decodable {
    let observedAt: Date
    let expiresAt: Date
}

private enum DNSProxyObservationSettingsError: LocalizedError {
    case unsupportedSchema(Int)

    var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let version):
            return "지원하지 않는 DNS 관찰 스키마 버전입니다: \(version)"
        }
    }
}
