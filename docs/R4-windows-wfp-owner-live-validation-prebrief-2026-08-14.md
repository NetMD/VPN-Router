# R4 프리브리프 — Windows WFP 소유자 실기 재검증 (2026-08-14)

> 프로젝트: vpn_router · 대상 차수(예정): R4 · 성격: 파이프라인 시작 전 준비 문서(독립)
> 조회 소스: 이 PC 실측(WFP·네트워크·툴체인) · 프로젝트 코드 · 체크리스트 · 저널 · 차수 기록 · 백로그
> 조회 시각: 2026-08-14 20:33~20:58 (KST) · 1차 검증 재조회 20:55~20:58 · 2차 검증 재조회 21:00~21:12
> 상태: **2차 검증 완료 · 최종 판정 조건부 GO** (§10) · 열린 질문 0건

## 0. 한 줄 요약

Windows 실기에서 "사용자가 고른 앱의 새 흐름을 사용자 모드 WFP로 소유할 수 있는가"에 답한다.
**이번은 두 번째 실행이다.** 2026-08-10에 이미 64사례를 끝까지 돌려 `PASS 5 / FAIL 27 / NOT_RUN 32`가 나왔다 (출처: `inter-pipeline-2026-08-10T22-38-22_technical-changelog.md:73-78`). R4는 (a) 증거를 만들어 낼 관찰 수단을 먼저 만들고 → (b) **IPv4 16사례를 막는 실패만** 다루고 → (c) 그 위에서 64사례를 다시 세우는 차수다. 원인 규명과 IPv6는 다음 차수 몫이다(§8-1 안 2).

**시작 전에 알아야 할 세 가지** (§8-0에 근거):
1. 이 PC에는 IPv6 전역 주소와 기본 경로가 없다. `M-001`~`M-032` 중 **IPv6 사례 16건**(`M-009`~`M-016` · `M-025`~`M-032`)은 이 회선으로 관찰할 수 없다. 시험용 터널이 IPv6를 주는지 §4-2 3단계에서 먼저 확인한다.
2. 최종 `PASS`는 `M-001`~`M-032`가 **모두** `PASS`일 때만 나온다(`OwnerHarnessRunner.cs:190`). 따라서 `PASS`는 도달 불가다.
3. 더 중요한 것 — **`FAIL`이 한 건이라도 있으면 전체 판정은 `FAIL`이다**(`:194`). 한계를 정직하게 측정한 결과도 `FAIL`로 나온다. **그래서 이번 차수의 성공을 JSON `verdict`로 재지 않는다.** 성공 기준은 §8-0의 표에 따로 적었다.

---

## 0-1. 사용자 확정 사항 (2026-08-14, 열린 질문 6건 전부 종결)

| # | 확정 내용 |
|---|---|
| 1 | R4를 "27건 FAIL을 고쳐 다시 세우는 **두 번째 실행**"으로 다시 쓴다. 순서는 **관찰 수단 → 알려진 실패 수정 → 64사례 재실행**. "AC 12개 중 8개는 증거를 만들어 낼 수단이 없다"가 **첫 작업 항목**이다. |
| 2 | 다음 홉은 **시험용 WireGuard 터널**을 띄워 마련한다. 설정 파일 `C:\Users\NetMD\Downloads\63543_jp_wg.conf`를 그대로 쓴다. 실행기 `C:\Program Files\WireGuard\wg.exe` 확인됨. |
| 3 | `INCONCLUSIVE`를 **결과 형식에 넣는다.** 열거형·스크립트 허용 목록·JSON 스키마를 함께 고치고 **스키마 버전을 올린다.** |
| 4 | `M-033`~`M-064`는 **근거를 적어 일괄 `NOT_RUN`** 으로 닫는다. 패키지 신원 증명 코드는 이번에 만들지 않는다(`R3-DEC-05` 미결). |
| 5 | `R3-DOC-01`(package `NOT_RUN` 문구 정리)을 **R4 범위에 넣는다.** |
| 6 | R4 종료 시점에 사용자에게 올리는 결정은 **`R3-DEC-04` 하나뿐.** `R3-DEC-01`·`02`·`03`·`05`는 실기에서 나온 사실만 근거로 붙이고 결정하지 않는다. |
| 7 | **범위는 §8-1 안 2를 채택한다.** 이번 차수 = 선행 조치 + 관찰 수단 + 판정 어휘 + **IPv4 16사례 실기** + OWNER-04·05·06 + 문서. 다음 차수 = 원인 규명(버그냐 한계냐) + IPv6. 단 **알려진 실패 중 IPv4 16사례를 막는 부분은 이번에 다룬다**(§8-1에 사례 단위로 갈라 적음). |
| 8 | **IPv6는 터널이 주는지 먼저 확인한다.** §4-2 3단계에서 시험용 터널이 IPv6 전역 주소와 `::/0` 경로를 주면 IPv6 16사례를 이번 실기에 포함하고, 안 주면 그 자리에서 근거를 적은 `INCONCLUSIVE`로 닫는다. 판정 규칙은 §4-2 표에 고정해 두었다. |

> `INCONCLUSIVE` 와 `NOT_RUN` 의 뜻 차이 — **`NOT_RUN`은 "실행하지 않았다"** (예: 패키지 환경이 없어 아예 시도하지 않음). **`INCONCLUSIVE`는 "실행했으나 결론을 내지 못했다"** (예: 흐름은 만들었으나 어느 인터페이스로 나갔는지 관찰하지 못함). 둘 다 `PASS`가 아니지만, 앞의 것은 환경 부재이고 뒤의 것은 증거 부재다. **어느 쪽도 "실패 아님"으로 세지 않는다.**

---

## 0-2. R4 시작 전 선행 조치 (파이프라인이 수행 · 프리브리프는 저장소를 고치지 않음)

### 선행-1. 미커밋 문서 커밋 — **확정된 필수 조치, 판단 사항이 아님**

`macos/AppRoutingSpike/Docs/spike-decision.md` 변경 1건이 남아 있다. `test-wfp-app-routing-spike.ps1:1333-1338`이 이것을 **빌드 시작 전에** 차단한다.

```powershell
# test-wfp-app-routing-spike.ps1:1333-1338
$protectedDiff = @(git diff --name-only -- macos docs/v0.1.0-release-plan.md artifacts)
if ($LASTEXITCODE -ne 0 -or $protectedDiff.Count -ne 0) {
    $finalResult = New-LimitedResult -Mode "DRY_RUN" -Verdict "FAIL" -Fingerprint "MATCH" -FailureCode "AUTOMATED_GATE_FAILED"
```

두 번 실측 재현했다 (2026-08-14 20:41, 20:55 — 결과 동일):
```
exit=0 count=1 -> macos/AppRoutingSpike/Docs/spike-decision.md
-> 게이트 판정: AUTOMATED_GATE_FAILED (차단)
```

이 상태로는 자동 검사 한 줄도 못 돌린다. diff 내용은 R3 LIVE 결과를 반영한 정당한 문서 갱신이다(확인함). **커밋 없이는 R4가 시작되지 않는다.**

### 선행-2. 복구 수단에 WFP 정리 추가 — **위험이 아니라 실기 전 필수 작업**

`restore-network-dev.ps1` 전문을 읽었다. WFP 관련 정리가 **한 줄도 없다.** 되돌리는 것은 프로세스 종료(`:8`) · WireGuard 서비스 중지(`:11`) · `/32` 경로 제거(`:13-24`) · IPv4 DNS 복원(`:26-62`) · Adguard 상태 복원(`:64-79`) · `active-connection.json` 삭제(`:81-82`)뿐이다.

**이것이 없으면 OWNER-04를 닫을 수 없다.** OWNER-04는 "정상 종료·부분 실패·Ctrl+C·강제 종료 각각에서 소유 정책이 0건인지 확인"인데, 0건이 아닐 때 되돌릴 수단이 없으면 그 시험을 안전하게 반복할 수 없다. 사용자가 PC 앞에 있어 최악의 경우 재부팅은 가능하지만, **재부팅이 유일한 복구 수단인 상태로 실기를 시작하면 안 된다.**

갖춰야 할 것:
1. 소유 정책 4개(`WfpOwnedPolicyKeys.cs:7-10`의 고정 GUID) 열거·삭제
2. `%LOCALAPPDATA%\VpnRouter\wfp-spike-spool` 잔여 폴더 정리
3. `%TEMP%\wfp-feature-*` 잔여 정리
4. IPv6 DNS 복원 (지금은 `:46`에서 IPv4만 통과시킴)

**잔여물은 이미 증거로 남아 있다.** 스크립트는 자기 spool 폴더를 `finally`(`:1561-1565`)에서 지우도록 되어 있는데, 2026-08-10 실기의 폴더 10개가 그대로 남아 있다. 내용물이 `step-solution-build.tmp` · `step-focused-tests.tmp`(`:498-500`이 지워야 할 것) 와 `VpnRouter.WfpSpike.Harness.exe`(잠긴 payload 사본)다. **`finally`가 10번 건너뛰어졌다는 뜻이고**, 이는 §8 R-04(Ctrl+C·강제 종료가 정리를 건너뛴다)의 직접 증거다.

### 선행-3. 시험용 WireGuard 터널 준비 (§4-2에 절차)

### 선행-4. 나머지는 막지 않는다 — 적대 점검 결과 (2차 검증)

"실행 당일에 '아 이것도 필요했네'가 나오지 않도록" 실기 첫 실행을 막을 수 있는 것을 전부 되짚었다. **선행-1~3 말고 추가로 막는 것은 없다.** 확인한 것과 근거는 아래와 같다.

| 점검 대상 | 결과 | 근거 |
|---|---|---|
| 관리자 승격 | 통과 | 실측 `True`. 판정은 토큰 `TokenElevation` (`LiveApplyGate.cs:20-37`) |
| BFE 서비스 | 통과 | `Running`/`Automatic` 실측. 거부 시 `BFE_ACCESS_DENIED`(`WfpNativeApi.cs:44`) |
| 네이티브 내보내기 12종 | 통과 | 실측 전부 `OK`. 스크립트도 `:847-867`에서 4종을 따로 확인 |
| **`VpnRouterVs.sln` 빌드에 MSBuild가 필요한가** | **불필요** | `:1347`이 `dotnet build .\windows\VpnRouterVs.sln`을 쓴다. `MSBuild.exe`가 PATH에 없어도 막히지 않는다 |
| C++ ABI probe 툴체인 | 통과 | vswhere · VC++ x64 · SDK 헤더 6종 실측 존재 (§1-2) |
| 선택 앱 실행 파일 | 통과 | `msedge.exe` 존재. **조상 디렉토리에 재분석 지점 0건** — `WfpInputValidator.RejectReparseChain`(`:54-63`)을 그대로 재현해 확인 |
| 통제(비선택) 앱 | 통과 | `chrome.exe` 존재, 재분석 지점 0건 |
| spool ACL 요구(`AreAccessRulesProtected`) | 통과 | `New-PrivateSpool`(`:190`)이 만들고, 2026-08-10에 실제로 통과한 이력이 있다 |
| 게시물 증거 5종 | 통과 | 빌드가 만든다. 다만 `wfp-sdk-abi-x64.json` 누락 시 진단이 흐려진다(§8 R-07) |
| `artifacts/`가 보호 경로 검사에 걸리는가 | 안 걸림 | `.gitignore:17`에 `artifacts/`가 있어 `git diff -- artifacts`가 비어 있다 |
| 작업 트리 지문 전후 일치 | 통과 예상 | 같은 실행 안에서 앞뒤로 찍는다(`:1331` · `:1411`). 빌드가 추적 파일을 바꾸지 않으면 일치 |

### 회복 보장 확인 — 재부팅이 실제로 통하는가

`restore-network-dev.ps1`이 WFP를 못 되돌린다는 사실 위에서 "최악이면 재부팅"이 성립하는지 따졌다. 갈림길은 **소유 정책이 재부팅 뒤에도 살아남는 종류인가**이다.

- `NativeSessionBuffer.cs:38` — `Flags = 1 // FWPM_SESSION_FLAG_DYNAMIC`
- SDK 헤더에서 값 대조: `Windows Kits\10\Include\10.0.26100.0\shared\fwpmtypes.h:125` — `#define FWPM_SESSION_FLAG_DYNAMIC (0x00000001)` ✔ 일치
- 동적 세션에 붙은 WFP 개체는 세션이 끝날 때 커널이 스스로 지운다. 영구(persistent) 개체가 아니므로 **재부팅하면 반드시 사라진다.**

**결론: 재부팅은 확실한 최후 수단이다.** 다만 이것은 "실행 중에 안전하게 되돌릴 수단"을 대신하지 못하므로 선행-2는 그대로 필수다. 재부팅은 세션을 끊는 것이지 OWNER-04가 요구하는 "0건 확인"을 대신해 주지 않는다.

---

## 1. 운영 실측 (이 PC 직접 조회, 2026-08-14 20:33~20:58 KST)

운영 DB는 이 프로젝트에 없다. 대신 입력으로 받은 상태 폴더와 이 PC의 실제 네트워크·WFP 상태를 직접 조회했다.

