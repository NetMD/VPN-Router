import AppKit
import NetworkExtension

@MainActor
final class ActiveConnectionTerminationPolicy {
    static let shared = ActiveConnectionTerminationPolicy()

    private(set) var shouldKeepCoordinatorRunning = false
    private var retainedManager: NETunnelProviderManager?

    private init() {}

    func update(
        status: NEVPNStatus,
        manager: NETunnelProviderManager?
    ) {
        shouldKeepCoordinatorRunning =
            status == .connecting
                || status == .connected
                || status == .reasserting
                || status == .disconnecting
        retainedManager = shouldKeepCoordinatorRunning ? manager : nil
    }
}

final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(
        _ sender: NSApplication
    ) -> NSApplication.TerminateReply {
        guard ActiveConnectionTerminationPolicy.shared
                .shouldKeepCoordinatorRunning else {
            return .terminateNow
        }

        Self.closeMainWindows(in: sender)
        return .terminateCancel
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        if !flag {
            showMainWindow(in: sender)
        }
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard
            ActiveConnectionTerminationPolicy.shared.shouldKeepCoordinatorRunning,
            let application = notification.object as? NSApplication,
            !application.windows.contains(where: \.isVisible)
        else {
            return
        }

        showMainWindow(in: application)
    }

    private func showMainWindow(in application: NSApplication) {
        application.windows.first?.makeKeyAndOrderFront(nil)
        application.activate()
    }

    static func closeMainWindows(in application: NSApplication) {
        for window in application.windows where window.canBecomeMain {
            window.orderOut(nil)
        }
    }
}
