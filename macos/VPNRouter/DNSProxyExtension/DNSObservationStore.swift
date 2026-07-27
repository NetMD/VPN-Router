import Foundation

final class DNSObservationStore {
    static let maximumObservationCount = 512
    static let maximumTargetCount = 256

    private let queue = DispatchQueue(label: "VPNRouter.DNSObservationStore")
    private let encoder = JSONEncoder()
    private var targetDomains = Set<String>()
    private var observationsByAddress: [String: DNSRouteObservation] = [:]
    private var runtimeDiagnostics = DNSProxyRuntimeDiagnostics(
        schemaVersion: 1,
        eventCounts: [:],
        lastEventAt: nil,
        lastFailureDomain: nil,
        lastFailureCode: nil
    )

    init() {
        encoder.dateEncodingStrategy = .iso8601
    }

    func replaceTargetDomains(_ domains: [String], completion: @escaping (Bool) -> Void) {
        queue.async {
            let normalized = domains
                .prefix(Self.maximumTargetCount)
                .map(Self.normalize)
                .filter { !$0.isEmpty }
            self.targetDomains = Set(normalized)
            self.observationsByAddress.removeAll()
            self.runtimeDiagnostics = DNSProxyRuntimeDiagnostics(
                schemaVersion: 1,
                eventCounts: self.runtimeDiagnostics.eventCounts,
                lastEventAt: self.runtimeDiagnostics.lastEventAt,
                lastFailureDomain: self.runtimeDiagnostics.lastFailureDomain,
                lastFailureCode: self.runtimeDiagnostics.lastFailureCode
            )
            completion(!self.targetDomains.isEmpty)
        }
    }

    func inspectResponse(_ response: Data, observedAt: Date = Date()) {
        queue.async {
            self.inspectResponseLocked(response, observedAt: observedAt)
        }
    }

    func processResponse(_ response: Data, observedAt: Date = Date()) -> Data {
        queue.sync {
            inspectResponseLocked(response, observedAt: observedAt)
            guard let filtered = try? DNSMessageParser.emptyAAAAResponse(
                for: response,
                matching: targetDomains
            ) else {
                return response
            }
            recordLocked(.aaaaResponseFiltered, error: nil, at: observedAt)
            return filtered
        }
    }

    func record(_ event: DNSProxyRuntimeEvent, error: Error? = nil, at date: Date = Date()) {
        queue.async {
            self.recordLocked(event, error: error, at: date)
        }
    }

    func snapshotData(completion: @escaping (Data) -> Void) {
        queue.async {
            let snapshot = DNSProxyXPCSnapshot(
                schemaVersion: 1,
                routes: self.observationsByAddress.values.sorted {
                    if $0.expiresAt != $1.expiresAt {
                        return $0.expiresAt > $1.expiresAt
                    }
                    return $0.address < $1.address
                },
                eventCounts: self.runtimeDiagnostics.eventCounts,
                lastEventAt: self.runtimeDiagnostics.lastEventAt,
                lastFailureDomain: self.runtimeDiagnostics.lastFailureDomain,
                lastFailureCode: self.runtimeDiagnostics.lastFailureCode
            )
            completion((try? self.encoder.encode(snapshot)) ?? Data())
        }
    }

    private static func normalize(_ domain: String) -> String {
        domain
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
    }

    private func inspectResponseLocked(_ response: Data, observedAt: Date) {
        guard !targetDomains.isEmpty,
              let observations = try? DNSMessageParser.addressObservations(
                in: response,
                matching: targetDomains
              ),
              !observations.isEmpty else {
            return
        }

        observationsByAddress = observationsByAddress.filter {
            $0.value.expiresAt > observedAt
        }
        for observation in observations where observation.ttl > 0 {
            let boundedTTL = min(TimeInterval(observation.ttl), 3_600)
            let route = DNSRouteObservation(
                domain: Self.normalize(observation.domain),
                address: observation.address,
                observedAt: observedAt,
                expiresAt: observedAt.addingTimeInterval(boundedTTL)
            )
            if let current = observationsByAddress[route.address] {
                if route.expiresAt > current.expiresAt
                    || (route.expiresAt == current.expiresAt && route.domain < current.domain) {
                    observationsByAddress[route.address] = route
                }
            } else {
                observationsByAddress[route.address] = route
            }
        }

        let boundedRoutes = observationsByAddress.values
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
        observationsByAddress = Dictionary(
            uniqueKeysWithValues: boundedRoutes.map { ($0.address, $0) }
        )
    }

    private func recordLocked(
        _ event: DNSProxyRuntimeEvent,
        error: Error?,
        at date: Date
    ) {
        var counts = runtimeDiagnostics.eventCounts
        let currentCount = counts[event.rawValue, default: 0]
        if currentCount < Int.max {
            counts[event.rawValue] = currentCount + 1
        }
        let nsError = error as NSError?
        runtimeDiagnostics = DNSProxyRuntimeDiagnostics(
            schemaVersion: 1,
            eventCounts: counts,
            lastEventAt: date,
            lastFailureDomain: nsError?.domain ?? runtimeDiagnostics.lastFailureDomain,
            lastFailureCode: nsError?.code ?? runtimeDiagnostics.lastFailureCode
        )
    }
}

enum DNSProxyRuntimeEvent: String {
    case providerStarted
    case providerStopped
    case udpFlowAccepted
    case tcpFlowAccepted
    case flowOpened
    case upstreamReady
    case responseReceived
    case responseDelivered
    case aaaaResponseFiltered
    case forwardingFailure
}

private struct DNSProxyXPCSnapshot: Codable {
    let schemaVersion: Int
    let routes: [DNSRouteObservation]
    let eventCounts: [String: Int]
    let lastEventAt: Date?
    let lastFailureDomain: String?
    let lastFailureCode: Int?
}

private struct DNSRouteObservation: Codable {
    let domain: String
    let address: String
    let observedAt: Date
    let expiresAt: Date
}

private struct DNSProxyRuntimeDiagnostics {
    let schemaVersion: Int
    let eventCounts: [String: Int]
    let lastEventAt: Date?
    let lastFailureDomain: String?
    let lastFailureCode: Int?
}
