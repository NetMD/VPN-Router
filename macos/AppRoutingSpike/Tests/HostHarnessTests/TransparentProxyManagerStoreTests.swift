@preconcurrency import NetworkExtension
import XCTest
@testable import AppRoutingSpikeHost

final class TransparentProxyManagerStoreTests: XCTestCase {
    private enum StoreFailure: Error {
        case removalFailed
    }

    private actor FakeManagerStore: TransparentProxyManagerStoring {
        private var managers: [TransparentProxyManagerHandle]
        private let failingRemovalNumber: Int?
        private let retainRemovedManagers: Bool
        private var removalAttempts = 0
        private var loadCalls = 0
        private var operations: [String] = []

        init(
            managers: [TransparentProxyManagerHandle],
            failingRemovalNumber: Int? = nil,
            retainRemovedManagers: Bool = false
        ) {
            self.managers = managers
            self.failingRemovalNumber = failingRemovalNumber
            self.retainRemovedManagers = retainRemovedManagers
        }

        func loadAll() async throws -> [TransparentProxyManagerHandle] {
            loadCalls += 1
            return managers
        }

        func makeManager() async -> TransparentProxyManagerHandle {
            Self.makeHandle(providerBundleIdentifier: nil)
        }

        func save(_ handle: TransparentProxyManagerHandle) async throws {
            operations.append("save")
        }

        func reload(_ handle: TransparentProxyManagerHandle) async throws {
            operations.append("reload")
        }

        func remove(_ handle: TransparentProxyManagerHandle) async throws {
            removalAttempts += 1
            if removalAttempts == failingRemovalNumber {
                throw StoreFailure.removalFailed
            }
            guard !retainRemovedManagers else { return }
            managers.removeAll { $0.manager === handle.manager }
        }

        func snapshot() -> (providerIdentifiers: [String?], removalAttempts: Int, loadCalls: Int) {
            (managers.map(\.providerBundleIdentifier), removalAttempts, loadCalls)
        }

        func operationSnapshot() -> [String] {
            operations
        }

        nonisolated static func makeHandle(providerBundleIdentifier: String?) -> TransparentProxyManagerHandle {
            let manager = NETransparentProxyManager()
            if let providerBundleIdentifier {
                let configuration = NETunnelProviderProtocol()
                configuration.providerBundleIdentifier = providerBundleIdentifier
                manager.protocolConfiguration = configuration
            }
            return TransparentProxyManagerHandle(manager: manager)
        }
    }

    private let ownedIdentifier = "com.example.vpnrouter.approutingspike.proxy"
    private let otherIdentifier = "com.example.unrelated.proxy"

