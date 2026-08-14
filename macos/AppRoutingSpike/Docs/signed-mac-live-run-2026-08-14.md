# 서명 Mac 실제 실행 기록 — 2026-08-14

이 문서는 실제 서명·공증된 빌드를 이 Mac에 설치해 관찰한 결과만 적습니다. 자동 검사 결과를 옮겨 적지 않았습니다.
Team ID, 인증서 이름, 프로비저닝 전문, 실제 번들 식별자, 주소, DNS 내용은 적지 않습니다.

- 증거 등급: `signedMac`
- 후보: `transparentProxy`
- 범위: P0~P2. P3 WireGuard 전달과 제품 통합은 하지 않았습니다.
- 실행 빌드: 7 (Host·Extension 모두)

## 1. 실행 전 게이트

| 게이트 | 확인 방법 | 결과 |
|---|---|---|
| 개발 팀 권한 | 서명된 앱에서 entitlement 키 이름만 읽음 | Host에 시스템 확장 설치·Network Extension·App Group, Extension에 Network Extension·App Group |
| 이 Mac용 프로비저닝 | 내장 프로파일의 허용 목록과 만료일만 읽음 | 두 프로파일 모두 내장·유효. 기기 목록이 없는 배포형이라 이 Mac에서 씁니다 |
| 사용자 승인 | `systemextensionsctl` 상태 | 설치 요청 뒤 `activated waiting for user` → 약 60초 뒤 `activated enabled`. 앞선 승인이 이월되어 추가 조작은 없었습니다 |
| 다른 보안 제품 | 시작 전후 목록 비교 | 광고 차단·메시 VPN·기존 DNS 프록시 확장 상태가 시작 전후 같습니다. Harness는 이들을 건드리지 않았습니다 |
| 시험 앱 | 선택 앱 1개, 통제 앱 1개 | 서명 식별자가 서로 다르고 팀은 같습니다 |
| fixture | 예약 문서 주소만 사용 | 실제 설정·개인 키를 고르지 않았습니다 |

## 2. 시간순 실행표

시각은 이 Mac의 현지 시각입니다.

| 시각 | 한 일 | 관찰한 것 |
|---|---|---|
| 19:17:12 | 설치 전 기준선 측정 | DNS 사용 가능 · IPv4 사용 가능 · IPv6 없음 |
| 19:17:2x | 빌드 7 설치 | 공증 티켓 확인, Gatekeeper 통과, 서명 검증 통과 |
| 19:17:4x | 시스템 확장 설치 요청 | `activated waiting for user` |
| 19:18:5x | 승인 상태 확인 | `activated enabled` |
| 19:19:48 | 시험 시작 | 세션 `connected`, Provider `startProxy` 호출됨 |
| 19:19:48 | 제어 경로 흐름 1건 (Host가 직접 생성) | `directPass` · `pass` · 새 흐름 |
| 19:20:12 | 선택 앱 새 TCP 흐름 | `ownedAndClosed` · `inconclusive` (WireGuard 전달 없음) |
| 19:20:15 | 선택 앱 새 UDP 흐름 | `ownedAndClosed` · `inconclusive` (WireGuard 전달 없음) |
| 19:20:23 | 통제 앱 새 TCP 흐름 | `directPass` · `pass` |
| 19:20:26 | 통제 앱 새 UDP 흐름 | `directPass` · `pass` |
| 19:20:3x | 통제 앱 일반 인터넷 확인 (시험 중) | 사용 가능 |
| 19:20:44 | 시험 중단 | 중단 명령 → `disconnected` → 세션 제거 → 설정 제거 |
| 19:21:09 | 중단 뒤 측정 | DNS 사용 가능 · IPv4 사용 가능 · IPv6 없음 · 소유 설정 0건 |
| 19:21:1x | 정리 뒤 통제 앱 일반 인터넷 확인 | 사용 가능 |
| 19:21:26 | 회복 비교 완료 | `signedMac` 판정 `PASS` (실행 11 · 통과 11 · 실패 0) |

## 3. 역할별 흐름 판정

| 앱 역할 | 새 TCP | 새 UDP | 일반 인터넷 |
|---|---|---|---|
| 선택 앱 | 소유·닫힘 | 소유·닫힘 | 해당 없음 |
| 통제 앱 | 직접 통과 | 직접 통과 | 사용 가능 |
| 제어 경로 | 직접 통과 | 하지 않음 (설계상 보조) | 사용 가능 |

- 선택 앱 흐름이 일반 인터넷으로 조용히 빠지지 않았습니다. 소유한 뒤 닫혔습니다.
- 선택 앱 판정이 `inconclusive`인 것은 정상입니다. P2는 흐름 수신과 앱 신원까지만 보고 WireGuard 출구는 이번 범위가 아닙니다.
- 제어 경로 재귀는 0건입니다. Provider가 소유한 흐름 중 이 시험 자신의 흐름은 없습니다.

