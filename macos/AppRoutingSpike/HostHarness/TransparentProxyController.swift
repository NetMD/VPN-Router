@preconcurrency import NetworkExtension
import Foundation

struct TransparentProxyManagerHandle: @unchecked Sendable {
    let manager: NETransparentProxyManager

    var providerBundleIdentifier: String? {
        (manager.protocolConfiguration as? NETunnelProviderProtocol)?.providerBundleIdentifier
    }
}

protocol TransparentProxyManagerStoring: Sendable {
    func loadAll() async throws -> [TransparentProxyManagerHandle]
    func makeManager() async -> TransparentProxyManagerHandle
    func save(_ handle: TransparentProxyManagerHandle) async throws
    func reload(_ handle: TransparentProxyManagerHandle) async throws
    func remove(_ handle: TransparentProxyManagerHandle) async throws
}

private struct SystemTransparentProxyManagerStore: TransparentProxyManagerStoring {
    private struct ManagerList: @unchecked Sendable {
        let values: [NETransparentProxyManager]
    }

    func loadAll() async throws -> [TransparentProxyManagerHandle] {
        let managerList: ManagerList = try await withCheckedThrowingContinuation { continuation in
            NETransparentProxyManager.loadAllFromPreferences { managers, error in
                if error != nil {
                    continuation.resume(throwing: SpikeHostServiceError.proxyConfigurationFailed)
                } else {
                    continuation.resume(returning: ManagerList(values: managers ?? []))
                }
            }
        }
        return managerList.values.map(TransparentProxyManagerHandle.init(manager:))
    }

    func makeManager() async -> TransparentProxyManagerHandle {
        TransparentProxyManagerHandle(manager: NETransparentProxyManager())
    }

    func save(_ handle: TransparentProxyManagerHandle) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            handle.manager.saveToPreferences { error in
                if error != nil {
                    continuation.resume(throwing: SpikeHostServiceError.proxyConfigurationFailed)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    func reload(_ handle: TransparentProxyManagerHandle) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            handle.manager.loadFromPreferences { error in
                if error != nil {
                    continuation.resume(throwing: SpikeHostServiceError.proxyConfigurationFailed)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    func remove(_ handle: TransparentProxyManagerHandle) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            handle.manager.removeFromPreferences { error in
                if error != nil {
                    continuation.resume(throwing: SpikeHostServiceError.proxyCleanupFailed)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}

public actor TransparentProxyController: TransparentProxyControlling {
    private let providerBundleIdentifier: String
    private let localizedDescription: String
    private let managerStore: any TransparentProxyManagerStoring
    private var activeManager: TransparentProxyManagerHandle?

    public init(
        providerBundleIdentifier: String,
        localizedDescription: String = "앱 라우팅 기술 시험"
    ) {
        self.providerBundleIdentifier = providerBundleIdentifier
        self.localizedDescription = localizedDescription
        managerStore = SystemTransparentProxyManagerStore()
    }

    init(
        providerBundleIdentifier: String,
        localizedDescription: String = "앱 라우팅 기술 시험",
        managerStore: any TransparentProxyManagerStoring
    ) {
        self.providerBundleIdentifier = providerBundleIdentifier
        self.localizedDescription = localizedDescription
        self.managerStore = managerStore
    }

    public func start() async throws {
        let existingManager = try await loadOwnedManager()
        let handle: TransparentProxyManagerHandle
        if let existingManager {
            handle = existingManager
        } else {
            handle = await managerStore.makeManager()
        }
        let manager = handle.manager
        let configuration = NETunnelProviderProtocol()
        configuration.providerBundleIdentifier = providerBundleIdentifier
        configuration.serverAddress = "로컬 기술 시험"
        manager.protocolConfiguration = configuration
        manager.localizedDescription = localizedDescription
        manager.isEnabled = true

        do {
            try await managerStore.save(handle)
            // NetworkExtension does not guarantee that a newly saved manager is
            // immediately loaded into this instance. Starting before this reload
            // can fail on a real Mac with "configuration has not been loaded yet".
            try await managerStore.reload(handle)
            try manager.connection.startVPNTunnel()
            activeManager = handle
        } catch {
            throw SpikeHostServiceError.proxyStartFailed
        }
    }

    public func startAndWaitUntilConnected(timeout: Duration) async throws {
        try await start()
        try await waitForStatus([.connected], timeout: timeout, failure: .proxyStartFailed)
    }

    public func stopProvider() async throws {
        let manager = activeManager
        let ownedManager: TransparentProxyManagerHandle?
        if let manager {
            ownedManager = manager
        } else {
            ownedManager = try await loadOwnedManager()
        }
        guard let ownedManager else {
            return
        }
        ownedManager.manager.connection.stopVPNTunnel()
        ownedManager.manager.isEnabled = false

        do {
            try await managerStore.save(ownedManager)
        } catch {
            throw SpikeHostServiceError.proxyCleanupFailed
        }
    }

    public func stopAndWaitUntilDisconnected(timeout: Duration) async throws {
        try await stopProvider()
        try await waitForStatus([.disconnected, .invalid], timeout: timeout, failure: .proxyCleanupFailed)
    }

    public func removeOwnedConfiguration() async throws {
        _ = try await removeAllOwnedConfigurations()
    }

    public func removeAllOwnedConfigurations() async throws -> Int {
        do {
            let managers = try await loadOwnedManagers()
            for manager in managers {
                try await managerStore.remove(manager)
            }
            activeManager = nil
            guard try await loadOwnedManagers().isEmpty else {
                throw SpikeHostServiceError.proxyCleanupFailed
            }
            return managers.count
        } catch {
            throw SpikeHostServiceError.proxyCleanupFailed
        }
    }

    public func ownedConfigurationCount() async throws -> Int {
        try await loadOwnedManagers().count
    }

    private func loadOwnedManager() async throws -> TransparentProxyManagerHandle? {
        try await loadOwnedManagers().first
    }

    private func loadOwnedManagers() async throws -> [TransparentProxyManagerHandle] {
        try await managerStore.loadAll().filter { handle in
            handle.providerBundleIdentifier == providerBundleIdentifier
        }
    }

    private func waitForStatus(_ accepted: Set<NEVPNStatus>, timeout: Duration,
                               failure: SpikeHostServiceError) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if let status = activeManager?.manager.connection.status, accepted.contains(status) { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw failure
    }

}