    func testCleanupWithNoOwnedManagerIsStableAndRequeriesZero() async throws {
        let store = FakeManagerStore(managers: [])
        let controller = makeController(store: store)

        let removedCount = try await controller.removeAllOwnedConfigurations()
        let remainingCount = try await controller.ownedConfigurationCount()
        XCTAssertEqual(removedCount, 0)
        XCTAssertEqual(remainingCount, 0)

        let snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.removalAttempts, 0)
        XCTAssertEqual(snapshot.loadCalls, 3)
    }

    func testCleanupRemovesSingleOwnedManagerAndRequeriesZero() async throws {
        let store = FakeManagerStore(managers: [makeHandle(ownedIdentifier)])
        let controller = makeController(store: store)

        let removedCount = try await controller.removeAllOwnedConfigurations()
        let remainingCount = try await controller.ownedConfigurationCount()
        XCTAssertEqual(removedCount, 1)
        XCTAssertEqual(remainingCount, 0)

        let snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.providerIdentifiers.count, 0)
        XCTAssertEqual(snapshot.removalAttempts, 1)
    }

    func testCleanupRemovesAllOwnedManagersPreservesOtherProviderAndIsIdempotent() async throws {
        let store = FakeManagerStore(managers: [
            makeHandle(ownedIdentifier),
            makeHandle(otherIdentifier),
            makeHandle(ownedIdentifier)
        ])
        let controller = makeController(store: store)

        let firstRemovedCount = try await controller.removeAllOwnedConfigurations()
        let firstRemainingCount = try await controller.ownedConfigurationCount()
        XCTAssertEqual(firstRemovedCount, 2)
        XCTAssertEqual(firstRemainingCount, 0)
        var snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.providerIdentifiers.compactMap { $0 }, [otherIdentifier])
        XCTAssertEqual(snapshot.removalAttempts, 2)

        let secondRemovedCount = try await controller.removeAllOwnedConfigurations()
        let secondRemainingCount = try await controller.ownedConfigurationCount()
        XCTAssertEqual(secondRemovedCount, 0)
        XCTAssertEqual(secondRemainingCount, 0)
        snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.providerIdentifiers.compactMap { $0 }, [otherIdentifier])
        XCTAssertEqual(snapshot.removalAttempts, 2)
    }

    func testLegacySingleRemovalEntryPointAlsoRemovesEveryOwnedManager() async throws {
        let store = FakeManagerStore(managers: [
            makeHandle(ownedIdentifier),
            makeHandle(otherIdentifier),
            makeHandle(ownedIdentifier)
        ])
        let controller = makeController(store: store)

        try await controller.removeOwnedConfiguration()
        let remainingCount = try await controller.ownedConfigurationCount()

        let snapshot = await store.snapshot()
        XCTAssertEqual(remainingCount, 0)
        XCTAssertEqual(snapshot.providerIdentifiers.compactMap { $0 }, [otherIdentifier])
        XCTAssertEqual(snapshot.removalAttempts, 2)
    }

    func testPartialRemovalFailureCannotReportCleanupSuccess() async throws {
        let store = FakeManagerStore(
            managers: [makeHandle(ownedIdentifier), makeHandle(ownedIdentifier)],
            failingRemovalNumber: 2
        )
        let controller = makeController(store: store)

        await assertCleanupFailure {
            _ = try await controller.removeAllOwnedConfigurations()
        }

        let snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.removalAttempts, 2)
        XCTAssertEqual(snapshot.providerIdentifiers.compactMap { $0 }, [ownedIdentifier])
    }

    func testResidualOwnedManagerAfterSuccessfulRemoveCallCannotReportCleanupSuccess() async throws {
        let store = FakeManagerStore(
            managers: [makeHandle(ownedIdentifier)],
            retainRemovedManagers: true
        )
        let controller = makeController(store: store)

        await assertCleanupFailure {
            _ = try await controller.removeAllOwnedConfigurations()
        }

        let snapshot = await store.snapshot()
        XCTAssertEqual(snapshot.removalAttempts, 1)
        XCTAssertEqual(snapshot.loadCalls, 2)
        XCTAssertEqual(snapshot.providerIdentifiers.compactMap { $0 }, [ownedIdentifier])
    }

    func testStartReloadsSavedManagerBeforeAttemptingConnection() async {
        let store = FakeManagerStore(managers: [])
        let controller = makeController(store: store)

        do {
            try await controller.start()
        } catch {
            // An in-memory NETransparentProxyManager has no real system session;
            // this test only proves the required save -> reload ordering.
        }

        let operations = await store.operationSnapshot()
        XCTAssertEqual(operations, ["save", "reload"])
    }

    private func makeController(store: FakeManagerStore) -> TransparentProxyController {
        TransparentProxyController(
            providerBundleIdentifier: ownedIdentifier,
            managerStore: store
        )
    }

    private func makeHandle(_ providerBundleIdentifier: String) -> TransparentProxyManagerHandle {
        FakeManagerStore.makeHandle(providerBundleIdentifier: providerBundleIdentifier)
    }

    private func assertCleanupFailure(
        operation: () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await operation()
            XCTFail("정리 실패가 성공으로 처리됐습니다.", file: file, line: line)
        } catch let error as SpikeHostServiceError {
            XCTAssertEqual(error, .proxyCleanupFailed, file: file, line: line)
        } catch {
            XCTFail("예상하지 못한 오류 형식입니다.", file: file, line: line)
        }
    }
}
