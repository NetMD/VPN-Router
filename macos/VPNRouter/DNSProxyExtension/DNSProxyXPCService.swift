import Foundation

@objc(VPNRouterDNSProxyXPCProtocol)
protocol DNSProxyXPCProtocol {
    func replaceTargetDomains(_ domains: [String], withReply reply: @escaping (Bool) -> Void)
    func fetchSnapshot(withReply reply: @escaping (Data) -> Void)
}

final class DNSProxyXPCService: NSObject, DNSProxyXPCProtocol, NSXPCListenerDelegate {
    static let machServiceName = "group.com.simple.vpnrouter.shared.DNSProxyExtension"

    private let observationStore: DNSObservationStore
    private let listener: NSXPCListener

    init(observationStore: DNSObservationStore) {
        self.observationStore = observationStore
        listener = NSXPCListener(machServiceName: Self.machServiceName)
        super.init()
        listener.delegate = self
    }

    func start() {
        listener.resume()
    }

    func stop() {
        listener.invalidate()
    }

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection newConnection: NSXPCConnection
    ) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: DNSProxyXPCProtocol.self)
        newConnection.exportedObject = self
        newConnection.activate()
        return true
    }

    func replaceTargetDomains(_ domains: [String], withReply reply: @escaping (Bool) -> Void) {
        observationStore.replaceTargetDomains(domains, completion: reply)
    }

    func fetchSnapshot(withReply reply: @escaping (Data) -> Void) {
        observationStore.snapshotData(completion: reply)
    }
}
