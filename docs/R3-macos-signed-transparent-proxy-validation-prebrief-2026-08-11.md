# R3 프리브리프 — macOS 서명 프록시 실제 검증 (2026-08-11)

> 프로젝트: vpn_router · 대상 차수(예정): R3 · 성격: 파이프라인 시작 전 준비 문서(독립)
> 조회 소스: 운영 DB/로그 · 코드 · 체크리스트 · 저널 · 차수 기록 · 백로그 · RAG

## 0. 한 줄 요약

R1에서 자동 검사까지만 끝낸 `macos/AppRoutingSpike/` Transparent Proxy 경로를 실제 서명 Mac에서 검증합니다. PASS 범위는 TCP·UDP 새 흐름 수신, 앱 신원, 선택 앱의 안전 실패, 통제 앱과 control plane의 일반 인터넷, manager 설정 제거, DNS·IPv4·IPv6 회복이라는 핵심 게이트입니다. 실제 개발 팀 권한과 프로비저닝은 아직 확인되지 않은 선행 조건입니다. 검증 중 찾은 P0~P2 결함만 같은 라운드에서 고칩니다. (출처: `R1/retrospective-2026-08-04_02-21.md`, `R1/2026-08-04_02-27_notification_r1-macos-app-routing-spike.md`; 사용자 추가 답변)

## 1. 운영 실측 (DB·로그 직접 조회, 2026-08-11 18:13 KST)

- 로컬 환경은 macOS 26.6.1 arm64, Xcode 26.6, Swift 6.3.3입니다. XcodeGen은 `/opt/homebrew/bin/xcodegen`에 있습니다. `.NET`과 PowerShell 실행 파일은 찾지 못했습니다. (출처: 로컬 환경 명령, 2026-08-11 18:13 KST)
- 현재 Git 기준 브랜치는 `main...origin/main`입니다. 기존 미추적 경로 `ai-drafts/`와 이 프리브리프가 보입니다. `ai-drafts/`는 사용자 답변에 따라 그대로 보존합니다. (출처: `git status --short --branch`, 2026-08-11 18:13 KST; 사용자 추가 답변)
- 운영 DB 연결은 성공했습니다. `SHOW TABLES` 결과에 vpn_router, macOS, Network Extension, Transparent Proxy와 이름이 겹치는 테이블이 없었습니다. 따라서 이 라운드에 쓸 운영 DB 수치나 스키마는 조회하지 않았습니다. `(관련 운영 DB 없음 — 연결된 DB가 다른 서비스용, 2026-08-11 조회)`
- 운영 로그 경로가 없습니다. `(로그 조회 불가 — 입력 경로 없음)`
- 프로젝트 코드 RAG는 결과가 0건이었습니다. `(코드 RAG 조회 불가 — 현재 색인 결과 0건)`
- PMO RAG에서는 R1의 중단 조건, 실제 서명 매트릭스, 앱 신원과 정리 조건을 찾았습니다. 1차 독립 재조회에서 유사도 0.50~0.54인 관련 문서를 실제 PMO 파일과 현재 코드로 다시 확인했습니다. (출처: PMO RAG + `R1/2026-08-04_00-27_plan_r1-macos-app-routing-spike.md`, `R1/2026-08-04_00-36_design_r1-macos-app-routing-spike.md`, 2026-08-11 18:13 KST)
- 1차 독립 재검증에서 Networking 시험 23/23, 소스 안전 검사, 격리 검사, 격리 자체 검사, 기존 Debug 산출물의 생성 plist 검사가 모두 다시 통과했습니다. 이 결과는 자동 검사 기준일 뿐 실제 Network Extension 동작 증거가 아닙니다. (출처: 로컬 자동 검사, 2026-08-11 18:13 KST)

## 2. 현재 구조 (CONFIRMED 사실 — file:line)

### 서명과 설치 경로

- Host 권한 파일에는 시스템 확장 설치 권한과 `app-proxy-provider-systemextension` 권한이 있습니다. Extension 권한 파일에도 같은 Network Extension 권한이 있습니다. (`macos/AppRoutingSpike/Entitlements/HostHarness.entitlements:5`, `macos/AppRoutingSpike/Entitlements/TransparentProxyExtension.entitlements:5`)
- XcodeGen 설정은 Host 앱 안에 Transparent Proxy 시스템 확장을 넣습니다. Host와 Extension은 실제 개발 팀 값을 외부 설정으로 받아 자동 서명하도록 되어 있습니다. 저장소 기본값의 `SPIKE_EXPECTED_TEAM_IDENTIFIER`는 빈 문자열이므로 실제 서명 실행 전에 저장소 밖에서 값을 넣어야 합니다. (`macos/AppRoutingSpike/project.yml:9`, `macos/AppRoutingSpike/project.yml:16`, `macos/AppRoutingSpike/project.yml:40`, `macos/AppRoutingSpike/project.yml:65`)
- Host의 설치 버튼은 `OSSystemExtensionRequest.activationRequest`를 제출합니다. 다만 delegate는 `didFinishWithResult`의 `result` 값을 나누어 보지 않고 모든 완료를 성공으로 처리합니다. ViewModel은 이 성공 뒤 곧바로 `hasSignedEntitlement = true`로 바꿉니다. 요청 완료만으로 실제 활성화나 흐름 수신을 성공 판정하면 안 됩니다. (`macos/AppRoutingSpike/HostHarness/ContentView.swift:61`, `macos/AppRoutingSpike/HostHarness/SystemExtensionActivator.swift:24`, `macos/AppRoutingSpike/HostHarness/SpikeViewModel.swift:75`)
- Transparent Proxy 시작은 VPN Router 소유 `NETransparentProxyManager` 구성을 저장한 뒤 `startVPNTunnel()`을 호출합니다. (`macos/AppRoutingSpike/HostHarness/TransparentProxyController.swift:21`)

### 실제 흐름과 앱 신원 경로

