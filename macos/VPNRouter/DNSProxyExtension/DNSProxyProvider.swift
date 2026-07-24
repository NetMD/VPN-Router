import NetworkExtension
import OSLog

final class DNSProxyProvider: NEDNSProxyProvider {
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "VPNRouter.DNSProxyExtension",
        category: "DNSProxy"
    )

    override func startProxy(
        options: [String: Any]? = nil,
        completionHandler: @escaping (Error?) -> Void
    ) {
        logger.notice("DNS Proxy provider started in non-intercepting Phase 3 spike mode")
        completionHandler(nil)
    }

    override func stopProxy(
        with reason: NEProviderStopReason,
        completionHandler: @escaping () -> Void
    ) {
        logger.notice("DNS Proxy provider stopped")
        completionHandler()
    }

    override func handleNewFlow(_ flow: NEAppProxyFlow) -> Bool {
        // Phase 3 checkpoint B never enables the DNS Proxy configuration. If the
        // provider is started unexpectedly, reject the flow instead of accepting
        // traffic without a complete UDP/TCP forwarding path.
        logger.error("Rejected an unexpected DNS flow in non-intercepting spike mode")
        return false
    }
}
