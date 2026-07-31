import Foundation

enum DNSProxyConfigurationOwnership: Equatable {
    case none
    case vpnRouter
    case other
}

enum DNSProxyRuntimeState: Equatable {
    case unknown
    case absent
    case ownedDisabled
    case ownedEnabled
    case other
    case unreadable
}

enum DNSProxyMonitorDecision: Equatable {
    case healthy
    case waitForHealthRetry
    case failSafe
}

enum SystemExtensionInstallLocationPolicy {
    static let applicationsDirectory = URL(fileURLWithPath: "/Applications", isDirectory: true)

    static func allowsActivation(for appBundleURL: URL) -> Bool {
        let standardizedBundleURL = appBundleURL.standardizedFileURL
        return standardizedBundleURL.pathExtension == "app"
            && standardizedBundleURL.deletingLastPathComponent()
                == applicationsDirectory.standardizedFileURL
    }

    static let activationGuidance =
        "시스템 확장을 활성화하려면 VPN Router.app을 응용 프로그램 폴더에 설치한 뒤, 설치된 앱을 다시 열어 주세요. 현재 앱은 응용 프로그램 폴더 밖에서 실행 중입니다."
}

enum BrowserSecureDNSMode: Equatable {
    case off
    case automatic
    case secure
    case unset
    case unsupported(String)

    init(rawValue: String?) {
        guard let normalizedValue = rawValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(), !normalizedValue.isEmpty else {
            self = .unset
            return
        }

        switch normalizedValue {
        case "off":
            self = .off
        case "automatic":
            self = .automatic
        case "secure":
            self = .secure
        default:
            self = .unsupported(normalizedValue)
        }
    }
}

struct BrowserSecureDNSState: Equatable {
    let displayName: String
    let isInstalled: Bool
    let mode: BrowserSecureDNSMode
}

enum EncryptedDNSPreflightDisposition: Equatable {
    case compatible
    case needsManualVerification
    case blocked
}

struct EncryptedDNSPreflightResult: Equatable {
    let disposition: EncryptedDNSPreflightDisposition
    let browserStates: [BrowserSecureDNSState]

    var allowsDNSProxyActivation: Bool {
        disposition != .blocked
    }
}

enum EncryptedDNSPreflightPolicy {
    static func evaluate(
        browserStates: [BrowserSecureDNSState]
    ) -> EncryptedDNSPreflightResult {
        let installedStates = browserStates.filter(\.isInstalled)

        if installedStates.contains(where: { state in
            switch state.mode {
            case .automatic, .secure, .unsupported:
                return true
            case .off, .unset:
                return false
            }
        }) {
            return EncryptedDNSPreflightResult(
                disposition: .blocked,
                browserStates: browserStates
            )
        }

        return EncryptedDNSPreflightResult(
            disposition: installedStates.contains(where: { $0.mode == .unset })
                ? .needsManualVerification
                : .compatible,
            browserStates: browserStates
        )
    }
}

enum DNSProxyConfigurationPolicy {
    static func ownership(
        hasConfiguration: Bool,
        providerBundleIdentifier: String?,
        localizedDescription: String?,
        hasProviderConfiguration: Bool,
        isEnabled: Bool,
        expectedBundleIdentifier: String,
        expectedLegacyDescription: String?
    ) -> DNSProxyConfigurationOwnership {
        guard hasConfiguration else {
            return .none
        }
        if providerBundleIdentifier == expectedBundleIdentifier {
            return .vpnRouter
        }

        let normalizedDescription = localizedDescription?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let hasDescription = normalizedDescription?.isEmpty == false
        if providerBundleIdentifier == nil,
           !hasProviderConfiguration,
           !isEnabled {
            if hasDescription == false || normalizedDescription == expectedLegacyDescription {
                return .none
            }
        }

        return .other
    }

    static func runtimeState(
        ownership: DNSProxyConfigurationOwnership,
        isEnabled: Bool
    ) -> DNSProxyRuntimeState {
        switch ownership {
        case .none:
            return .absent
        case .vpnRouter:
            return isEnabled ? .ownedEnabled : .ownedDisabled
        case .other:
            return .other
        }
    }

    static func monitorDecision(
        runtimeState: DNSProxyRuntimeState,
        consecutiveHealthFailures: Int,
        healthFailureLimit: Int = 3,
        tunnelInterfaceSetChanged: Bool = false
    ) -> DNSProxyMonitorDecision {
        precondition(healthFailureLimit > 0)

        guard runtimeState == .ownedEnabled, !tunnelInterfaceSetChanged else {
            return .failSafe
        }
        return consecutiveHealthFailures >= healthFailureLimit
            ? .failSafe
            : consecutiveHealthFailures > 0
                ? .waitForHealthRetry
                : .healthy
    }
}
