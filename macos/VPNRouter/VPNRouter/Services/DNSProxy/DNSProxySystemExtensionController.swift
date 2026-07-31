import Foundation
import Combine
import SystemExtensions

@MainActor
final class DNSProxySystemExtensionController: NSObject, ObservableObject {
    @Published private(set) var message = "DNS Proxy System Extension을 아직 활성화하지 않았습니다."
    @Published private(set) var isRequestInFlight = false

    private var activeRequest: OSSystemExtensionRequest?
    private var activationContinuation: CheckedContinuation<Void, Error>?

    func requestActivation() {
        Task {
            do {
                try await activateForConsumerConnection()
            } catch {
                // The published message contains the bounded result for developer diagnostics.
            }
        }
    }

    func activateForConsumerConnection() async throws {
        guard SystemExtensionInstallLocationPolicy.allowsActivation(
            for: Bundle.main.bundleURL
        ) else {
            message = SystemExtensionInstallLocationPolicy.activationGuidance
            throw DNSProxySystemExtensionError.unsupportedParentBundleLocation
        }
        guard !isRequestInFlight else {
            throw DNSProxySystemExtensionError.requestAlreadyInFlight
        }
        isRequestInFlight = true
        message = "DNS Proxy System Extension 활성화를 요청하고 있습니다."

        try await withCheckedThrowingContinuation { continuation in
            activationContinuation = continuation
            let request = OSSystemExtensionRequest.activationRequest(
                forExtensionWithIdentifier: TunnelIdentifiers.dnsProxySystemExtensionBundleIdentifier,
                queue: .main
            )
            request.delegate = self
            activeRequest = request
            OSSystemExtensionManager.shared.submitRequest(request)
        }
    }

    private func finish(
        with message: String,
        result: Result<Void, Error>
    ) {
        self.message = message
        isRequestInFlight = false
        activeRequest = nil
        let continuation = activationContinuation
        activationContinuation = nil
        continuation?.resume(with: result)
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
            finish(
                with: "DNS Proxy System Extension이 준비되었습니다. DNS Proxy 구성은 연결 과정에서만 활성화됩니다.",
                result: .success(())
            )
        case .willCompleteAfterReboot:
            finish(
                with: "DNS Proxy System Extension 활성화를 완료하려면 Mac을 재시동해야 합니다.",
                result: .failure(DNSProxySystemExtensionError.restartRequired)
            )
        @unknown default:
            finish(
                with: "DNS Proxy System Extension 요청이 알 수 없는 결과로 끝났습니다.",
                result: .failure(DNSProxySystemExtensionError.unknownResult)
            )
        }
    }

    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        let nsError = error as NSError
        finish(
            with: "DNS Proxy System Extension을 활성화하지 못했습니다: \(nsError.domain) \(nsError.code) — \(nsError.localizedDescription)",
            result: .failure(error)
        )
    }
}

private enum DNSProxySystemExtensionError: LocalizedError {
    case unsupportedParentBundleLocation
    case requestAlreadyInFlight
    case restartRequired
    case unknownResult

    var errorDescription: String? {
        switch self {
        case .unsupportedParentBundleLocation:
            SystemExtensionInstallLocationPolicy.activationGuidance
        case .requestAlreadyInFlight:
            "DNS Proxy System Extension 활성화 요청이 이미 진행 중입니다."
        case .restartRequired:
            "DNS Proxy System Extension을 사용하려면 Mac을 재시동해야 합니다."
        case .unknownResult:
            "DNS Proxy System Extension 활성화 결과를 확인할 수 없습니다."
        }
    }
}