- Provider의 현재 포함 규칙은 IPv4 문서용 주소 `192.0.2.1/32`의 443번 포트 한 곳이며 프로토콜은 `.any`입니다. 이 규칙 밖의 흐름은 현재 P2 관찰 대상이 아닙니다. (`macos/AppRoutingSpike/TransparentProxyExtension/TransparentProxyProvider.swift:17`)
- TCP는 `handleNewFlow`, UDP는 `handleNewUDPFlow`에서 같은 처리 경로로 들어갑니다. (`macos/AppRoutingSpike/TransparentProxyExtension/TransparentProxyProvider.swift:66`, `macos/AppRoutingSpike/TransparentProxyExtension/TransparentProxyProvider.swift:70`)
- Provider는 `sourceAppSigningIdentifier`와 `sourceAppAuditToken`을 함께 신원 검사기에 넘깁니다. (`macos/AppRoutingSpike/TransparentProxyExtension/TransparentProxyProvider.swift:85`, `macos/AppRoutingSpike/TransparentProxyExtension/TransparentProxyProvider.swift:91`)
- 신원 검사기는 metadata의 식별자가 기대 식별자와 정확히 같아야 합니다. audit token도 있어야 하며 실제 코드 서명 요구 조건을 통과해야 합니다. (`macos/AppRoutingSpike/Networking/FlowIdentityVerifier.swift:19`, `macos/AppRoutingSpike/TransparentProxyExtension/SecurityAuditTokenValidator.swift:5`)
- 유효한 control plane과 정상 통제 앱은 직접 통과합니다. 신원 정보가 없거나 검증이 실패한 흐름은 Provider가 소유하고 닫습니다. (`macos/AppRoutingSpike/Networking/FlowPolicyEvaluator.swift:54`, `macos/AppRoutingSpike/Networking/FlowPolicyEvaluator.swift:58`, `macos/AppRoutingSpike/Networking/FlowPolicyEvaluator.swift:66`, `macos/AppRoutingSpike/Networking/FlowPolicyEvaluator.swift:74`)
- Provider는 `.directPass`에서 곧바로 `false`를 반환합니다. 통제 앱과 control plane의 역할·흐름 결과는 현재 제한 결과 버퍼에 기록되지 않습니다. (`macos/AppRoutingSpike/TransparentProxyExtension/TransparentProxyProvider.swift:105`)
- P3 전송은 구현되어 있지 않습니다. `SelectedFlowTransport.forward()`는 항상 `.unsupported`를 반환합니다. 선택 흐름은 이 결과 뒤에 닫히고 `inconclusive`로 기록됩니다. (`macos/AppRoutingSpike/Networking/SelectedFlowTransport.swift:8`, `macos/AppRoutingSpike/TransparentProxyExtension/TransparentProxyProvider.swift:118`)
- Provider가 만드는 흐름 종류는 TCP/UDP와 IPv4/IPv6 조합뿐입니다. `quic`, `dnsA`, `dnsAAAA` 계약은 있지만 이 Provider 처리 경로에서 생성되지 않습니다. (`macos/AppRoutingSpike/TransparentProxyExtension/TransparentProxyProvider.swift:148`, `macos/AppRoutingSpike/Shared/SpikeContracts.swift:126`)

### 중단과 복구 경로

- Provider 중단은 새 흐름 수락을 멈추고 실행 상태와 XPC 서비스를 지웁니다. (`macos/AppRoutingSpike/TransparentProxyExtension/TransparentProxyProvider.swift:55`)
- Host 중단은 XPC 오류가 나도 Provider 중지와 VPN Router 소유 설정 제거를 계속 시도합니다. (`macos/AppRoutingSpike/HostHarness/SpikeViewModel.swift:134`, `macos/AppRoutingSpike/HostHarness/SpikeViewModel.swift:151`)
- `removeOwnedConfiguration()`은 `NETunnelProviderProtocol.providerBundleIdentifier`가 현재 Provider 식별자와 같은 첫 `NETransparentProxyManager`를 찾아 preference에서 제거합니다. `localizedDescription`은 조회 조건에 쓰지 않습니다. (`macos/AppRoutingSpike/HostHarness/TransparentProxyController.swift:60`, `macos/AppRoutingSpike/HostHarness/TransparentProxyController.swift:79`)
- 정리 뒤 연결 검사는 자동 측정이 아닙니다. 기본 검사기는 사용자 확인이 필요하다고만 반환합니다. 화면에서 사용자가 DNS·IPv4·IPv6 세 항목을 직접 체크해야 완료 상태가 됩니다. (`macos/AppRoutingSpike/HostHarness/SpikeServiceProtocols.swift:30`, `macos/AppRoutingSpike/HostHarness/ContentView.swift:94`, `macos/AppRoutingSpike/HostHarness/SpikeViewModel.swift:180`)

### 영향 범위 전수 확인

- `SystemExtensionActivator`와 `TransparentProxyController`의 실제 소비처는 `HostHarnessApp`에서 만든 `SpikeViewModel`입니다. 화면과 Host 시험도 같은 ViewModel을 사용합니다. (`macos/AppRoutingSpike/HostHarness/HostHarnessApp.swift:11`, `macos/AppRoutingSpike/HostHarness/ContentView.swift:5`, `macos/AppRoutingSpike/Tests/HostHarnessTests/SpikeViewModelTests.swift:108`)
- 앱 신원 경로의 소비처는 Provider, `FlowIdentityPolicyAdapter`, `FlowIdentityVerifier`, `FlowPolicyEvaluator`, Networking 시험입니다. (`macos/AppRoutingSpike/TransparentProxyExtension/TransparentProxyProvider.swift:91`, `macos/AppRoutingSpike/Networking/FlowIdentityPolicyAdapter.swift:4`, `macos/AppRoutingSpike/Tests/NetworkingTests/NetworkingTests.swift:443`)
- `SpikeRunRequest`는 Host 설정, ViewModel, XPC client/service, 요청 검사기, 실행 상태, 정책 평가기, 계약 시험에서 함께 씁니다. 이 계약을 바꾸면 적어도 12개 Swift 파일을 다시 확인해야 합니다. (`macos/AppRoutingSpike/Shared/SpikeContracts.swift:152`; 출처: 라이브 심볼 사용처 전수 검색, 2026-08-11)
- `RedactedFlowResult`는 Provider에서 만들어져 기록기, XPC snapshot, ViewModel, 결과 내보내기, Host·Networking 시험까지 이어집니다. 이 형식을 바꾸면 적어도 12개 Swift 파일을 다시 확인해야 합니다. (`macos/AppRoutingSpike/Shared/SpikeContracts.swift:181`; 출처: 라이브 심볼 사용처 전수 검색, 2026-08-11)
- 현재 `macos/AppRoutingSpike/**`에는 `NWConnection` 또는 `NWListener`를 쓰는 TCP·UDP 시험 하네스가 없습니다. `NWConnection` 금지 검사는 `Networking`과 `TransparentProxyExtension`만 봅니다. 따라서 새 하네스는 별도 시험 대상에 두고 P3 전송 코드와 구분해야 합니다. (`macos/AppRoutingSpike/Scripts/verify-source-safety.sh:7`; 출처: 라이브 코드 검색, 2026-08-11 18:13 KST)

