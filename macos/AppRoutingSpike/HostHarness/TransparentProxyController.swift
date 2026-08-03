@preconcurrency import NetworkExtension
import Foundation

public actor TransparentProxyController: TransparentProxyControlling {
    private struct ManagerList: @unchecked Sendable {
        let values: [NETransparentProxyManager]
    }

    private let providerBundleIdentifier: String
    private let localizedDescription: String
    private var activeManager: NETransparentProxyManager?

    public init(
        providerBundleIdentifier: String,
        localizedDescription: String = "앱 라우팅 기술 시험"
    ) {
        self.providerBundleIdentifier = providerBundleIdentifier
        self.localizedDescription = localizedDescription
    }

    public func start() async throws {
        let manager = try await loadOwnedManager() ?? NETransparentProxyManager()
        let configuration = NETunnelProviderProtocol()
        configuration.providerBundleIdentifier = providerBundleIdentifier
        configuration.serverAddress = "로컬 기술 시험"
        manager.protocolConfiguration = configuration
        manager.localizedDescription = localizedDescription
        manager.isEnabled = true

        do {
            try await save(manager)
            try manager.connection.startVPNTunnel()
            activeManager = manager
        } catch {
            throw SpikeHostServiceError.proxyStartFailed
        }
    }

    public func stopProvider() async throws {
        let manager = activeManager
        let ownedManager: NETransparentProxyManager?
        if let manager {
            ownedManager = manager
        } else {
            ownedManager = try await loadOwnedManager()
        }
        guard let ownedManager else {
            return
        }
        ownedManager.connection.stopVPNTunnel()
        ownedManager.isEnabled = false

        do {
            try await save(ownedManager)
        } catch {
            throw SpikeHostServiceError.proxyCleanupFailed
        }
    }

    public func removeOwnedConfiguration() async throws {
        let manager = activeManager
        activeManager = nil
        let ownedManager: NETransparentProxyManager?
        if let manager {
            ownedManager = manager
        } else {
            ownedManager = try await loadOwnedManager()
        }
        guard let ownedManager else {
            return
        }
        do {
            try await remove(ownedManager)
        } catch {
            throw SpikeHostServiceError.proxyCleanupFailed
        }
    }

    private func loadOwnedManager() async throws -> NETransparentProxyManager? {
        let managerList: ManagerList = try await withCheckedThrowingContinuation { continuation in
            NETransparentProxyManager.loadAllFromPreferences { managers, error in
                if error != nil {
                    continuation.resume(throwing: SpikeHostServiceError.proxyConfigurationFailed)
                } else {
                    continuation.resume(returning: ManagerList(values: managers ?? []))
                }
            }
        }
        return managerList.values.first { manager in
            guard let configuration = manager.protocolConfiguration as? NETunnelProviderProtocol else {
                return false
            }
            return configuration.providerBundleIdentifier == providerBundleIdentifier
        }
    }

    private func save(_ manager: NETransparentProxyManager) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            manager.saveToPreferences { error in
                if error != nil {
                    continuation.resume(throwing: SpikeHostServiceError.proxyConfigurationFailed)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func remove(_ manager: NETransparentProxyManager) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            manager.removeFromPreferences { error in
                if error != nil {
                    continuation.resume(throwing: SpikeHostServiceError.proxyCleanupFailed)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}
