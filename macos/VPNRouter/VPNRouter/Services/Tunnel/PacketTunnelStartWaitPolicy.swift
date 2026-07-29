import Foundation

enum PacketTunnelStartState: Equatable {
    case invalid
    case disconnected
    case connecting
    case connected
    case reasserting
    case disconnecting
}

enum PacketTunnelStartDecision: Equatable {
    case wait
    case connected
    case failed
}

struct PacketTunnelStartWaitPolicy {
    let initialDisconnectedPollLimit: Int
    private(set) var hasObservedProgress = false

    init(initialDisconnectedPollLimit: Int = 50) {
        precondition(initialDisconnectedPollLimit >= 0)
        self.initialDisconnectedPollLimit = initialDisconnectedPollLimit
    }

    mutating func evaluate(
        _ state: PacketTunnelStartState,
        pollIndex: Int
    ) -> PacketTunnelStartDecision {
        switch state {
        case .connected:
            return .connected
        case .connecting, .reasserting:
            hasObservedProgress = true
            return .wait
        case .disconnecting:
            return .failed
        case .invalid, .disconnected:
            if hasObservedProgress || pollIndex >= initialDisconnectedPollLimit {
                return .failed
            }
            return .wait
        }
    }
}
