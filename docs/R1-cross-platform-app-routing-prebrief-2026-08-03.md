# R1 프리브리프 — 앱 선택 VPN 라우팅 기술 검증 (2026-08-03)

> 프로젝트: vpn_router · 대상 차수(예정): R1 · 대상 버전: 미정(v0.2.0은 후보) · 성격: 파이프라인 시작 전 준비 문서(독립)
> 조회 소스: 운영 DB/로그 · 코드 · 체크리스트 · 저널 · 차수 기록 · 백로그 · RAG · Microsoft/Apple 공식 문서

## 0. 한 줄 요약

선택한 앱의 통신만 VPN으로 보내는 기능을 두 플랫폼에 같은 의미로 제공하려 합니다. Apple의 `appRules` 기반 per-app VPN에는 MDM(기기 관리)이 필요합니다. 다만 Transparent Proxy 같은 다른 Network Extension 조합으로 MDM 없는 macOS 제품을 만들 수 있는지는 공식 문서만으로 아직 기각할 수 없습니다. 따라서 이번에는 제품 구현이 아니라 Windows WFP와 macOS 대안의 기술 가능성을 나란히 검증합니다.

## 1. 운영 실측 (DB·로그 직접 조회, 2026-08-03 KST)

- 운영 DB 조회는 입력에서 생략되었습니다. `(DB 조회 생략 — 입력 계약)`
- 운영 로그 경로가 없습니다. `(로그 조회 불가 — 경로 없음)`
- 저장소와 PMO 경로의 의미 기반 검색 결과가 모두 비어 있었습니다. `(RAG 조회 불가 — 현재 인덱스 결과 0건)`
- PMO 경로에서 체크리스트, 저널, 회고, 누적 인사이트, 백로그를 찾지 못했습니다. `(해당 없음 — 신규 차수)`

## 2. 현재 구조 (CONFIRMED 사실 — file:line)

### 공통 제품 상태

- v0.1.0 범위는 사이트 규칙, IPv4 호스트 경로, DNS 보호, 실패 시 정리입니다. 앱 기준 라우팅은 다음 버전 이후로 미뤄져 있습니다. (`docs/v0.1.0-release-plan.md:32`, `docs/v0.1.0-release-plan.md:52`)
- 두 플랫폼은 사용자에게 같은 라우팅·안전 의미를 보여야 합니다. 낮은 수준의 네트워킹, 권한, 저장소, 서명, 배포 코드는 플랫폼별로 나눠 둬야 합니다. (`docs/platform-parity-contract.md:5`)
- 공통 진단은 버전이 있는 형식과 제한된 개수·상태·시각·실패 코드만 내보냅니다. 도메인, 주소, DNS 내용, 설정, 키, 제한 없는 로그는 내보내지 않습니다. (`docs/platform-parity-contract.md:21`)
- `v0.1.0` 태그는 커밋 `6e6fbb5`에 실제로 존재하며 현재 `HEAD`의 조상입니다. 반면 릴리스 계획에는 아직 체크되지 않은 실제 기기·서명·Windows 재검사·태그 항목이 있고, 동등성 감사도 공개 동등성이 증명되지 않았다고 적습니다. 태그 유무와 문서상 게이트 상태가 서로 맞지 않습니다. `(출처: git tag/show/merge-base, 2026-08-03 KST; docs/v0.1.0-release-plan.md:166; docs/platform-parity-audit.md:129)`

### Windows 현재 경로와 소비처

- 연결 요청에는 프로필 ID와 `DomainRule` 목록만 있습니다. 앱 규칙 필드는 없습니다. (`windows/VpnRouter.Ipc/Contracts/ConnectionCommands.cs:5`)
- UI는 화면의 사이트 목록을 `DomainRule`로 만들고 `ConnectRequest`에 넣습니다. (`windows/VpnRouter.App/MainWindow.xaml.cs:163`, `windows/VpnRouter.App/MainWindow.xaml.cs:751`)
- 서비스는 사이트 규칙을 확장하고 DNS로 IPv4를 찾은 뒤 WireGuard를 연결합니다. 그 다음 VPN 인터페이스에 호스트 경로를 추가합니다. (`windows/VpnRouter.Service/Connection/ConnectionOrchestrator.cs:26`)
- 경로 추가는 대상 IPv4 `/32`와 VPN 인터페이스 인덱스를 사용한 `New-NetRoute`입니다. 이 경로는 프로세스별 규칙이 아니라 대상 주소별 시스템 경로입니다. (`windows/VpnRouter.Service/Networking/WindowsRouteManager.cs:168`)
- DNS Proxy가 새 대상 주소를 관찰하면 같은 `IRouteManager.AddHostRoutesAsync`를 다시 사용합니다. 앱 규칙을 추가하면 최초 연결뿐 아니라 이 동적 소비처도 함께 다뤄야 합니다. (`windows/VpnRouter.Service/Networking/WindowsDnsProxyController.cs:412`)
- 진단 DTO는 관리 경로 수와 DNS 관찰 수를 전달합니다. 앱 규칙 수, 적용 앱 수, 차단·우회 수는 아직 없습니다. (`windows/VpnRouter.Ipc/Contracts/ConnectionCommands.cs:30`)
- 현재 코드 검색에서 Windows 앱 라우팅 구현은 확인되지 않았습니다. 직접 소비처는 `ConnectRequest`뿐 아니라 연결 계획 검증 DTO와 처리기, 사이트 규칙 저장/조회 IPC, 연결 상태, 복구 상태, 의존성 등록, 휴대용 빌드까지 이어집니다. (`windows/VpnRouter.Ipc/Contracts/ConnectionCommands.cs:44`, `windows/VpnRouter.Ipc/Contracts/ConnectionCommands.cs:56`, `windows/VpnRouter.Service/Ipc/IpcCommandHandler.cs:226`, `windows/VpnRouter.Service/Ipc/IpcCommandHandler.cs:287`, `windows/VpnRouter.Service/Program.cs:35`)

### macOS 현재 경로와 소비처

