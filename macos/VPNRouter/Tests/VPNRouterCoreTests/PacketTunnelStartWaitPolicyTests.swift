import Testing
@testable import VPNRouterConnection

struct PacketTunnelStartWaitPolicyTests {
    @Test
    func initialDisconnectedStateWaitsForAsynchronousTransition() {
        var policy = PacketTunnelStartWaitPolicy(
            initialDisconnectedPollLimit: 3
        )

        #expect(policy.evaluate(.disconnected, pollIndex: 0) == .wait)
        #expect(policy.evaluate(.invalid, pollIndex: 1) == .wait)
        #expect(policy.evaluate(.connecting, pollIndex: 2) == .wait)
        #expect(policy.evaluate(.connected, pollIndex: 3) == .connected)
    }

    @Test
    func disconnectedAfterProgressFailsImmediately() {
        var policy = PacketTunnelStartWaitPolicy(
            initialDisconnectedPollLimit: 50
        )

        #expect(policy.evaluate(.connecting, pollIndex: 0) == .wait)
        #expect(policy.evaluate(.disconnected, pollIndex: 1) == .failed)
    }

    @Test
    func disconnectedWithoutProgressFailsAfterInitialGrace() {
        var policy = PacketTunnelStartWaitPolicy(
            initialDisconnectedPollLimit: 2
        )

        #expect(policy.evaluate(.disconnected, pollIndex: 0) == .wait)
        #expect(policy.evaluate(.disconnected, pollIndex: 1) == .wait)
        #expect(policy.evaluate(.disconnected, pollIndex: 2) == .failed)
    }

    @Test
    func disconnectingAlwaysFails() {
        var policy = PacketTunnelStartWaitPolicy()

        #expect(policy.evaluate(.disconnecting, pollIndex: 0) == .failed)
    }
}
