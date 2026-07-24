import Combine
import Foundation
import NetworkExtension

@MainActor
final class DNSProxyConfigurationController: ObservableObject {
    @Published private(set) var message = "DNS Proxy 진단 구성 상태를 아직 확인하지 않았습니다."
    @Published private(set) var isRequestInFlight = false
    @Published private(set) var isEnabled = false

    func refresh(expectedBundleIdentifier: String) async {
        guard !isRequestInFlight else { return }
        isRequestInFlight = true
        defer { isRequestInFlight = false }

        do {
            let manager = NEDNSProxyManager.shared()
            try await loadPreferences(for: manager)
            let ownership = ownership(
                of: manager.providerProtocol,
                expectedBundleIdentifier: expectedBundleIdentifier
            )
            isEnabled = ownership == .vpnRouter && manager.isEnabled
            switch ownership {
            case .none:
                message = "VPN Router DNS Proxy 진단 구성이 없습니다."
            case .vpnRouter:
                message = manager.isEnabled
                    ? "VPN Router DNS Proxy 진단 구성이 활성 상태입니다."
                    : "VPN Router DNS Proxy 진단 구성이 비활성 상태입니다."
            case .other:
                message = "VPN Router가 소유하지 않은 DNS Proxy 구성이 감지되어 변경하지 않았습니다."
            }
        } catch {
            isEnabled = false
            message = failureMessage(prefix: "DNS Proxy 상태를 읽지 못했습니다", error: error)
        }
    }

    func enableForDiagnostics(expectedBundleIdentifier: String) async {
        guard !isRequestInFlight else { return }
        isRequestInFlight = true
        defer { isRequestInFlight = false }

        do {
            let manager = NEDNSProxyManager.shared()
            try await loadPreferences(for: manager)
            guard ownership(
                of: manager.providerProtocol,
                expectedBundleIdentifier: expectedBundleIdentifier
            ) != .other else {
                throw DNSProxyConfigurationError.configurationNotOwned
            }

            let providerProtocol = NEDNSProxyProviderProtocol()
            providerProtocol.providerBundleIdentifier = expectedBundleIdentifier
            providerProtocol.providerConfiguration = [
                DNSProxyProviderConfigurationKeys.schemaVersion: 1,
                DNSProxyProviderConfigurationKeys.mode: DNSProxyProviderConfigurationKeys.diagnosticMode
            ]
            manager.localizedDescription = "VPN Router DNS Discovery (Diagnostic)"
            manager.providerProtocol = providerProtocol
            manager.isEnabled = true
            try await savePreferences(for: manager)
            try await loadPreferences(for: manager)

            guard ownership(
                of: manager.providerProtocol,
                expectedBundleIdentifier: expectedBundleIdentifier
            ) == .vpnRouter, manager.isEnabled else {
                throw DNSProxyConfigurationError.enableVerificationFailed
            }

            isEnabled = true
            message = "DNS Proxy 진단 구성이 활성화되었습니다. 문제가 생기면 즉시 끄기를 누르세요."
        } catch {
            isEnabled = false
            message = failureMessage(prefix: "DNS Proxy 진단 구성을 활성화하지 못했습니다", error: error)
        }
    }

    func disable(expectedBundleIdentifier: String, allowOwnedRemovalFallback: Bool) async {
        guard !isRequestInFlight else { return }
        isRequestInFlight = true
        defer { isRequestInFlight = false }

        let manager = NEDNSProxyManager.shared()
        do {
            try await loadPreferences(for: manager)
            switch ownership(
                of: manager.providerProtocol,
                expectedBundleIdentifier: expectedBundleIdentifier
            ) {
            case .none:
                isEnabled = false
                message = "끄기 작업이 필요하지 않습니다. VPN Router DNS Proxy 구성이 없습니다."
                return
            case .other:
                throw DNSProxyConfigurationError.configurationNotOwned
            case .vpnRouter:
                break
            }

            manager.isEnabled = false
            do {
                try await savePreferences(for: manager)
                try await loadPreferences(for: manager)
                guard !manager.isEnabled else {
                    throw DNSProxyConfigurationError.disableVerificationFailed
                }
                isEnabled = false
                message = "VPN Router DNS Proxy 진단 구성을 비활성화했습니다."
            } catch {
                guard allowOwnedRemovalFallback else {
                    throw error
                }
                try await loadPreferences(for: manager)
                guard ownership(
                    of: manager.providerProtocol,
                    expectedBundleIdentifier: expectedBundleIdentifier
                ) == .vpnRouter else {
                    throw DNSProxyConfigurationError.configurationNotOwned
                }
                try await removePreferences(for: manager)
                isEnabled = false
                message = "비활성화 저장에 실패하여 VPN Router 소유 DNS Proxy 진단 구성을 제거했습니다."
            }
        } catch {
            message = failureMessage(prefix: "DNS Proxy 진단 구성을 끄지 못했습니다", error: error)
        }
    }

    private func ownership(
        of providerProtocol: NEDNSProxyProviderProtocol?,
        expectedBundleIdentifier: String
    ) -> DNSProxyConfigurationOwnership {
        DNSProxyConfigurationPolicy.ownership(
            hasConfiguration: providerProtocol != nil,
            providerBundleIdentifier: providerProtocol?.providerBundleIdentifier,
            expectedBundleIdentifier: expectedBundleIdentifier
        )
    }

    private func failureMessage(prefix: String, error: Error) -> String {
        let nsError = error as NSError
        return "\(prefix): \(nsError.domain) \(nsError.code) — \(nsError.localizedDescription)"
    }

    private func loadPreferences(for manager: NEDNSProxyManager) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            manager.loadFromPreferences { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func savePreferences(for manager: NEDNSProxyManager) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            manager.saveToPreferences { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func removePreferences(for manager: NEDNSProxyManager) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            manager.removeFromPreferences { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}

private enum DNSProxyConfigurationError: LocalizedError {
    case configurationNotOwned
    case enableVerificationFailed
    case disableVerificationFailed

    var errorDescription: String? {
        switch self {
        case .configurationNotOwned:
            return "VPN Router가 소유하지 않은 DNS Proxy 구성은 변경할 수 없습니다."
        case .enableVerificationFailed:
            return "저장 후 DNS Proxy 활성 상태를 확인할 수 없습니다."
        case .disableVerificationFailed:
            return "저장 후 DNS Proxy 비활성 상태를 확인할 수 없습니다."
        }
    }
}

private enum DNSProxyProviderConfigurationKeys {
    static let schemaVersion = "schemaVersion"
    static let mode = "mode"
    static let diagnosticMode = "phase3-diagnostic"
}