- 사이트 규칙은 별도 JSON 파일에 저장됩니다. 현재 스키마 버전은 1이며 앱 규칙 저장소는 없습니다. (`macos/VPNRouter/VPNRouter/Services/Rules/DomainRuleStore.swift:3`)
- 연결 전 검사는 선택 프로필과 사이트 목록이 모두 있어야 통과합니다. 앱만 선택한 연결은 현재 시작할 수 없습니다. (`macos/VPNRouter/VPNRouter/ContentView.swift:1825`)
- 터널 설정 payload에는 프로필과 사이트 기반 `DomainRoutePlan`만 들어갑니다. (`macos/VPNRouter/VPNRouter/Services/Tunnel/TunnelProfileConfiguration.swift:4`)
- Packet Tunnel은 계획에 든 IPv4만 `includedRoutes`에 넣습니다. WireGuard peer의 `allowedIPs`도 같은 목록으로 바꿉니다. (`macos/VPNRouter/PacketTunnel/PacketTunnelProvider.swift:131`, `macos/VPNRouter/PacketTunnel/PacketTunnelProvider.swift:475`)
- 연결 순서는 사전 확인, DNS Proxy 시스템 확장 확인, Packet Tunnel 준비·시작, DNS Proxy 활성화, 대상 게시, 소유권 확인, 안전 감시 순입니다. 어느 단계가 실패해도 VPN Router 소유 상태만 역순으로 정리합니다. (`macos/VPNRouter/VPNRouter/Services/Tunnel/ConsumerConnectionCoordinator.swift:113`, `macos/VPNRouter/VPNRouter/Services/Tunnel/ConsumerConnectionCoordinator.swift:132`)
- 진단 스키마 2는 선택 사이트 수와 계획 경로 수를 담지만 앱 정보는 담지 않습니다. (`macos/VPNRouter/VPNRouter/Shared/Diagnostics/TroubleshootingReport.swift:3`, `macos/VPNRouter/VPNRouter/Shared/Diagnostics/TroubleshootingReport.swift:55`)
- Host App, Packet Tunnel, DNS Proxy에는 각각 현재 기능에 필요한 Network Extension 권한이 있습니다. 임의 앱 선택 가능성을 증명하는 별도 설정은 확인되지 않았습니다. (`macos/VPNRouter/VPNRouter/VPNRouter.entitlements:9`, `macos/VPNRouter/PacketTunnel/PacketTunnel.entitlements:9`, `macos/VPNRouter/DNSProxyExtension/DNSProxyExtension.entitlements:5`)
- 현재 코드 검색에서 `NEAppRule` 구현은 확인되지 않았습니다. 초안이 적은 범위 외에도 `AppBackgroundWork`, `DomainRoutePlanService`, 정적·동적 경로 병합과 새로고침, provider 메시지, DNS Proxy 관찰 설정이 사이트 계획을 직접 소비합니다. (`macos/VPNRouter/VPNRouter/Services/AppBackgroundWork.swift:67`, `macos/VPNRouter/VPNRouter/Services/Rules/DomainRoutePlanService.swift:15`, `macos/VPNRouter/VPNRouter/ContentView.swift:2156`, `macos/VPNRouter/VPNRouter/ContentView.swift:2588`)

### 공식 플랫폼 사실