## 4. 정리 확인

설계가 정한 순서를 그대로 지켰습니다.

1. 새 흐름 거부
2. Provider 중단 확인 — 관찰함
3. 소유 설정 전건 제거 — 관찰함
4. 같은 Provider의 설정 0건 재조회 — 0건
5. DNS·IPv4·IPv6를 설치 전 기준선과 비교 — 세 항목 모두 기준선과 같음

수동 경로 변경, 네트워크 설정 변경, 시스템 DNS 변경은 하지 않았습니다.

## 5. 실제 기기에서만 드러난 결함

이번 실행 전까지 자동 검사는 계속 10/10으로 통과했지만, 실제 기기에서 아래 결함들이 차례로 드러났습니다.

| 결함 | 증상 | 고친 방법 |
|---|---|---|
| 시스템 확장 폴더 이름 | 설치가 `code=4`로 거절됨 | 폴더 이름을 번들 식별자와 같게 만듦 |
| 설정 다시 읽기 누락 | 저장 직후 시작해 "아직 불러오지 않음"으로 실패 | 저장 뒤 다시 읽는 단계를 넣음 |
| 설치본 교체 | 이전 등록이 새 설치본을 붙잡음 | 빌드 번호를 올려 갱신 경로로 설치 |
| Mach 서비스 이름 | App Group 접두사 규칙과 어긋남 | 프로파일의 App Group 값으로 이름을 만듦 |
| 서명·프로파일 불일치 | 프로세스가 즉시 종료됨 | 프로파일에서 허용 값을 직접 뽑아 다시 서명 |
| 확장 진입점 | 시작 함수만 부르고 20ms 만에 종료 | 메인 루프를 추가해 프로세스를 살림 |
| 공급자 클래스 이름 | plist가 가리키는 모듈 이름과 실제 Swift 모듈 이름이 다름 | 모듈 이름을 빌드 설정에 고정하고 자동 검사에 이름 대조를 넣음 |
| XPC 연결 시점 | 앱을 켤 때 연결을 만들어 두어, Provider가 뜨기 전 이름 조회 실패로 그 연결이 영영 못 쓰게 됨 | 첫 요청 때 연결하고 끊기면 다시 연결하도록 바꿈 |
| 접속 사용자 검사 | 확장은 root, 앱은 로그인 사용자라 "확장과 같은 사용자" 조건이 절대 통과할 수 없음 | "지금 로그인한 사용자"인지 보도록 고침. 서명 요구 조건은 그대로 둠 |
| 제어 경로 흐름 없음 | 설계가 정한 Host의 흐름 1건이 구현되지 않아 판정이 `INCONCLUSIVE`에 갇힘 | Host가 시작 직후 흐름을 한 번 만들도록 연결 |

## 6. 남은 한계

- DNS, QUIC, IPv6 경로는 이번에 확인하지 않았습니다. 성공으로 적지 않습니다.
- 이 Mac은 시작할 때부터 IPv6가 없었습니다. 회복 비교에서도 없음이 기준입니다.
- 앱 재실행, 다시 연결, 잠자기·깨우기, 주 네트워크 변경, 다른 VPN 전환 뒤의 같은 결과 확인은 아직 하지 않았습니다.
- P3 WireGuard 전달과 제품 통합은 사용자 승인 전까지 하지 않습니다.
- Windows 실제 시험은 이 작업과 섞지 않고 별도 Windows PC에서 합니다.

## 7. 가려진 결과 요약

```json
{
  "schemaVersion": 2,
  "validationSummaries": [
    { "validationAxis": "automated", "validationVerdict": "notRun", "executedCount": 0, "passedCount": 0, "failedCount": 0 },
    { "validationAxis": "signedMac", "validationVerdict": "pass", "executedCount": 11, "passedCount": 11, "failedCount": 0 },
    { "validationAxis": "p3ProductIntegration", "validationVerdict": "noGo", "executedCount": 0, "passedCount": 0, "failedCount": 0 }
  ],
  "cleanupSummary": {
    "providerStopObserved": true,
    "managerCountAfterCleanup": 0,
    "dnsMatchedBaseline": true,
    "ipv4MatchedBaseline": true,
    "ipv6MatchedBaseline": true
  },
  "resultCount": 5
}
```

내보낸 파일에서 Team ID, 실제 번들 식별자, 주소, 인증서·프로비저닝 정보, 사용자 이름, 앱 경로가 모두 0건인 것을 확인했습니다.

`automated` 칸이 `notRun`인 것은 이 앱 화면이 자동 검사를 직접 실행하지 않기 때문입니다. 자동 검사는 별도로 `Scripts/run-r3-automated-validation.sh`가 10개 검사 전건 통과로 기록합니다.
