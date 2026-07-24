import Foundation
import Security

final class DNSObservationStore {
    static let targetDomainsKey = "dnsProxyTargetDomainsV1"
    static let observationsKey = "dnsProxyRouteObservationsV1"
    static let maximumObservationCount = 512

    private let defaults: UserDefaults
    private let queue = DispatchQueue(label: "VPNRouter.DNSObservationStore")
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        let defaults = Self.appGroupIdentifier()
            .flatMap(UserDefaults.init(suiteName:))
            ?? .standard
        self.defaults = defaults
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func inspectResponse(_ response: Data, observedAt: Date = Date()) {
        queue.async { [defaults, decoder, encoder] in
            let targets = Set(
                defaults.stringArray(forKey: Self.targetDomainsKey)?
                    .prefix(256)
                    .map(Self.normalize) ?? []
            )
            guard !targets.isEmpty,
                  let observations = try? DNSMessageParser.addressObservations(
                    in: response,
                    matching: targets
                  ),
                  !observations.isEmpty else {
                return
            }

            let existing: DNSRouteObservationSnapshot
            if let data = defaults.data(forKey: Self.observationsKey),
               let decoded = try? decoder.decode(DNSRouteObservationSnapshot.self, from: data),
               decoded.schemaVersion == 1 {
                existing = decoded
            } else {
                existing = DNSRouteObservationSnapshot(schemaVersion: 1, routes: [])
            }

            var byAddress: [String: DNSRouteObservation] = [:]
            for route in existing.routes where route.expiresAt > observedAt {
                if let current = byAddress[route.address] {
                    if route.expiresAt > current.expiresAt
                        || (route.expiresAt == current.expiresAt && route.domain < current.domain) {
                        byAddress[route.address] = route
                    }
                } else {
                    byAddress[route.address] = route
                }
            }

            for observation in observations where observation.ttl > 0 {
                let boundedTTL = min(TimeInterval(observation.ttl), 3_600)
                let route = DNSRouteObservation(
                    domain: Self.normalize(observation.domain),
                    address: observation.address,
                    observedAt: observedAt,
                    expiresAt: observedAt.addingTimeInterval(boundedTTL)
                )
                if let current = byAddress[route.address] {
                    if route.expiresAt > current.expiresAt
                        || (route.expiresAt == current.expiresAt && route.domain < current.domain) {
                        byAddress[route.address] = route
                    }
                } else {
                    byAddress[route.address] = route
                }
            }

            let boundedRoutes = byAddress.values
                .sorted {
                    if $0.expiresAt != $1.expiresAt {
                        return $0.expiresAt > $1.expiresAt
                    }
                    if $0.address != $1.address {
                        return $0.address < $1.address
                    }
                    return $0.domain < $1.domain
                }
                .prefix(Self.maximumObservationCount)

            let snapshot = DNSRouteObservationSnapshot(
                schemaVersion: 1,
                routes: Array(boundedRoutes)
            )
            if let encoded = try? encoder.encode(snapshot) {
                defaults.set(encoded, forKey: Self.observationsKey)
            }
        }
    }

    private static func normalize(_ domain: String) -> String {
        domain
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
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

private struct DNSRouteObservationSnapshot: Codable {
    let schemaVersion: Int
    let routes: [DNSRouteObservation]
}

private struct DNSRouteObservation: Codable {
    let domain: String
    let address: String
    let observedAt: Date
    let expiresAt: Date
}
