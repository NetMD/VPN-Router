import SwiftUI

@main
struct HostHarnessApp: App {
    @StateObject private var viewModel: SpikeViewModel

    init() {
        let model: SpikeViewModel
        do {
            let configuration = try SpikeHostConfiguration()
            model = SpikeViewModel(
                systemExtensionActivator: SystemExtensionActivator(
                    extensionIdentifier: configuration.extensionIdentifier
                ),
                proxyController: TransparentProxyController(
                    providerBundleIdentifier: configuration.extensionIdentifier
                ),
                xpcClient: SpikeXPCClient(
                    machServiceName: configuration.machServiceName
                ),
                selectedTestAppSelector: SelectedTestAppSelector()
            )
        } catch {
            model = SpikeViewModel(
                systemExtensionActivator: UnavailableSystemExtensionActivator(),
                proxyController: UnavailableTransparentProxyController(),
                xpcClient: UnavailableSpikeXPCClient(),
                selectedTestAppSelector: SelectedTestAppSelector(),
                configurationError: "시험 앱 구성을 확인하지 못했습니다."
            )
        }
        _viewModel = StateObject(wrappedValue: model)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
        .windowResizability(.contentMinSize)
    }
}
