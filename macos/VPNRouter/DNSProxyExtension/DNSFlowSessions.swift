import Foundation
import Network
import NetworkExtension

protocol DNSFlowSession: AnyObject {
    func start()
    func stop()
}

@available(macOS 15.0, *)
final class TCPDNSFlowSession: DNSFlowSession {
    private let flow: NEAppProxyTCPFlow
    private let connection: NWConnection
    private let queue: DispatchQueue
    private let observationStore: DNSObservationStore
    private let completion: () -> Void
    private var didFinish = false
    private var responseBuffer = Data()

    init(
        flow: NEAppProxyTCPFlow,
        observationStore: DNSObservationStore,
        completion: @escaping () -> Void
    ) {
        self.flow = flow
        self.observationStore = observationStore
        self.completion = completion
        queue = DispatchQueue(label: "VPNRouter.TCPDNSFlow.\(UUID().uuidString)")

        let parameters = NWParameters.tcp
        flow.setMetadata(on: parameters)
        connection = NWConnection(to: flow.remoteFlowEndpoint, using: parameters)
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.observationStore.record(.upstreamReady)
                self.openFlow()
            case .failed(let error):
                self.finish(error)
            case .cancelled:
                self.finish(nil)
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    func stop() {
        queue.async { [weak self] in
            self?.finish(nil)
        }
    }

    private func openFlow() {
        flow.open(withLocalFlowEndpoint: nil) { [weak self] error in
            guard let self else { return }
            self.queue.async {
                if let error {
                    self.finish(error)
                    return
                }
                self.observationStore.record(.flowOpened)
                self.copyInbound()
                self.copyOutbound()
            }
        }
    }

    private func copyInbound() {
        guard !didFinish else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_537) {
            [weak self] data, _, isComplete, error in
            guard let self else { return }
            self.queue.async {
                if let data, !data.isEmpty {
                    self.observationStore.record(.responseReceived)
                    self.inspectTCPResponses(data)
                    self.flow.write(data) { [weak self] writeError in
                        self?.queue.async {
                            if let writeError {
                                self?.finish(writeError)
                            } else if isComplete {
                                self?.observationStore.record(.responseDelivered)
                                self?.finish(error)
                            } else {
                                self?.observationStore.record(.responseDelivered)
                                self?.copyInbound()
                            }
                        }
                    }
                } else if isComplete || error != nil {
                    self.finish(error)
                } else {
                    self.copyInbound()
                }
            }
        }
    }

    private func copyOutbound() {
        guard !didFinish else { return }
        flow.readData { [weak self] data, error in
            guard let self else { return }
            self.queue.async {
                guard error == nil, let data, !data.isEmpty else {
                    self.finish(error)
                    return
                }
                self.connection.send(content: data, completion: .contentProcessed {
                    [weak self] sendError in
                    self?.queue.async {
                        if let sendError {
                            self?.finish(sendError)
                        } else {
                            self?.copyOutbound()
                        }
                    }
                })
            }
        }
    }

    private func inspectTCPResponses(_ data: Data) {
        responseBuffer.append(data)
        if responseBuffer.count > 131_074 {
            responseBuffer.removeAll(keepingCapacity: true)
            return
        }

        while responseBuffer.count >= 2 {
            let messageLength = Int(responseBuffer[0]) << 8 | Int(responseBuffer[1])
            guard messageLength > 0 else {
                responseBuffer.removeFirst(2)
                continue
            }
            guard responseBuffer.count >= messageLength + 2 else {
                return
            }
            let message = Data(responseBuffer[2..<(messageLength + 2)])
            responseBuffer.removeFirst(messageLength + 2)
            observationStore.inspectResponse(message)
        }
    }

    private func finish(_ error: Error?) {
        guard !didFinish else { return }
        didFinish = true
        if let error {
            observationStore.record(.forwardingFailure, error: error)
        }
        connection.stateUpdateHandler = nil
        connection.cancel()
        flow.closeReadWithError(error)
        flow.closeWriteWithError(error)
        completion()
    }
}

@available(macOS 15.0, *)
final class UDPDNSFlowSession: DNSFlowSession {
    private static let maximumActiveQueries = 128
    private let flow: NEAppProxyUDPFlow
    private let queue: DispatchQueue
    private let observationStore: DNSObservationStore
    private let completion: () -> Void
    private var activeQueries: [UUID: UDPDNSQuery] = [:]
    private var didFinish = false

    init(
        flow: NEAppProxyUDPFlow,
        observationStore: DNSObservationStore,
        completion: @escaping () -> Void
    ) {
        self.flow = flow
        self.observationStore = observationStore
        self.completion = completion
        queue = DispatchQueue(label: "VPNRouter.UDPDNSFlow.\(UUID().uuidString)")
    }