### 1-1. 실행 전제 (모두 통과)

| 항목 | 실측값 | 판정 |
|---|---|---|
| 관리자 권한(승격) | `True` | CONFIRMED |
| dotnet SDK | `10.0.303` | CONFIRMED |
| OS 빌드 | `Microsoft Windows NT 10.0.26200.0` | CONFIRMED |
| BFE 서비스 (WFP 엔진) | `Running` / `Automatic` | CONFIRMED |
| `Fwpuclnt.dll:FwpmConnectionPolicyAdd0` | **존재** | CONFIRMED |
| `Fwpuclnt.dll:FwpmConnectionPolicyDeleteByKey0` | **존재** | CONFIRMED |
| 나머지 필수 내보내기 10개 | 전부 `OK` | CONFIRMED |
| 프로세스 아키텍처 | `X64` | CONFIRMED |

이번 차수의 가장 중요한 실측이다. 스파이크가 쓰는 **연결 정책 API가 이 PC의 Windows 빌드에 실제로 있다.** `NativeMethods.cs:7-49`의 12개 내보내기를 `NativeLibrary.TryGetExport`로 직접 확인했다. API 부재로 시작조차 못 하는 경우는 배제됐다.

### 1-2. C++ ABI probe 툴체인

| 항목 | 실측값 | 판정 |
|---|---|---|
| `vswhere.exe` | 존재 | CONFIRMED |
| VS + VC++ x64 도구 (`Microsoft.VisualStudio.Component.VC.Tools.x86.x64`) | `C:\Program Files\Microsoft Visual Studio\18\Community` | CONFIRMED |
| Windows SDK Include | `10.0.26100.0` 한 개 | CONFIRMED |
| 필요한 SDK 헤더 6종 | `fwpmtypes.h` · `fwptypes.h` · `netioapi.h` · `ifdef.h` · `fwpmu.h` · `userenv.h` 전부 존재 | CONFIRMED |
| `fwpmu.h`의 `FwpmConnectionPolicyAdd0` 선언 | 5382행 | CONFIRMED |
| `fwpmtypes.h`의 `FWPM_NETWORK_CONNECTION_POLICY_SETTINGS0` | 197행 | CONFIRMED |

SDK 헤더(26100)와 OS 빌드(26200)가 다르지만 `WfpSdkAbiValidator.ComputeInstalledSdkHeaderHash`(`WfpSdkAbiValidator.cs:132-147`)가 설치된 것 중 가장 높은 버전을 쓰므로 한 개만 있으면 문제되지 않는다.

### 1-3. WFP 현재 상태 — 시작 기준선

| 조회 | 결과 |
|---|---|
| `netsh wfp show filters` 전체 항목 | 약 5391건 |
| 그중 스파이크 소유 GUID 4개 (`...70601`~`...70604`) | **0건** |
| `netsh wfp show state`의 `<providerContext>` 항목 | **0건** |
| 문자열 `VpnRouter` / `VPN Router` / `VpnRouter.WfpSpike` | 각 0건 |

**소유 정책 잔여물 0건인 깨끗한 기준선에서 시작한다.** 소유 GUID는 `Policy/WfpOwnedPolicyKeys.cs:7-10`에 고정값 4개로 박혀 있다.

### 1-4. 네트워크 기준선

| 항목 | 실측값 |
|---|---|
| 활성 어댑터 | **단 하나** — ifIndex 8 `Wi-Fi 2` (Intel Wi-Fi 7 BE200) |
| IPv4 기본 경로 | ifIndex 8 → `192.168.1.1` (metric 0) |
| **IPv6 전역 주소** | **없음** — 링크 로컬 `fe80::...%8` 하나뿐 |
| **IPv6 기본 경로 (`::/0`)** | **없음** |
| 현재 IPv4 `/32` 호스트 경로 | 11건 |
| IPv4 DNS (ifIndex 8) | `192.168.1.1` |
| IPv6 DNS (ifIndex 8) | 비어 있음 |
| WireGuard/Wintun 어댑터 | 없음 (서비스도 없음) |
| WireGuard 실행기 | `wg.exe` 1.0.20260223 · `wireguard.exe` 1.1 — 존재 |
| 제3자 VPN 어댑터 | `VPN Unlimited TAP` (ifIndex 21, `Disconnected`) |
| 백신 | Windows Defender 단독 |
| 방화벽 프로필 | Domain·Private·Public 전부 `Enabled` |
| 제3자 DNS 필터 | `Adguard Service` — `Running` / `Automatic` |
| 기타 | `WarpJITSvc` — `Stopped` / `Manual` |

**IPv6가 없다는 사실이 이번 차수의 상한을 정한다** → §8-0.
이 표에서 **WireGuard를 뺀 나머지**가 OWNER-05의 "시작 전" 기준선이다. 우리가 띄울 터널은 제3자 제품이 아니라 시험 장치다(§4-2).

### 1-5. 상태 폴더 (`%LOCALAPPDATA%\VpnRouter`)