## 3. 이번 목표 / 범위

- **할 것**:
  - 실제 개발 팀 권한과 이 Mac용 프로비저닝은 미확인 선행 조건으로 둡니다. 준비됨을 추정하지 않습니다. 준비 여부가 확인된 뒤에만 실제 서명 설치 단계로 넘어갑니다.
  - 권한과 프로비저닝이 준비된 경우 실제 서명 Host와 Extension을 만들고 사용자가 시스템 확장 설치와 활성화를 직접 승인합니다.
  - `192.0.2.1:443` 규칙에 맞는 공개 시험용 로컬 TCP·UDP 하네스를 `macos/AppRoutingSpike/**` 안에 마련합니다. 하네스는 원문 앱 신원, 주소, 도메인, payload를 결과에 남기지 않습니다.
  - 선택 앱과 통제 앱에서 정책 적용 뒤 새 TCP·UDP 흐름을 만듭니다. Provider 수신, `sourceAppSigningIdentifier`와 audit token 기반 신원 결과를 제한된 역할·상태 값으로 확인합니다.
  - 선택 앱은 P3가 없는 동안 조용히 일반 인터넷으로 빠지지 않고 안전하게 실패해야 합니다. 통제 앱과 control plane은 일반 인터넷과 제어 경로를 유지해야 합니다.
  - 정상 중단, Host 종료, Provider 종료, 실패 중단에서 VPN Router 소유 상태만 정리합니다. 정리 뒤 DNS·IPv4·IPv6 회복을 확인합니다.
  - P0~P2 결함이 나오면 `macos/AppRoutingSpike/**` 안에서 고칩니다. 관련 자동 검사와 실제 서명 검증을 다시 실행합니다.
  - 제품 공용 DTO/IPC는 건드리지 않습니다. 다만 핵심 P0~P2 증거를 안전하게 남기는 데 꼭 필요하면 `macos/AppRoutingSpike/Shared/SpikeContracts.swift`와 이 스파이크의 로컬 XPC만 최소 수정할 수 있습니다. 이 경우 확인된 소비처를 모두 다시 검사합니다.
  - 자동 검사, 실제 서명 결과, P3/제품 통합 판정을 서로 다른 칸으로 남깁니다. 실제 관찰이 없는 항목은 `inconclusive`로 둡니다.
  - QUIC·DNS·수명 전체 매트릭스는 관찰할 수 있으면 기록합니다. 이번 PASS 필수조건으로 넓히지 않습니다.
- **안 할 것(이번 비범위)**:
  - `windows/**`, Windows 스크립트와 문서, WFP 진단과 Windows LIVE 실행은 건드리지 않습니다.
  - P3 WireGuard 흐름 전달, 범용 사용자 공간 전송 계층, 원격 프록시를 구현하지 않습니다.
  - 제품 UI, 저장소, 제품 공용 DTO/IPC, 제품 진단 통합, 커널 드라이버를 구현하지 않습니다.
  - `macos/VPNRouter/**`, `docs/v0.1.0-release-plan.md`, 릴리스 태그와 릴리스 산출물을 바꾸지 않습니다.
  - 시스템 확장 deactivation은 하지 않습니다. 정리 범위는 Transparent Proxy manager 설정 제거와 DNS·IPv4·IPv6 회복까지입니다.
  - 기존 미추적 `ai-drafts/`를 수정하거나 삭제하지 않습니다.
  - 실제 WireGuard `.conf`, 개인 키, Team ID, 인증서 이름, 프로비저닝 전문, 앱 원문 신원, 주소, DNS 내용을 읽거나 기록하지 않습니다.
  - 다른 VPN·DNS·광고 차단·백신·보안 제품을 자동 중지하거나 재설정하지 않습니다.

이번 요청은 `backlog.md`의 「다음 라운드 후보」 5건에 없습니다. 해당 후보는 모두 Windows WFP 후속 작업입니다. R3는 사용자가 별도로 지정한 macOS 요청으로 진행합니다. (출처: `backlog.md`)

## 3-1. 이번 라운드에 해소할 체크리스트 (3건)

