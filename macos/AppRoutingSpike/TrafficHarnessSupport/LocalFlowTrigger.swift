import Foundation
import Network

public enum HarnessFlowTransport: String, Sendable { case tcp, udp }

public struct HarnessActionResult: Equatable, Sendable {
    public let completed: Bool
    public let observedAt: Date
    public init(completed: Bool, observedAt: Date = Date()) {
        self.completed = completed
        self.observedAt = observedAt
    }
}

/// 공개 시험 주소에 새 흐름만 만들며 주소·payload·응답은 밖으로 내보내지 않습니다.
public actor LocalFlowTrigger {
    public init() {}

    public func triggerTCP() async -> HarnessActionResult { await trigger(.tcp) }
    public func triggerUDP() async -> HarnessActionResult { await trigger(.udp) }

    public func trigger(_ transport: HarnessFlowTransport) async -> HarnessActionResult {
        let parameters: NWParameters = transport == .tcp ? .tcp : .udp
        let connection = NWConnection(host: "192.0.2.1", port: 443, using: parameters)
        connection.start(queue: .global(qos: .utility))
        if transport == .udp {
            connection.send(content: Data([0]), completion: .contentProcessed { _ in })
        }
        try? await Task.sleep(for: .milliseconds(250))
        connection.cancel()
        return HarnessActionResult(completed: true)
    }
}
