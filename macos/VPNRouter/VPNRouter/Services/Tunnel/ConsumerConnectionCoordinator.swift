import Combine
import Foundation

enum ConsumerConnectionStage: String, Codable, CaseIterable, Sendable {
    case idle
    case preflighting
    case activatingDNSProxyExtension
    case preparingPacketTunnel
    case startingPacketTunnel
    case enablingDNSProxy
    case publishingTargets
    case verifyingDNSProxy
    case armingSafetyMonitor
    case ready
    case disconnecting
}

enum ConsumerConnectionState: Equatable, Sendable {
    case idle
    case running(ConsumerConnectionStage)
    case ready
    case failed(stage: ConsumerConnectionStage, code: String)

    var stage: ConsumerConnectionStage {
        switch self {
        case .idle:
            .idle
        case .running(let stage):
            stage
        case .ready:
            .ready
        case .failed(let stage, _):
            stage
        }
    }

    var failureCode: String? {
        guard case .failed(_, let code) = self else {
            return nil
        }
        return code
    }

    var isReady: Bool {
        self == .ready
    }

    var isStarting: Bool {
        guard case .running(let stage) = self else {
            return false
        }
        return stage != .disconnecting
    }
}

struct ConsumerConnectionStepError: LocalizedError, Equatable, Sendable {
    let code: String
    let message: String

    init(code: String, message: String) {
        self.code = Self.normalizedCode(code)
        self.message = message
    }

    var errorDescription: String? {
        message
    }

    private static func normalizedCode(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-_")
        let normalized = value
            .lowercased()
            .unicodeScalars
            .map { allowed.contains($0) ? Character(String($0)) : "-" }
        let compact = String(normalized)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        return String(compact.prefix(64)).isEmpty ? "unexpected" : String(compact.prefix(64))
    }
}

@MainActor
final class ConsumerConnectionCoordinator: ObservableObject {
    typealias ThrowingStep = @MainActor () async throws -> Void
    typealias CleanupStep = @MainActor () async -> Void

    struct Operations {
        let preflight: ThrowingStep
        let activateDNSProxyExtension: ThrowingStep
        let preparePacketTunnel: ThrowingStep
        let startPacketTunnel: ThrowingStep
        let enableDNSProxy: ThrowingStep
        let publishTargets: ThrowingStep
        let verifyDNSProxy: ThrowingStep
        let armSafetyMonitor: ThrowingStep
        let disableOwnedDNSProxy: CleanupStep
        let stopPacketTunnel: CleanupStep
    }

    @Published private(set) var state: ConsumerConnectionState = .idle
    @Published private(set) var failureMessage: String?

    func connect(using operations: Operations) async {
        guard !state.isStarting, state != .ready else {
            return
        }

        failureMessage = nil
        var packetTunnelStartAttempted = false
        var dnsProxyEnableAttempted = false

        do {
            try await run(.preflighting, operations.preflight)
            try await run(
                .activatingDNSProxyExtension,
                operations.activateDNSProxyExtension
            )
            try await run(.preparingPacketTunnel, operations.preparePacketTunnel)

            packetTunnelStartAttempted = true
            try await run(.startingPacketTunnel, operations.startPacketTunnel)

            dnsProxyEnableAttempted = true
            try await run(.enablingDNSProxy, operations.enableDNSProxy)
            try await run(.publishingTargets, operations.publishTargets)
            try await run(.verifyingDNSProxy, operations.verifyDNSProxy)
            try await run(.armingSafetyMonitor, operations.armSafetyMonitor)
            state = .ready
        } catch {
            let failedStage = state.stage
            failureMessage = error.localizedDescription
            if dnsProxyEnableAttempted {
                await operations.disableOwnedDNSProxy()
            }
            if packetTunnelStartAttempted {
                await operations.stopPacketTunnel()
            }
            state = .failed(
                stage: failedStage,
                code: (error as? ConsumerConnectionStepError)?.code ?? "unexpected"
            )
        }
    }

    func disconnect(
        disableOwnedDNSProxy: CleanupStep,
        stopPacketTunnel: CleanupStep
    ) async {
        guard state != .running(.disconnecting) else {
            return
        }
        state = .running(.disconnecting)
        failureMessage = nil
        await disableOwnedDNSProxy()
        await stopPacketTunnel()
        state = .idle
    }

    func restoreReadyState() {
        failureMessage = nil
        state = .ready
    }

    func recordFailure(stage: ConsumerConnectionStage, code: String) {
        failureMessage = nil
        state = .failed(
            stage: stage,
            code: ConsumerConnectionStepError(code: code, message: code).code
        )
    }

    func reset() {
        failureMessage = nil
        state = .idle
    }

    private func run(
        _ stage: ConsumerConnectionStage,
        _ operation: ThrowingStep
    ) async throws {
        state = .running(stage)
        try await operation()
    }
}