| # | 항목 원문 | 해소 방법 (어디에 어떤 줄을) | 담당 단계 | 왜 이번인가 |
|---|---|---|---|---|
| 1 | 자동 검사, 실제 서명 기기, 후속 구현의 판정 상태를 서로 다른 칸으로 관리할지 확인합니다. | 기획서의 판정표와 QA 결과표에 `automated`, `signedMac`, `P3/제품 통합` 3개 칸을 둡니다. 권한이 미확인이면 `signedMac`은 `inconclusive`로 유지합니다. | planner · qa | 실제 서명 선행 조건이 미확인이어도 한 줄 규칙으로 이번에 확실히 닫을 수 있습니다. |
| 2 | Provider부터 신원 검사기와 정책 평가기까지 이어지는 결합 시험이 있는지 확인합니다. | `TransparentProxyProvider.swift:77`의 입력부터 `FlowIdentityPolicyAdapter.swift:16`, `FlowIdentityVerifier.swift:19`, `FlowPolicyEvaluator.swift:51`, Provider 최종 `true/false`까지 한 시험 경로로 연결합니다. 실제 Provider를 건너뛰는 adapter 시험만으로 닫지 않습니다. | architect · dev-backend · qa · security | 이번 라운드가 같은 앱 신원 경로를 열며, 현재 자동 시험은 adapter 중심이라 실제 Provider 연결을 보강할 수 있습니다. |
| 3 | DNS·IPv4·IPv6 회복을 확인하기 전에 정리 완료로 표시하지 않는지 확인합니다. | 설계서와 QA 실제 실행표에 중단 → 소유 설정 제거 → DNS → IPv4 → IPv6 순서를 고정합니다. 세 확인이 끝나기 전에는 `inconclusive` 또는 `cleanupFailed`만 허용합니다. (`macos/AppRoutingSpike/HostHarness/SpikeViewModel.swift:151`, `macos/AppRoutingSpike/HostHarness/SpikeViewModel.swift:180`) | architect · qa · security | 이번 목표가 종료와 정리 뒤 실제 회복을 직접 확인하는 일이기 때문입니다. |

> 미완료 53건 중 3건. 나머지는 이번에 건드리지 않습니다.
> 사용자 결정·사람 수행이 필요한 준비 사항은 완료로 미리 표시하지 않고 §7 열린 질문과 실제 실행 게이트로 보냅니다. (출처: `next-project-checklist.md`)

## 4. 설계 방향 (잠정)

- R1의 `macos/AppRoutingSpike/**` 격리 경로를 그대로 씁니다. 먼저 자동 기준선을 다시 확인합니다. 그다음 권한·프로비저닝 상태를 확인합니다. 준비된 경우에만 사용자가 승인한 실제 서명 실행을 작은 단계로 나눕니다.
- 실제 실행 순서는 환경·서명 확인 → 시스템 확장 설치 승인 → Provider 활성화 → 선택/통제 TCP·UDP 새 흐름 생성 → 제한 결과 확인 → 중단 → VPN Router 소유 설정 제거 → DNS·IPv4·IPv6 확인입니다. 각 단계가 실패하면 뒤 단계를 성공으로 처리하지 않습니다.
- 공개 시험용 로컬 하네스는 TCP와 UDP 새 흐름을 만드는 서명된 시험 앱 경로로 둡니다. 선택 앱과 통제 앱의 신원을 구분할 수 있어야 합니다. `Networking`이나 Extension의 `SelectedFlowTransport`에는 `NWConnection`을 추가하지 않습니다.
- `192.0.2.1:443` 수신 확인과 통제 인터넷 보존은 서로 다른 증거입니다. 앞의 증거는 Provider가 흐름을 받았는지 봅니다. 뒤의 증거는 도달 가능한 일반 인터넷 확인을 별도로 수행하되 결과에는 성공 여부와 시각만 남깁니다.
- 선택 흐름은 `SelectedFlowTransport.unsupported`를 유지합니다. P3 전송 코드를 넣지 않습니다. 안전 실패를 확인하는 동안 선택 흐름은 Provider가 소유하고 닫아야 합니다.
- 선택 흐름의 `RedactedFlowResult.spikeResult = inconclusive`는 P3 전달이 없다는 뜻입니다. 별도 P2 게이트에서는 “Provider가 흐름을 소유하고 직접 인터넷으로 보내지 않은 뒤 닫았음”을 확인해 안전 실패를 PASS로 판정할 수 있습니다. 두 판정 축을 합치지 않습니다.
- 정리는 `stopProvider()` 호출 성공으로 끝내지 않습니다. 연결 상태를 제한 시간 안에 관찰하고, preference를 다시 읽어 같은 Provider 식별자의 manager가 0개인지 확인한 뒤, 시작 전 기준선과 비교해 DNS·IPv4·IPv6 회복을 판정합니다.
- 실제 결과에는 실행 시각, 증거 등급, 흐름 종류, 앱 역할, 새 흐름/기존 흐름, 결과, 제한된 실패 코드만 남깁니다. 앱 식별자, Team ID, 주소, DNS 내용은 남기지 않습니다.
- 결함을 고칠 때는 Provider → 신원 검사기 → 정책 평가기 → 결과 기록기 → XPC → Host 화면 → 시험 순서의 모든 소비처를 다시 확인합니다. 계약 변경이 필요하면 `SpikeRunRequest`와 `RedactedFlowResult` 소비처 12개씩을 다시 검사합니다.

### 처방 호환성 셀프체크

- 현재 포함 규칙의 `.any`는 같은 IPv4/443 대상의 TCP와 UDP를 받을 수 있습니다. 이번 PASS 필수조건은 이 두 새 흐름으로 한정합니다. 선택 앱의 IPv6·QUIC·DNS 흐름은 관찰하지 못해도 R3 핵심 게이트의 실패로 세지 않습니다. (`macos/AppRoutingSpike/TransparentProxyExtension/TransparentProxyProvider.swift:22`; 사용자 추가 답변)
- 현재 Provider 결과는 TCP/UDP의 IP 버전만 나눕니다. QUIC과 DNS 의미를 자동으로 구분할 수 없습니다. 관찰할 수 있으면 보조 결과로 남기되 PASS 필수조건으로 넓히지 않습니다. (`macos/AppRoutingSpike/TransparentProxyExtension/TransparentProxyProvider.swift:148`, `macos/AppRoutingSpike/Shared/SpikeContracts.swift:126`; 사용자 추가 답변)
- 실제 Team ID는 Provider 시작 전에 비어 있지 않아야 합니다. 값은 저장소 밖에서 주입해야 합니다. 빈 값이면 Provider가 `missingXPCConfiguration`으로 시작을 거부합니다. (`macos/AppRoutingSpike/project.yml:16`, `macos/AppRoutingSpike/TransparentProxyExtension/TransparentProxyProvider.swift:36`)
- 정리 후 기본 검사는 자동 네트워크 측정값을 반환하지 않습니다. 사용자의 세 체크를 증거로 쓰려면 실행 시각과 측정 방법을 실제 실행표에 함께 적어야 합니다. (`macos/AppRoutingSpike/HostHarness/SpikeServiceProtocols.swift:41`, `macos/AppRoutingSpike/HostHarness/ContentView.swift:94`)

