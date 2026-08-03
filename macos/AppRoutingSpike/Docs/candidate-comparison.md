# macOS 앱 라우팅 후보 비교

이 문서는 MDM 없는 소비자 배포 범위에서 후보를 좁힌 P0 결과입니다. 자동 검사나 컴파일은 실제 Network Extension 활성화 근거가 아닙니다.

| 후보 | 구성·권한 경계 | 앱 신원 | 전달 능력 | 이번 판정 |
|---|---|---|---|---|
| Packet Tunnel + `appRules` | 앱별 VPN 구성은 MDM 관리 경로 | OS 앱 규칙 | IP 패킷 전달 | MDM 없는 범위에서 구현하지 않음 |
| App Proxy | 관리형 앱 계층 프로필 필요 | 관리 앱 규칙 | TCP·UDP 흐름 | MDM 없는 범위에서 구현하지 않음 |
| Transparent Proxy | 시스템 확장과 App Proxy 계열 권한, 사용자 승인 필요 | 흐름 수신 뒤 signing identifier·Team ID·audit token 지정 요구 조건 확인 | TCP·UDP 흐름을 받지만 기존 WireGuard Packet Tunnel 직접 연결점은 확인되지 않음 | P0~P2 조건부 진행 |
| Content Filter | Filter 권한 | 흐름 metadata | 허용·차단만 제공 | 라우팅 수단으로 구현하지 않음 |
| 기존 Packet Tunnel | 기존 제품 권한 | 앱 구분 없음 | 목적지 IPv4 `/32` 중심 | 단독 앱 선택 후보 아님 |

공식 기준은 Apple의 [NETunnelProviderManager](https://developer.apple.com/documentation/networkextension/netunnelprovidermanager), [NEAppProxyProviderManager](https://developer.apple.com/documentation/networkextension/neappproxyprovidermanager), [NETransparentProxyProvider](https://developer.apple.com/documentation/networkextension/netransparentproxyprovider), [Network Extension 권한](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.networking.networkextension), [TN3134](https://developer.apple.com/documentation/technotes/tn3134-network-extension-provider-deployment), [TN3120](https://developer.apple.com/documentation/technotes/tn3120-expected-use-cases-for-network-extension-packet-tunnel-providers)입니다.

P2 시제품은 선택 흐름을 `SelectedFlowTransport.unsupported`로 안전하게 닫습니다. 일반 인터넷 연결을 WireGuard 전달 증거로 기록하지 않습니다.
