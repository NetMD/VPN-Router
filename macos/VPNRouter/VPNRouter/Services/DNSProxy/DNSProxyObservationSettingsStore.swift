import Foundation

@objc(VPNRouterDNSProxyXPCProtocol)
private protocol DNSProxyXPCProtocol {
    func replaceTargetDomains(_ domains: [String], withReply reply: @escaping (Bool) -> Void)
    func fetchSnapshot(withReply reply: @escaping (Data) -> Void)
}

struct DNSProxyObservationSettingsStore {
    static let maximumTargetCount = 256
    static let machServiceName = "group.com.simple.vpnrouter.shared.DNSProxyExtension"

    func configureForDiagnosticRun(domains: [String]) async throws {
        let targetDomains = expandedTargetDomains(domains)
        guard !targetDomains.isEmpty else {
            throw DNSProxyXPCError.emptyTargetDomains
        }
        let accepted: Bool = try await performRequest { proxy, reply in
            proxy.replaceTargetDomains(targetDomains, withReply: reply)
        }
        guard accepted else {
            throw DNSProxyXPCError.targetDomainsRejected
        }
    }

    func summary(at date: Date = Date()) async throws -> DNSProxyObservationSummary {
        let data: Data = try await performRequest { proxy, reply in
            proxy.fetchSnapshot(withReply: reply)
        }
        guard !data.isEmpty else {
            throw DNSProxyXPCError.emptySnapshot
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(DNSProxyXPCSnapshot.self, from: data)
        guard snapshot.schemaVersion == 1 else {
            throw DNSProxyXPCError.unsupportedSchema(snapshot.schemaVersion)
        }
        let activeCount = snapshot.routes.lazy.filter { $0.expiresAt > date }.count
        return DNSProxyObservationSummary(
            activeCount: activeCount,
            expiredCount: snapshot.routes.count - activeCount,
            latestObservationAt: snapshot.routes.map(\.observedAt).max(),
            routes: snapshot.routes,
            eventCounts: snapshot.eventCounts,
            lastEventAt: snapshot.lastEventAt,
            lastFailureDomain: snapshot.lastFailureDomain,
            lastFailureCode: snapshot.lastFailureCode
        )
    }

    private func expandedTargetDomains(_ domains: [String]) -> [String] {
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
        return Array(Set(expandedDomains).sorted().prefix(Self.maximumTargetCount))
    }

    private func performRequest<Value>(
        _ request: @escaping (DNSProxyXPCProtocol, @escaping (Value) -> Void) -> Void
    ) async throws -> Value {
        var lastError: Error = DNSProxyXPCError.connectionUnavailable
        for attempt in 0..<3 {
            do {
                return try await performSingleRequest(request)
            } catch {
                lastError = error
                if attempt < 2 {
                    try await Task.sleep(nanoseconds: 250_000_000)
                }
            }
        }
        throw lastError
    }

    private func performSingleRequest<Value>(
        _ request: @escaping (DNSProxyXPCProtocol, @escaping (Value) -> Void) -> Void
    ) async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            let gate = DNSProxyXPCContinuationGate(continuation)
            let connection = NSXPCConnection(
                machServiceName: Self.machServiceName,
                options: .privileged
            )
            let timeout = DispatchWorkItem {
                gate.resume(throwing: DNSProxyXPCError.requestTimedOut)
                connection.invalidate()
            }
            connection.remoteObjectInterface = NSXPCInterface(with: DNSProxyXPCProtocol.self)
            connection.interruptionHandler = {
                timeout.cancel()
                gate.resume(throwing: DNSProxyXPCError.connectionInterrupted)
            }
            connection.invalidationHandler = {
                timeout.cancel()
                gate.resume(throwing: DNSProxyXPCError.connectionInvalidated)
            }
            connection.activate()
            DispatchQueue.global(qos: .userInitiated).asyncAfter(
                deadline: .now() + 2,
                execute: timeout
            )

            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
                timeout.cancel()
                gate.resume(throwing: error)
                connection.invalidate()
            }) as? DNSProxyXPCProtocol else {
                timeout.cancel()
                gate.resume(throwing: DNSProxyXPCError.invalidRemoteProxy)
                connection.invalidate()
                return
            }

            request(proxy) { value in
                timeout.cancel()
                gate.resume(returning: value)
                connection.invalidate()
            }
        }
    }
}

struct DNSProxyObservationSummary {
    let activeCount: Int
    let expiredCount: Int
    let latestObservationAt: Date?
    let routes: [DNSProxyRouteObservation]
    let eventCounts: [String: Int]
    let lastEventAt: Date?
    let lastFailureDomain: String?
    let lastFailureCode: Int?
}

private struct DNSProxyXPCSnapshot: Decodable {
    let schemaVersion: Int
    let routes: [DNSProxyRouteObservation]
    let eventCounts: [String: Int]
    let lastEventAt: Date?
    let lastFailureDomain: String?
    let lastFailureCode: Int?
}

struct DNSProxyRouteObservation: Decodable {
    let domain: String
    let address: String
    let observedAt: Date
    let expiresAt: Date
}

private final class DNSProxyXPCContinuationGate<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?

    init(_ continuation: CheckedContinuation<Value, Error>) {
        self.continuation = continuation
    }

    func resume(returning value: Value) {
        takeContinuation()?.resume(returning: value)
    }

    func resume(throwing error: Error) {
        takeContinuation()?.resume(throwing: error)
    }

    private func takeContinuation() -> CheckedContinuation<Value, Error>? {
        lock.lock()
        defer { lock.unlock() }
        let continuation = continuation
        self.continuation = nil
        return continuation
    }
}

private enum DNSProxyXPCError: LocalizedError {
    case connectionUnavailable
    case connectionInterrupted
    case connectionInvalidated
    case requestTimedOut
    case invalidRemoteProxy
    case emptyTargetDomains
    case targetDomainsRejected
    case emptySnapshot
    case unsupportedSchema(Int)

    var errorDescription: String? {
        switch self {
        case .connectionUnavailable:
            "DNS Proxy XPC 연결을 만들 수 없습니다."
        case .connectionInterrupted:
            "DNS Proxy XPC 연결이 중단되었습니다."
        case .connectionInvalidated:
            "DNS Proxy XPC 연결이 무효화되었습니다."
        case .requestTimedOut:
            "DNS Proxy XPC 요청 시간이 초과되었습니다."
        case .invalidRemoteProxy:
            "DNS Proxy XPC 인터페이스를 읽을 수 없습니다."
        case .emptyTargetDomains:
            "DNS Proxy에 전달할 대상 도메인이 없습니다."
        case .targetDomainsRejected:
            "DNS Proxy가 대상 도메인 설정을 거부했습니다."
        case .emptySnapshot:
            "DNS Proxy가 빈 진단 응답을 반환했습니다."
        case .unsupportedSchema(let version):
            "지원하지 않는 DNS Proxy 진단 스키마입니다: \(version)"
        }
    }
}