## 5. 비협상 불변식 (반드시 보존)

- **증거 등급 분리**: 자동 검사나 컴파일이 통과해도 실제 서명 Mac 항목을 PASS로 올리지 않습니다. 실제 증거가 없으면 `signedMac = INCONCLUSIVE`입니다. (출처: `R1/retrospective-2026-08-04_02-21.md`, `next-project-checklist.md`)
- **단계별 실제 증거**: 시스템 확장 요청 완료, manager 시작, Provider 시작, XPC 실행, 실제 TCP·UDP 수신을 각각 나눕니다. ViewModel에 `evidenceTier = signedMac`이 보이는 것만으로 핵심 게이트를 PASS로 올리지 않습니다. (`macos/AppRoutingSpike/HostHarness/SpikeViewModel.swift:117`)
- **P2와 P3 판정 분리**: 선택 흐름의 안전 실패 게이트는 P2에서 따로 판정합니다. P3 미구현 때문에 흐름 결과가 `inconclusive`인 사실은 그대로 보존하며 이를 P2 PASS나 P3 PASS로 바꾸지 않습니다. (`macos/AppRoutingSpike/TransparentProxyExtension/TransparentProxyProvider.swift:118`)
- **P3 경계**: P0~P2 결과를 WireGuard 전달 성공으로 넓혀 해석하지 않습니다. P3는 별도 설계와 사용자 승인이 있기 전까지 NO-GO입니다. (출처: `R1/retrospective-2026-08-04_02-21.md`)
- **선택 앱 안전 실패**: 신원이 없거나 틀린 선택 흐름과 P3 전송이 없는 선택 흐름은 직접 인터넷으로 보내지 않습니다. (`macos/AppRoutingSpike/Networking/FlowPolicyEvaluator.swift:58`, `macos/AppRoutingSpike/Networking/SelectedFlowTransport.swift:8`)
- **통제 경로 보존**: 유효한 통제 앱과 control plane은 직접 통과해야 합니다. 제어 흐름이 Provider로 재귀하면 실패입니다. (`macos/AppRoutingSpike/Networking/FlowPolicyEvaluator.swift:54`, `macos/AppRoutingSpike/Networking/FlowPolicyEvaluator.swift:74`)
- **소유 상태만 정리**: VPN Router의 manager만 중단하고 제거합니다. 제3자 네트워크·보안 제품은 자동 조작하지 않습니다. (`macos/AppRoutingSpike/HostHarness/TransparentProxyController.swift:79`; 출처: `R1/2026-08-04_00-27_plan_r1-macos-app-routing-spike.md`)
- **민감 정보 최소화**: 실제 설정, 개인 키, 서명 값, 앱 원문 신원, 주소, DNS 내용을 읽거나 기록하지 않습니다. 가린 결과만 씁니다. (`macos/AppRoutingSpike/Shared/SpikeContracts.swift:181`; 출처: `R1/2026-08-04_00-36_design_r1-macos-app-routing-spike.md`)
- **플랫폼 격리**: 이번 Mac 라운드는 `macos/AppRoutingSpike/**`만 개발 대상으로 삼습니다. Windows와 제품 macOS, 릴리스 경로는 읽기·회귀 확인만 합니다. (출처: 사용자 요구사항, `AGENTS.md`)
- **스파이크 로컬 계약 경계**: 제품 공용 DTO/IPC는 비범위입니다. P0~P2 제한 증거에 필요한 경우에만 `AppRoutingSpike/Shared`와 로컬 XPC 계약을 함께 고치고, 확인된 소비처 전체를 재검사합니다. (`macos/AppRoutingSpike/Shared/SpikeContracts.swift:1`; 출처: 사용자 요구사항)

## 6. 수정범위 (예상 파일)

- `macos/AppRoutingSpike/Docs/signed-mac-checklist.md`: 실제 실행표, 성공 범위, 가린 증거와 시각 기록 규칙을 보완합니다.
- `macos/AppRoutingSpike/Docs/spike-decision.md`: signedMac 항목별 최종 판정과 P3 NO-GO를 갱신합니다.
- `macos/AppRoutingSpike/project.yml`, `macos/AppRoutingSpike/Entitlements/HostHarness.entitlements`, `macos/AppRoutingSpike/Entitlements/TransparentProxyExtension.entitlements`: 실제 권한·서명 결함이 확인될 때만 수정합니다. 실제 값과 프로비저닝 전문은 읽거나 저장하지 않습니다.
- `macos/AppRoutingSpike/TransparentProxyExtension/TransparentProxyProvider.swift`: 포함 규칙, TCP/UDP 수신, 흐름 분류, 안전 실패 결함이 확인될 때만 수정합니다.
- `macos/AppRoutingSpike/TransparentProxyExtension/SecurityAuditTokenValidator.swift`: 실제 audit token과 서명 검증 결함이 확인될 때만 수정합니다.
- `macos/AppRoutingSpike/Networking/FlowIdentityVerifier.swift`, `FlowIdentityPolicyAdapter.swift`, `FlowPolicyEvaluator.swift`: 앱 역할과 신원 판정 결함이 확인될 때만 함께 수정합니다.
- `macos/AppRoutingSpike/Networking/SelectedFlowTransport.swift`: P3 경계를 지키는 `.unsupported` 동작을 보존합니다. 변경 예상 없음입니다.
- `macos/AppRoutingSpike/HostHarness/SystemExtensionActivator.swift`, `TransparentProxyController.swift`, `SpikeViewModel.swift`, `ContentView.swift`: 설치, 활성화, 중단, 소유 설정 제거, 수동 회복 확인 결함이 확인될 때만 수정합니다.
- `macos/AppRoutingSpike/TrafficHarness/**` 또는 architect가 정한 동등한 격리 경로: `192.0.2.1:443` TCP·UDP 새 흐름과 별도 통제 인터넷 확인을 만드는 공개 시험용 로컬 하네스를 둡니다. 원문 네트워크·앱 신원은 내보내지 않습니다.
- `macos/AppRoutingSpike/Shared/SpikeContracts.swift`, `HostHarness/SpikeXPCClient.swift`, `TransparentProxyExtension/SpikeXPCService.swift`: 제한 결과나 XPC 결함을 고칠 때만 수정합니다. 소비처 전수 재검사가 필요합니다.
- `macos/AppRoutingSpike/Tests/NetworkingTests/NetworkingTests.swift`, `macos/AppRoutingSpike/Tests/HostHarnessTests/SpikeViewModelTests.swift`, `macos/AppRoutingSpike/Scripts/verify-source-safety.sh`: 발견된 결함의 자동 재현과 재검사를 추가합니다. Provider 결합 시험은 격리된 새 시험 파일이 필요할 수 있습니다.
- `macos/VPNRouter/**`, `windows/**`, 릴리스 문서·태그·산출물은 수정하지 않습니다.

