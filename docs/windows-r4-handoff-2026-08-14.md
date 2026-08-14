# Windows 인계 — R4 파이프라인과 WFP 실제 시험 준비 (2026-08-14)

이 문서는 macOS에서 끝낸 R3 작업을 Windows PC에서 이어받기 위한 인계장입니다.
Windows에서 파이프라인을 새로 돌리고, macOS와 같은 방식으로 실제 기기 시험까지 하는 것이 목표입니다.

## 1. 지금 어디까지 왔나

| 차수 | 플랫폼 | 무엇을 | 결과 |
|---|---|---|---|
| R1 | macOS | 앱별 라우팅 후보 비교 | Transparent Proxy만 조건부 생존 |
| R2 | Windows | 사용자 모드 WFP 스파이크 하네스 | 코드·자동 검사까지. 실제 소유자 시험은 미실행 |
| R3 | macOS | 실제 서명 Mac에서 P0~P2 검증 | **`signedMac` = PASS (실행 11 · 통과 11 · 실패 0)** |

R3에서 확인한 것은 이것입니다. **관리되지 않는 일반 Mac에서, 사용자가 고른 앱의 새 TCP·UDP 흐름을 신원을 확인해 소유할 수 있다.** 통제 앱은 그대로 통과하고, 중단하면 DNS·IPv4·IPv6가 설치 전으로 돌아옵니다.

자세한 관찰 기록은 `macos/AppRoutingSpike/Docs/signed-mac-live-run-2026-08-14.md` 에 시간순 실행표로 있습니다.

R3에서 답이 나지 않은 것은 **P3** 입니다. 받은 흐름을 실제 WireGuard 터널로 넘기는 공식 연결점이 아직 확인되지 않았습니다. 이건 macOS 쪽 숙제이고 Windows 차수의 범위가 아닙니다.

## 2. Windows PC에서 가장 먼저 할 일 — 차수 맞추기

**파이프라인을 실행하기 전에 반드시 합니다.** 건너뛰면 2026-08-10에 실제로 났던 사고가 되풀이됩니다. 그때는 파이프라인이 스스로를 R1으로 적어 문서 23개를 옮기고 참조 53군데를 고쳐야 했습니다.

PMO 폴더는 저장소가 아니라 별도 폴더에 있고 자동 동기화가 없습니다. macOS에서 만든 압축본을 옮겨 풀어야 합니다.

```text
받을 파일: insight-hub-vpn_router-PMO-2026-08-14.zip
푸는 위치: <문서 폴더>\insight-hub\
결과 경로: <문서 폴더>\insight-hub\vpn_router\
```

푼 뒤 아래 세 가지를 눈으로 확인합니다.

1. `vpn_router\.current-round` 파일이 있고 값이 `R3` 이다 — 숨김 파일이라 탐색기 설정에 따라 안 보일 수 있습니다.
2. `vpn_router\R1`, `R2`, `R3` 폴더가 모두 있다 (각각 23 · 23 · 25건).
3. `vpn_router\backlog.md`, `next-project-checklist.md`, `journal-digest.md` 가 있다.

**이번에 Windows에서 돌릴 차수는 `R4` 입니다.** `.current-round` 값이 `R3` 이므로 다음 차수는 `R4` 입니다. 파이프라인이 R1이나 R3으로 적으려 하면 멈추고 차수부터 바로잡습니다.

기존 Windows PC에 이미 `insight-hub\vpn_router` 가 있다면 **덮어쓰기 전에 그쪽에만 있는 파일이 없는지 확인**합니다. R2 산출물은 원래 Windows에서 만들어 macOS로 옮겨 온 것이라, 양쪽에 서로 다른 판본이 있을 수 있습니다.

## 3. 저장소 받기

```powershell
cd <저장소 폴더>\vpn_router
git pull
git log --oneline -3
```

macOS R3 작업이 들어와 있어야 합니다. `macos/AppRoutingSpike/Docs/signed-mac-live-run-2026-08-14.md` 파일이 보이면 제대로 받은 것입니다.

Windows 코드(`windows/`, `scripts/windows/`)는 R2 이후 바뀐 것이 없습니다.

## 4. Windows에서 할 일

### 4-1. 파이프라인 (R4)

백로그와 체크리스트에 Windows 몫으로 이미 분리해 둔 항목들이 있습니다.

- `M-001`~`M-064` 데스크톱 사례와 실제 AC 12개를 하나의 실행표로 연결
- `R3-OWNER-01`~`03` 소유자 WFP 실제 검증 후보
- `R3-DEC-04` 사용자 모드 WFP가 부족할 때 커널 driver 연구 여부 — 사용자 결정 대기

