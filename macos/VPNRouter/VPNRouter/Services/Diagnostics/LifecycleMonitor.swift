import AppKit
import Combine
import Foundation
import Network

@MainActor
final class LifecycleMonitor: ObservableObject {
    @Published private(set) var networkState = "확인 중"
    @Published private(set) var latestEvent = "앱 수명주기 이벤트가 아직 없습니다."
    @Published private(set) var sleepCount = 0
    @Published private(set) var wakeCount = 0
    @Published private(set) var networkChangeCount = 0

    private let pathMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(
        label: "VPNRouter.LifecycleMonitor",
        qos: .utility
    )
    private var observers: [NSObjectProtocol] = []

    init() {
        observeWorkspace()
        observeNetwork()
    }

    deinit {
        pathMonitor.cancel()
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
    }

    private func observeWorkspace() {
        let center = NSWorkspace.shared.notificationCenter
        observers.append(
            center.addObserver(
                forName: NSWorkspace.willSleepNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.sleepCount += 1
                    self?.latestEvent = "Mac이 잠자기 상태로 전환되었습니다."
                }
            }
        )
        observers.append(
            center.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.wakeCount += 1
                    self?.latestEvent = "Mac이 잠자기에서 깨어났습니다. VPN 상태를 다시 확인하세요."
                }
            }
        )
    }

    private func observeNetwork() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let state: String
            switch path.status {
            case .satisfied:
                state = path.isExpensive ? "사용 가능, 비용이 드는 연결" : "사용 가능"
            case .requiresConnection:
                state = "연결 필요"
            case .unsatisfied:
                state = "사용 불가"
            @unknown default:
                state = "알 수 없음"
            }

            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }
                networkState = state
                networkChangeCount += 1
                latestEvent = "기본 네트워크 경로가 변경되었습니다: \(state)."
            }
        }
        pathMonitor.start(queue: monitorQueue)
    }
}