> 현재 수정 후보 하한은 기존 개별 파일 21개입니다. 실제 결함이 없는 조건부 파일은 바꾸지 않습니다. 새 `TrafficHarness`와 Provider 결합 시험의 파일 수는 architect가 표적 구성을 정한 뒤 확정하므로 현재 미정입니다.

## 7. 열린 질문 (OQ — 사용자/architect 판단)

- ✅ **사용자 결정 반영**: PASS는 핵심 게이트로 한정합니다. 공개 시험용 로컬 TCP·UDP 하네스를 마련합니다. 정리는 manager 설정 제거와 네트워크 회복까지입니다. 시스템 확장 deactivation은 제외합니다. `ai-drafts/`는 보존합니다. (출처: 사용자 추가 답변)
- ❓ **architect — 통제 흐름 증거 방법**: 현재 `.directPass`는 결과를 남기지 않습니다. 원문 앱 신원이나 목적지를 저장하지 않으면서 control app과 control plane의 판정, 일반 인터넷 성공을 연결할 제한 결과 형식을 정해야 합니다. (`macos/AppRoutingSpike/TransparentProxyExtension/TransparentProxyProvider.swift:105`)
- ❓ **architect — 하네스 구성**: 선택 앱과 통제 앱의 서로 다른 서명 신원을 실제로 만들면서 `192.0.2.1:443` 수신과 도달 가능한 통제 인터넷 확인을 분리할 하네스 표적 구성을 정해야 합니다. 수동 `route`, `networksetup`, 인터페이스 주소 추가는 허용하지 않습니다. (`macos/AppRoutingSpike/Scripts/verify-source-safety.sh:13`)
- ⚪ **미확인 선행 조건**: 실제 개발 팀 권한과 이 Mac용 프로비저닝은 아직 확인되지 않았습니다. 준비됨을 추정하지 않습니다. 확인 전에는 실제 서명 설치를 실행하지 않으며 `signedMac`은 `inconclusive`입니다. (출처: 사용자 추가 답변)

## 8. 위험 요소 (스스로 발견한 보완점)

