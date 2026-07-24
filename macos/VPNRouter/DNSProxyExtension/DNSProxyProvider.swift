import Foundation
import NetworkExtension
import OSLog

final class DNSProxyProvider: NEDNSProxyProvider {
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "VPNRouter.DNSProxyExtension",
        category: "DNSProxy"
    )
    private let observationStore = DNSObservationStore()
    private let sessionLock = NSLock()
    private var sessions: [UUID: DNSFlowSession] = [:]
    private var xpcService: DNSProxyXPCService?

    override func startProxy(
        options: [String: Any]? = nil,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard #available(macOS 15.0, *) else {
            completionHandler(DNSProxyProviderError.unsupportedOperatingSystem)
            return
        }
        let xpcService = DNSProxyXPCService(observationStore: observationStore)
        xpcService.start()
        self.xpcService = xpcService
        logger.notice("DNS Proxy provider started")
        observationStore.record(.providerStarted)
        completionHandler(nil)
    }

    override func stopProxy(
        with reason: NEProviderStopReason,
        completionHandler: @escaping () -> Void
    ) {
        sessionLock.lock()
        let activeSessions = Array(sessions.values)
        sessions.removeAll()
        sessionLock.unlock()
        activeSessions.forEach { $0.stop() }
        xpcService?.stop()
        xpcService = nil
        observationStore.record(.providerStopped)
        logger.notice("DNS Proxy provider stopped")
        completionHandler()
    }

    override func handleNewFlow(_ flow: NEAppProxyFlow) -> Bool {
        guard #available(macOS 15.0, *) else {
            logger.error("Rejected a DNS flow on an unsupported macOS version")
            return false
        }
        let id = UUID()
        let completion: () -> Void = { [weak self] in
            guard let self else { return }
            self.removeSession(id)
        }

        let session: DNSFlowSession
        if let tcpFlow = flow as? NEAppProxyTCPFlow {
            observationStore.record(.tcpFlowAccepted)
            session = TCPDNSFlowSession(
                flow: tcpFlow,
                observationStore: observationStore,
                completion: completion
            )
        } else if let udpFlow = flow as? NEAppProxyUDPFlow {
            observationStore.record(.udpFlowAccepted)
            session = UDPDNSFlowSession(
                flow: udpFlow,
                observationStore: observationStore,
                completion: completion
            )
        } else {
            logger.error("Rejected an unsupported DNS flow type")
            return false
        }

        sessionLock.lock()
        sessions[id] = session
        sessionLock.unlock()
        session.start()
        return true
    }

    private func removeSession(_ id: UUID) {
        sessionLock.lock()
        sessions[id] = nil
        sessionLock.unlock()
    }
}

private enum DNSProxyProviderError: LocalizedError {
    case unsupportedOperatingSystem

    var errorDescription: String? {
        "DNS Proxy 전달 기능은 macOS 15 이상에서 지원됩니다."
    }
}
