import Foundation
import NetworkExtension

struct DNSProxyCapabilityProbeResult: Sendable {
    let preferenceAccessAvailable: Bool
    let configurationExists: Bool
    let configurationEnabled: Bool
    let message: String
}

enum DNSProxyCapabilityProbe {
    static func run() async -> DNSProxyCapabilityProbeResult {
        let manager = NEDNSProxyManager.shared()

        do {
            try await loadPreferences(for: manager)
            let configurationExists = manager.providerProtocol != nil
            return DNSProxyCapabilityProbeResult(
                preferenceAccessAvailable: true,
                configurationExists: configurationExists,
                configurationEnabled: configurationExists && manager.isEnabled,
                message: configurationExists
                    ? "DNS Proxy preferences를 읽었습니다. VPN Router용 구성이 존재합니다."
                    : "DNS Proxy preferences를 읽었습니다. VPN Router용 구성은 아직 없습니다."
            )
        } catch {
            return DNSProxyCapabilityProbeResult(
                preferenceAccessAvailable: false,
                configurationExists: false,
                configurationEnabled: false,
                message: "DNS Proxy preferences에 접근하지 못했습니다: \(error.localizedDescription)"
            )
        }
    }

    private static func loadPreferences(for manager: NEDNSProxyManager) async throws {
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
}