- ⚠️ **통제 흐름이 결과에 없음**: `.directPass`는 `false`만 반환하고 `RedactedFlowResult`를 만들지 않습니다. 현재 결과 파일만으로는 통제 앱과 control plane의 신원 판정이 실제로 일어났는지 확인할 수 없습니다. 규모: 이번 핵심 PASS 게이트 2개에 직접 영향합니다. (`macos/AppRoutingSpike/TransparentProxyExtension/TransparentProxyProvider.swift:105`)
- ⚠️ **수신 대상과 인터넷 성공 대상이 다름**: `192.0.2.1`은 현재 코드의 문서용 시험 대상입니다. 이 흐름의 직접 통과 결과만으로 일반 인터넷 성공을 증명할 수 없습니다. Provider 수신과 통제 인터넷 확인을 별도 결과로 나눠야 합니다. (`macos/AppRoutingSpike/TransparentProxyExtension/TransparentProxyProvider.swift:17`)
- ⚠️ **하네스가 아직 없음**: 현재 저장소에는 TCP·UDP 실제 새 흐름을 만드는 `NWConnection`/`NWListener` 코드가 없습니다. 하네스 구현과 서명 표적 연결을 먼저 끝내지 않으면 실제 Provider 결함과 입력 부재를 구분할 수 없습니다. 규모: TCP와 UDP 핵심 셀 2개 모두에 영향합니다. (출처: 라이브 코드 검색, 2026-08-11 18:13 KST)
- ⚠️ **소스 안전 검사 허용 경계**: 현재 검사는 `Networking`과 Extension의 `NWConnection`만 금지합니다. 새 하네스에 `NWConnection`을 넣으면 “P3 전송은 계속 없음”을 보여 주는 경로별 허용 목록 검사가 필요합니다. (`macos/AppRoutingSpike/Scripts/verify-source-safety.sh:7`)
- ⚠️ **수동 체크의 증거 약함**: DNS·IPv4·IPv6 회복은 화면 토글만으로 완료할 수 있습니다. 외부 측정 결과, 시각, 시작 전 기준선이 없으면 재현하기 어렵습니다. 원문 주소와 DNS 내용을 남기지 않는 제한 안에서 측정 방법과 제한 결과 형식을 정해야 합니다. (`macos/AppRoutingSpike/HostHarness/ContentView.swift:94`)
- ⚠️ **회복의 절대값 오판**: 현재 화면은 DNS·IPv4·IPv6를 모두 `true`로 받아야 정리 성공입니다. 시작 전부터 IPv6가 없던 환경에서는 정상 회복도 실패로 오판할 수 있고, 반대로 사용자가 토글만 켜면 실제 회복 없이 성공으로 오판할 수 있습니다. 시작 전 기준선과 같은 상태로 돌아왔는지 비교해야 합니다. (`macos/AppRoutingSpike/HostHarness/SpikeViewModel.swift:180`)
- ⚠️ **설치 결과 값 무시와 단계 혼동**: activator는 `didFinishWithResult`의 값을 나누지 않고 성공으로 끝냅니다. ViewModel은 곧바로 권한 준비 상태와 `signedMac` 증거 등급을 올릴 수 있습니다. 설치 요청, 완전한 활성화, manager 시작, Provider/XPC 시작, 실제 흐름을 각각 증명해야 합니다. (`macos/AppRoutingSpike/HostHarness/SystemExtensionActivator.swift:24`, `macos/AppRoutingSpike/HostHarness/SpikeViewModel.swift:75`, `macos/AppRoutingSpike/HostHarness/SpikeViewModel.swift:117`)
- ⚠️ **deactivation 비범위 혼동**: `removeOwnedConfiguration()`은 manager preference만 지웁니다. 시스템 확장 deactivation이 없는 것은 이번 실패가 아닙니다. 대신 manager 설정 0개와 네트워크 회복을 확인하지 못하면 정리 PASS를 주지 않습니다. (`macos/AppRoutingSpike/HostHarness/TransparentProxyController.swift:60`; 사용자 추가 답변)
- ⚠️ **manager 중복 잔존 가능성**: 조회 조건은 provider bundle identifier 하나이고 첫 항목만 고릅니다. 같은 식별자의 오래된 설정이 여러 개면 정리 뒤에도 남을 수 있습니다. 규모는 미측정입니다. 정리 뒤 `loadAllFromPreferences`를 다시 실행해 일치 항목 0개를 증명해야 합니다. (`macos/AppRoutingSpike/HostHarness/TransparentProxyController.swift:79`)
- ⚠️ **중단과 제거 사이 경합**: `stopVPNTunnel()`은 완료 상태를 기다리지 않고 곧바로 비활성 저장과 설정 제거로 이어집니다. 연결 상태 전환이 늦으면 네트워크 회복 확인 시점이 앞설 수 있습니다. 제한 시간과 상태 관찰이 필요하며, 시간 안에 확인하지 못하면 정리 게이트는 `inconclusive` 또는 `fail`로 남겨야 합니다. (`macos/AppRoutingSpike/HostHarness/TransparentProxyController.swift:50`, `macos/AppRoutingSpike/HostHarness/SpikeViewModel.swift:151`)
- ⚠️ **P2 안전 실패와 P3 결과 축 충돌**: 현재 선택 흐름 결과는 P3 미구현 때문에 `inconclusive`입니다. 이를 그대로 P2 실패로 읽으면 안전 실패를 검증할 수 없고, 반대로 `pass`로 바꾸면 P3 성공처럼 보입니다. 별도 핵심 게이트 표가 필요합니다. (`macos/AppRoutingSpike/TransparentProxyExtension/TransparentProxyProvider.swift:118`)
- ⚠️ **로컬 계약 범위 확장**: 통제 흐름 제한 증거를 추가하려고 제품 공용 DTO/IPC까지 바꾸면 비범위를 침범합니다. `AppRoutingSpike/Shared`와 로컬 XPC 안으로 제한하고, `SpikeRunRequest`와 `RedactedFlowResult`의 확인된 소비처 12개씩을 다시 검사해야 합니다. (`macos/AppRoutingSpike/Shared/SpikeContracts.swift:152`, `macos/AppRoutingSpike/Shared/SpikeContracts.swift:181`)
- ⚠️ **서명 선행 조건 미확인**: 실제 권한과 프로비저닝이 없으면 설치·활성화·실제 흐름은 실행할 수 없습니다. 자동 결함 수정은 진행할 수 있지만 signedMac 핵심 게이트는 `inconclusive`로 남습니다. (출처: 사용자 추가 답변, `R1/retrospective-2026-08-04_02-21.md`)
- ⚠️ **작업 트리 기준선**: 기존 `ai-drafts/` 때문에 시작 전 clean 상태가 아닙니다. 사용자 결정에 따라 이 경로를 보존하고 R3 변경 집계에서 제외해야 합니다. `(출처: git status, 2026-08-11 18:13 KST; 사용자 추가 답변)`
- ⚠️ **제3자 제품 보호 경계**: 이번에는 다른 VPN·DNS·광고 차단·백신·보안 제품의 전환 매트릭스를 실행하지 않습니다. 코드와 실행 절차가 이 제품들을 자동 변경하지 않는지만 확인합니다. 제3자 제품을 바꾸지 않았다는 전제에서만 보호 판정이 성립하며, 사용자가 직접 바꾼 상태의 영향 규모는 미측정입니다. (출처: 사용자 요구사항)

## 9. 관련 문서·메모리·차수

- `docs/R1-cross-platform-app-routing-prebrief-2026-08-03.md`: 앱 선택 라우팅의 첫 기술 검증 준비 문서입니다.
- `macos/AppRoutingSpike/Docs/signed-mac-checklist.md`: 이번 실제 실행의 기본 수동 체크리스트입니다.
- `macos/AppRoutingSpike/Docs/spike-decision.md`: 현재 자동 PASS, signedMac INCONCLUSIVE, P3 NO-GO 판정입니다.
- `R1/retrospective-2026-08-04_02-21.md`: 자동 검사와 실제 서명 증거를 나누고 P3 경계를 지킨 회고입니다.
- `R1/2026-08-04_02-27_notification_r1-macos-app-routing-spike.md`: P0~P2 구현과 남은 signedMac 게이트를 요약합니다.
- `next-project-checklist.md`: 미완료 53건 중 이번에 닫을 3건을 §3-1에 골랐습니다.
- `backlog.md`: 다음 라운드 후보는 Windows WFP 항목뿐입니다. 이번 macOS 요청은 후보 목록에 없던 요청입니다.
- `journal-digest.md`: 최신 저널의 활성 제약은 Windows와 PMO 이관 중심입니다. macOS P0~P2 코드 제약은 R1 문서와 실제 코드에서 다시 확인했습니다.
- 직전 회고 협업 제안 반영(AI에게): 실제 소유자 시험과 제품 구현을 분리합니다. 이번에는 실제 macOS 시험을 승인된 범위에서만 수행하고 P3·제품 통합은 계속 분리합니다. (출처: `R2/retrospective-2026-08-10_19-15.md` §8)

