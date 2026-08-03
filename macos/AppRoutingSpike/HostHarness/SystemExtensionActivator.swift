@preconcurrency import SystemExtensions
import Foundation

public actor SystemExtensionActivator: SystemExtensionActivating {
    private final class RequestDelegate: NSObject, OSSystemExtensionRequestDelegate {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Void, Error>?

        init(continuation: CheckedContinuation<Void, Error>) {
            self.continuation = continuation
        }

        func request(
            _ request: OSSystemExtensionRequest,
            actionForReplacingExtension existing: OSSystemExtensionProperties,
            withExtension extension: OSSystemExtensionProperties
        ) -> OSSystemExtensionRequest.ReplacementAction {
            .replace
        }

        func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
            // 승인 화면은 macOS와 사용자가 직접 처리합니다.
        }

        func request(
            _ request: OSSystemExtensionRequest,
            didFinishWithResult result: OSSystemExtensionRequest.Result
        ) {
            finish(with: .success(()))
        }

        func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
            finish(with: .failure(SpikeHostServiceError.extensionActivationFailed))
        }

        private func finish(with result: Result<Void, Error>) {
            lock.lock()
            let current = continuation
            continuation = nil
            lock.unlock()
            current?.resume(with: result)
        }
    }

    private let extensionIdentifier: String
    private let requestQueue: DispatchQueue
    private var activeDelegate: RequestDelegate?

    public init(
        extensionIdentifier: String,
        requestQueue: DispatchQueue = .main
    ) {
        self.extensionIdentifier = extensionIdentifier
        self.requestQueue = requestQueue
    }

    public func activate() async throws {
        try await withCheckedThrowingContinuation { continuation in
            let delegate = RequestDelegate(continuation: continuation)
            activeDelegate = delegate

            let request = OSSystemExtensionRequest.activationRequest(
                forExtensionWithIdentifier: extensionIdentifier,
                queue: requestQueue
            )
            request.delegate = delegate
            OSSystemExtensionManager.shared.submitRequest(request)
        }
        activeDelegate = nil
    }
}
