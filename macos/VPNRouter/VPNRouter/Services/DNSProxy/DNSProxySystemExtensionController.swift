import Foundation
import Combine
import SystemExtensions

@MainActor
final class DNSProxySystemExtensionController: NSObject, ObservableObject {
    @Published private(set) var message = "DNS Proxy System Extension을 아직 활성화하지 않았습니다."
    @Published private(set) var isRequestInFlight = false

    private var activeRequest: OSSystemExtensionRequest?

    func requestActivation() {
        guard !isRequestInFlight else {
            return
        }

        isRequestInFlight = true
        message = "DNS Proxy System Extension 활성화를 요청하고 있습니다."

        let request = OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: TunnelIdentifiers.dnsProxySystemExtensionBundleIdentifier,
            queue: .main
        )
        request.delegate = self
        activeRequest = request
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    private func finish(with message: String) {
        self.message = message
        isRequestInFlight = false
        activeRequest = nil
    }
}

extension DNSProxySystemExtensionController: OSSystemExtensionRequestDelegate {
    func request(
        _ request: OSSystemExtensionRequest,
        actionForReplacingExtension existing: OSSystemExtensionProperties,
        withExtension ext: OSSystemExtensionProperties
    ) -> OSSystemExtensionRequest.ReplacementAction {
        .replace
    }

    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        message = "시스템 설정에서 VPN Router DNS Proxy System Extension 승인이 필요합니다. 이 단계는 DNS Proxy 구성을 활성화하지 않습니다."
    }

    func request(
        _ request: OSSystemExtensionRequest,
        didFinishWithResult result: OSSystemExtensionRequest.Result
    ) {
        switch result {
        case .completed:
            finish(with: "DNS Proxy System Extension이 활성화되었습니다. DNS Proxy 구성은 아직 비활성 상태입니다.")
        case .willCompleteAfterReboot:
            finish(with: "DNS Proxy System Extension 활성화는 Mac을 재시동한 뒤 완료됩니다. DNS Proxy 구성은 아직 비활성 상태입니다.")
        @unknown default:
            finish(with: "DNS Proxy System Extension 요청이 알 수 없는 결과로 끝났습니다.")
        }
    }

    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        let nsError = error as NSError
        finish(
            with: "DNS Proxy System Extension을 활성화하지 못했습니다: \(nsError.domain) \(nsError.code) — \(nsError.localizedDescription)"
        )
    }
}
