# macOS 앱 라우팅 스파이크 결정

> 마지막 갱신: 2026-08-14 — 실제 서명 Mac LIVE 실행 결과를 반영했습니다.

## 현재 판정

| 증거 | 판정 | 의미 |
|---|---|---|
| 계약·정책·가림·정리 자동 검사 | `pass` | P0~P2 코드 구조와 안전 실패 분기를 확인했습니다. |
| unsigned 컴파일·빌드 | `pass` 또는 실행 결과 참조 | 소스와 표적 구성이 컴파일된다는 뜻뿐입니다. |
| 실제 서명 Mac 활성화·TCP/UDP 수신·앱 신원 | `pass` | 2026-08-14 서명·공증 빌드로 실행했습니다. 실행 11 · 통과 11 · 실패 0. (`Docs/signed-mac-live-run-2026-08-14.md`) |
| 선택 흐름 WireGuard 전달 | `inconclusive` / NO-GO | P3 승인 범위 밖이며 공식 연결점이 확인되지 않았습니다. |
| 제품 통합 | NO-GO | 필수 흐름과 배포·복구 근거가 없습니다. |

`automated`, `signedMac`, `p3ProductIntegration`은 서로 독립된 판정 축입니다. 2026-08-14 실행으로 `signedMac`의 P0~P2 핵심 게이트가 `pass`가 됐습니다. 이 결과를 `p3ProductIntegration`으로 옮기지 않습니다. P3와 제품 통합은 그대로 NO-GO입니다. Windows 판정도 이 결과로 대신하지 않으며 별도 실기로 세웁니다.

## P2 안전 불변식

- 선택 앱 signing/team identifier는 활성 실행 동안 Provider 메모리에만 있고, 멱등 기록에는 SHA-256 지문만 최대 32건 보관합니다. snapshot·로그·설정 파일에는 저장하지 않습니다.
- 통제 앱과 helper는 audit token의 관찰된 bundle identifier가 일치하는 유효 서명일 때 직접 통과합니다. 선택 앱 Team ID를 요구하지 않습니다.
- Host·Extension 제어 흐름은 제어 allowlist, 관찰된 bundle identifier, Host Team ID가 모두 일치할 때 직접 통과해 재귀를 막습니다.
- 정확히 일치하고 코드 서명이 유효한 선택 흐름은 `true`로 소유한 뒤 닫습니다.
- 앱 식별자가 없거나 audit token 검증이 실패하면 흐름을 닫고 실행을 실패 상태로 바꿉니다.
- 동시에 처리하는 선택 흐름은 256개로 제한하고, 증거 2,000건 버퍼가 차면 실행을 실패 상태로 바꿔 이후 흐름을 닫습니다.
- `SelectedFlowTransport`는 `unsupported`만 반환하며 `NWConnection`을 만들지 않습니다.
- 선택 흐름 결과는 `wireguard-transport-unavailable`과 `inconclusive`로 기록합니다. VPN 경로 성공으로 올리지 않습니다.
- 정리 순서는 새 흐름 거부 → Provider 중단 확인 → 소유 manager 전건 제거 → manager 0건 재조회 → DNS·IPv4·IPv6 기준선 비교입니다.
- `ProviderFlowBridge`는 Provider 투영부터 신원 검증·정책·최종 Bool·가려진 결과까지 한 경로로 연결합니다. 통제 흐름도 `directPass` 결과를 남긴 뒤 `false`를 반환합니다.
- 실제 TCP·UDP 흐름은 서로 다른 번들 식별자를 가진 Selected/Control Traffic Harness가 만들며, `NWConnection`은 하네스 지원 코드 한 곳에서만 사용합니다.

## 실제 서명 게이트 — 2026-08-14 실행 결과

사용자가 승인한 서명 Mac에서 아래 게이트를 모두 확인했습니다. 권한·프로비저닝, 시스템 확장 설치와 활성화, TCP·UDP 새 흐름 수신, `sourceAppSigningIdentifier`와 audit token 일치, 선택 앱 안전 실패, 통제 앱과 제어 경로의 직접 통과, 중단 뒤 소유 manager 0건, DNS·IPv4·IPv6의 설치 전 기준선 회복입니다. 시간순 실행표와 가려진 결과는 `Docs/signed-mac-live-run-2026-08-14.md` 에 있습니다.

이번 실행에서 확인하지 않은 것은 그대로 남습니다. DNS·QUIC·IPv6 경로 처리와, 앱 재실행·다시 연결·잠자기·깨우기·주 네트워크 변경·다른 VPN 전환 뒤의 같은 결과 확인입니다. 이 항목들은 통과했다고 적지 않습니다. 이 Mac은 시작할 때부터 IPv6가 없었고 회복 비교의 기준도 없음입니다.

P3부터는 범용 사용자 공간 전송 계층 또는 별도 원격 프록시가 필요할 가능성이 높습니다. 성능·보안·배포·운영 범위를 바꾸므로 이번 라운드에서는 구현하지 않습니다.

## 설계와 다른 구현

| 항목 | 설계 원문 | 구현 | 사유 |
|---|---|---|---|
| XPC 호출자 인증 | audit token 또는 동등한 코드 서명 증거로 정확한 Host를 확인 | `NSXPCConnection.setCodeSigningRequirement`에 Host bundle identifier와 Team ID를 함께 고정하고, 같은 사용자 및 PID 기반 `SecCode` 검사를 보조로 수행 | 공개 연결 API 안에서 연결 수명 전체에 지정 요구 조건을 적용하기 위함 |
| 실행 멱등 기록 | 선택 식별자는 Provider 메모리에서만 보유 | 활성 요청만 원문으로 보유하고 종료 뒤 SHA-256 지문·응답만 최대 32건 유지 | 재시도 멱등성과 민감 식별자 최소 보유를 함께 충족하기 위함 |
| 역할별 Team 검증 | 선택 앱과 비선택 앱의 신원 검증 | 선택 앱에는 선택 Team, 제어 흐름에는 Host Team, 그 밖의 앱에는 Team 제한 없이 관찰 식별자와 유효 서명을 요구 | 다른 회사가 서명한 정상 통제 앱을 보존하면서 선택 앱 위장을 차단하기 위함 |

`NEFlowMetaData.sourceAppAuditToken`은 흐름 앱 신원 검증에 사용하며 bundle identifier와 Team ID를 함께 검사합니다. private API는 사용하지 않았습니다. 실제 연결 시점 안전성은 2026-08-14 실행에서 확인했습니다. 그 과정에서 XPC 연결을 앱 시작 시점에 미리 만들던 문제와, 확장이 root·앱이 로그인 사용자라 통과할 수 없던 접속 사용자 검사를 함께 고쳤습니다.