    func start() {
        flow.open(withLocalFlowEndpoint: nil) { [weak self] error in
            guard let self else { return }
            self.queue.async {
                if let error {
                    self.finish(error)
                } else {
                    self.observationStore.record(.flowOpened)
                    self.readDatagrams()
                }
            }
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.finish(nil)
        }
    }

    private func readDatagrams() {
        guard !didFinish else { return }
        flow.readDatagrams { [weak self] datagrams, error in
            guard let self else { return }
            self.queue.async {
                if let error {
                    self.finish(error)
                    return
                }
                guard let datagrams, !datagrams.isEmpty else {
                    self.finish(nil)
                    return
                }
                guard self.activeQueries.count + datagrams.count <= Self.maximumActiveQueries else {
                    self.finish(DNSFlowSessionError.queryLimitExceeded)
                    return
                }

                for (data, endpoint) in datagrams {
                    let id = UUID()
                    let query = UDPDNSQuery(
                        data: data,
                        endpoint: endpoint,
                        flow: self.flow,
                        observationStore: self.observationStore,
                        queue: self.queue
                    ) { [weak self] in
                        self?.activeQueries[id] = nil
                    }
                    self.activeQueries[id] = query
                    query.start()
                }
                self.readDatagrams()
            }
        }
    }

    private func finish(_ error: Error?) {
        guard !didFinish else { return }
        didFinish = true
        if let error {
            observationStore.record(.forwardingFailure, error: error)
        }
        let queries = activeQueries.values
        activeQueries.removeAll()
        queries.forEach { $0.stop() }
        flow.closeReadWithError(error)
        flow.closeWriteWithError(error)
        completion()
    }
}

@available(macOS 15.0, *)
private final class UDPDNSQuery {
    private let data: Data
    private let endpoint: Network.NWEndpoint
    private let flow: NEAppProxyUDPFlow
    private let observationStore: DNSObservationStore
    private let queue: DispatchQueue
    private let completion: () -> Void
    private let connection: NWConnection
    private var didFinish = false

    init(
        data: Data,
        endpoint: Network.NWEndpoint,
        flow: NEAppProxyUDPFlow,
        observationStore: DNSObservationStore,
        queue: DispatchQueue,
        completion: @escaping () -> Void
    ) {
        self.data = data
        self.endpoint = endpoint
        self.flow = flow
        self.observationStore = observationStore
        self.queue = queue
        self.completion = completion

        let parameters = NWParameters.udp
        flow.setMetadata(on: parameters)
        connection = NWConnection(to: endpoint, using: parameters)
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.observationStore.record(.upstreamReady)
                self.send()
            case .failed(let error):
                self.finish(error: error)
            case .cancelled:
                self.finish(error: nil)
            default:
                break
            }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 10) { [weak self] in
            self?.finish(error: DNSFlowSessionError.queryTimedOut)
        }
    }

    func stop() {
        finish(error: nil)
    }

    private func send() {
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            self.queue.async {
                if error != nil {
                    self.finish(error: error)
                    return
                }
                self.connection.receiveMessage { [weak self] response, _, _, receiveError in
                    guard let self else { return }
                    self.queue.async {
                        guard receiveError == nil, let response, !response.isEmpty else {
                            self.finish(error: receiveError ?? DNSFlowSessionError.emptyResponse)
                            return
                        }
                        self.observationStore.record(.responseReceived)
                        self.observationStore.inspectResponse(response)
                        self.flow.writeDatagrams([(response, self.endpoint)]) { [weak self] writeError in
                            self?.queue.async {
                                if writeError == nil {
                                    self?.observationStore.record(.responseDelivered)
                                }
                                self?.finish(error: writeError)
                            }
                        }
                    }
                }
            }
        })
    }

    private func finish(error: Error?) {
        guard !didFinish else { return }
        didFinish = true
        if let error {
            observationStore.record(.forwardingFailure, error: error)
        }
        connection.stateUpdateHandler = nil
        connection.cancel()
        completion()
    }
}

private enum DNSFlowSessionError: LocalizedError {
    case queryLimitExceeded
    case queryTimedOut
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .queryLimitExceeded:
            "동시에 전달할 수 있는 DNS 질의 수를 초과했습니다."
        case .queryTimedOut:
            "DNS upstream 응답 시간이 초과되었습니다."
        case .emptyResponse:
            "DNS upstream이 빈 응답을 반환했습니다."
        }
    }
}
