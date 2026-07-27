import AppKit
import CoreFoundation
import Foundation

struct EncryptedDNSPreflightService {
    private struct Browser {
        let displayName: String
        let applicationBundleIdentifiers: [String]
        let policyDomain: String
    }

    private let browsers = [
        Browser(
            displayName: "Google Chrome",
            applicationBundleIdentifiers: ["com.google.Chrome"],
            policyDomain: "com.google.Chrome"
        ),
        Browser(
            displayName: "Microsoft Edge",
            applicationBundleIdentifiers: ["com.microsoft.edgemac", "com.microsoft.Edge"],
            policyDomain: "com.microsoft.Edge"
        )
    ]

    func evaluate() -> EncryptedDNSPreflightResult {
        EncryptedDNSPreflightPolicy.evaluate(
            browserStates: browsers.map { browser in
                BrowserSecureDNSState(
                    displayName: browser.displayName,
                    isInstalled: browser.applicationBundleIdentifiers.contains {
                        NSWorkspace.shared.urlForApplication(
                            withBundleIdentifier: $0
                        ) != nil
                    },
                    mode: BrowserSecureDNSMode(
                        rawValue: effectivePolicyValue(
                            key: "DnsOverHttpsMode",
                            domain: browser.policyDomain
                        )
                    )
                )
            }
        )
    }

    func message(for result: EncryptedDNSPreflightResult) -> String {
        let installedStates = result.browserStates.filter(\.isInstalled)
        let browserMessage: String

        if installedStates.isEmpty {
            browserMessage = "확인 대상 Chrome·Edge가 설치되어 있지 않습니다."
        } else {
            browserMessage = installedStates.map { state in
                "\(state.displayName): \(modeDescription(state.mode))"
            }.joined(separator: " / ")
        }

        let actionMessage: String
        switch result.disposition {
        case .compatible:
            actionMessage = "확인된 브라우저 DoH 정책 충돌은 없습니다."
        case .needsManualVerification:
            actionMessage = "정책이 없는 브라우저의 보안 DNS 설정은 앱에서 확인할 수 없으므로 직접 확인해야 합니다."
        case .blocked:
            actionMessage = "DoH가 켜졌거나 알 수 없는 정책 값이 있어 DNS Proxy 진단을 시작하지 않습니다."
        }

        return """
        \(browserMessage) \(actionMessage) iCloud Private Relay 상태는 공개 API로 판정하지 \
        않으며, 현재 네트워크의 ‘IP 주소 추적 제한’을 직접 확인해야 합니다. 어떤 설정도 \
        자동으로 변경하지 않았습니다.
        """
    }

    private func effectivePolicyValue(key: String, domain: String) -> String? {
        CFPreferencesCopyAppValue(
            key as CFString,
            domain as CFString
        ) as? String
    }

    private func modeDescription(_ mode: BrowserSecureDNSMode) -> String {
        switch mode {
        case .off:
            return "DoH 정책 꺼짐"
        case .automatic:
            return "DoH 자동 정책"
        case .secure:
            return "DoH 보안 정책"
        case .unset:
            return "DoH 정책 없음(수동 확인 필요)"
        case .unsupported:
            return "알 수 없는 DoH 정책"
        }
    }
}