### 4-2. 실제 기기 시험

| 수단 | 위치 |
|---|---|
| 자동 검사 | `scripts/windows/test-wfp-app-routing-spike.ps1` |
| 소유자 실행 하네스 | `windows/VpnRouter.WfpSpike.Harness/OwnerHarnessRunner.cs` |
| 관찰 수집 | `windows/VpnRouter.WfpSpike.Harness/WfpObservationCollector.cs` |
| 네트워크 복구 | `scripts/windows/restore-network-dev.ps1` |

관리자 권한 환경이 필요하고, macOS와 마찬가지로 **시작 전 기준선 → 흐름 생성 → 중단 → 회복 비교** 순서를 지킵니다.

## 5. macOS R3에서 배운 것 — Windows에서도 그대로 적용됩니다

오늘 macOS에서 실기 결함이 **10개** 나왔습니다. 그동안 자동 검사는 계속 10/10 초록이었습니다. Windows WFP 실제 시험에서도 같은 종류의 문제가 나올 것이므로 미리 적어 둡니다.

**자동 검사 초록은 실제 동작 증거가 아닙니다.** 컴파일이 되고 단위 시험이 통과하는 것과, 필터가 실제로 커널에 올라가고 트래픽을 가르는 것은 다른 이야기입니다. 판정 칸을 처음부터 나눠 두고, 실기 증거가 없으면 그 칸은 `INCONCLUSIVE` 로 둡니다.

**"관찰하지 못함"을 "실패 아님"으로 세지 마세요.** 오늘 가장 오래 걸린 결함이 이것이었습니다. 판정 배열에 `nil`(관찰 못 함)이 하나 섞여 있었는데, 그 관찰을 만들어 낼 수단이 하네스에 아예 없었습니다. 그래서 판정이 구조적으로 `PASS` 에 도달할 수 없는데도 오류는 나지 않았습니다. **설계 문서가 요구한 관찰마다 그것을 실제로 만들어 내는 수단이 있는지 대조하세요.**

**프로세스 권한 경계는 실기에서만 드러납니다.** macOS에서는 확장이 root, 앱이 로그인 사용자로 돌아서 "같은 사용자인가" 검사가 절대 통과할 수 없었습니다. Windows도 서비스와 사용자 앱의 권한 수준이 다르니 IPC 인가 조건을 실기에서 확인하세요.

**자원의 수명과 만드는 시점은 mock으로 못 잡습니다.** macOS에서는 앱을 켤 때 IPC 연결을 미리 만들어 두었는데, 상대가 아직 없어서 그 연결이 영구히 무효가 됐습니다. 시험은 가짜 transport를 주입해서 이 문제를 볼 수 없었습니다.

**환경에만 있는 도구에 기대면 검사가 조용히 뒤집힙니다.** macOS의 `Scripts/verify-source-safety.sh` 는 `rg`(ripgrep)를 쓰는데, 그게 없는 환경에서는 검사가 실패하면서 10/10이 9/10으로 떨어집니다. Windows PowerShell 스크립트에도 같은 종류의 미선언 의존이 없는지 보세요.

**설치본을 바꿀 때는 버전을 올리세요.** macOS에서 같은 버전으로 덮으면 이전 등록이 새 설치본을 붙잡았습니다. Windows에서도 필터·서비스 갱신 시 같은 문제가 날 수 있습니다.

## 6. 하지 말 것

- macOS R3 LIVE를 Windows에서 재현하려 하지 마세요. 시스템 확장·공증·Xcode가 없어 불가능합니다. Windows는 WFP로 **같은 질문에 따로 답하는** 별도 트랙입니다.
- macOS 결과를 Windows 증거로 옮겨 적지 마세요. 두 플랫폼의 판정은 각각 실기로 세웁니다.
- P3 WireGuard 전달과 제품 통합은 사용자 승인 전까지 시작하지 않습니다.
- 제품 코드(`macos/VPNRouter/`)와 릴리스 문서는 스파이크에서 건드리지 않습니다.

## 7. 참고 문서

- macOS 실제 실행 기록: `macos/AppRoutingSpike/Docs/signed-mac-live-run-2026-08-14.md`
- macOS 판정과 안전 불변식: `macos/AppRoutingSpike/Docs/spike-decision.md`
- 후보 비교: `macos/AppRoutingSpike/Docs/candidate-comparison.md`
- R3 프리브리프: `docs/R3-macos-signed-transparent-proxy-validation-prebrief-2026-08-11.md`
- Windows 이전 인계: `docs/windows-next-session.md`, `docs/windows-mvp-handoff.md`
