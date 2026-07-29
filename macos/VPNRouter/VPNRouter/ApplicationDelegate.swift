import AppKit

@MainActor
final class ActiveConnectionTerminationPolicy {
    static let shared = ActiveConnectionTerminationPolicy()

    var shouldKeepCoordinatorRunning = false

    private init() {}
}

final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(
        _ sender: NSApplication
    ) -> NSApplication.TerminateReply {
        guard ActiveConnectionTerminationPolicy.shared
                .shouldKeepCoordinatorRunning else {
            return .terminateNow
        }

        sender.hide(nil)
        return .terminateCancel
    }
}