- Microsoft의 사용자 모드 `FwpmConnectionPolicyAdd0`는 outbound 연결에 프로세스 기준 정책을 추가할 수 있습니다. `ALE_APP_ID`와 `ALE_PACKAGE_ID` 조건, IP 버전별 호출, 정책 가중치, 다음 홉 인터페이스 **LUID**를 사용합니다. 현재 코드는 WireGuard 인터페이스의 **index**만 받아 `/32` 시스템 경로를 만드므로 LUID 획득과 정책 우선순위는 새로 구현·실측해야 합니다. (`windows/VpnRouter.Service/Connection/ConnectionOrchestrator.cs:51`, `windows/VpnRouter.Service/Networking/WindowsRouteManager.cs:175`; [Microsoft Learn — FwpmConnectionPolicyAdd0](https://learn.microsoft.com/en-us/windows/win32/api/fwpmu/nf-fwpmu-fwpmconnectionpolicyadd0))
- WFP의 ALE 계층은 앱의 정규화된 전체 경로와 사용자 보안 정보를 기준으로 연결을 구분할 수 있습니다. 경로 변경, 앱 업데이트, helper 프로세스는 앱 규칙 안정성 검사 대상입니다. ([Microsoft Learn — Application Layer Enforcement](https://learn.microsoft.com/en-us/windows/win32/fwp/application-layer-enforcement--ale-))
- Windows VPNv2 CSP도 데스크톱 앱 경로나 Store 앱의 Package Family Name을 앱 기준으로 쓸 수 있습니다. 다만 이는 기기 관리 서버가 VPN 프로필을 설정하는 경로이므로 현재 휴대용 앱의 첫 선택지로 확정하지 않습니다. ([Microsoft Learn — VPNv2 CSP](https://learn.microsoft.com/en-us/windows/client-management/mdm/vpnv2-csp))
- Apple은 `appRules` 기반 per-app VPN 구성이 MDM 등록과 관리 앱 연결을 통해 만들어진다고 명시합니다. App Proxy 구성도 `com.apple.vpn.managed.applayer` payload에서만 만들어집니다. 개발용 `NETestAppMapping`은 Distribution 프로비저닝에서 효력이 없습니다. 따라서 **MDM 없는 배포에서 `appRules`/App Proxy per-app 구성을 쓰는 길은 지원되지 않습니다(CONFIRMED, 이 API 경로에 한함)**. ([Apple Developer — NETunnelProviderManager](https://developer.apple.com/documentation/networkextension/netunnelprovidermanager), [Apple Developer — NEAppProxyProviderManager](https://developer.apple.com/documentation/networkextension/neappproxyprovidermanager), [Apple Developer — Routing your VPN network traffic](https://developer.apple.com/documentation/networkextension/routing-your-vpn-network-traffic))
- Transparent Proxy는 IP·포트·TCP/UDP·방향 규칙으로 흐름을 받으며, 받은 흐름의 메타데이터에는 원본 앱의 signing identifier가 있습니다. Content Filter는 공식 verdict가 허용·차단·일시 정지 중심입니다. 이 문서들만으로는 “사용자가 고른 임의 앱의 TCP/UDP/QUIC/DNS를 기존 WireGuard Packet Tunnel로 누수 없이 전달”이 지원된다고도, 불가능하다고도 확정할 수 없습니다. **macOS 소비자 경로는 미확인**이며 실제 서명 빌드 기술 스파이크가 필요합니다. ([Apple Developer — NETransparentProxyNetworkSettings](https://developer.apple.com/documentation/networkextension/netransparentproxynetworksettings), [Apple Developer — sourceAppSigningIdentifier](https://developer.apple.com/documentation/networkextension/neflowmetadata/sourceappsigningidentifier), [Apple Developer — Content filter providers](https://developer.apple.com/documentation/networkextension/content-filter-providers), [Apple Developer — TN3120](https://developer.apple.com/documentation/technotes/tn3120-expected-use-cases-for-network-extension-packet-tunnel-providers))
- Mac App Store 밖의 Network Extension은 Developer ID용 권한과 프로비저닝 프로필이 필요합니다. 시스템 확장은 Host App과 같은 Team ID로 서명하고 공증해야 합니다. ([Apple Developer — Network Extensions Entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.networking.networkextension), [Apple Developer — System Extensions](https://developer.apple.com/documentation/systemextensions), [Apple Developer — Notarizing macOS software](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution))

## 3. 이번 목표 / 범위

- **할 것**:
  - 사용자가 고른 앱의 모든 통신만 VPN으로 보내고, 고르지 않은 앱은 기본 인터넷을 쓰는 공통 제품 의미를 정의합니다.
  - 기존 사이트 선택 라우팅을 유지합니다.
  - 앱 규칙과 사이트 규칙을 함께 켰을 때의 합치기 규칙을 결정합니다.
  - Windows에서는 `FwpmConnectionPolicyAdd0` 기반 프로세스 라우팅을 가장 먼저 시험합니다.
  - macOS에서는 두 갈래를 구분합니다. MDM 관리형 `appRules` proof와 MDM 없는 Transparent Proxy 중심 대안 proof입니다. 후자는 기존 Packet Tunnel과의 결합, TCP/UDP/QUIC/DNS 전 범위, 재귀와 누수를 실제 서명 빌드에서 확인합니다.
  - 앱 본체와 helper/업데이터/하위 프로세스를 하나의 제품 앱으로 묶는 식별 규칙을 만듭니다.
  - TCP, UDP, QUIC, IPv4, IPv6, DNS, 루프백, 새 연결과 기존 연결, sleep/wake, 앱 업데이트, VPN 재연결을 검사합니다.
  - 공통 진단에는 앱 이름·경로·번들 ID 원문을 넣지 않고 제한된 개수와 결과 코드만 넣습니다.
- **안 할 것(이번 비범위)**:
  - v0.1.0의 남은 릴리스 문서, 코드, 검사 결과를 바꾸거나 완료로 표시하지 않습니다.
  - Windows에서 서명되지 않은 커널 드라이버를 배포하지 않습니다. 첫 스파이크에서 필요성이 증명되기 전에는 WFP callout driver를 만들지 않습니다.
  - macOS에서 MDM 도입을 사용자 동의 없이 제품 전제로 정하지 않습니다.
  - 전체 IPv6 사이트 분할 라우팅, 모바일, OpenVPN/L2TP, 자동 업데이트를 함께 넣지 않습니다.
  - 실제 WireGuard `.conf`나 개인 키를 읽거나 출력하지 않습니다.
  - 제3자 DNS, VPN, 광고 차단, 보안 제품을 멈추거나 설정을 바꾸지 않습니다.

## 4. 설계 방향 (잠정)

### 공통 제품 계약

- 앱 규칙은 실행 중인 PID가 아니라 안정된 앱 신원으로 저장합니다. Windows 후보는 정규화된 실행 파일 경로와 패키지 ID입니다. macOS 후보는 signing identifier와 designated requirement입니다.
- 앱 표시 이름과 아이콘은 UI용입니다. 정책의 실제 키로 쓰지 않습니다.
- 선택 앱이 종료되거나 업데이트되어 신원이 달라지면 그 앱 규칙만 `재확인 필요`로 바꿉니다. 다른 앱이나 제3자 제품은 건드리지 않습니다.
- 기본 안전 원칙은 fail-closed입니다. 선택 앱을 VPN으로 보낸다고 표시한 상태에서 앱별 경로 소유권을 증명하지 못하면 `Connected`를 보여 주지 않습니다. 다만 사용자가 고르지 않은 앱의 기본 인터넷은 유지합니다.
- 진단 스키마 3 후보는 `selectedAppCount`, `resolvedAppCount`, `unresolvedAppCount`, `appPolicyState`, `sitePolicyState`, `compositionMode`, `failureCode`, 시각만 공유합니다. 앱 경로·번들 ID·실행 중 프로세스·목적지는 넣지 않습니다.

### 앱 규칙과 사이트 규칙 결합 후보

| 후보 | 선택 앱 | 선택하지 않은 앱 | 장점 | 주요 위험 |
|---|---|---|---|---|
| **합집합** | 모든 목적지를 VPN으로 보냄 | 선택 사이트만 VPN으로 보냄 | 새 요구와 기존 사이트 기능을 함께 보존 | 선택하지 않은 앱도 일부 VPN을 쓰므로 “선택한 앱만”이라는 문구와 충돌할 수 있음 |
| **앱 우선** | 모든 목적지를 VPN으로 보냄 | 항상 기본 인터넷 사용 | “선택한 앱만”을 가장 엄격히 따름 | 사이트 규칙이 켜져 있어도 선택하지 않은 앱에는 적용되지 않아 기존 의미가 약해짐 |
| **교집합** | 선택 사이트만 VPN으로 보냄 | 기본 인터넷 사용 | 가장 좁은 변경 | 선택 앱의 모든 통신을 VPN으로 보낸다는 핵심 요구를 만족하지 못함 |
| **명시적 모드** | 사용자가 합집합/앱 우선을 고름 | 모드에 따름 | 의미가 분명함 | 첫 버전 UI와 테스트 조합이 크게 늘어남 |

- 요구사항 원문과 일치하는 기본안은 **앱 우선**입니다. 앱 규칙이 하나 이상 활성화되면 선택하지 않은 앱은 사이트와 관계없이 일반 인터넷을 써야 합니다.
- 기존 사이트 기능은 앱 규칙이 0개일 때 기존 사이트 모드로 유지할 수 있습니다. 합집합은 선택하지 않은 앱도 선택 사이트에서 VPN을 쓰므로, 사용자가 요구한 “선택한 앱의 통신만”과 충돌합니다. 사용자가 명시적으로 의미를 바꾸지 않는 한 권장하지 않습니다.

### 기본 상태표

| 활성 앱 규칙 | 사이트 규칙 | 기본 동작 | 사이트 규칙 상태 | 시작 차단 여부 |
|---:|---:|---|---|---|
| 0개 | 0개 | 연결을 시작하지 않고 선택 안내 | 비활성 | 제품 구현에서는 차단. 기술 스파이크는 가짜 규칙 fixture로 진행 가능 |
| 0개 | 1개 이상 | 현재와 같은 사이트 모드. 모든 앱에서 선택 사이트만 VPN | 활성 | 차단 아님 |
| 1개 이상 | 0개 | 앱 우선 모드. 선택 앱의 모든 통신만 VPN, 나머지 앱은 일반 인터넷 | 없음 | 차단 아님. 단, 플랫폼 proof 통과 필요 |
| 1개 이상 | 1개 이상 | 앱 우선 모드. 선택 앱의 모든 통신만 VPN, 나머지 앱은 사이트와 관계없이 일반 인터넷 | 저장·표시는 유지하되 라우팅에는 미적용 | 차단 아님. 이 상태표를 바꾸려면 사용자 결정 필요 |

- 기술 스파이크의 기본값은 위 표입니다. 사용자가 합집합을 명시적으로 고르지 않는 한 앱 규칙이 하나라도 있으면 앱 우선으로 봅니다.
- “기존 사이트 기능 보존”은 사이트 규칙과 UI를 없애지 않고, 앱 규칙 0개에서 현재 동작을 그대로 유지한다는 뜻으로 고정합니다. 앱 규칙이 활성화된 동안 사이트 규칙은 삭제하지 않고 잠시 적용하지 않습니다.

### 파이프라인 분리

#### A. 기술 스파이크 파이프라인 — 두 플랫폼 병렬 진행

1. **공통 의미 고정**: 위 상태표를 시험 계약으로 사용합니다. 실제 사용자 앱·키 대신 가짜 앱과 정리된 WireGuard fixture를 씁니다.
2. **Windows proof**: 앱 신원 수집과 `FwpmConnectionPolicyAdd0`를 현재 elevated backend에서 시험합니다. interface index→LUID, IPv4/IPv6, TCP/UDP/QUIC/DNS, 정책 가중치, BFE 권한, 새 연결, 동적 세션 수명, portable publish를 확인합니다. ([Microsoft Learn — Object Management](https://learn.microsoft.com/en-us/windows/win32/fwp/object-management); `windows/VpnRouter.Launcher/Program.cs:152`, `docs/windows-next-session.md:136`)
3. **Windows 복구 proof**: backend/UI 종료, 재부팅, WireGuard 인터페이스 교체, 앱 업데이트 때 VPN Router 소유 정책만 정리되는지 확인합니다.
4. **macOS 후보 비교**: (a) MDM `appRules`+Packet Tunnel, (b) MDM 없는 Transparent Proxy에서 source app 식별 후 자체 WireGuard 전달, (c) 그 밖의 Apple 공식 Network Extension 조합을 작은 prototype으로 비교합니다. Content Filter는 라우팅 수단으로 가정하지 않고 허용·차단 능력만 확인합니다.
5. **macOS 실제 서명 proof**: 임의의 서명된 제3자 시험 앱과 helper를 골라 TCP, UDP/QUIC, DNS, IPv4/IPv6, 기존 연결, sleep/wake, 다른 VPN 전환을 확인합니다. 선택하지 않은 앱과 VPN 제어 경로가 일반 인터넷을 유지하는지도 패킷·경로 증거로 확인합니다. 컴파일 결과는 proof가 아닙니다.
6. **플랫폼별 판정**: 같은 제품 의미를 네이티브로 만족하는 후보만 PASS로 둡니다. macOS 후보가 기존 Packet Tunnel로 안전하게 연결되지 않거나 사용자 공간 네트워크 스택이 필요하면, 그 비용과 배포 제약을 별도 결과로 남기고 제품 구현을 멈춥니다.

#### B. 제품 구현 파이프라인 — proof 뒤에만 시작

1. 두 플랫폼 proof가 모두 PASS이고 상태표·helper 범위·기존 연결 정책이 확정된 뒤 시작합니다.
2. 공통 계약·진단·검사표를 먼저 정합니다. 구현은 플랫폼별 디렉토리와 권한 경계 안에서 따로 진행합니다.
3. 한 플랫폼이 FAIL이면 두 플랫폼 동시 출시를 구현하지 않습니다. 사용자가 플랫폼별 출시, MDM 제품, 기능 축소 중 하나를 새로 정해야 합니다.

### 처방 정합성 셀프체크

- Windows의 기존 `/32` 사이트 경로와 새 프로세스 경로 정책은 서로 다른 층에서 동작합니다. 같은 목적지에 둘 다 맞을 때 우선순위를 실측하기 전에는 합집합 의미가 보장된다고 적지 않습니다.
- Windows API는 IPv4/IPv6 정책을 따로 받습니다. IPv4만 시험하고 앱 전체 통신이 보호된다고 판단하면 안 됩니다.
- macOS `appRules` 경로의 `sourceApplication` 모드는 앱을 기준으로 터널에 보낼 통신을 정합니다. 현재 Packet Tunnel은 사이트 `/32`만 `includedRoutes`와 WireGuard peer `allowedIPs`에 넣고 빈 계획을 거부합니다. 선택 앱의 모든 목적지를 처리하려면 provider/WireGuard 쪽도 전체 목적지를 전달할 수 있게 별도로 설계해야 합니다. Transparent Proxy 후보는 기존 Packet Tunnel에 흐름을 그대로 넘길 수 있다고 가정하지 않습니다. 자체 사용자 공간 WireGuard 전달, DNS·UDP/QUIC 지원, 제어 흐름 재귀, 다른 VPN과의 결합을 각각 proof로 확인합니다. (`macos/VPNRouter/PacketTunnel/PacketTunnelProvider.swift:131`, `macos/VPNRouter/PacketTunnel/PacketTunnelProvider.swift:452`, `macos/VPNRouter/PacketTunnel/PacketTunnelProvider.swift:475`)
- 앱 규칙을 기존 `DomainRule`에 억지로 넣지 않습니다. 저장 수명, 신원 검증, 실패 코드가 다르므로 별도 `AppRule` 계약이 필요합니다.

## 5. 비협상 불변식 (반드시 보존)

- **네이티브 구현 격리**: 제품 의미·진단 항목·검사 사례만 공유합니다. Windows의 서비스/WFP/경로/IPC와 macOS의 Network Extension/XPC/서명 코드는 섞지 않습니다. (출처: `AGENTS.md`, `docs/platform-parity-contract.md`)
- **비밀 보호**: 실제 WireGuard `.conf`와 개인 키를 읽거나 출력하거나 진단·payload·로그에 넣지 않습니다. 가짜 키가 든 정리된 fixture만 씁니다. (출처: `AGENTS.md`, `docs/platform-parity-contract.md`)
- **제3자 제품 존중**: 다른 DNS/VPN/광고 차단/보안 제품을 자동으로 멈추거나 설정을 바꾸지 않습니다. 충돌 시 안내하고 VPN Router 소유 상태만 정리합니다. (출처: `AGENTS.md`, `docs/v0.1.0-release-plan.md`)
- **연결 상태의 진실성**: 앱별 경로, DNS, Packet Tunnel, 안전 감시가 실제로 준비되기 전에 `Connected`를 보여 주지 않습니다. 컴파일만으로 실제 동작을 주장하지 않습니다. (출처: `docs/platform-parity-contract.md`)
- **기존 사이트 안전 계약 보존**: 5분 새로고침, 답변별 15분 수명, 512개 IPv4 상한, 대상 AAAA 보호, DNS 소유권 확인, 실패 시 정리를 약하게 만들지 않습니다. (출처: `docs/platform-parity-contract.md`)
- **v0.1.0 게이트 보존**: 현재 남은 macOS 실제 기기·배포 검사, Windows 네이티브 재검사, 동등성 감사, 정확한 태그 조건을 완료로 바꾸지 않습니다. (출처: `docs/v0.1.0-release-plan.md`)
- **사용자 변경 보존**: 현재 `.gitignore` 수정은 사용자 작업입니다. 이번 문서는 이를 바꾸지 않습니다. `(출처: git status, 2026-08-03 KST)`

## 6. 수정범위 (예상 파일)

> 아래는 기술 스파이크가 통과한 뒤의 예상 범위입니다. 이번 초안 작성에서는 어느 파일도 수정하지 않았습니다.

### 공통 문서·검사 계약

- `docs/platform-parity-contract.md`: 앱 규칙과 사이트 규칙의 제품 의미, 안전 결과, 진단 금지 항목을 추가합니다.
- `docs/platform-parity-audit.md`: 플랫폼별 구현과 실제 기기 증거를 분리해 기록합니다.
- `docs/v0.1.0-release-plan.md`: 수정하지 않습니다. 다음 버전 이름을 사용자가 정한 뒤 별도 계획 문서를 만듭니다.

### Windows

- `windows/VpnRouter.Ipc/Contracts/ConnectionCommands.cs`: `AppRule` DTO, 연결·검증·진단 필드를 추가합니다.
- `windows/VpnRouter.Ipc/NamedPipes/IpcCommandKind.cs`: 앱 목록 저장·조회·검증 명령을 추가합니다.
- `windows/VpnRouter.App/MainWindow.xaml`, `windows/VpnRouter.App/MainWindow.xaml.cs`: 앱 선택 화면, 결합 의미, 재확인 상태를 추가합니다.
- `windows/VpnRouter.Service/Ipc/IpcCommandHandler.cs`: 앱 신원 검증과 연결 전 검사를 추가합니다.
- `windows/VpnRouter.Service/Connection/ConnectionOrchestrator.cs`: 앱 정책 설치와 제거를 원자적으로 묶고 실패 시 정리합니다.
- 신규 `windows/VpnRouter.Networking/Abstractions/IConnectionPolicyManager.cs`, `windows/VpnRouter.Service/Networking/*ConnectionPolicy*`: WFP 연결 정책의 생성·소유권·삭제와 인터페이스 LUID 변환을 맡습니다.
- `windows/VpnRouter.Service/Program.cs`: 새 정책 관리자를 elevated backend 수명에 맞춰 등록합니다.
- `windows/VpnRouter.Service/Storage/ProfileStore.cs`: 앱 규칙을 비밀 정보 없이 저장하고 이전 버전과 함께 읽습니다. 기존 사이트 규칙 저장/조회와 분리 여부를 결정합니다.
- `windows/VpnRouter.Service/Connection/ConnectionStateStore.cs`, `windows/VpnRouter.Service/Recovery/StartupRecoveryCoordinator.cs`: 앱 정책 상태와 비정상 종료 복구를 포함합니다.
- `windows/VpnRouter.Service/Diagnostics/DiagnosticsService.cs`: 제한된 앱 정책 개수와 상태만 추가합니다.
- `windows/VpnRouter.Tests/Program.cs`: 앱 신원, 결합표, 정책 우선순위, 누수, 실패 시 정리, 진단 가림 검사를 추가합니다.
- `scripts/windows/build-portable.ps1`: 사용자 모드 WFP interop이 한 파일 휴대용 payload에 포함되고 서명 없는 배포 제약을 늘리지 않는지 검증합니다.

### macOS

- `macos/VPNRouter/VPNRouter/ContentView.swift`: 앱 선택 화면, 결합 의미, 승인·관리 제약 안내를 추가합니다.
- 신규 `macos/VPNRouter/VPNRouter/Services/Rules/AppRuleStore.swift`: signing identifier와 지정 요구 조건을 저장하고 다시 확인합니다.
- `macos/VPNRouter/VPNRouter/Services/AppBackgroundWork.swift`, `macos/VPNRouter/VPNRouter/Services/Rules/DomainRoutePlanService.swift`: 앱 모드일 때 사이트 계획 생성·빈 계획 검사 의미를 분리합니다.
- `macos/VPNRouter/VPNRouter/Services/Tunnel/TunnelProfileConfiguration.swift`: 앱 규칙과 결합 모드를 버전이 있는 payload로 전달합니다.
- `macos/VPNRouter/VPNRouter/Services/Tunnel/ConsumerConnectionCoordinator.swift`: per-app 구성 준비·확인·정리 단계를 추가합니다.
- `macos/VPNRouter/PacketTunnel/PacketTunnelProvider.swift`: per-app 터널에서 사이트 경로와 전체 앱 경로의 관계를 적용합니다.
- `macos/VPNRouter/VPNRouter/Shared/Rules/DomainRouteRefreshPolicy.swift`, `macos/VPNRouter/VPNRouter/Shared/Rules/DynamicRoutePlanMerger.swift`, `macos/VPNRouter/VPNRouter/Services/DNSProxy/DNSProxyObservationSettingsStore.swift`: 앱 우선 모드에서 사이트 경로·DNS 관찰·512개 상한을 어떻게 유지할지 정합니다.
- `macos/VPNRouter/VPNRouter/Shared/Diagnostics/TroubleshootingReport.swift`: 제한된 앱 정책 개수와 상태를 스키마 3으로 추가합니다.
- `macos/VPNRouter/Tests/VPNRouterCoreTests/*`: 앱 규칙 저장, 결합표, payload 이전 버전, 진단 가림, 실패 시 정리를 검사합니다.
- Xcode 프로젝트와 entitlements/provisioning: signed real-Mac 스파이크 결과가 추가 권한을 요구할 때만 바꿉니다.

## 7. 열린 질문 (OQ — 사용자/architect 판단)

- ❓ **결합 의미** — 시작 차단: 기술 스파이크 아님 / 제품 구현 전 확정 필요. **기본값: 앱 우선**입니다. 앱 규칙이 있으면 선택하지 않은 앱은 사이트와 관계없이 일반 인터넷을 씁니다. 합집합을 고르면 요구 문구 자체를 바꿔야 합니다.
- ❓ **규칙이 비었을 때** — 시작 차단: 아님. **기본값: §4 상태표**입니다. 앱 0·사이트 N은 기존 사이트 모드, 앱 N·사이트 0은 앱 전체 통신 모드, 둘 다 0은 연결 차단입니다.
- ❓ **앱 묶음 단위** — 시작 차단: 기술 스파이크 아님 / 제품 구현은 차단. **스파이크 기본값: 사용자가 직접 고른 실행 파일 또는 signing identifier만 포함**하고 helper 누락을 측정합니다. 제품에서는 브라우저 renderer/helper/updater의 자동 포함 경계를 사용자가 확정해야 합니다.
- ❓ **기존 연결 처리** — 시작 차단: 기술 스파이크 아님 / 제품 구현은 차단. **스파이크 기본값: 정책 적용 뒤 새 연결만 성공으로 인정**하고, 기존 연결은 누수 가능 상태로 기록합니다. 제품 기본 후보는 앱 재시작을 요구하고 확인 전 `Connected`를 표시하지 않는 것입니다.
- ❓ **macOS 제품 선택** — 시작 차단: 기술 스파이크 아님 / 제품 구현은 차단. **기본값: MDM 없는 Transparent Proxy 대안을 먼저 검증하되 제품 가능성을 약속하지 않음**입니다. proof 결과 뒤 MDM 제품, 소비자 대안, macOS 범위 축소, 플랫폼별 출시 중 하나를 정합니다.
- ❓ **버전명** — 시작 차단: 기술 스파이크 아님 / 제품 구현 계획 문서 작성 전 확정 필요. **기본값: 스파이크에는 버전명을 붙이지 않고 `v0.2.0`은 후보로만 유지**합니다.
- ❓ **기존 릴리스 상태 정리** — 시작 차단: 격리된 기술 스파이크는 아님 / 현재 릴리스 문서·artifact와 섞는 작업은 차단. **기본값: 현재 `HEAD`에서 별도 브랜치 또는 worktree를 만들고, v0.1.0 문서·artifact·태그는 수정하지 않음**입니다. 제품 통합 전에 태그 의미와 미완료 게이트를 별도 정리합니다.

## 8. 위험 요소 (스스로 발견한 보완점)

- ⚠️ **macOS `appRules` 경로 제약(CONFIRMED, 전제: `appRules`/App Proxy per-app 구성을 사용)**: 이 경로는 MDM 관리 구성이 필요하며 개발용 `NETestAppMapping`은 Distribution에서 작동하지 않습니다. 영향 규모는 이 API 경로를 이용한 소비자용 macOS 앱 선택 기능 전부입니다. 다만 Transparent Proxy 등 다른 Network Extension 조합의 가능성은 **미측정**이므로 “macOS 소비자 경로 전체가 없음”으로 확대 해석하지 않습니다.
- ⚠️ **macOS 대안 경로 — 미측정**: Transparent Proxy는 흐름의 source app 정보를 볼 수 있지만, 설정 규칙 자체는 앱이 아니라 네트워크 속성을 기준으로 합니다. TCP/UDP 흐름을 자체 WireGuard 전송으로 다시 만드는 데 필요한 성능·반종료·UDP/QUIC·DNS·IPv6·제어 경로 재귀·다른 VPN 공존은 확인되지 않았습니다. Content Filter의 공식 역할은 허용/차단이므로 재라우팅 수단으로 간주하지 않습니다.
- ⚠️ **Windows API와 현재 구조의 연결 — 미확인**: API는 사용자 모드에서 호출할 수 있어 현재 elevated backend에 둘 후보는 맞습니다. 그러나 현재 코드는 interface index만 알고 API는 LUID를 요구합니다. BFE 권한, IPv4/IPv6 두 정책, 가중치, 동적 세션 수명, 새 연결 적용, 휴대용 publish는 아직 측정하지 않았습니다.
- ⚠️ **교차 규칙 우선순위 — 미측정**: 시스템 `/32` 사이트 경로와 프로세스 기반 다음 홉 정책이 동시에 맞을 때 실제 우선순위와 IPv4/IPv6 결과를 모릅니다. 합집합 또는 앱 우선 의미는 패킷 실측 전까지 잠정입니다.
- ⚠️ **앱 신원 변동**: Windows 실행 파일 경로, Store 패키지, macOS signing identifier와 designated requirement는 업데이트·이동·재서명·helper 분리 때 달라질 수 있습니다. PID만 저장하면 재실행 때 잘못된 앱이 선택될 수 있습니다.
- ⚠️ **자식·helper 통신 누락**: 브라우저, 게임 런처, 업데이터는 여러 프로세스로 통신합니다. 대표 실행 파일 하나만 고르면 로그인·업데이트·영상·QUIC가 기본 인터넷으로 샐 수 있습니다.
- ⚠️ **기존 연결**: 정책 설치 전에 열린 TCP/UDP 흐름이 계속 기본 경로를 쓸 수 있습니다. 앱을 강제 종료하지 않고 새 연결만 보호할지, 연결을 막고 사용자에게 재시작을 요청할지 정해야 합니다.
- ⚠️ **DNS 의미 충돌**: 현재 DNS Proxy는 사이트 대상 관찰과 AAAA 보호를 위해 시스템 DNS 경로를 다룹니다. 앱 전체 통신 모드에서 선택하지 않은 앱의 DNS를 가로채면 “선택하지 않은 앱은 일반 인터넷” 의미를 해칠 수 있습니다.
- ⚠️ **IPv6 누수**: 현재 사이트 기능은 대상 AAAA 응답을 비우는 방식입니다. 선택 앱 전체 통신은 IPv6도 앱 단위로 VPN 또는 차단해야 하며, IPv4 성공만으로 완료라 할 수 없습니다.
- ⚠️ **WireGuard 제어 경로 재귀**: VPN endpoint와 DNS upstream, WFP 정책을 설치하는 backend 자체가 선택 앱으로 잘못 묶이면 터널이 자기 자신을 다시 통과할 수 있습니다. 제어 경로 제외 규칙을 양쪽 플랫폼에서 증명해야 합니다.
- ⚠️ **다른 VPN과의 경합**: 다른 제품도 WFP 정책, Network Extension, DNS 또는 기본 경로를 소유할 수 있습니다. 안정 상태뿐 아니라 상대 VPN의 연결·해제 전환 중에도 VPN Router 소유 상태만 정리해야 합니다.
- ⚠️ **복구 범위 확대**: 앱 정책은 경로·DNS·터널 외의 새 소유 상태입니다. crash/reboot 복구가 이를 놓치면 선택 앱이 오프라인이거나 의도치 않은 인터페이스를 계속 쓸 수 있습니다.
- ⚠️ **Windows 배포 변화 가능성**: 공식 연결 정책이 요구사항을 다 채우지 못해 WFP callout driver가 필요해지면 커널 드라이버 서명, 설치·제거, 관리자 권한, Secure Boot/HVCI 검사가 추가됩니다. 현재 한 파일 휴대용 배포 전제와 충돌할 수 있습니다. ([Microsoft Learn — Driver signing options](https://learn.microsoft.com/en-us/windows-hardware/drivers/dashboard/driver-signing-offerings))
- ⚠️ **v0.1.0 상태 불일치(격리 조건에서는 스파이크 비차단)**: annotated tag는 이미 존재하지만 문서에는 미완료 게이트와 태그 전 조건이 남아 있습니다. 별도 브랜치 또는 worktree, 별도 스파이크 산출물, v0.1.0 문서·artifact·태그 무수정 조건이면 기술 스파이크는 진행할 수 있습니다. 이 조건이 깨지거나 제품 코드를 현재 릴리스 흐름에 합치려 하면 차단합니다.
- ⚠️ **검사 조합 폭증**: 앱/사이트 4가지 빈 상태, 결합 모드, TCP/UDP/QUIC, IPv4/IPv6, 업데이트 전후, helper, sleep/wake, 다른 VPN 전환을 모두 곱하면 검사량이 큽니다. 대표 앱군과 필수 조합을 먼저 정해야 합니다.

## 9. 관련 문서·메모리·차수

- `docs/windows-next-session.md`: Windows 네이티브 재검사와 v0.1.0 남은 순서. 앱 라우팅은 당시 비범위입니다.
- `docs/windows-mvp-handoff.md`: Windows 11 x64, 서비스·DNS·경로·WireGuard 네이티브 경계.
- `docs/windows-mvp-progress.md`, `docs/windows-release-hardening.md`: 현재 휴대용 앱의 실제 검사와 서명하지 않은 배포 제약.
- `docs/macos-mvp-handoff.md`, `docs/macos-next-session.md`, `docs/macos-mvp-progress.md`: macOS 15 Apple Silicon, 실제 서명 Network Extension 검사, 배포 공증 제약.
- `docs/v0.1.0-release-plan.md`: 완료되지 않은 네 가지 Phase 4 항목과 11개 릴리스 게이트. 라이브 저장소에는 문서와 달리 `v0.1.0` 태그가 이미 있습니다.
- `docs/platform-parity-contract.md`, `docs/platform-parity-audit.md`: 공유 제품 의미와 현재 남은 동등성 증거.
- 체크리스트·저널·회고·백로그·누적 인사이트: `(해당 없음 — PMO 경로에서 파일 0개)`
- 직전 회고 협업 제안 반영(AI 에게): 해당 없음. `(직전 회고 없음)`

## 10. 검증 기록

- 1차 검증: 초안 결론을 독립 재확인해 다음을 정정했습니다.

  | 초안 | 라이브 재확인 | 정정 |
  |---|---|---|
  | macOS MDM 없는 임의 앱 선택은 미확인 | Apple은 `appRules` 기반 per-app VPN 구성을 MDM 등록과 관리 앱 연결로 명시합니다. `NETestAppMapping`은 Development 전용입니다. | 1차에서는 소비자 배포 전체의 지원 경로 없음으로 넓게 판정했습니다. 2차에서 다른 Network Extension 경로가 빠졌음을 확인해 §2·§8·아래 2차 기록에서 범위를 다시 좁혔습니다. |
  | 합집합 잠정 권장 | 합집합은 선택하지 않은 앱도 선택 사이트에서 VPN을 쓰게 합니다. | 요구 문구와 맞는 기본안을 앱 우선으로 변경했습니다. |
  | Windows API를 현재 backend에 바로 시험 | API는 interface LUID, IP 버전별 정책, 가중치와 WFP 세션 수명이 필요합니다. 현재 코드는 interface index와 `/32` 경로만 관리합니다. | LUID 변환·BFE 권한·동적 세션·휴대용 publish를 선행 proof로 추가했습니다. |
  | `v0.1.0`은 아직 미태그 | annotated tag `v0.1.0`이 커밋 `6e6fbb5`에 있고 현재 `HEAD`의 조상입니다. 문서에는 미완료 게이트가 남아 있습니다. | “미태그”를 “태그와 문서상 게이트 상태 불일치”로 바꿨습니다. |
  | 예상 수정범위가 UI·DTO·조정자 중심 | Windows 검증/저장/상태/복구/DI/휴대용 빌드와 macOS 계획 생성·병합·새로고침·DNS 관찰 소비처가 추가로 확인됐습니다. | §6에 누락 소비처를 추가했습니다. |

  재확인 근거: Apple/Microsoft 공식 문서, 프로젝트 코드와 참조처, `git tag/show/merge-base`, 모든 플랫폼 인수인계·진행·릴리스·동등성 문서. PMO와 저장소 RAG는 다시 조회했으나 결과가 0건이었습니다. `(1차 검증: 2026-08-03 KST)`
- 2차 검증: 2026-08-03 KST에 초안과 1차 결론을 다시 의심해 확인했습니다.

  | 적대 확인 항목 | 재확인 결과 | 문서 보정 |
  |---|---|---|
  | “MDM 없는 macOS 소비자 경로 전체가 지원되지 않음” | Apple 공식 문서는 `appRules` 기반 Packet Tunnel과 App Proxy per-app 구성의 MDM 제약은 확정합니다. Transparent Proxy는 네트워크 규칙으로 흐름을 받고 source app 메타데이터를 제공하지만, 임의 앱의 모든 TCP/UDP/QUIC/DNS를 기존 WireGuard Packet Tunnel로 누수 없이 전달할 수 있는지는 공식 문서만으로 확정되지 않습니다. Content Filter는 허용·차단 수단입니다. | 전건 지원 불가 단정을 삭제했습니다. MDM 없는 대안은 실제 서명 빌드 기술 스파이크 게이트로 바꿨습니다. |
  | 앱 우선 기본안의 완전성 | “앱 규칙이 있을 때”만 적혀 있어 0/N 조합과 사이트 규칙 보존 의미가 구현자마다 달라질 수 있었습니다. | 앱 0/N × 사이트 0/N 상태표와 기본값을 §4에 추가했습니다. |
  | 두 플랫폼 동시 작업 가능성 | Windows WFP proof와 macOS 대안 proof는 공통 상태표만 공유하면 네이티브 코드 경계를 지킨 채 동시에 진행할 수 있습니다. 제품 구현은 두 proof 결과에 의존합니다. | 기술 스파이크 파이프라인과 제품 구현 파이프라인을 분리했습니다. |
  | `v0.1.0` 상태 불일치의 차단 범위 | annotated tag `v0.1.0`은 `6e6fbb5695bbf1432bfbf830a743264a2a38bda2`를 가리키며 현재 `HEAD`의 조상입니다. 릴리스 계획에는 macOS 서명·공증·실기기, Windows 재검사, 태그 항목이 미완료입니다. | 별도 브랜치/worktree와 v0.1.0 산출물 무수정 조건에서는 스파이크 비차단으로 낮췄습니다. 제품 통합과 기존 릴리스 변경은 차단합니다. `(출처: git show-ref/cat-file/show/merge-base, 2026-08-03 KST; docs/v0.1.0-release-plan.md:166)` |
  | 열린 질문의 실행 영향 | 질문별 기본값과 어느 단계가 막히는지 구분되지 않았습니다. | §7의 모든 질문에 시작 차단 여부와 기본값을 붙였습니다. |

  best-effort 공백도 다시 평가했습니다. DB와 운영 로그는 이 기능의 플랫폼 API 가능성을 판정하는 필수 근거가 아니므로 현재 스파이크 시작을 막지 않습니다. RAG와 PMO 과거 기록이 비어 있어 과거 제약 누락 가능성은 남지만, 저장소 코드·릴리스 문서·Apple/Microsoft 공식 문서를 직접 확인했으므로 격리된 proof는 시작할 수 있습니다. `(DB 조회 생략 — 입력 계약; 로그 조회 불가 — 경로 없음; RAG 결과 0건)`
- **최종 판정: 조건부 GO**
  - **시작 가능 범위 — 기술 스파이크 파이프라인**: Windows WFP proof와 macOS MDM 없는 대안 proof를 병렬로 시작할 수 있습니다. 조건은 (1) §4 상태표를 시험 기본값으로 사용, (2) 별도 브랜치 또는 worktree 사용, (3) v0.1.0 문서·artifact·태그 무수정, (4) 실제 비밀 대신 정리된 fixture 사용, (5) macOS는 실제 서명 빌드와 패킷·경로 증거로 판정하는 것입니다.
  - **차단 범위 — 제품 구현 파이프라인: NO-GO**: macOS 배포 가능성, 두 플랫폼의 TCP/UDP/QUIC/DNS·IPv4/IPv6 누수 방지, helper 범위, 기존 연결 처리 proof가 끝나지 않았습니다. 두 플랫폼 proof가 PASS하고 §7의 제품 차단 질문이 확정되기 전에는 UI·저장소·공용 DTO·진단 스키마를 제품 코드에 통합하지 않습니다.
  - **조건 실패 시**: 스파이크가 현재 릴리스 흐름과 격리되지 않거나 실제 서명 macOS 검증 환경을 마련할 수 없으면 기술 스파이크도 NO-GO입니다.

## 11. 파이프라인 시작

- 사용자 직접 실행이며 자동으로 시작하지 않습니다.
- 권장 PM 입력 시드: `docs/R1-cross-platform-app-routing-prebrief-2026-08-03.md`를 기준 문서로 사용합니다. 이번 파이프라인 이름과 산출물을 “교차 플랫폼 앱 라우팅 기술 스파이크”로 한정합니다. §4 상태표를 기본 계약으로 두고 Windows WFP proof와 macOS Transparent Proxy 중심 대안 proof를 병렬 계획합니다. 제품 UI·저장소·DTO 구현은 후속 파이프라인으로 분리합니다. `v0.1.0` 태그와 문서상 미완료 게이트는 바꾸지 않습니다.