## 10. 검증 기록

- 1차 검증: 사용자 답변 5건을 반영해 PASS 범위를 핵심 게이트로 좁혔습니다. 공개 시험용 TCP·UDP 하네스와 manager 정리 범위를 명시했습니다. 사람 수행·미확인 권한 항목을 §3-1에서 빼고, 이번에 코드·문서로 닫을 수 있는 3건으로 바꿨습니다. 코드·DB·RAG·체크리스트를 독립 재조회하고 자동 검사 23/23 및 안전·격리·plist 검사를 다시 실행했습니다.

| 초안 항목 | 1차 독립 재확인 | 정정 |
|---|---|---|
| PMO RAG 유사도 0.56~0.57 | 새 독립 질의 결과 0.50~0.54 | 현재 조회값으로 갱신. 유사도는 질의에 따라 달라지므로 사실 판정은 실제 파일·코드 재확인을 사용 |
| manager 조회가 bundle identifier와 설명을 모두 비교 | `loadOwnedManager()`는 provider bundle identifier만 비교 | §2와 §8을 실제 코드에 맞게 수정 |
| signedMac 전체 매트릭스가 PASS 후보 | 사용자는 TCP·UDP와 핵심 안전·복구 게이트만 PASS 범위로 확정 | QUIC·DNS·수명 전체 매트릭스는 보조 관찰로 이동 |
| Team 권한·프로비저닝 확인을 이번 체크리스트 해소 항목으로 선정 | 상태가 미확인이며 사람이 확인해야 하는 선행 조건 | §3-1에서 제거하고 §7 미확인 선행 조건으로 이동 |
| 통제 앱은 직접 통과한다는 정책 사실만 기록 | Provider의 `.directPass`는 제한 결과를 남기지 않음 | 실제 통제 경로 증거 공백을 §2·§7·§8에 추가 |

- **1차 현재 준비도**: 조건부 GO 후보 — 자동 개발과 하네스 준비는 시작할 수 있습니다. 실제 서명 설치·핵심 PASS 판정은 권한과 프로비저닝 준비 여부를 확인한 뒤에만 진행할 수 있습니다.
- 2차 검증: 핵심 PASS 게이트와 비범위를 적대적으로 다시 맞췄습니다. 설치 요청 완료와 실제 활성화·흐름 증거를 분리했습니다. P2 안전 실패와 P3 `inconclusive`를 별도 판정 축으로 고정했습니다. 통제 경로의 증거 공백, manager 중복 잔존, 중단 상태 경합, 기준선 없는 네트워크 회복 오판을 시작 전 위험으로 보강했습니다. 제품 공용 DTO/IPC는 제외하되 스파이크 로컬 제한 계약만 필요할 때 수정할 수 있도록 경계를 명확히 했습니다. §3-1의 3건은 모두 이번 코드·시험·결과표 안에서 닫히며 Windows, P3, 제품 통합, deactivation 비범위와 충돌하지 않습니다.
- 2차 소스 재확인: 운영 DB는 다시 연결됐지만 관련 테이블은 없었습니다. 로그 입력은 계속 없습니다. 코드 RAG는 0건, PMO RAG는 관련 8건과 유사도 0.47~0.50을 반환했습니다. 유사도는 질의에 따라 달라지므로 판정 근거로 쓰지 않았습니다. 체크리스트 미완료 53건과 §3-1 원문 3건도 다시 일치했습니다. (출처: 운영 DB·RAG·`next-project-checklist.md`, 2026-08-11 18:20 KST)
- **최종 판정: 조건부 GO** — 자동 기획·하네스 개발·자동 검사는 지금 시작할 수 있습니다. 실제 서명 설치와 LIVE 실행은 사용자가 개발 팀 권한 및 이 Mac용 프로비저닝의 준비 여부만 확인한 뒤 진행합니다. 값을 읽거나 기록하지 않습니다. 준비되지 않았거나 확인되지 않으면 signedMac 핵심 게이트는 `INCONCLUSIVE`로 끝내며 설치를 시도하지 않습니다.

### 최종 집계

- 비협상 불변식 10개입니다.
- 수정 후보는 기존 개별 파일 21개입니다. 새 하네스와 Provider 결합 시험 파일 수는 architect 결정 전이라 미정입니다.
- 열린 질문 2개, 위험 15개입니다. 별도로 실제 서명 전 미확인 선행 조건 1개가 있습니다.
- 운영 DB는 연결됐지만 관련 테이블이 없습니다. 로그는 입력 경로가 없습니다. 코드 RAG는 0건이고 PMO RAG는 관련 결과가 있습니다.
- 체크리스트는 미완료 53건 중 3건을 선정했습니다.

## 11. 파이프라인 시작

- 사용자 직접 실행(자동 진입 안 함). 권장 PM 입력 시드: `docs/R3-macos-signed-transparent-proxy-validation-prebrief-2026-08-11.md`를 R3의 근거 문서로 읽고, §3의 핵심 PASS 범위와 §5 불변식을 채택합니다. 먼저 공개 시험용 TCP·UDP 하네스와 제한 결과 경로를 만듭니다. 실제 서명 단계 직전에 권한·프로비저닝의 준비 여부만 사용자에게 확인합니다. 준비됐다고 확인된 경우에만 설치와 LIVE 실행으로 넘어갑니다.
- **§3-1을 PM 입력에 그대로 붙여 넣을 것** — PM은 그 표를 자기 선정 결과로 채택해 체크리스트를 그만큼 비웁니다 (`pm.md` §0.2).