| 항목 | 마지막 기록 | 내용 |
|---|---|---|
| `managed-routes.json` | 2026-08-10 22:42 | `[]` (빈 배열) |
| `dns-observations.json` | 2026-08-10 22:41 | 2026-07-18 관측 기록 |
| `wfp-spike-spool\` | 2026-08-10 | **폴더 10개 · 파일 12개 잔여** (선행-2 근거) |
| `network-snapshot.json` | — | **없음** |
| `dns-filter-handoff.json` | — | **없음** |
| `edge-test-profile-*\` | 2026-08-10 | Edge 시험 프로필 잔여 |
| `%TEMP%\wfp-feature-*` | 2026-08-10 | **549개 잔여** |
| VpnRouter 서비스·프로세스 | — | 실행 중인 것 없음 |

`network-snapshot.json`이 없으므로 지금 `restore-network-dev.ps1`을 돌리면 DNS 복원은 "저장된 스냅샷 없음" 경고만 낸다.

---

## 2. 현재 구조 (CONFIRMED 사실 — file:line)

### 2-1. LIVE 실행이 열리는 조건

`OwnerHarnessRunner.RunAsync`가 순서대로 통과시키는 관문이다.

1. `--result` 인자가 있으면 즉시 `DRY_RUN/NOT_RUN` (`OwnerHarnessRunner.cs:55`)
2. `--apply-live-wfp` 없으면 `EXPLICIT_OPTION_REQUIRED` (`:56`)
3. `TrustedGateEvidence.ConsumeAndValidate` — 자동 검사 표식 검증 (`:59`, 본체 `:203-222`)
4. `LiveApplyGate.Evaluate(true, IsElevatedAdministrator(), true)` (`:65`, 본체 `Safety/LiveApplyGate.cs:12-18`)
5. stdin 첫 줄의 nonce와 승인 토큰 해시 대조 (`:72-74`)
6. 이름 있는 뮤텍스 `Local\VpnRouter.WfpSpike.OwnerHarness` 단독 확보 (`:78-84`)
7. 실행 파일 열기·정규화·재분석 지점 거부 (`:86`, 본체 `Safety/WfpInputValidator.cs:27-63`)
8. ABI 증거 검증 (`:88` → `Native/WfpNativeApiFactory.cs:9` → `WfpSdkAbiValidator.ValidateOrThrow`)

표식(`AutomatedMarker`) 검증이 요구하는 것 (`:215-218`):
- 스키마 버전 1, 나이 0~15분, commit 40/64자 hex 일치, nonce 길이 16~128
- `beforeAfterFingerprint == "MATCH"`
- 빌드·시험·게시·추출·DRY 하네스 **exit code 6개가 모두 0**
- 해시 9종이 전부 64자 hex
- 표식 파일은 읽은 뒤 **즉시 삭제**(`:212`) — 1회 사용
- spool 디렉토리 소유자·ACL·재분석 지점 검사 (`:224-233`)
- 게시물 매니페스트·ABI 증거·probe 소스·gate 증거·feature 매니페스트 5개 파일 해시 대조 (`:235-254`)

### 2-2. 실제로 설치되는 정책

- 계획은 **IPv4·IPv6 두 개뿐**이다 (`Policy/WfpPolicyPlanner.cs:9-13`). TCP/UDP/QUIC/DNS를 나누지 않는다.
- 정책 내용은 "이 앱 신원(`ALE_APP_ID` blob 또는 `ALE_PACKAGE_ID` SID)의 흐름을 이 인터페이스 LUID를 다음 홉으로 보내라" 한 줄이다 (`Native/NativePolicyBuffer.cs:52-74`).
- 엔진은 동적 세션으로 연다 (`Native/WfpNativeApi.cs:39-47`). 프로세스가 죽으면 커널이 동적 정책을 스스로 거둔다.
- 정리는 역순 삭제 후 엔진 닫기, 1회만 수행 (`Policy/WfpPolicySession.cs:88-113`).

### 2-3. 패키지 신원은 코드가 막아 두었다 — 확정 사항 4의 근거

```csharp
// windows/VpnRouter.WfpSpike/Native/WfpNativeApi.cs:25-27
// Package Query API로 설치 PFN은 확인했지만 PFN↔AppContainer 이름↔토큰 SID 관계를
// 공식 API로 같은 실행에서 증명하기 전에는 package live 정책을 열지 않습니다.
throw new WfpSpikeException(WfpSpikeResultCode.PACKAGE_IDENTITY_UNAVAILABLE);
```

**PFN·AppContainer 이름·SID를 모두 정확히 넣어도 무조건 예외를 던진다.** `OwnerHarnessRunner.cs:111-114`가 그 예외를 받아 32건을 `NOT_RUN/PACKAGE_IDENTITY_UNAVAILABLE`로 채운다. 즉 `M-033`~`M-064`는 **코드 수준에서 이미 일괄 `NOT_RUN`만 가능하다.**

이것이 확정 사항 4의 근거다. R4는 이 코드 위치를 인용해 32건을 닫고, 패키지 신원 증명 코드는 만들지 않는다. 기획서도 이 처리를 허용한다 (`AC-02-3` — R2 기획서 64행, `BL-03` — 127행).

### 2-4. 판정 어휘에 `INCONCLUSIVE`가 없다 — 확정 사항 3의 대상

`Contracts/WfpSpikeEnums.cs:5-6`:
```csharp
public enum WfpSpikeOutcome { PASS, FAIL, NOT_RUN }
public enum WfpSpikeVerdict { PASS, FAIL, PARTIAL }
```

R2 기획서는 관찰값 어휘를 이미 정의해 두었다 — **"관찰값은 `VPN`, `BASELINE`, `OTHER`, `UNOBSERVED` 중 하나로만 메모리에서 판정"** (기획서 222행). 그런데 코드에는 이 네 값을 담을 자료형이 **아예 없다.** 관찰을 못 만들어 내니 관찰값 자료형도 없는 것이다. `INCONCLUSIVE`는 기획서의 `UNOBSERVED`에 대응하는 공유 결과 쪽 표현이다.

### 2-5. 안전 관문 4개

| 파일 | 실제 조건 | 근거 |
|---|---|---|
| `LiveApplyGate.cs` | 명시 옵션 → 관리자 승격 → 자동 검사 통과, 이 순서. 승격 판정은 `WindowsPrincipal.IsInRole`이 아니라 토큰의 `TokenElevation` 조회 | `:12-18`, `:20-37` |
| `WfpInputValidator.cs` | `.exe`·존재·디렉토리 아님·재분석 지점 아님 → 파일을 **열어 둔 채**(`FileShare.Read`) `GetFinalPathNameByHandle`로 최종 경로 재확인 → 조상 디렉토리 전부 재분석 지점 검사. 정책 설치 직전 `Revalidate()` | `:10-25`, `:27-52`, `:54-63`, `:69-73` |
| `WfpResultRedactor.cs` | 금지 패턴 **3종**(윈도우 경로 · IP 주소 · 비밀 이름) | `:7-15` |
| `PayloadIntegrityLease.cs` | 매니페스트의 모든 파일을 `FileShare.Read`로 열어 놓고 길이·SHA256 검증, `Revalidate()` 제공 | `:12-32` |

**뒤의 둘은 LIVE 경로에서 호출되지 않는다.** 전수 검색 결과 `WfpResultRedactor.ContainsProhibitedContent`와 `PayloadIntegrityLease`는 `windows/VpnRouter.Tests/Program.cs:947-949`, `:1155`에서만 쓰인다. 실제 LIVE 금지 패턴 검사와 payload 잠금은 PowerShell 쪽 별도 구현이 담당한다:
- 금지 패턴: `test-wfp-app-routing-spike.ps1:79-99` `Test-ProhibitedContent` — 패턴 **7종**(경로 · PFN/AppId/blob · IPv4 · IPv6 · DNS/URL · WireGuard 설정과 키 · 진단 필드). 호출 `:336-338`, `:71-74`, 역검증 `:382-388`
- payload 잠금: `Copy-AndLockPrivatePayload`(`:913`)가 `:930`에서 핸들을 열고 `finally`(`:1549-1553`)에서 닫는다. 음성 검사는 `Test-PrivatePayloadLockNegativeGates`(`:939`)

같은 일을 하는 구현이 C#과 PowerShell에 따로 있고 **검사 범위가 다르다**(3종 대 7종) → §8 R-09.

### 2-6. LIVE 승인 절차 (사용자가 실제로 하는 일)

| # | 사용자가 하는 일 | 근거 |
|---|---|---|
| 1 | `-ApplyLiveWfp` 스위치를 붙여 관리자 셸에서 실행 | `:3` |
| 2 | 자동 게이트가 통과하기를 기다림 (솔루션 빌드 2종·집중 시험·게시·추출·DRY 하네스·전후 지문·작업 트리 지문) | `:1404-1422` |
| 3 | 프롬프트에 **`APPLY LIVE WFP`** 를 대소문자 그대로 입력 | `:1470-1479` |
| 4 | **WireGuard 인터페이스 index** 입력 | `:1481-1491` |
| 5 | 시험 실행 파일의 전체 경로 입력 | `:1492-1501` |
| 6 | 패키지 이름 입력(없으면 Enter). 넣으면 AppContainer 이름과 SID(base64)를 추가 입력 | `:1502-1513` |
| 7 | `M-001`~`M-032` 각 사례의 결과와 실패 코드를 **손으로 입력** — 또는 `-LiveObservationJson`으로 미리 넘김 | `:983-985`, `:999-1033` |
| 8 | 패키지 경로를 탔다면 `M-033`~`M-064`도 손으로 입력. 이 구간은 미리 넘길 수 없음 | `:1015` 정규식이 `M-001`~`M-032`만 허용 |

승인 토큰(`approvalToken`)은 사용자가 만들거나 보는 값이 **아니다.** 스크립트가 난수로 만들어(`:1431`) 해시만 표식에 넣고 평문은 stdin으로 하네스에 넘긴다(`:1522`). 스크립트와 하네스 사이의 능력 증표다.

### 2-7. 복구 스크립트가 되돌리는 것 / 되돌리지 않는 것

→ **§0-2 선행-2**로 승격했다. 요약: WFP 관련 정리가 한 줄도 없다.

---

## 2-8. ★ 관찰 수단 대조표 (R4의 첫 작업 항목)

인계장 §5의 가장 오래 걸린 macOS 결함은 "설계가 요구한 관찰을 실제로 만들어 낼 수단이 하네스에 없었다"였다. 그것을 Windows 코드에 그대로 대 봤다.

**결론: AC 12개 중 하네스·스크립트가 스스로 만들어 내는 관찰은 4개뿐이고, 7개는 수단이 아예 없고, 1개는 절반만 있다.**

| AC | 요구하는 관찰 (원문 위치: R2 기획서) | 수단 | 근거 |
|---|---|---|---|
| AC-02-1 (62행) | 정규화된 경로로 AppId blob 획득, `FwpmFreeMemory0`로 해제 | **있음** | `WfpNativeApi.cs:10-15`, 해제 `:87-91` |
| AC-02-3 (64행) | 패키지 신원 blob 또는 근거 있는 `NOT_RUN` | **NOT_RUN만** | `WfpNativeApi.cs:27` 무조건 예외 |
| AC-02-5 (66행) | index→LUID→index 왕복 일치 | **있음** | `WfpNativeApi.cs:30-37` |
| AC-03-8 (76행) | 강제 종료 뒤 RPC rundown으로 소유 정책 **0건** 확인 | **없음** | 열거 API 미구현. `NativeMethods.cs:19-23`에 Add·DeleteByKey만 |
| AC-05-3 (87행) | WireGuard index를 읽기 전용으로 확인, 시작·중지 안 함 | **있음** | `ConvertIndexToLuidAndBack`만 호출. 서비스 제어 코드 0건 |
| AC-05-4 (88행) | DNS와 `/32` 경로를 **읽기 전용으로 관찰**, 제3자 제품 안 건드림 | **절반** | 안 건드리는 쪽은 충족(제어 코드 0건). **관찰하는 쪽은 스크립트의 `Get-NetworkFingerprint`(`:454`)가 경로·DNS·어댑터를 찍지만 하네스에는 없고, 시작 전후 비교도 안 함**(§8 R-12) |
| AC-05-5 (89행) | 정상·중간 실패·Ctrl+C·인터페이스 교체에서 자기 세션만 닫기 | **부분** | Ctrl+C `Harness/Program.cs:6-10`, 정리 `WfpPolicySession.cs:88-113`, 인터페이스 교체 `:68-72`. **강제 종료 경로만 확인 수단 없음** |
| AC-06-1 (92행) | 기존 연결과 새 연결을 구분, 기존 연결은 성공 수치에서 제외 | **없음** | 연결 생성·구분 코드 0건 |
| AC-06-2 (93행) | 16조합 × TCP·UDP·QUIC·DNS를 **실행해** 64사례에 판정 | **형식만** | `WfpObservationCollector.cs:17-30` 순서·조합 검증, `OwnerHarnessRunner.cs:160-171` 전수 검증. **실행과 값은 사람 몫** |
| AC-06-3 (94행) | 선택 앱은 VPN, 비선택 앱은 기준 인터페이스가 **관찰되어야** PASS | **없음** | 인터페이스 관찰 코드 0건 |
| AC-06-4 (95행) | `/32` 경로와 WFP 정책의 우선순위를 실제 관찰로 판정, 추정 금지 | **없음** | 위와 같음 |
| AC-06-5 (96행) | DNS가 어느 인터페이스 경로로 관찰됐는지 판정, 신원 미전파 시 FAIL | **없음** | 실패 코드 `DNS_APP_ID_NOT_PROPAGATED`(`WfpSpikeEnums.cs:29`)는 정의만 있고 만들어 내는 코드가 없음 |

### 흐름을 만들고 관찰하는 수단이 없다는 근거 (전수 검색)

- `test-wfp-app-routing-spike.ps1`(1573행) 전문에 `Test-NetConnection` · `Invoke-WebRequest` · `Resolve-DnsName` · `curl` · 소켓 생성 **0건**
- 같은 파일에 `Get-NetTCPConnection` · `pktmon` · `netsh trace` · ETW 수집 **0건**
- `windows/VpnRouter.WfpSpike/**`에 `System.Net` · `Socket` · `HttpClient` **0건**
- 2026-08-10 실기는 **`pktmon`(Microsoft-Windows-PktMon ETW)으로 손수 관찰**했다. 증거가 `artifacts/wfp-spike/`에 `m006/m007/m008-monitor.etl` · `quic-monitor.etl` · `dns-monitor.etl` · `chrome-m21-m24.etl`로 남아 있다(2026-08-10 22:08~22:28). **이 도구는 스크립트 밖에 있다.**

### 만들어야 할 수단 4가지 (R4 첫 작업 항목)

| # | 수단 | 닫히는 AC |
|---|---|---|
| 1 | **흐름 발생기** — 선택 앱·비선택 앱으로 TCP·UDP·QUIC·DNS를 IPv4·IPv6로 실제로 흘림. 정책 적용 전 열린 연결과 이후 새 연결을 구분 | AC-06-1 · 06-2 |
| 2 | **인터페이스 관찰기** — 그 흐름이 어느 인터페이스로 나갔는지 기계가 읽어 `VPN`/`BASELINE`/`OTHER`/`UNOBSERVED`를 정함. 2026-08-10의 `pktmon` 절차를 스크립트로 굳히는 것이 가장 싸다 | AC-06-3 · 06-4 · 06-5 |
| 3 | **소유 정책 열거기** — 4개 GUID의 0건 확인. 후보는 `netsh wfp show state`의 `<providerContext>`(기준선 0건 실측). 동적 세션 정책이 거기 보이는지는 **미확인 — R4 첫 실행에서 "올린 뒤 보이나 → 지운 뒤 사라지나"부터 확인** | AC-03-8 · 05-5 |
| 4 | **제3자 제품 상태 수집·비교기** — §1-4 표를 시작 전후로 찍어 비교. 자동 중지·재설정은 하지 않음 | AC-05-4 |

---

## 3. 이번 목표 / 범위

### 할 것 (확정된 순서대로)

**(a) 선행 작업**
1. `spike-decision.md` 커밋 (§0-2 선행-1)
2. `restore-network-dev.ps1`에 WFP 소유 정책·spool·`%TEMP%` 잔여물 정리와 IPv6 DNS 복원 추가 (§0-2 선행-2)
3. 시험용 WireGuard 터널 준비·확인 절차 확립 (§4-2)

**(b) 관찰 수단 만들기 — 첫 작업 항목**
4. §2-8의 수단 4가지를 만들어 사람 `Read-Host` 타이핑 의존을 없앤다
5. 판정 어휘에 `INCONCLUSIVE` 추가 + 스키마 버전 상승 (§3-2에 대상 전수)

**(c) IPv4 16사례를 막는 실패만 다룬다** (안 2 — §8-1에 사례 단위 분해)
6. Edge의 UDP·QUIC이 Wi-Fi로 빠지는 것 중 **IPv4 몫**: `M-002` · `M-003` · `M-006` · `M-007`
7. 비선택 Chrome이 VPN으로 들어오는 것 중 **IPv4 몫**: `M-017`~`M-024`. **단 이것은 "고치는 대상"이 아닐 수 있다** — §8-1의 버그·한계 판별 절차를 먼저 돌린다
8. 두 원인의 IPv6 몫과 근본 원인 규명은 **다음 차수**

**(d) 실기와 기록**
9. `M-001`~`M-032` 실행. **IPv4 16건은 측정 기반 판정**, IPv6 16건은 §4-2 3단계 결과에 따라 실측 또는 `INCONCLUSIVE`
10. `M-033`~`M-064`는 `WfpNativeApi.cs:27`을 근거로 일괄 `NOT_RUN`
11. AC 12개를 하나의 실행표로 잇는다 (OWNER-01)
12. OWNER-04(4가지 종료 경로) · OWNER-05(제3자 상태 비교) · OWNER-06(금지 패턴·schema)
13. `R3-DOC-01` 문구 정리 (§3-3)
14. `R3-DEC-04` 근거표 제출 — **결정은 하지 않음**

### 안 할 것 (이번 비범위)

- macOS R3 LIVE 재현. 시스템 확장·공증·Xcode가 없다.
- macOS 결과를 Windows 증거로 옮겨 적기.
- 커널 driver 연구 착수. R4 종료 시점에 사용자가 결정한다.
- P3 WireGuard 전달과 제품 통합. **시험용 터널을 띄우는 것은 P3가 아니라 관찰 대상 마련이다** — 흐름을 터널로 넘기는 제품 경로는 만들지 않는다.
- 패키지 신원 증명 코드 (`R3-DEC-05` 미결).
- 제품 코드(`windows/VpnRouter.Service` · `App` · `Vpn` · `Installer` 등)와 릴리스 문서 수정.
- `R3-DEC-01` · `02` · `03` · `05` 결정. 근거만 붙인다.
- macOS 범위 백로그 3건 (`backlog.md:17-19`).

### 3-2. `INCONCLUSIVE` 추가가 건드리는 자리 (전수 — 2차 검증에서 다시 셈)

사용자는 "3곳"으로 말했고 **1차 검증은 "9곳"이라고 했다. 둘 다 적다.** 2차 검증에서 스크립트의 독립 검증기(`Assert-LimitedResult`)와 fixture 대조기(`Test-Fixtures`)를 직접 읽어 다시 세니 **6개 파일 · 24개 자리**다. 1차 검증이 초안에게 지적한 바로 그 실수(하위 조사 결과를 그대로 옮겨 적기)를 1차 검증 자신도 반복했다.

**먼저 반드시 알아야 할 함정 4개**

| 함정 | 위치 | 무슨 일이 일어나나 |
|---|---|---|
| ⚠ **암묵 흡수** | `OwnerHarnessRunner.cs:189` | `var notRun = cases.Count - pass - fail;` — 새 값이 **말없이 `notRunCount`로 흡수된다.** 오류도 안 난다. 이번 차수의 핵심 불변식이 여기서 조용히 깨진다 |
| ⚠ **산술 불변식** | `test-...ps1:275` | `caseTotal -ne (passCount + failCount + notRunCount)` → `LIMITED_RESULT_SCHEMA_INVALID`. **`inconclusiveCount`를 더하면 이 검사가 반드시 깨진다** |
| ⚠ **미지 필드 거부** | `test-...ps1:247-252`, `:258` | 허용 목록에 없는 속성이 하나라도 있으면 거부. 새 집계 필드는 **목록에 먼저 넣어야 한다** |
| ⚠ **버전 상수 고정** | `test-...ps1:262` | `$Result.schemaVersion -ne 1` — **스키마 버전을 올리는 순간 이 줄이 모든 결과를 거부한다** |

**전수 목록**

| # | 파일 | 위치 | 무엇을 |
|---|---|---|---|
| 1 | `WfpSpike/Contracts/WfpSpikeEnums.cs` | `:5` | `WfpSpikeOutcome`에 값 추가 |
| 2 | `Harness/WfpObservationCollector.cs` | `:32-38` | `IsValidCombination` — `_ => false`라 새 값은 **거부**된다(닫힌 실패라 안전하지만 반드시 수정) |
| 3 | `Harness/OwnerHarnessRunner.cs` | `:189` | ⚠ 암묵 흡수 (위 표) |
| 4 | 〃 | `:190-194` | `requiredPass`·`optionalValid`·`verdict`. `INCONCLUSIVE`가 `PASS`로 세어지지 않게 |
| 5 | 〃 | `:12`, `:195` | record 필드와 `SchemaVersion` 상수 |
| 6 | 〃 | `:168` | `ValidateCases`의 조합 검증 |
| 7 | `scripts/.../test-wfp-app-routing-spike.ps1` | `:31-40` | `$allowedResultCodes` — 새 실패 코드를 쓸 경우 |
| 8 | 〃 | `:51`, `:57-60` | `New-LimitedResult`의 `schemaVersion`과 집계 필드 |
| 9 | 〃 | `:247-252`, `:258` | ⚠ 미지 필드 거부 (위 표) |
| 10 | 〃 | `:262` | ⚠ 버전 상수 고정 (위 표) |
| 11 | 〃 | `:267` | `cleanupOutcome` 허용 목록 |
| 12 | 〃 | `:275` | ⚠ 산술 불변식 (위 표) |
| 13 | 〃 | `:284-286` | 사례 속성이 **정확히 4개**여야 함 |
| 14 | 〃 | `:292` | 사례 `outcome` 허용 목록 |
| 15 | 〃 | `:299-301` | `outcome`↔`failureCode` 조합 규칙 — **C#과 이미 어긋나 있다**(§8 R-14) |
| 16 | 〃 | `:308-325` | LIVE `PASS` 규칙(필수 32건 전건 `PASS`, 패키지 32건) |
| 17 | 〃 | `:356-366` | `Test-Fixtures`가 스키마의 `required` **개수와 이름을 정확히 대조**한다. 필드를 늘리면 이 목록도 함께 |
| 18 | 〃 | `:415-416`, `:427-429`, `:441` | 음성 시험용 결과 조립 |
| 19 | 〃 | `:984`, `:987` | 손입력 경로의 outcome 목록·조합 규칙 |
| 20 | 〃 | `:1004`, `:1015`, `:1017`, `:1021` | `-LiveObservationJson` 검증(개수 32 강제 · caseId 정규식 · outcome 목록 · 조합) |
| 21 | `fixtures/wfp-spike/limited-result.schema.json` | `:22` | `schemaVersion` const 상승 |
| 22 | 〃 | `:32`, `:43` | `cleanupOutcome`·`outcome` enum 확장 |
| 23 | 〃 | `:6-20`, `:5` | `required` 배열에 새 집계 필드 + `additionalProperties:false` |
| 24 | `fixtures/wfp-spike/dry-run-result.json` | `:2` | fixture의 `schemaVersion` |
| — | `windows/VpnRouter.Tests/Program.cs` | — | 위 전부의 집중 시험 |

> `fixtures/wfp-spike/case-matrix.json`은 고칠 필요가 없다. 확인해 보니 16행의 `expectedPath`(`VPN`/`BASELINE`)만 담고 있고 판정 어휘는 들어 있지 않다. **오히려 관찰기가 기대값을 읽어 쓸 자리로 그대로 쓸 수 있다.**

### 3-3. `R3-DOC-01` 대상 (확정 사항 5)

대상 파일: `{PMO}/R2/2026-08-10_16-08_plan_r2-windows-wfp-app-routing-spike.md`

| 줄 | 현재 문장 | 문제 |
|---|---|---|
| 264 | `| 패키지 환경 없음 | 패키지 사례를 NOT_RUN | PACKAGE_IDENTITY_UNAVAILABLE | 데스크톱 사례는 계속 가능하나 최종 PASS 금지 |` | **"최종 PASS 금지"** |
| 347 | `- 패키지 신원은 필수 구현 경로이지만 실환경 부재는 NOT_RUN을 허용합니다. 다만 실제 증거가 빠지므로 최종 PASS는 허용하지 않습니다.` | **"최종 PASS는 허용하지 않습니다"** |

맞춰야 할 기준 (전부 근거 있는 일괄 `NOT_RUN`이면 `PASS` 허용):
- `AC-08-5` — 109행
- 판정 규칙 — 196행
- 최종 판정 정의 — 365행
- 코드 구현 — `OwnerHarnessRunner.cs:192` (`optionalValid`가 전건 `NOT_RUN/PACKAGE_IDENTITY_UNAVAILABLE`를 허용)

**판정 규칙은 바꾸지 않는다.** 264행과 347행의 문장만 AC-08-5에 맞춘다.

---

## 3-1. 이번 라운드에 해소할 체크리스트 (3건 — 1차 검증에서 재선정)

범위가 커져 관찰 수단 만들기가 R4의 첫 작업이 됐으므로, 이제 실제로 닫히는 항목으로 바꿨다.

| # | 항목 원문 | 해소 방법 (어디에 어떤 줄을) | 담당 단계 | 왜 이번인가 |
|---|---|---|---|---|
| 1 | `M-001`~`M-032` 데스크톱 사례의 TCP·UDP·QUIC·DNS와 IPv4·IPv6 관찰 환경을 준비한다. (`next-project-checklist.md:51`) | §2-8의 수단 1·2(흐름 발생기 · `pktmon` 인터페이스 관찰기)를 `scripts/windows/`에 만들고, §4-2의 WireGuard 터널 절차를 확립한다. **IPv6는 이 네트워크에 없으므로(§8-0) "IPv6는 환경 부재로 관찰 불가"를 근거와 함께 명시하는 것까지가 준비 완료다** | architect · dev-backend | R4의 첫 작업 항목 그 자체다. 이것이 안 되면 나머지가 전부 막힌다 |
| 2 | AC-02-1·02-3·02-5·03-8·05-3~5·06-1~5의 실제 증거 항목 12개를 실행표에 연결한다. (`:50`) | 실행표 1개를 만들어 AC 12개 × 증거(사례 ID·관찰값·시각) × 판정(`PASS`/`FAIL`/`INCONCLUSIVE`/`NOT_RUN`)을 잇는다. **"연결"은 판정을 남기는 일이지 전부 `PASS`를 받는 일이 아니다** — `INCONCLUSIVE`도 연결된 판정이다 | QA | OWNER-01의 산출물 그 자체이고, 판정 어휘가 갖춰지면 반드시 완성된다 |
| 3 | LIVE 결과에서 원문 앱 경로·PFN·IP·DNS·설정·키가 0건인지 다시 검사한다. (`:55`) | `Test-ProhibitedContent`(`test-wfp-app-routing-spike.ps1:79-99`) 7종 패턴 검사 결과를 실행표에 한 행으로 기록. 검사 자체는 `:336-338`에서 이미 자동 수행됨 | QA | OWNER-06이 범위 안이고 **수단이 이미 코드에 있다.** 세 건 중 유일하게 새로 만들 것이 없다 |

> 미완료 52건 중 3건.
> **초안의 선택(`:55` · `:58` · `:60`)에서 두 건을 바꿨다.** `:58`(marker 재확인)과 `:60`(payload lease 유지)은 LIVE를 열면 저절로 증거가 생기는 항목이라 슬롯을 쓸 이유가 없다. 대신 §2-5에 사실만 기록해 두었다(`PayloadIntegrityLease`가 LIVE 경로에서 안 쓰인다는 것 포함). 다음 차수에 그대로 남는다.
> `:52`(패키지)·`:53`(종료 4경로)·`:54`(제3자 비교)는 이번 범위의 본 작업이지만, `:53`·`:54`는 §2-8 수단 3·4를 먼저 만들어야 닫히므로 미리 약속하지 않았다.
> 사용자 결정이 필요한 항목(`:66`~`:70`)은 §7로 보냈다.
>
> **2차 검증 재확인 (안 2 채택 후에도 세 건 모두 유효)**
> - `:51` — "관찰 환경을 **준비**한다"이다. 준비의 완료 조건은 수단이 서는 것이고, IPv6가 없으면 **"없다는 것을 근거와 함께 확정하는 것"까지가 준비 완료**다(§4-2 3단계 판정 규칙이 그 결론을 반드시 내리게 한다). 원인 규명을 미뤄도 닫힌다.
> - `:50` — "실행표에 **연결**한다"이다. `INCONCLUSIVE`도 연결된 판정이다. AC-06-1은 흐름 발생기(수단 1)가 이번 범위라 연결된다. 닫힌다.
> - `:55` — 수단이 이미 있고 IPv4·IPv6 어느 쪽이든 결과 파일은 나온다. 닫힌다.
> 세 건 모두 **다음 차수로 미룬 D(원인 규명)·IPv6 실측에 의존하지 않는다.**

---

## 4. 설계 방향 (잠정)

### 4-1. 작업 순서 (확정 사항 1)

```
선행(커밋 · 복구 스크립트 · 터널 절차)
   ↓
관찰 수단 4가지 + 판정 어휘 INCONCLUSIVE
   ↓
알려진 실패 원인 조사·수정 (Edge UDP·QUIC / 비선택 Chrome 유입)
   ↓
M-001~M-032 재실행 → AC 12개 실행표
   ↓
OWNER-04·05·06 + R3-DOC-01 + R3-DEC-04 근거표
```

관찰 수단이 없는 상태로 재실행을 먼저 하면 2026-08-10과 똑같이 사람이 128번 타이핑한 값을 결과로 갖게 된다. 순서를 뒤집지 않는다.

### 4-2. 시험용 WireGuard 터널 절차 (확정 사항 2)

**이 터널은 시험 장치다. OWNER-05가 상태를 비교하는 "제3자 DNS·VPN·광고 차단·백신·보안 제품"이 아니다.** 두 개념을 실행표에서 다른 칸으로 관리한다.
- **시험 장치**: 우리가 띄우고, 우리가 정리하고, 다음 홉 인터페이스로 쓰는 WireGuard 터널
- **제3자 제품**: `Adguard Service` · `VPN Unlimited TAP` · Windows Defender · Windows 방화벽 · `WarpJITSvc` — **건드리지 않고 시작 전후 상태만 비교**

| 단계 | 하는 일 | 확인 명령 | 실패하면 |
|---|---|---|---|
| 0. **기준선 고정** | 터널을 올리기 **전에** §1-3(WFP)·§1-4(네트워크·제3자 제품) 두 표를 다시 찍는다 | `netsh wfp show state` · `Get-NetAdapter` · `Get-NetRoute` · `Get-DnsClientServerAddress` · `Get-Service` | 기준선 없이 시작하면 회복 비교가 불가능하다 |
| 1. 준비 | 설정 파일 `C:\Users\NetMD\Downloads\63543_jp_wg.conf`를 그대로 써서 터널을 올린다. **설정 내용(키·엔드포인트·주소)은 어떤 산출물에도 적지 않는다** | `wireguard.exe /installtunnelservice` | — |
| 2. **생존 확인** | 어댑터가 `Up`인지, index를 얻을 수 있는지, **서버가 살아 있어 실제로 통신되는지** | `Get-NetAdapter` · `Test-NetConnection` (터널 너머 대상) | **서버가 죽어 있으면 그 시점에 사용자에게 알린다.** 대체 설정을 임의로 찾지 않는다 |
| 3. **IPv6 확인 (확정 사항 8)** | 터널이 IPv6 전역 주소와 기본 경로를 주는가 | `Get-NetIPAddress -InterfaceIndex {터널} -AddressFamily IPv6` · `Get-NetRoute -DestinationPrefix '::/0'` | **판정 규칙은 아래 표에 고정** |
| 4. **기준 경로 확인 (버그·한계 판별 1단계)** | **WFP 정책을 걸기 전에** 비선택 앱(Chrome)이 어디로 나가는지 관찰한다 | 관찰기로 Chrome의 새 연결 인터페이스 확인 | 결과 해석은 §8-1 판별표 |
| 5. 시험 | 터널 index를 하네스에 넘긴다(`:1481-1491`). 하네스는 읽기만 한다(AC-05-3) | — | — |
| 6. 중단·정리 | 정책을 지우고 **터널을 내려 0단계 상태로 되돌린다.** 어댑터 없음 · 경로 원복 · DNS 원복을 0단계와 비교 | `wireguard.exe /uninstalltunnelservice` 후 0단계 명령 재실행 | 회복 비교에 `FAIL`로 남긴다 |

**3단계 IPv6 판정 규칙 (실행 중에 판단이 갈리지 않게 미리 고정)**

| 3단계 관찰 | IPv6 16사례(`M-009`~`M-016` · `M-025`~`M-032`) 처리 |
|---|---|
| 터널에 IPv6 전역 주소가 있고 `::/0` 경로가 터널을 가리킴 | **실측한다.** 이번 실기에 포함 |
| 둘 중 하나라도 없음 | **그 자리에서 16건을 `INCONCLUSIVE`로 닫는다.** 근거 문장: "이 회선과 시험용 터널 모두 IPv6 전역 주소·기본 경로를 제공하지 않아 관찰 수단이 성립하지 않음(관찰 시각 기록)". 재시도하지 않는다 |

> 시작 시점 예측: 이 PC의 물리 회선에는 IPv6가 없다(§1-4 실측). 터널이 IPv6를 줄지는 **해 봐야 안다.** 그래서 확인을 절차에 넣었다.

**순서에 모순이 없도록 못 박는 것**
- 터널은 **WFP 정책보다 먼저 올리고, WFP 정책보다 나중에 내린다.** 정책이 터널 LUID를 다음 홉으로 잡고 있으므로(`NativePolicyBuffer.cs:52-57`) 터널을 먼저 내리면 정책이 없는 인터페이스를 가리킨다.
- **회복 비교의 기준선은 터널을 올리기 전(0단계)이다.** 터널이 올라간 상태를 기준선으로 삼으면 "설치 전으로 돌아왔다"가 터널이 남아 있는 상태를 뜻하게 되어 오염된다.
- 터널을 내리는 것까지가 회복의 일부다(§4-3).

### 4-3. 회복 비교 (macOS와 같은 순서)

`시작 전 기준선 → 흐름 생성 → 중단 → 회복 비교`. 지금 코드에는 마지막 단계가 없다(§8 R-12). 기준선은 §1-3(WFP)과 §1-4(네트워크·제3자 제품) 두 표다.

### 4-4. 이미 아는 실패부터 본다

2026-08-10의 세 원인을 사례군으로 묶어 원인별로 판정한다 (출처: `...22-38-22_debugging-journal.md:94-97`).
**"비선택 Chrome의 TCP·DNS가 VPN으로 들어온다"는 앱 경계가 새는 쪽이라 사용자 모드 WFP의 한계를 직접 가리킨다. `R3-DEC-04` 근거표의 핵심 항목이다.** 동시에 `R3-DEC-01`(helper·renderer 자동 포함)·`R3-DEC-02`(기존 연결 처리)와도 맞닿으므로, 그 두 항목 밑에 **근거로만** 붙인다(확정 사항 6).

---

## 5. 비협상 불변식 (반드시 보존)

- **관찰하지 못한 것을 실패 아님으로 세지 않는다.** macOS에서 가장 오래 걸린 결함이다. (출처: `docs/windows-r4-handoff-2026-08-14.md:81`) — `INCONCLUSIVE`가 `notRunCount`로 조용히 흡수되지 않게 하는 것이 이 불변식의 코드 표현이다(§3-2 #3).
- **자동 결과를 실기 증거로 복사하지 않는다.** 직전 회고가 AI에게 남긴 요구다. (출처: R3 회고 `retrospective-2026-08-11_20-56.md:219`)
- **손으로 넣은 값을 측정으로 적지 않는다.** `-LiveObservationJson`(`test-...ps1:999-1033`)은 형식만 검사하고 값의 출처를 확인하지 않는다. 관찰값의 출처를 실행표에 반드시 함께 적는다.
- **제3자 DNS·VPN·광고 차단·백신·보안 제품을 중지하거나 재설정하지 않는다.** 읽기만 한다. (출처: AC-05-4 — 기획서 88행)
- **우리가 띄운 시험용 터널과 제3자 제품을 같은 칸에 적지 않는다.** (확정 사항 2)
- **WireGuard 설정 파일의 내용을 산출물에 적지 않는다.** 경로만 적는다. 금지 패턴 검사가 이를 강제한다(`Test-ProhibitedContent:88` — `[Interface]`·`[Peer]`·`PrivateKey`·`Endpoint`·`AllowedIPs`·`.conf`).
- **PFN만으로 SID를 추정하지 않는다.** `M-033`~`M-064`는 `WfpNativeApi.cs:27`을 근거로 일괄 `NOT_RUN`. (확정 사항 4)
- **제품 코드와 macOS 코드를 건드리지 않는다.** `test-...ps1:1333-1338`이 강제한다.
- **정리 성공과 기능 성공은 별개 판정이다.** 2026-08-10에 정리는 `PASS/NONE`이었지만 제품 판정은 `FAIL`이었다.
- **실기 결함이 나오면 처음 실패한 관문부터 다시 실행하고 범위를 넓히지 않는다.** (출처: R3 회고 §6, `:171`)

---

## 6. 수정범위 (예상 파일)

전부 스파이크·시험 범위 안이다. 제품 코드는 없다.

| 경로 | 무엇을 |
|---|---|
| `scripts/windows/restore-network-dev.ps1` | **선행 작업** — WFP 소유 정책 4개·spool·`%TEMP%` 잔여물 정리, IPv6 DNS 복원 |
| `scripts/windows/` (신규 4개) | 흐름 발생기 · `pktmon` 인터페이스 관찰기 · 소유 정책 열거기 · 제3자 제품 상태 수집기 |
| `scripts/windows/` (신규 1개) | 시험용 WireGuard 터널 준비·확인·정리 (설정 내용은 기록하지 않음) |
| `scripts/windows/test-wfp-app-routing-spike.ps1` | 위 수단 연결, 관찰값 출처 기록, 결과 파일 저장(§8 R-08), LIVE 이후 지문 재측정(§8 R-12), 비대화형 입력 확장(§8 R-11) |
| `scripts/windows/fixtures/wfp-spike/limited-result.schema.json` | §3-2 #9 |
| `scripts/windows/fixtures/wfp-spike/dry-run-result.json` | §3-2 #10 |
| `windows/VpnRouter.WfpSpike/Contracts/WfpSpikeEnums.cs` | §3-2 #1 |
| `windows/VpnRouter.WfpSpike.Harness/WfpObservationCollector.cs` | §3-2 #2 |
| `windows/VpnRouter.WfpSpike.Harness/OwnerHarnessRunner.cs` | §3-2 #3~#6, 실패 시 사례 보존(§8 R-05) |
| `windows/VpnRouter.WfpSpike/Native/NativeMethods.cs` | 소유 정책 열거 API 추가 시 |
| `windows/VpnRouter.Tests/Program.cs` | 위 전부의 집중 시험 |
| `{PMO}/R2/2026-08-10_16-08_plan_...md` | **264행·347행** 문구만 AC-08-5에 맞춤 (§3-3) |
| `docs/` | R4 실기 실행표 · `R3-DEC-04` 근거표 |

### 영향 범위 전수 추적

| 대상 | 소비처 (전수) |
|---|---|
| `WfpResultRedactor.ContainsProhibitedContent` | `VpnRouter.Tests/Program.cs:947-949` **뿐** — LIVE 경로 0건 |
| `PayloadIntegrityLease` | `VpnRouter.Tests/Program.cs:1155` **뿐** — LIVE 경로 0건 |
| `LiveApplyGate` | `OwnerHarnessRunner.cs:65`, `Tests/Program.cs:954-957` |
| `WfpInputValidator` | `OwnerHarnessRunner.cs:86`, `Tests/Program.cs:962-976` |
| `WfpOwnedPolicyKeys` (GUID 4개) | `WfpPolicySession.cs:74`, `WfpNativeApi.cs:51,69` |
| `WfpSpikeOutcome` | §3-2의 **24곳 · 6개 파일** — 여러 군데가 **각각 값을 나열**하므로 하나만 고치면 조용히 어긋난다 |
| `NOT_RUN` 허용 실패 코드 | `WfpObservationCollector.cs:36`(3종 허용) 과 `test-...ps1:301`(1종만 허용) 이 **이미 서로 다르다** → R-14 |

---

## 7. 열린 질문 (OQ) — **0건**

초안의 OQ 6건과 1차 검증의 OQ-A·OQ-B까지 **전부 확정됐다**(§0-1 확정 사항 1~8). 사용자 판단을 기다리는 항목은 남아 있지 않다.

실행 중에 갈릴 수 있는 갈림길 두 개는 **질문이 아니라 미리 고정된 판정 규칙**으로 바꿔 두었다.
- IPv6를 실측할지 `INCONCLUSIVE`로 닫을지 → §4-2 3단계 판정 규칙표
- 비선택 앱 유입이 버그인지 한계인지 → §8-1 관찰 A·B·C 판별표

---

## 8-0. ★ 이번 차수가 도달할 수 있는 상한 (1차 검증에서 새로 발견)

| 사실 | 근거 |
|---|---|
| 최종 `PASS`는 `M-001`~`M-032`가 **모두** `PASS`일 때만 나온다 | `OwnerHarnessRunner.cs:190` `requiredPass`, R2 기획서 196행·365행 |
| `M-001`~`M-032` 중 IPv6 사례는 **16건**이다 (행 3·4 = `M-009`~`M-016`, 행 7·8 = `M-025`~`M-032`) | R2 기획서 228·229·232·233행 |
| 이 PC에는 IPv6 전역 주소도 기본 경로도 없다 | 2026-08-14 20:58 실측 — `fe80::...%8` 링크 로컬 하나뿐, `::/0` 경로 0건 |
| 2026-08-10 실기도 같은 조건이었다 | 저널 `:97` "Wi‑Fi와 VPN 모두 IPv6 전역 주소와 기본 경로가 없었다" |

**따라서 IPv6가 없으면 R4의 최종 판정은 `PARTIAL`이 상한이다.**

### 그런데 상한보다 더 중요한 것 — `FAIL`이 정상 결과일 수 있다 (2차 검증에서 추가)

`OwnerHarnessRunner.cs:194`를 직접 읽었다.

```csharp
var verdict = cleanupFailed || fail > 0 ? WfpSpikeVerdict.FAIL : ... PASS : PARTIAL;
```

**`FAIL`이 한 건이라도 있으면 전체 판정은 `PARTIAL`이 아니라 `FAIL`이다.** 즉 결과 어휘에는 "정직하게 측정했더니 플랫폼 한계를 발견했다"를 담을 자리가 없다. 그것도 `FAIL`로 나온다. 2026-08-10의 제품 판정 `FAIL`이 정확히 이 경우였다.

**그러므로 R4의 성공 기준을 JSON `verdict`로 정의하지 않는다.**

| 무엇 | 이번 차수의 성공 기준 |
|---|---|
| JSON `verdict` | `PARTIAL` 또는 `FAIL` **둘 다 정상**. 이 값으로 차수를 평가하지 않는다 |
| 실제 성공 기준 | ① IPv4 16사례에 **측정 기반** 판정(손입력 아님)이 서 있다 ② 나머지가 근거 있는 `INCONCLUSIVE`·`NOT_RUN`으로 닫혔다 ③ OWNER-04·05·06이 증거와 함께 닫혔다 ④ `R3-DEC-04` 근거표가 나왔다 |

### 안 2에서의 사례 내역 (조건부)

| 구간 | 터널이 IPv6를 주는 경우 | 안 주는 경우 |
|---|---|---|
| IPv4 16건 (`M-001`~`M-008` · `M-017`~`M-024`) | 실측 → `PASS` 또는 `FAIL` | 좌동 |
| IPv6 16건 (`M-009`~`M-016` · `M-025`~`M-032`) | 실측 → `PASS` 또는 `FAIL` | **`INCONCLUSIVE` 16건** |
| 패키지 32건 (`M-033`~`M-064`) | `NOT_RUN`(`PACKAGE_IDENTITY_UNAVAILABLE`) | 좌동 |
| 합계 | 64건 | 64건 |

`INCONCLUSIVE`가 하나라도 있으면 `requiredPass`가 거짓이 되어 `PASS`는 나오지 않는다. 이는 설계대로다 — **"관찰 못 함"을 "실패 아님"으로 세지 않는다**는 불변식의 코드 표현이다.

---

## 8-1. ★ 범위 — 안 2 채택 (확정) · 실패의 사례 단위 분해 · 버그와 한계 판별

### 지금 R4에 들어 있는 것

| 묶음 | 내용 | 크기 |
|---|---|---|
| A. 선행 | 커밋 · 복구 스크립트 WFP 정리 · 터널 절차 | 작음 |
| B. 관찰 수단 | 신규 도구 **4개** + 터널 스크립트 1개 | **큼** |
| C. 판정 어휘 | `INCONCLUSIVE` + 스키마 버전 — **6개 파일 · 24곳** + 시험 | **큼** |
| D. 실패 원인 수정 | Edge UDP·QUIC / 비선택 Chrome 유입 | **크고 불확실** |
| E. 재실행·기록 | 64사례 + AC 12개 실행표 + OWNER-04·05·06 | 큼 |
| F. 문서 | `R3-DOC-01` · `R3-DEC-04` 근거표 | 작음 |

### 채택 결과 — 안 2 (사용자 확정)

| 이번 차수 (R4) | 다음 차수 (R5) |
|---|---|
| A 선행 조치 · B 관찰 수단 · C 판정 어휘 24자리 | D 원인 규명 (버그냐 한계냐) |
| **IPv4 16사례 실기** + 조건부 IPv6 16사례 (§4-2 3단계) | IPv6 회선 확보 후 재실행 (터널이 안 줄 경우) |
| OWNER-04 · 05 · 06 | `R3-DEC-04` 최종 결정 |
| F 문서 (`R3-DOC-01` 264행·347행) | `R3-DEC-01`·`02`·`03`·`05` |

### 알려진 실패를 사례 단위로 가른다 (이번 몫 / 다음 몫)

"어느 실패가 IPv4 16사례를 막는가"를 사례 ID로 갈랐다. 행 번호는 R2 기획서 226~233행.

| 알려진 실패 (2026-08-10) | IPv4 몫 — **이번 범위** | IPv6 몫 — 다음 차수 |
|---|---|---|
| Edge의 UDP·QUIC이 Wi-Fi로 빠짐 | **`M-002` · `M-003`**(행 1) · **`M-006` · `M-007`**(행 2) | `M-010`·`M-011`·`M-014`·`M-015` |
| 비선택 Chrome이 VPN으로 들어옴 | **`M-017`~`M-024`**(행 5·6) — 특히 TCP·DNS | `M-025`~`M-032` |
| IPv6 전역 경로 없음 | 해당 없음 | 16건 전부 (§4-2 3단계로 판정) |

**Edge UDP·QUIC 누출은 IPv4 사례 4건에 직접 걸리므로 이번 범위다.** 비선택 Chrome 유입도 IPv4 8건에 걸리지만, 고치는 대상인지부터 가려야 한다.

### 버그냐 한계냐 — 판별 절차 (실행 중에 갈리지 않게 미리 고정)

비선택 앱이 VPN으로 가는 현상을 **세 번 관찰**해서 가른다. §4-2의 4단계가 첫 관찰이다.

| # | 언제 | 무엇을 본다 |
|---|---|---|
| 관찰 A | 터널 올림 · **WFP 정책 없음** | Chrome의 새 연결이 어디로 가나 |
| 관찰 B | 터널 올림 · **WFP 정책 있음** | 〃 |
| 관찰 C | 터널 올림 · **정책만 제거** | 〃 |

| 관찰 A | 관찰 B | 관찰 C | 판정 | 처리 |
|---|---|---|---|---|
| VPN | VPN | VPN | **환경** — 터널이 기본 경로를 가져갔다. 우리 정책과 무관 | 행 5·6의 기대값 `BASELINE`이 이 환경에서 성립하지 않는다 → **`INCONCLUSIVE`** + 근거. `R3-DEC-04`와 무관 |
| BASELINE | VPN | BASELINE | **버그** — 정책을 걸 때만 샌다. 우리가 만든 것 | 이번에 고친다 |
| BASELINE | VPN | VPN | **버그(정리 결함)** — 정책을 지워도 안 돌아온다 | 이번에 고친다. OWNER-04와 같은 뿌리 |
| BASELINE | BASELINE | BASELINE | 재현 안 됨 | 2026-08-10 조건과 무엇이 다른지 기록 |

> **관찰 A가 이 판별의 핵심이다.** WireGuard 터널은 보통 기본 경로를 통째로 가져간다. 그러면 **정책과 무관하게 모든 앱**이 VPN으로 간다. 2026-08-10의 "비선택 Chrome이 VPN으로 들어왔다"가 이 경우였을 가능성이 높다 — 그렇다면 그것은 사용자 모드 WFP의 앱 경계가 샌 것이 아니라 **애초에 비선택 앱을 관찰할 조건이 아니었던 것**이고, `R3-DEC-04` 근거로 쓰면 안 된다. 관찰 A 없이 `R3-DEC-04` 근거표를 쓰면 잘못된 결론을 사용자에게 올리게 된다.

> 위 표에서 **어느 칸도 "고친다"로 끝나지 않는 경우**(첫 행)에는 그 사실 자체를 `R3-DEC-01`(helper·renderer 자동 포함)·`R3-DEC-02`(기존 연결 처리) 밑에 **근거로만** 붙인다. 결정은 하지 않는다(확정 사항 6).

### 왜 나눴는가 — 근거 셋

1. **D는 "고친다"가 성립하지 않을 수 있다.** 비선택 Chrome이 VPN으로 들어오는 것은 정책이 앱 신원 조건 하나만 걸고 다음 홉을 지정하는 구조(`NativePolicyBuffer.cs:52-74`)에서 나온 결과일 수 있다. 그렇다면 이것은 **버그가 아니라 사용자 모드 WFP의 한계**이고, 고치는 대신 `R3-DEC-04` 근거로 기록하는 것이 맞다. 어느 쪽인지는 조사해 봐야 안다 — 즉 D는 **작업량을 미리 셀 수 없다.**
2. **B와 E가 서로를 기다린다.** 관찰 수단이 완성돼야 재실행이 의미 있고, 재실행해 봐야 관찰 수단의 결함이 드러난다. macOS R3에서 실기 결함 10건이 나온 자리가 정확히 여기다.
3. **C는 조용히 틀리기 쉽다.** `OwnerHarnessRunner.cs:189`의 `notRun = count - pass - fail` 같은 자리가 **24곳**에 흩어져 있다(§3-2). 한 곳만 놓쳐도 `INCONCLUSIVE`가 `NOT_RUN`으로 흡수되어 **"관찰 못 함을 실패 아님으로 세는"** 바로 그 불변식이 깨진다.

### 검토했으나 채택하지 않은 안 (기록 보존)

**안 1 — 기반과 실기를 나눈다**

| 차수 | 묶음 | 산출물 | 판정 |
|---|---|---|---|
| **R4** | A + B + C + F(`R3-DOC-01`) | 관찰 수단 4개 · 판정 어휘 · 복구 수단 · 터널 절차. **DRY 검증까지** | 기반 완성 여부 |
| **R5** | D + E + F(`R3-DEC-04`) | 64사례 실기 · AC 12개 실행표 · 근거표 | `PARTIAL` (§8-0) |

장점: R4가 실기 없이 끝나 되돌리기 쉽고, R5는 수단이 갖춰진 상태에서 한 번에 돈다. 단점: 실기 증거가 한 차수 늦다.

**안 2 — IPv4만 먼저 닫는다**

| 차수 | 범위 |
|---|---|
| **R4** | A + B + C + IPv4 16사례 실기 + OWNER-04·05·06 + F |
| **R5** | D 원인 조사 · IPv6 회선 확보 후 16사례 · `R3-DEC-04` 최종 |

장점: 이번에도 실기 증거가 나온다. 단점: D를 미루므로 `FAIL` 사례가 남은 채 차수가 끝난다.

**안 3 — 그대로 간다**
전부 한 차수에. 재작업 한도를 넘길 가능성이 높다. 체크리스트 `:76`("기본 재작업 한도를 넘기기 전에 사용자 판단을 받는다")이 걸릴 것을 예상해야 한다.

> **사용자가 안 2를 채택했다**(확정 사항 7). 실기 증거를 이번에도 남기면서 가장 불확실한 D만 뒤로 미룬다. §8-0에 따라 어차피 이번 상한이 `PARTIAL`이므로 D를 미뤄도 판정 등급이 내려가지 않는다.

### 안 2에서도 남는 크기 경고

안 2로 줄여도 **C(판정 어휘 24자리)와 B(관찰 수단 4개)는 그대로 남는다.** 이 둘이 이번 차수 작업량의 대부분이다. 특히 C는 6개 파일을 동시에 고쳐야 하고, 하나라도 빠지면 자동 검사가 `LIMITED_RESULT_SCHEMA_INVALID`로 막혀 **실기 근처에도 못 간다.** 설계 단계가 §3-2 표를 그대로 작업 목록으로 받는 것이 안전하다.

---

## 8. 위험 요소

### R-01 · 2026-08-10 실기가 이미 있었다 (반영 완료)

요구사항의 "첫 실행" 전제는 **폐기됐다**(§0-1 확정 사항 1). 사실은 아래와 같다.

- 결과: `PASS 5 · FAIL 27 · NOT_RUN 32`, 정책 정리 `PASS/NONE`, 제품 판정 `FAIL` (`...22-38-22_technical-changelog.md:73-78`)
- 흔적: `artifacts/wfp-spike/*.etl` 6개 (2026-08-10 22:08~22:28)
- 그 실기에서 고친 내용이 커밋 `33bdd98`(2026-08-10 22:40:02)에 있다. 저널 작성 시각(22:38)보다 **뒤**다 → **지금 코드는 그 실기 이후 코드다.**
- R2 회고의 "실제 LIVE 호출 0건"은 맞는 기록이다. 그 실기는 R2 파이프라인이 끝난 뒤(19:25 이후) 파이프라인 밖 저널 회차에서 이뤄졌다.

알려진 실패 원인 3가지는 §4-4로 옮겼다.

### R-02 · 미커밋 파일이 자동 게이트를 막는다 → **§0-2 선행-1로 승격**

### R-03 · 복구 수단에 WFP 정리가 없다 → **§0-2 선행-2로 승격**

### R-04 · 강제 종료·Ctrl+C가 정리를 건너뛴다 (높음)

- 스크립트는 LIVE 실패 시 `$process.Kill($true)`(`:1140`)로 하네스를 죽인다. C#의 `finally`/`DisposeAsync`가 돌지 않아 `WfpPolicySession.CleanupOnce()`(`WfpPolicySession.cs:88`)가 실행되지 않는다. 동적 세션 자동 해제에만 기대게 되고, 스크립트는 정리 성공 여부를 확인하지 않는다.
- `Read-Host`(`:969`) 앞에서 Ctrl+C를 누르면 PowerShell의 `finally`(`:1549-1566`) 실행이 보장되지 않는다. 하네스 자식 프로세스가 고아로 남아 **최대 30분간 정책을 붙인 채 살아 있을 수 있다**(하네스 타임아웃 `OwnerHarnessRunner.cs:149`).
- **이것은 가설이 아니라 이미 일어난 일이다.** spool 폴더 10개가 남아 있고 내용물이 `step-*.tmp`(`:498-500`이 지워야 할 것)와 잠긴 payload 사본이다 → `finally`가 10번 건너뛰어졌다.

이 상태가 정확히 OWNER-04가 확인해야 할 대상이므로, 확인 수단(§2-8 수단 3)과 복구 수단(선행-2)이 **먼저** 필요하다.

### R-05 · 실패하면 이미 모은 관찰이 버려진다 (중간)

`OwnerHarnessRunner.cs:119-123`의 `catch (WfpSpikeException)`은 `Result(..., WfpSpikeOutcome.FAIL, [])` — **빈 사례 목록**을 반환한다. DESKTOP 32건을 다 모은 뒤 PACKAGE 단계에서 예외가 나면 그 32건이 사라지고 `caseTotal=0`이 된다. 패키지 인자를 일부만 넣으면 `:116`에서 바로 이 경로를 탄다. **`M-033`~`M-064`를 일괄 `NOT_RUN`으로 닫기로 한 이번 차수에서는 반드시 지나가는 자리다.**

### R-06 · 시간 제약 네 개가 서로 어긋난다 (중간)

| 제약 | 값 | 위치 |
|---|---|---|
| 표식 만료 | 15분 | `OwnerHarnessRunner.cs:215` |
| 하네스 관찰 대기 | 30분 | `OwnerHarnessRunner.cs:149` |
| 스크립트 `Read-Host` | **제한 없음** | `test-...ps1:969` |
| 스크립트 프로세스 대기 | 60초 | `:1090`, `:1128` |

표식을 만든 뒤(`:1433`) 하네스를 띄우기까지(`:1530`) 사람이 최대 6번 타이핑한다. 15분을 넘기면 거부되는데, 그 시점엔 빌드 2종·집중 시험·게시·추출이 이미 끝난 뒤라 재시도 비용이 크다. 30분 제한은 2026-08-10에 실제로 사람 입력 중 만료돼 `M-025`에서 중단됐다(저널 `:110-120`). **관찰 자동화(§2-8 수단 1·2)가 이 위험도 함께 없앤다.**

### R-07 · C++ 툴체인 의존이 사용자에게 도달하지 않는다 (중간)

`build-portable.ps1:219-221`은 의존을 **명시적으로 선언한다**:
```powershell
throw "Visual Studio discovery tool is required for the WFP SDK ABI probe."
```
`:223`은 `Microsoft.VisualStudio.Component.VC.Tools.x86.x64`를, `:225-228`은 Windows SDK와 `cl.exe`를 요구한다.

**문제는 선언이 없는 것이 아니라 그 메시지가 사용자에게 안 보이는 것이다.** `Invoke-LoggedCommand`(`:481-501`)가 `catch { return 1 }`(`:495-497`)로 예외를 삼키고 로그 파일도 `finally`에서 지운다(`:498-500`). 사용자가 보는 것은 `PUBLISH_CONTENT_MISSING`(`:1418`)뿐이다 — **"C++ 컴파일러가 없다"가 "게시물이 없다"로 바뀌어 나온다.** macOS `rg` 사례와 같은 종류다.

이 PC에는 셋 다 있다(§1-2). 전제 조건을 문서에 적고, 실패 메시지를 보존하도록 고친다.

관련 구멍: `:875-879`는 `wfp-sdk-abi-x64.json`이 없어도 실패하지 않고 상수 문자열 해시로 대체한다. 필수 존재 검사 목록(`:831-836`)에도 빠져 있다. 결국 하네스가 `EVIDENCE_FILES:ABI`로 거부하지만(`OwnerHarnessRunner.cs:238-246`), 그때는 원인이 또 한 겹 멀어진다.

### R-08 · 결과가 파일로 남지 않는다 (중간)

LIVE 결과는 stdout 한 줄이 전부다(`:76`, `:1569`). 스크립트 전문에 `Out-File` · `Set-Content` · `Add-Content` **0건**(전수 검색). 단계별 로그(`step-*.tmp`)는 `finally`에서 즉시 삭제된다(`:499`). 콘솔 리다이렉트를 미리 걸지 않으면 수 시간짜리 실기의 증거가 사라진다. **실행 전에 결과 저장 경로부터 정한다.**

### R-09 · 금지 패턴 검사 구현이 둘로 갈라져 있다 (중간)

C# `WfpResultRedactor`(3종)와 PowerShell `Test-ProhibitedContent`(7종)가 같은 일을 다른 범위로 한다. C# 쪽은 PFN·DNS·진단 필드를 잡지 못한다. LIVE 경로는 PowerShell 쪽만 쓰므로 지금 새는 곳은 없지만, C# 쪽을 믿고 쓰는 코드가 생기면 바로 구멍이 된다. 체크리스트 `:63`의 "탐색 규칙을 한 구현으로 모을지 결정한다"와 같은 종류다.

### R-10 · `-Verbose` 경로는 금지 패턴 검사를 지나가지 않는다 (낮음)

`:1092` · `:1130` · `:1144`의 `"HARNESS_DIAGNOSTIC=" + $harnessError`는 하네스 stderr 원문이고, `:1544`는 예외 메시지 원문이다. `-Verbose`로 실행하면 경로·주소가 그대로 나올 수 있다. **R4는 `-Verbose` 없이 실행하거나 이 경로에도 검사를 건다.**

### R-11 · 비대화형 실행이 불가능하다 (중간 — 관찰 자동화의 전제)

`-LiveObservationJson`은 `M-001`~`M-032`만 받는다(`:1015` 정규식, `:1004` 개수 강제). `M-033`~`M-064`와 패키지 AppContainer·SID(`:1510-1511`)는 `Read-Host` 전용이다. 관찰 자동화를 만들면 이 입력 경로도 함께 넓혀야 한다.

### R-12 · LIVE 이후 네트워크 지문을 다시 찍지 않는다 (중간)

`beforeAfterFingerprint`는 LIVE **이전** 값을 그대로 붙일 뿐이다(`:1540`). LIVE가 라우팅·DNS·어댑터 상태를 바꿨는지 검증하는 사후 검사가 없다. 요구사항이 요구한 "시작 전 기준선 → 흐름 생성 → 중단 → 회복 비교"의 마지막 단계가 코드에 없다. §4-3에서 만든다.

### R-13 · 터널 서버가 죽어 있을 수 있다 (중간)

설정 파일은 2026-07-16에 받은 것이다(수정 시각 확인, 내용은 읽지 않음). 서버가 아직 살아 있는지는 **실행 직전에만 알 수 있다.** §4-2 2단계에서 확인하고, 안 되면 그 시점에 사용자에게 알린다. 대체 설정을 임의로 찾지 않는다.

### R-14 · 두 검증기가 `NOT_RUN` 실패 코드에 대해 이미 다르게 판단한다 (높음 — 2차 검증에서 새로 발견)

같은 결과를 두 곳이 검사하는데 규칙이 다르다.

| 검증기 | `NOT_RUN`에 허용하는 실패 코드 |
|---|---|
| C# `WfpObservationCollector.cs:36` | `PACKAGE_IDENTITY_UNAVAILABLE` · `OWNER_ABORTED` · `ENVIRONMENT_UNAVAILABLE` **(3종)** |
| PowerShell `test-...ps1:301` | `PACKAGE_IDENTITY_UNAVAILABLE` **(1종만)** |

**하네스가 받아들인 결과를 스크립트가 `LIMITED_RESULT_SCHEMA_INVALID`로 되던진다.**

지금 당장 터지지 않는 이유는 하네스가 중단 시 사례를 **비운 채**(`OwnerHarnessRunner.cs:122`) 돌려주기 때문이다. 그런데 R2 기획서 251행은 **"중간 실패나 취소가 발생하면 남은 사례는 `NOT_RUN/OWNER_ABORTED`로 채우고 세션을 닫습니다"** 를 요구한다. 이 요구는 아직 구현돼 있지 않고(R-05와 같은 뿌리), **구현하는 순간 `:301`에 걸린다.**

**이번 차수는 이 자리를 반드시 지나간다.** OWNER-04가 일부러 Ctrl+C와 강제 종료를 일으키기 때문이다. `INCONCLUSIVE`를 넣으면서 두 규칙을 함께 맞춘다(§3-2 #2·#15).

### R-15 · 프리브리프 자체에 이 PC의 LAN 주소가 들어 있다 (낮음)

§1-4에 게이트웨이·DNS 주소 `192.168.1.1`이 적혀 있다. 시작 기준선 증거라 뺄 수 없다. 금지 패턴 검사는 **LIVE 결과 JSON**에만 적용되므로(`Test-ProhibitedContent` 호출 지점 `:336`·`:71`) 이 문서는 대상이 아니다. 다만 이 문서를 저장소 밖으로 공유할 일이 생기면 그 두 칸이 유일한 가릴 대상이다.

**설정 파일 내용은 새어 들어가지 않았다.** 문서 전문을 `PrivateKey` · `PublicKey` · `PresharedKey` · `Endpoint` · `AllowedIPs` · `[Interface]` · `[Peer]` · `ListenPort` · `Address =` · `DNS =` · base64 키 형태로 검색한 결과, 걸린 것은 **금지 규칙 자체를 적은 §5의 한 줄뿐**이고 실제 설정값은 0건이다. `63543_jp_wg.conf`는 크기·수정 시각만 조회했고 내용을 읽은 적이 없다.

---

## 8-2. 인계장 §5의 macOS 교훈 6가지 → Windows 사전 점검 항목

| # | macOS 교훈 (`windows-r4-handoff-2026-08-14.md`) | Windows 번역 | 상태 |
|---|---|---|---|
| 1 | 자동 검사 초록은 실제 동작 증거가 아니다 (`:79`) | 자동 게이트 통과는 필터가 커널에 올라갔다는 뜻이 아니다. 판정 칸을 처음부터 나눈다 | 확정 사항 3으로 해결 |
| 2 | 설계가 요구한 관찰마다 만들어 낼 수단이 있는지 대조하라 (`:81`) | **§2-8 대조표 완료.** AC 12개 중 7개 수단 없음 · 2개 부분. 4가지 수단을 먼저 만든다 | R4 첫 작업 항목 |
| 3 | 프로세스 권한 경계는 실기에서만 드러난다 (`:83`) | 하네스는 승격 관리자로 돈다(`LiveApplyGate.cs:20-37`). 이 스파이크는 서비스↔앱 IPC가 없어 macOS와 같은 함정은 없다. 다만 **BFE 접근 거부 시 `BFE_ACCESS_DENIED`**(`WfpNativeApi.cs:44`)로 갈리므로 실기 확인 | BFE `Running` 실측 완료 |
| 4 | 자원의 수명과 만드는 시점은 mock으로 못 잡는다 (`:85`) | 엔진 핸들·신원 blob·실행 파일 핸들의 수명이 실기 대상. `ValidatedExecutableLease`(`WfpInputValidator.cs:66-75`)와 `WfpMemoryIdentityLease`(`WfpNativeApi.cs:82-92`) — 특히 **실패 경로에서 `identity.Dispose()`가 도는지**(`WfpPolicySession.cs:30,41,57`) | 실기 확인 항목 |
| 5 | 환경에만 있는 도구에 기대면 검사가 조용히 뒤집힌다 (`:87`) | **R-07.** `rg` 대응물은 vswhere + VC++ x64 + Windows SDK. 선언은 있으나(`build-portable.ps1:221`) 메시지가 사용자에게 도달하지 않는다. `pktmon`도 새 의존으로 추가된다 | §1-2 실측 완료, 문서화 필요 |
| 6 | 설치본을 바꿀 때는 버전을 올려라 (`:89`) | 이 스파이크는 **해시 대조**로 같은 문제를 막는다. 코드를 고치면 `harnessSha256`·`worktreeFingerprint`가 바뀌어 옛 표식이 자동 거부된다(`OwnerHarnessRunner.cs:248-251`). 다만 게시물 이름이 `VpnRouter-WfpSpike-0.1.0-x64.exe`로 고정이라 **옛 게시물이 남아 있으면 헷갈린다** — 매 실행 전 `artifacts/wfp-spike/`를 비운다. **확정 사항 3의 스키마 버전 상승이 이 교훈의 직접 적용이다** | 절차로 반영 |

---

## 9. 관련 문서·메모리·차수

- 인계장: `docs/windows-r4-handoff-2026-08-14.md`
- **`M-001`~`M-064` 원 정의**: `{PMO}/R2/2026-08-10_16-08_plan_r2-windows-wfp-app-routing-spike.md` **§6.1 — 219~241행** (규칙 219-222, 표 224-241). 축은 앱 선택 여부 × IP 버전 × 기존 `/32` 일치 경로 유무(16행) × TCP·UDP·QUIC·DNS(4열). 행 1~8이 데스크톱(`M-001`~`M-032`), 행 9~16이 패키지(`M-033`~`M-064`). 실행 규칙은 §6.2 — 243행부터
- **AC 12개 원 정의**: 같은 파일 **62 · 64 · 66 · 76 · 87 · 88 · 89 · 92 · 93 · 94 · 95 · 96행**. `AC-08-5`는 **109행**
- AC별 자동 판정 권위 기록: `{PMO}/R2/2026-08-10_19-05_review-plan_r2-windows-wfp-app-routing-spike.md` **80~115행** — 12개 AC 전부 `owner NOT_RUN`, `AC-08-5`는 `자동 완료`, 전체 기술 판정 `PARTIAL`(6·12·13행)
- 2026-08-10 실기 기록: `{PMO}/inter-pipeline-2026-08-10T22-38-22_debugging-journal.md` + 짝 문서 `..._technical-changelog.md`
- 백로그 후보: `{PMO}/backlog.md:16` — **이번 요구사항은 「다음 라운드 후보」 1번과 같은 항목이다**
- R3 회고: `{PMO}/R3/retrospective-2026-08-11_20-56.md` · R2 회고: `{PMO}/R2/retrospective-2026-08-10_19-15.md`
- macOS 실기 기록(대조용, 옮겨 적지 않음): `macos/AppRoutingSpike/Docs/signed-mac-live-run-2026-08-14.md`
- 직전 회고 협업 제안 반영(AI 에게): R3 회고 **219행** — **"AI는 자동 결과를 재사용하지 않고 실제 관찰을 새로 기록해야 합니다."** → §5 비협상 불변식 2·3번, §2-8 대조표, §4-1 작업 순서로 반영했다.

---

## 9-1. 다음 차수로 미루는 항목 (백로그 등재용)

안 2 채택으로 R4에서 빠진 것들이다. 파이프라인 STEP 18이 `backlog.md` 「다음 라운드 후보」에 그대로 옮겨 적을 수 있는 형태로 적었다.

- [ ] **R5-CAUSE-01 비선택 앱의 VPN 유입이 버그인지 사용자 모드 WFP의 한계인지 규명** — R4의 관찰 A·B·C 판별표(§8-1) 결과를 받아 원인을 확정하고, 한계로 판명되면 `R3-DEC-04` 근거로 굳힌다. (출처: 저널 `inter-pipeline-2026-08-10T22-38-22_debugging-journal.md:96`, 보류 사유: R4 안 2에서 원인 규명을 다음 차수로 나눔)
- [ ] **R5-CAUSE-02 Edge UDP·QUIC 누출의 IPv6 몫** — `M-010`·`M-011`·`M-014`·`M-015`. IPv4 몫(`M-002`·`M-003`·`M-006`·`M-007`)은 R4에서 다룬다. (출처: 같은 저널 `:95`, 보류 사유: IPv6 관찰 환경 부재)
- [ ] **R5-IPV6-01 IPv6 16사례 실측** — `M-009`~`M-016` · `M-025`~`M-032`. R4에서 `INCONCLUSIVE`로 닫혔을 경우에만 남는다(§4-2 3단계에서 터널이 IPv6를 주면 R4에서 끝난다). IPv6 전역 주소와 `::/0` 경로가 있는 회선이 필요하다. (출처: 2026-08-14 실측 — 이 PC에 IPv6 전역 주소·기본 경로 0건, 보류 사유: 관찰 환경 부재)
- [ ] **R5-DEC-04 사용자 모드 WFP 실패 뒤 커널 driver 연구 여부 최종 결정** — R4가 제출한 근거표 위에서 사용자가 결정한다. (출처: `backlog.md:60` `R3-DEC-04`, 보류 사유: R4는 근거만 만들고 결정하지 않기로 확정)
- [ ] **R5-PKG-01 패키지 신원 증명(PFN↔AppContainer↔토큰 SID)** — `WfpNativeApi.cs:27`이 막고 있는 경로를 열지 여부. `R3-DEC-05`(패키지 앱 제품 범위)가 정해진 뒤에 착수한다. (출처: `WfpNativeApi.cs:25-27`, 보류 사유: 제품 범위 미결)
- [ ] **R5-MAINT-01 금지 패턴·payload lease 구현 일원화** — C# `WfpResultRedactor`(3종)와 PowerShell `Test-ProhibitedContent`(7종), `PayloadIntegrityLease`(미사용)와 `$payloadReadHandles`가 갈라져 있다. 체크리스트 `:58`·`:60`·`:63`과 같은 뿌리. (출처: §2-5 전수 검색, 보류 사유: R4 판정을 바꾸지 않는 정리 작업)

---

## 10. 검증 기록

### 1차 검증 (2026-08-14 20:55~20:58) — 수정 내역

초안의 결론을 신뢰하지 않고 인용한 사실을 **전부 라이브 소스로 재조회**했다. 초안이 하위 조사에서 받은 줄 번호를 그대로 옮겨 적은 부분이 있어 특히 그쪽을 다시 확인했다.

**재쿼리 불일치 표**

| # | 초안 서술 | 재확인 결과 | 조치 |
|---|---|---|---|
| 1 | `M-001`~`M-064` 정의 "215~241행" | 실제는 **219~241행** (규칙 219-222 + 표 224-241). 215행은 무관 | 정정 |
| 2 | AC별 판정표 "76~115행" | 실제는 **80~115행** | 정정 |
| 3 | `R3-DOC-01` 대상 "§7 264행" | 264행 맞음. **347행에도 같은 충돌 문장이 하나 더 있다** | 대상 추가 |
| 4 | R3 회고 협업 제안 "§8 :219" | **정확** (`:214` 절 제목, `:219` 제안 문장) | 유지 |
| 5 | AC 12개 줄 번호 62·64·66·76·87·88·89·92·93·94·95·96 | **전부 정확** | 유지 |
| 6 | AC-05-4를 "제3자 제품 전후 비교 수단 없음"으로 표시 | **과장.** AC-05-4 원문(88행)은 "읽기 전용으로 관찰 + 제3자 제품을 건드리지 않음"이다. **안 건드리는 쪽은 이미 충족**이고, 관찰·비교 쪽만 미비 | "없음" → **"절반"** 으로 정정 |
| 7 | `restore-network-dev.ps1`이 spool 잔여물을 "정리 대상으로 두지 않는다" | **부정확.** 스크립트 본체가 `finally`(`:1561-1565`)에서 자기 spool을 지우게 되어 있다. 잔여 10개는 **`finally`가 건너뛰어졌다는 증거**다 | 서술 교체 + R-04의 직접 증거로 승격 |
| 8 | R-07을 "미선언 외부 의존" 으로 규정 | **부정확.** `build-portable.ps1:221`이 의존을 명시적으로 선언한다. 진짜 문제는 `Invoke-LoggedCommand:495-497`이 그 메시지를 삼키는 것 | "선언은 있으나 도달하지 않음"으로 정정 |
| 9 | `INCONCLUSIVE` 추가가 "3곳" | **과소평가.** 전수 추적 결과 **9곳 + 시험**. 특히 `OwnerHarnessRunner.cs:189`의 `notRun = count - pass - fail`이 새 값을 조용히 흡수한다 | §3-2 신설 |
| 10 | (초안에 없던 사실) | **IPv6 전역 주소·기본 경로가 이 PC에 없다.** `M-001`~`M-032` 중 16건이 관찰 불가이고, `PASS` 조건이 전건 `PASS`라 **이번 차수 상한은 `PARTIAL`** | §8-0 신설 |
| 11 | (초안에 없던 사실) | 기획서 222행이 관찰값 어휘 `VPN`/`BASELINE`/`OTHER`/`UNOBSERVED`를 이미 정의했는데 **코드에 대응 자료형이 없다** | §2-4에 추가 |
| 12 | 보호 경로 게이트 차단 | **20:41·20:55 두 번 재현, 결과 동일** | 유지·강화 |
| 13 | WFP 기준선 0건 | 재확인 — 필터 5391건 중 소유 GUID 0건, `<providerContext>` 0건 | 유지 |

**그 밖의 수정**
- 요구사항 정정을 반영해 "첫 실행" 전제를 문서 전체에서 제거하고 "두 번째 실행"으로 다시 썼다.
- 사용자 확정 6건을 §0-1로 옮기고 열린 질문에서 뺐다.
- 선행 조치 절(§0-2)을 신설해 커밋과 복구 스크립트를 위험에서 **필수 작업**으로 승격했다.
- 시험용 WireGuard 터널 절차(§4-2)를 넣고 **제3자 제품과 다른 칸으로 관리**하도록 명시했다. 설정 파일은 경로만 적었다.
- §3-1 체크리스트 3건을 재선정했다(`:55`·`:58`·`:60` → `:51`·`:50`·`:55`). 바꾼 이유를 표 아래에 적었다.
- 범위 크기 평가와 분할안 3개를 §8-1에 넣었다.
- R-13(터널 서버 생존 확인)을 새로 등재했다.

### 2차 검증 (2026-08-14 21:00~21:12) — 적대 재확인

1차 검증의 결론 자체를 의심하고, 1차가 "재조회로 확인했다"고 주장한 것을 표본으로 다시 확인했다. **1차 검증도 같은 실수를 한 곳에서 반복했다.**

**뒤집힌 항목**

| # | 1차 검증 서술 | 2차 재확인 결과 | 조치 |
|---|---|---|---|
| 1 | `INCONCLUSIVE`가 건드리는 자리 **"9곳"** | **틀림. 6개 파일 · 24곳.** 스크립트의 독립 검증기 `Assert-LimitedResult`(`:245-339`)와 fixture 대조기 `Test-Fixtures`(`:354-366`)를 1차가 아예 안 봤다. 그 안에 **버전 상수 고정(`:262`)** · **산술 불변식(`:275`)** · **미지 필드 거부(`:258`)** 라는 치명적 함정 3개가 있다 | §3-2 전면 교체 |
| 2 | (1차에 없음) | **새 결함 발견 — R-14.** `WfpObservationCollector.cs:36`은 `NOT_RUN`에 실패 코드 3종을 허용하는데 `test-...ps1:301`은 1종만 허용한다. 두 검증기가 이미 어긋나 있고, R2 기획서 251행이 요구하는 `NOT_RUN/OWNER_ABORTED` 채우기를 구현하는 순간 터진다. **OWNER-04가 반드시 지나가는 자리다** | R-14 신설 |
| 3 | §8-0 "상한은 `PARTIAL`" | **맞지만 불충분.** `OwnerHarnessRunner.cs:194`는 `fail > 0`이면 `PARTIAL`이 아니라 **`FAIL`** 을 낸다. 한계를 정직하게 측정한 결과도 `FAIL`로 나온다 | §8-0에 절 추가, 성공 기준을 `verdict`와 분리 |
| 4 | (1차에 없음) | **관찰 A 누락.** WireGuard 터널은 보통 기본 경로를 통째로 가져간다. 그러면 정책과 무관하게 모든 앱이 VPN으로 간다. **2026-08-10의 "비선택 Chrome 유입"이 이 경우였을 가능성이 높고, 그렇다면 `R3-DEC-04` 근거로 쓰면 안 된다.** 1차 문서는 이 갈림길 없이 그것을 "한계를 가리키는 핵심 증거"로 단정했다 | §8-1 판별표 신설, §4-2에 4단계 추가 |

**표본 재확인 — 뒤집히지 않은 것**

| 1차 주장 | 2차 직접 재유도 | 결과 |
|---|---|---|
| `OwnerHarnessRunner.cs:190`이 32건 전건 `PASS`를 요구 | 코드 직접 읽음 — `cases.Where(번호<=32).All(Outcome == PASS)` | **확인** |
| IPv6 사례가 정확히 16건 | 기획서 226~233행을 프로그램으로 파싱해 IPv6 행의 ID를 추출 → `M-009`~`M-016` · `M-025`~`M-032` = **16건** | **확인** |
| AC 12개 줄 번호 · 매트릭스 219~241행 · 판정표 80~115행 | 재조회 | **확인** |
| 보호 경로 게이트 차단 | 세 번째 재현(20:55) | **확인** |
| 설정 파일 내용 미유출 | 문서 전문을 11개 패턴으로 검색 | **확인 — 실제 설정값 0건** |

**적대 점검에서 깨끗하게 나온 것 (막지 않음)**

- `VpnRouterVs.sln`은 `dotnet build`로 짓는다(`:1347`). **MSBuild가 PATH에 없어도 막히지 않는다** — 1차가 걱정할 뻔한 자리인데 실제로는 문제없다.
- 선택 앱 `msedge.exe`·통제 앱 `chrome.exe` 존재. `RejectReparseChain`(`WfpInputValidator.cs:54-63`)을 재현해 조상 재분석 지점 **0건** 확인.
- **재부팅은 확실한 최후 수단이다.** `NativeSessionBuffer.cs:38`의 `Flags = 1`이 SDK 헤더 `fwpmtypes.h:125` `FWPM_SESSION_FLAG_DYNAMIC (0x00000001)`와 일치한다. 동적 세션 개체는 영구 개체가 아니라 재부팅으로 반드시 사라진다.
- `case-matrix.json`은 판정 어휘를 담고 있지 않아 고칠 필요가 없다. 오히려 관찰기가 기대값을 읽을 자리로 쓸 수 있다.

**그 밖의 수정**: 범위를 안 2로 좁히고 알려진 실패를 사례 ID 단위로 갈랐다(§8-1). IPv6·터널 판정 규칙을 실행 중 판단이 갈리지 않게 표로 고정했다(§4-2). 열린 질문을 0건으로 닫았다(§7). 미룬 항목을 백로그 등재 형태로 §9-1에 적었다. §3-1 세 건이 안 2에서도 닫히는지 재확인했다.

---

## **최종 판정: 조건부 GO**

**아래 3건이 끝나면 바로 `/pipeline` 시작 가능하다.** 셋 다 파이프라인 안에서 처리할 수 있고, 사용자 결정을 기다리는 항목은 없다(열린 질문 0건).

| # | 조건 | 왜 시작 전인가 | 근거 |
|---|---|---|---|
| 1 | `macos/AppRoutingSpike/Docs/spike-decision.md` 커밋 | 이것이 남아 있으면 자동 게이트가 **빌드 한 줄 돌기 전에** 막는다. 세 번 실측 재현 | §0-2 선행-1 |
| 2 | `restore-network-dev.ps1`에 WFP 소유 정책·spool 정리 추가 | 없으면 OWNER-04(Ctrl+C·강제 종료 뒤 0건 확인)를 안전하게 반복할 수 없다. 재부팅은 세션을 끊을 뿐 "0건 확인"을 대신하지 못한다 | §0-2 선행-2 |
| 3 | 시험용 WireGuard 터널 생존 확인 | 서버가 죽어 있으면 다음 홉이 없어 `M-001`~`M-032`의 선택 앱 행이 성립하지 않는다. 확인 결과에 따라 IPv6 16사례의 처리가 갈린다 | §4-2 2·3단계 |

**`NO-GO`가 아닌 이유**: 실기를 막을 수 있는 환경 요인(연결 정책 API · BFE · 관리자 권한 · C++ 툴체인 · 시험 앱 · 빌드 도구)을 전부 실측했고 **막는 것이 하나도 없다**(§0-2 선행-4). 남은 3건은 전부 이쪽에서 처리 가능한 작업이다.

**`GO`가 아닌 이유**: 1번은 지금 이 순간 게이트를 차단하고 있고, 2번은 없으면 이번 차수의 핵심 산출물(OWNER-04)을 닫을 수 없다.

---

## 11. 파이프라인 시작

- 사용자가 직접 실행한다. 이 문서가 파이프라인으로 자동 진입하지 않는다.
- **최종 판정: 조건부 GO** — §10의 조건 3건을 끝내면 시작한다. **사용자 판단 대기 항목은 없다(열린 질문 0건).**
- 권장 PM 입력 시드:
  1. 요구사항 원문 + **§0-1 확정 사항 8건** + **§0-2 선행 조치 1~3**
  2. **§2-8 관찰 수단 대조표** — "수단 없음" 7개 + "부분" 2개가 R4의 첫 작업 항목이다
  3. **§8-0** — R4의 성공 기준을 JSON `verdict`로 정의하지 않는다는 것을 PM 단계에서 먼저 못 박는다. `PARTIAL`도 `FAIL`도 정상 결과다
  4. **§3-2의 24곳 표** — 설계 단계가 이 목록을 **그대로** 작업 목록으로 받아야 한 곳도 안 빠진다. 함정 4개(버전 상수·산술 불변식·미지 필드 거부·암묵 흡수)를 특히 강조
  5. **§4-2 판정 규칙표**와 **§8-1 관찰 A·B·C 판별표** — 실행 중에 판단이 갈리지 않게 미리 고정된 규칙이다. 실행 담당이 이 두 표를 손에 들고 시작해야 한다
  6. **§9-1 이월 항목 6건** — 회고·STEP 18이 백로그로 옮겨 적을 형태로 이미 적혀 있다
- **§3-1을 PM 입력에 그대로 붙여 넣을 것** — PM은 그 표를 자기 선정 결과로 채택해 체크리스트를 그만큼 비운다.
