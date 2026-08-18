# Windows WFP 실기 절차 v2 — 사전 감사 결과와 고친 절차 (2026-08-17)

> 앞 문서: `docs/windows-wfp-live-run-handoff-2026-08-17.md` (중단 기록 + 절차 v1)
> 이 문서가 **절차의 최신본**이다. v1 의 §4 절차는 이 문서로 대체한다. v1 은 중단 기록으로만 읽는다.
> 성격: 실기 전 사전 감사 + 관찰 도구 결함 6건 수정 + 고친 절차. **실기는 아직 안 했다.**
>
> **2026-08-18 갱신 (R5 도구 굳히기)** — 도구가 바뀌는 라운드라 절차도 함께 고쳤다. 고친 자리는 §3-0 · §3 · §4 단계 1·2·3·5·8 · §5 다.
> 이 갱신은 **도구가 아직 안 바뀐 자리를 바뀐 것처럼 적지 않는다.** 갈리는 자리마다 §3-0 의 확인 블록을 먼저 돌리고 (가)·(나) 중 하나를 고른다.

## 0. 한 줄 요약

실기를 시작하기 전에 절차와 도구를 먼저 검사했다. **관찰 도구에 결함 6건이 있었고, 그대로 실기했으면 32사례가 전부 `INCONCLUSIVE` 로 끝났을 것이다.** 6건을 고쳤고 예행 5회 연속으로 `observedPath: BASELINE` · `packetCount 225~261` 을 실측했다. 절차 문서에서도 막힘 9건을 찾아 아래 §4 로 고쳐 적었다.

**아직 못 하는 것: split-tunnel 설정 파일(`r4split.conf`)이 없다.** 사용자가 만들기로 했다(v1 §2). 그 파일이 생기면 §4 를 그대로 돌리면 된다.

---

## 1. 관찰 도구 결함 6건 — 전부 실측으로 찾고 고쳤다

> **[2026-08-18] 줄 번호 주의** — 아래 §1·§2 표의 `파일:줄번호` 는 **2026-08-17 시점 값**이다.
> R5 가 순수 함수 5개를 `WfpObservationText.psm1` 로 옮기고 네 스크립트를 고쳤으므로 **그 줄 번호는 이미 밀렸다.**
> 다시 찾을 때는 **줄 번호가 아니라 함수·변수 이름으로 찾는다.** 표의 내용(무엇이 왜 고장 났나)은 그대로 유효하다.

측정 도구가 고장 난 채로 재면 안 잰 것만 못하다. 그래서 터널도 WFP 정책도 없이 관찰 사슬만 돌려 봤다(`-VpnInterfaceIndex` 에 끊긴 이더넷 17, `-BaselineInterfaceIndex` 에 Wi-Fi 8 을 넣으면 기대값은 `BASELINE`).

| # | 결함 | 어디 | 어떻게 드러났나 | 고친 것 |
|---|---|---|---|---|
| D-1 | `pktmon start --capture --file-size 16` 이 꾸러미를 **하나도 안 남긴다.** pktmon 은 CPU 하나마다 16MB ETW 버퍼를 잡는데, 최대 파일 크기가 버퍼 전체보다 작으면 순환 기록이 통째로 덮어쓴다 | `Get-WfpSpikeInterface.ps1:428` | 같은 거르개·같은 연결로 값만 바꿔 반복: `16`→0줄 · `32`→346줄 · `64`→1009줄 · `512`→1149줄(완전). 손으로 부른 pktmon 도 같았다 | `--file-size 512` 로 바꿨다. 파일을 미리 잡지 않으므로 실제 크기는 담긴 만큼이다(실측 46KB) |
| D-2 | 실행 폴더에 남긴 시각을 다시 읽을 때 `ConvertFrom-Json` 이 ISO 글자를 `[datetime]` 으로 바꾸고, `[string]` 이 **현지시각·초 단위로 잘라** 놓는다. 그 값을 `-PolicyAppliedAtUtc` 와 견주니 같은 초에 걸린 두 시각이 뒤집혔다 | `Get-WfpSpikeInterface.ps1:461-462`·`:479`·`:484` | 정책과 잡기 시작 간격 0.2초 → `CAPTURE_BEFORE_POLICY`, 10초 → 정상. 기록된 값도 `"08/17/2026 15:35:26"` 로 UTC 가 아니었다 | `ConvertTo-RoundTripUtcText` 를 넣어 UTC 왕복 서식으로 되돌린다. 증거 칸도 다시 UTC 가 됐다 |
| D-3 | 흐름 확인이 `Get-NetTCPConnection -OwningProcess <우리가 띄운 번호>` 였다. 브라우저는 이미 떠 있으면 실행기가 일을 넘기고 죽고, 연결 주인은 network service 자식이다 | `New-WfpSpikeFlow.ps1:259-265` | `FLOW_TIMEOUT` 이 1.3초 만에 났다. 같은 순간 pktmon 은 그 흐름을 1,449줄로 정상 포착. 실측 PID: 실행기 22384 · 브라우저 뿌리 18700 · 연결 주인 18908 | 실행기 종료로 빠져나오지 않는다. 대상 주소·포트로 가는 연결 가운데 **앱을 띄우기 전에 없던 로컬 포트**를 새 연결로 본다 |
| D-4 | 꾸러미를 세는 정규식이 `Component` 라는 **영어 이름표**만 찾는다. 이 PC 의 pktmon 은 `구성 요소 80` 으로 쓴다 | `Get-WfpSpikeInterface.ps1:574` | 잡기가 정상이고 ETL 에 꾸러미가 1,423줄 있는데 스크립트는 `packetCount:0` 을 냈다 | 번역되지 않는 `PktGroupId` 로 꾸러미 줄을 가리고, 이름표가 영어면 그대로 쓰되 아니면 쉼표 6번째 칸에서 뽑는다 |
| D-5 | `pktmon list --json` 은 **중첩 구조**인데(`[{Group, Components:[{Id, Properties:[{Name:"ifIndex"}]}]}]`) 맨 바깥에서 `Id` 와 `ifIndex` 를 직접 찾고 있었다. 지도가 늘 빈 채로 끝난다 | `Get-WfpSpikeInterface.ps1:548-568` | 꾸러미를 세도 `COMPONENT_INDEX_UNREADABLE` 로 닫힐 자리였다 | `Components` 를 타고 들어가고 `Properties` 안에서 `ifIndex` 를 찾는다. 평평한 판도 함께 받는다. 실측 50개 항목이 지도에 들어온다(구성 요소 12·124 → ifIndex 8) |
| D-6 | 확인기가 **짧게 살다 죽는 연결을 놓친다.** `Get-NetTCPConnection` 한 번이 165~233ms 라 250ms 쉬며 물으면 표본 간격이 0.4초를 넘는다 | `New-WfpSpikeFlow.ps1` 확인 고리 | 3회 중 2회 `FLOW_TIMEOUT`. 그런데 같은 회차 pktmon 기록에 SYN 이 16개 있었고 로컬 포트도 회차마다 전부 달랐다 — 재사용이 아니라 놓친 것 | 3.3ms 로 끝나는 `IPGlobalProperties.GetActiveTcpConnections()` 로 25ms 마다 본다 |

### 고친 뒤 예행 (5회 연속)

| 회차 | 걸린 시간 | 흐름 | 새 연결 로컬 포트 | 판정 | 인터페이스 | 꾸러미 |
|---|---|---|---|---|---|---|
| 1 | 2.6초 | `OK/NONE` | 50410 | `BASELINE` | 8 | 252 |
| 2 | 1.5초 | `OK/NONE` | 55696 | `BASELINE` | 8 | 225 |
| 3 | 1.6초 | `OK/NONE` | 52732 (주인 18908) | `BASELINE` | 8 | 241 |
| 4 | 1.5초 | `OK/NONE` | 56016 (주인 18908) | `BASELINE` | 8 | 261 |
| 5 | 1.6초 | `OK/NONE` | 62062 (주인 18908) | `BASELINE` | 8 | 252 |

사례당 1.5~2.6초다. 사례 상한 60초(`test-wfp-app-routing-spike.ps1:1364`)와 측정 예산 20분(`:1263-1266`) 안에 32사례가 넉넉히 들어간다. 매 회 끝난 뒤 `pktmon filter list` 가 "없음"이었다 — 되돌리기도 정상이다.

### 회귀 확인

| 확인 | 결과 |
|---|---|
| 마른 실행 `test-wfp-app-routing-spike.ps1` (인자 없음) | `mode:DRY_RUN` · `verdict:PARTIAL` · `beforeAfterFingerprint:MATCH` · exit 0 |
| `dotnet run --project windows\VpnRouter.Tests` (Release) | 40여 건 **전부 PASS** · exit 0 |
| 하네스 이진 최신 여부 | Release exe 08-15 01:58 > 최신 소스 08-15 00:51 — **다시 빌드 불필요** |

### 고친 파일

- `scripts/windows/wfp-observation/Get-WfpSpikeInterface.ps1` — D-1·D-2·D-4·D-5
- `scripts/windows/wfp-observation/New-WfpSpikeFlow.ps1` — D-3·D-6

~~두 파일 모두 아직 **커밋하지 않았다.** 작업 나무에만 있다.~~
**[2026-08-18 정정]** 이 줄은 낡았다. 두 파일은 커밋 `c6888b8` (`feat(windows): add WFP observation tooling and verdict contract`) 에 관찰 도구 5종과 함께 들어갔고, 이 문서는 커밋 `25ea153` 에 들어갔다. 확인 명령: `git -C 'C:\dev\vpn_router' log --oneline -- scripts/windows/wfp-observation/Get-WfpSpikeInterface.ps1`

---

## 2. 절차 문서(v1)에서 나온 막힘 9건

v1 §4 를 실제 코드와 한 줄씩 대조해 나온 것이다. 전부 근거 줄을 확인했다.

| # | v1 이 시킨 것 | 실제 코드 | 결과 |
|---|---|---|---|
| B-1 | §6 "인터넷이 끊긴다 → 단계 8 Teardown 을 바로 돌린다" | `Use-WfpSpikeTunnel.ps1:343-346` 이 `ownerSessionCount`·`harnessProcessCount` 가 **둘 다 0** 이어야 통과시키고, `/uninstalltunnelservice` 는 `:350` 으로 그 뒤에 있다 | 단계 7 진행 중에는 하네스가 살아 있어 **반드시 `POLICY_STILL_PRESENT` 로 막힌다.** 끊김이 안 풀린다 |
| B-2 | §6 비상 복구가 `/uninstalltunnelservice` 를 먼저 부른다 | 정책이 터널 LUID 를 다음 홉으로 쥐고 있다(`Use-WfpSpikeTunnel.ps1:11-15`) | 순서가 뒤집혀 죽은 LUID 를 가리키는 정책이 남는다. `tunnel-installed.json` 도 남아 "정리 미완" 표식이 영구히 남는다 |
| B-3·B-8 | 단계 1 `$run = ...\VpnRouter\r4-live-plan-a` | `restore-network-dev.ps1:61` 이 훑는 뿌리는 `...\VpnRouter\wfp-spike-runs` 한 곳으로 못 박혀 있고 `:105`·`:140`·`:161` 이 전부 그 아래만 본다 | 복구 도구가 이번 차수의 남은 경로·pktmon 기록·터널 표식을 **구조적으로 못 본다** |
| B-4 | 단계 5 에 "쪼개지 말라"는 경고가 없다 | `-Mode Start` 는 일부러 남긴다 — `:449` `keepCaptureRunning=$true`, 그리고 `:396` 의 `pktmon filter remove` 는 **이 PC 의 거르개를 전부 지운다** | Start 와 Stop 사이에 끊으면 잡기가 계속 돌고 거르개가 지워진 채로 남는다 |
| B-5 | 단계 7 을 아무 폴더에서나 돌린다 | `test-wfp-app-routing-spike.ps1:871`·`:1783`·`:1874` 가 `git` 을 `-C` 없이 부르고 `:1794`·`:1797`·`:1800` 이 `.\windows\...` 상대 경로로 `dotnet` 을 부른다 | 승격 셸의 기본 폴더(`C:\WINDOWS\system32`)에서 돌리면 게이트가 터진다 — **터널을 이미 올린 뒤에** |
| B-6 | 셸 종류를 안 적었다 | `:22` 의 `[Convert]::ToHexString` 이 최상위, `try` 바깥이다(.NET 5+ 전용). `:149`·`:1604`·`:1572` 도 마찬가지 | Windows PowerShell 5.1 로 돌리면 결과 JSON 을 **한 줄도 못 내고** 죽는다 |
| B-7 | §3 확인표의 `git diff --name-only -- macos ...` | 진짜 게이트는 `:1783` 의 `git diff --name-only HEAD -- macos ...` | `HEAD` 를 빼면 스테이징된 변경을 못 본다. 확인이 통과해도 게이트는 막는다 |
| B-9 | 단계 8 "`POLICY_STILL_PRESENT` 면 `restore-network-dev.ps1` 을 돌린다" | 그 스크립트는 `:169` 의 `Stop-Service` 뿐이고 `/uninstalltunnelservice` 를 부르는 줄이 0건이다 | restore 뒤에도 터널 서비스가 등록된 채로 남는다. 절차대로 끝내면 잔여물이 남는다 |

### 그 밖에 고쳐 넣은 것

- **`-Mode Stop` 은 사례마다 한 번만.** `capture-state.json` 을 지우지 않으므로(`:399`·`:493`·`:506`) 두 번째 Stop 이 그대로 진행되고, 그때 되돌릴 목록은 이미 지워져 있어(`:293-296`) `pktmon filter remove` 만 돌고 **되돌리지 못한다**(`:250-254`).
- **단계 5 는 `observedPath` 를 화면에 내지 않는다.** 아무 파일에도 안 적힌다. 값을 받아 찍는 줄이 필요하다.
- **`observedPath` 는 네 값이다.** v1 표에 `OTHER` 가 빠졌다(`:589-599`). `observationAPath` 에 `OTHER` 를 적으면 `:1256` 이 걸러 주지 않아 안 고른 앱 8사례가 근거 없이 채워진다.
- **`TUNNEL_NOT_REACHABLE` 은 "서버가 죽었다"가 아니다.** ICMP 를 **한 번** 보내고 예외면 무조건 실패다(`Use-WfpSpikeTunnel.ps1:120-131`). `-ReachabilityTimeoutMs` 가 있는데 v1 이 안 썼다.
- **단계 3 의 ping 은 터널을 지났다는 증거가 아니다.** 원본 주소·인터페이스를 묶지 않는다(`:124-130`). 경로가 안 심겼으면 기준 랜카드로 나가고도 `OK` 가 나온다. 지우기 **전에** 경로가 터널로 향하는지 봐야 한다.
- **단계 7 이 실패하면 승격 셸이 닫힐 수 있다**(`:2062-2064` `SetShouldExit`). 값을 미리 파일로 남겨야 이어갈 수 있다.
- **증거가 쌓이는 곳은 `$run` 이 아니다.** `%LOCALAPPDATA%\VpnRouter\wfp-spike-runs\<yyyyMMdd-HHmmss>Z-<nonce8자>` 다(`:27-28`).
- **`$svc` 와 conf 파일 이름이 어긋나면 조용히 어긋난 채로 진행한다.** 설치는 `$ConfigPath` 로 하고 어댑터는 `$TunnelServiceName` 으로 찾는다(`:201` vs `:222`).
- **`$baseIdx` 를 손으로 적은 값과 Prepare 가 계산한 값이 다를 수 있다**(`:190-197`).
- 단계 3 실패 경로가 **아무것도 안 깔린 상태에서도** Teardown 을 부른다 → 없는 서비스에 `/uninstalltunnelservice` 를 걸어 `TUNNEL_STOP_FAILED` 가 뜨고 회복 지문도 안 남는다.
- 단계 3 은 "몇 초 안에 원상복구"가 아니다. 최악 **90초 남짓**이다(Prepare 어댑터 대기 30초 + `netsh wfp` 상태 뜨기 + Teardown 어댑터 대기 30초).

---

## 3-0. 먼저 돌린다 — R5 도구 굳히기가 이 저장소에 들어왔나

이 문서는 도구가 바뀌는 도중에 고쳤다. 아래 네 칸이 **이 문서의 갈림길을 정한다.** 실기를 시작하기 전에 한 번 돌리고 값을 적어 둔다.

```powershell
$repo = 'C:\dev\vpn_router'
[pscustomobject]@{
  'A-1 사람이 고르는 정리 갈래'  = ((Select-String -LiteralPath "$repo\scripts\windows\wfp-observation\Use-WfpSpikeTunnel.ps1" -Pattern 'StopHarnessFirst' -Quiet) -eq $true)
  'A-2 Stop 재실행 안전'         = ((Select-String -LiteralPath "$repo\scripts\windows\wfp-observation\Get-WfpSpikeInterface.ps1" -Pattern 'pktmonUndoSucceeded' -Quiet) -eq $true)
  'A-3 되돌리기가 훑는 뿌리 2곳' = ((Select-String -LiteralPath "$repo\scripts\windows\restore-network-dev.ps1" -Pattern 'restoreRunRoots' -Quiet) -eq $true)
  'A-4 git·dotnet 폴더 독립'     = (@(Select-String -LiteralPath "$repo\scripts\windows\test-wfp-app-routing-spike.ps1" -Pattern '(?<!-C \$repoRoot )\bgit (ls-files|diff|rev-parse)').Count -eq 0)
} | Format-List
```

| 칸 | `True` 면 | `False` 면 |
|---|---|---|
| **A-1** | §5 비상 복구 ① 의 **(가)** 를 쓴다 | §5 비상 복구 ① 의 **(나)** 를 쓴다 |
| **A-2** | 단계 5 의 두 번째 Stop 이 되돌아간다 — §4 단계 5 의 (가) | `-Mode Stop` 을 사례마다 **한 번만** 돌린다 — §4 단계 5 의 (나) |
| **A-3** | 손 예행 폴더를 `wfp-spike-manual-runs` 아래에 만든다 — §4 단계 1 의 (가) | 손 예행 폴더를 `wfp-spike-runs` 아래에 만든다 — §4 단계 1 의 (나) |
| **A-4** | 작업 폴더가 어디든 단계 7 이 저장소를 본다 | 작업 폴더를 **반드시** `C:\dev\vpn_router` 로 둔다 |

> **새 규약 (R5)**: **손으로 도는 예행은 `%LOCALAPPDATA%\VpnRouter\wfp-spike-manual-runs\<이름>` 아래에 만든다.**
> 자동 실행이 스스로 만드는 자리(`wfp-spike-runs\<날짜>Z-<8자>`)와 섞지 않는다. 되돌리기 도구가 두 뿌리를 함께 훑게 하려는 것이고,
> 차수 이름(`r4-live-plan-a` 같은 것)을 도구 안에 적지 않으려는 것이다. **A-3 이 `False` 인 동안에는 이 규약을 쓰면 안 된다** — 되돌리기 도구가 그 뿌리를 아직 못 본다.

2026-08-18 **04:13** 기준 이 저장소 실측: **A-1 `True` · A-2 `True` · A-3 `True` · A-4 `True`** (네 자리 다 작업 나무에 있고 **아직 커밋 전이다**).
**이 값은 그대로 믿지 않는다.** 되돌리거나 다시 고치면 바뀌므로 **실기를 여는 그 자리에서 위 블록을 다시 돌린다.**

> **회귀 시험 쪽 (2026-08-18 04:20 실측)** — **이 문서는 안 들어온 것을 들어온 것처럼 적지 않는다.**
>
> | 파일 | 있나 | 확인 명령 |
> |---|---|---|
> | `scripts\windows\wfp-observation-tests\Test-WfpObservationFixture.ps1` (고정값 회귀 시험) | **있음** (작업 나무 · 커밋 전) | `Test-Path` |
> | `.github\workflows\powershell-tests.yml` (push·PR 워크플로) | **있음** (작업 나무 · 커밋 전 · **아직 한 번도 안 돌았다**) | `Test-Path` |
>
> ⚠ 워크플로는 **밀어야 돈다.** 파일이 저장소에 있는 것과 GitHub 에서 실제로 돈 기록이 있는 것은 다르다. 이 차수에는 미는 일이 범위 밖이라 **실행 기록이 아직 0건**이다.
>
> 실기 진입 조건 2번(「회귀 시험이 돌고 통과」)은 **시험을 실제로 돌려 통과를 본 기록**으로 답한다. 파일이 있는 것과 통과한 것은 다르다.
> 시험은 관리자 권한도 랜카드도 pktmon 도 필요 없으므로 **아무 때나 돌려도 이 기계 상태를 안 바꾼다.** 돌리는 명령:
>
> ```powershell
> & 'C:\dev\vpn_router\scripts\windows\wfp-observation-tests\Test-WfpObservationFixture.ps1'
> ```
>
> 2026-08-18 04:15 에 이 문서를 고치면서 **5회 돌려 봤다** — 매번 `고정값 시험 21/21 통과.` · 종료 코드 **0** · 한 번에 **0.14초** ·
> `git status` 가 앞뒤로 **똑같았다**(시험이 저장소에 아무것도 안 쓴다). **그래도 실기 전에는 그 자리에서 다시 돌린다.**

---

## 3. 실행 전 전제 (단계 0)

| 확인 | 명령 | 있어야 할 값 |
|---|---|---|
| **셸** | `$PSVersionTable.PSVersion.Major` | **`7` 이상.** 관리자 권한 `pwsh` 로 연다. "Windows PowerShell(관리자)"는 안 된다 |
| 관리자 승격 | `([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole('Administrators')` | `True` |
| **작업 폴더** | `Set-Location 'C:\dev\vpn_router'` 뒤 `$PWD.Path` | §3-0 의 **A-4 가 `False` 면 반드시 `C:\dev\vpn_router`** (하위 폴더도 안 된다). **A-4 가 `True` 면 어느 폴더에서 돌려도 단계 7 이 저장소를 본다.** 어느 쪽이든 이 줄을 그대로 두면 손해가 없으므로 **습관으로는 계속 이 폴더에 둔다** |
| BFE 서비스 | `(Get-Service BFE).Status` | `Running` |
| 보호 경로 diff | `git -C 'C:\dev\vpn_router' diff --name-only HEAD -- macos docs/v0.1.0-release-plan.md artifacts` | **빈 출력.** `-C` 를 빼면 **하위 폴더에서 통째로 눈이 먼다** — 아래 상자를 본다 |
| 기준 인터페이스 | `Get-NetAdapter \| Where-Object Status -eq 'Up'` | **한 개만.** 그 index 가 `$baseIdx` |
| 설정 파일 | `Test-Path $conf` | `True` (v1 §2 대로 사용자가 만든다) |

2026-08-17 15:50 기준 실측: `pwsh 7.6.5` · 관리자 `True` · BFE `Running` · 보호 경로 diff 빈 출력 · `Up` 인 어댑터는 **Wi-Fi 2 (index 8) 하나뿐** · WireGuard 어댑터 0건 · 터널 서비스 0건 · `ownedPolicyCount:0`(세 신호 `AGREE`) · pktmon 거르개 0건.

> 기본 경로표에 ifIndex 17(이더넷)이 아직 한 줄 남아 있지만 그 어댑터는 `Disconnected` 이고, `Find-NetRoute 1.1.1.1` 은 **8** 을 낸다. 실제 나가는 길은 하나다.

### ★ 보호 경로 관문은 폴더를 바꾸면 눈이 먼다 (2026-08-18 실측)

`git` 의 경로 무늬(`-- macos ...`)는 **지금 서 있는 폴더**를 기준으로 읽는다. 그래서 같은 명령을 하위 폴더에서 돌리면 아무것도 못 본다.
작업 나무를 한 글자도 안 건드리고 지난 커밋 하나로 시연한 결과다.

```powershell
# 같은 커밋 범위 · 같은 명령 · 폴더만 다르다
cd C:\dev\vpn_router          ; @(git diff --name-only c685f1c~1 c685f1c -- macos docs/v0.1.0-release-plan.md artifacts).Count   # -> 49
cd C:\dev\vpn_router\scripts\windows ; @(git diff --name-only c685f1c~1 c685f1c -- macos docs/v0.1.0-release-plan.md artifacts).Count   # -> 0
```

| 어디서 돌렸나 | `git ls-files -- macos` | 위 시연의 보호 경로 diff |
|---|---|---|
| `C:\dev\vpn_router` (저장소 뿌리) | **368** | **49** |
| `C:\dev\vpn_router\scripts` | 2 | — |
| `C:\dev\vpn_router\scripts\windows` | **0** | **0** |

- 즉 하위 폴더에서 돌린 "빈 출력"은 **"변경이 없다"가 아니라 "안 봤다"** 이다. 관문이 있으나 마나가 된다.
- 손으로 치는 확인은 **`git -C 'C:\dev\vpn_router'` 를 붙인다.** 붙이면 어느 폴더에서도 같은 답이 나온다.
- 단계 7 안에서 도는 같은 관문은 A-4 가 고치는 자리다. §3-0 의 A-4 가 `False` 면 **그 관문은 아직 이 성질을 그대로 갖고 있다.**

---

## 4. 고친 절차 (복사해 붙이는 순서)

### 단계 1 — 변수와 사전 검사

> **먼저 §3-0 을 돌린다.** 아래 `$run` 한 줄이 §3-0 의 **A-3** 값으로 갈린다.

```powershell
# [R5] A-4 가 True 면 단계 7 이 폴더에 안 매인다. 그래도 이 줄은 그대로 둔다 — 손으로 치는 git 명령이 아직 폴더를 본다
Set-Location 'C:\dev\vpn_router'

$obs     = 'C:\dev\vpn_router\scripts\windows\wfp-observation'

# [R5] 손으로 도는 자리는 새 규약대로 wfp-spike-manual-runs 아래에 만든다 (§3-0 새 규약)
#      (가) A-3 이 True — 되돌리기 도구가 이 뿌리를 훑는다
$run     = Join-Path $env:LOCALAPPDATA 'VpnRouter\wfp-spike-manual-runs\r4-live-plan-a'
#      (나) A-3 이 False — 되돌리기 도구가 아직 manual-runs 를 못 본다. 아래 줄로 바꿔 쓴다
# $run   = Join-Path $env:LOCALAPPDATA 'VpnRouter\wfp-spike-runs\r4-live-plan-a'

$conf    = 'C:\Users\NetMD\Downloads\r4split.conf'
$svc     = 'r4split'
$target  = [ipaddress]'1.1.1.1'
$baseIdx = 8
New-Item -ItemType Directory -Force -Path $run | Out-Null

# [수정] 서비스 이름과 설정 파일 이름이 어긋나면 조용히 어긋난 채로 진행한다
if ($svc -ne [IO.Path]::GetFileNameWithoutExtension($conf)) { throw "svc($svc) 와 conf 이름이 다르다 — 멈춘다" }
if (-not (Test-Path -LiteralPath $conf)) { throw "설정 파일이 없다: $conf" }   # 있는지만 본다. 열지 않는다
if ($PSVersionTable.PSVersion.Major -lt 7) { throw "pwsh 7 이상에서 돌려야 한다" }
if (@(Get-NetAdapter | Where-Object Status -eq 'Up').Count -ne 1) { throw "Up 인 어댑터가 하나가 아니다 — 하나만 남긴다" }
# [R5] -C 를 붙인다. 없으면 하위 폴더에서 통째로 눈이 먼다 (§3 상자 · 실측 49 대 0)
if (@(git -C 'C:\dev\vpn_router' diff --name-only HEAD -- macos docs/v0.1.0-release-plan.md artifacts).Count -ne 0) { throw "보호 경로에 변경이 있다" }
```

- `$run` 을 (가)로 골랐으면 **단계 8 뒤 잔여물 확인도 그 뿌리에서** 본다. 되돌리기 도구가 못 훑는 뿌리에 증거를 쌓으면 뒤에 아무도 못 찾는다.
- 설정 파일은 **있는지만 본다.** 이 절차도 도구도 그 파일을 열지 않고, 그 안의 값을 어느 문서에도 적지 않는다.

### 단계 2 — 기준선 (터널 올리기 **전**)

```powershell
& "$obs\Get-WfpThirdPartyState.ps1" -Mode Capture -RunDirectory $run -Label 'baseline'
& "$obs\Get-WfpOwnedPolicyState.ps1" -RunDirectory $run -Label 'baseline'
@{
  measuredAtUtc = [DateTimeOffset]::UtcNow.ToString('O')
  adapters      = @(Get-NetAdapter | Select-Object Name,InterfaceIndex,Status)
  ipv4Default   = @(Get-NetRoute -DestinationPrefix '0.0.0.0/0' -EA SilentlyContinue | Select-Object InterfaceIndex,NextHop,RouteMetric)
  ipv6Default   = @(Get-NetRoute -DestinationPrefix '::/0' -EA SilentlyContinue | Select-Object InterfaceIndex,NextHop)
  hostRoutes32  = @(Get-NetRoute -AddressFamily IPv4 -EA SilentlyContinue | Where-Object { $_.DestinationPrefix -like '*/32' } | Select-Object DestinationPrefix,InterfaceIndex)
  dns           = @(Get-DnsClientServerAddress | Where-Object { $_.ServerAddresses.Count -gt 0 } | Select-Object InterfaceIndex,AddressFamily,ServerAddresses)
} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath "$run\baseline-network.json" -Encoding utf8
```

`ownedPolicyCount` 가 **0 이 아니면 여기서 멈춘다.**

### ★ B-7a 판정 — 단계 2·3 을 읽는 방법이 바뀐다 (2026-08-18 실측)

**「답 없는 상대에게 보낸 SYN 이 흐름 관문을 지납니다. 다만 이것은 기준 인터페이스로 나가는 흐름에 대한 답입니다. 터널에 갇힌 흐름은 B-7b 가 따로 답해야 합니다.」**

| 무엇 | 값 |
|---|---|
| 결과 원본 (저장소 **밖**) | `%LOCALAPPDATA%\VpnRouter\wfp-spike-manual-runs\b7a-20260818\b7a-flow-gate-probe.json` · 2026-08-17T18:50:25Z |
| `status` / `failureReason` | **`OK`** / `NONE` |
| `newConnectionCreated` / `newConnectionLocalPort` | **`true`** / `59587` |
| `hostRouteInstalled` | **`false`** — 경로표를 안 건드렸다 (`-InstallHostRoute` 를 안 줬다) |
| 걸린 시간 | 0.3초 |

- 시험용 주소는 **인자로만 넘겼다.** 이 문서에도 저장소 어느 파일에도 적지 않는다.
- **판정 문장의 정본은 이번 라운드 dev-backend 보고서(W-1)다.** 위는 그 실측 원본에서 옮긴 네 칸이다.
- **이 판정이 바꾸는 것**: 흐름 관문 하나만 보면 **살아 있는 서버가 없어도 통과한다.** 그래서 단계 3 의 `TUNNEL_NOT_REACHABLE` 은 "측정이 불가능하다"는 뜻이 아니다.
- **이 판정이 안 바꾸는 것**: 단계 3 의 "세 번 다 실패면 끝낸다"는 그대로다. 위는 **기준 인터페이스**로 나가는 흐름을 잰 것이고, 터널 안에서 같은 일이 되는지는 **아직 아무도 안 쟀다**(B-7b 몫). 서버 없이 실기를 여는 근거로 쓰지 않는다.

### 단계 3 — 터널 올리고 **곧바로** 확인 (한 덩어리로 붙여 넣는다)

> **쪼개지 않는다.** 2026-08-17 의 31분 끊김이 Prepare 와 Verify 사이가 벌어져 생겼다.
> 실패해도 자동으로 내려가지만 **최악 90초쯤** 걸린다(Prepare 어댑터 대기 30초 · `netsh wfp` 상태 뜨기 · Teardown 어댑터 대기 30초). 그 안에 인터넷이 급하면 §6 비상 복구를 쓴다.

```powershell
$tunIdx = $null; $ipv6Verdict = 'INCONCLUSIVE'
$p = & "$obs\Use-WfpSpikeTunnel.ps1" -Mode Prepare -ConfigPath $conf -RunDirectory $run -TunnelServiceName $svc
$p
if (($p | ConvertFrom-Json).status -eq 'OK') {
    # [수정] ping 한 번으로 끝내지 않는다. 한 번 놓친 꾸러미로 실기를 접지 않기 위함이다
    foreach ($i in 1..3) {
        $v = & "$obs\Use-WfpSpikeTunnel.ps1" -Mode Verify -RunDirectory $run -TunnelServiceName $svc `
                -ReachabilityAddress $target -ReachabilityTimeoutMs 8000
        $v
        $vo = $v | ConvertFrom-Json
        if ($vo.status -eq 'OK') { $tunIdx = [int]$vo.tunnelInterfaceIndex; $ipv6Verdict = [string]$vo.ipv6Verdict; break }
        Start-Sleep -Seconds 3
    }
}
if ($null -eq $tunIdx) {
    # [수정] 아무것도 안 깔렸으면 Teardown 을 부르지 않는다 (없는 서비스에 걸면 TUNNEL_STOP_FAILED 가 뜬다)
    if (Test-Path -LiteralPath "$run\tunnel-installed.json") {
        Write-Warning '터널 확인 실패 — 즉시 내린다'
        & "$obs\Use-WfpSpikeTunnel.ps1" -Mode Teardown -RunDirectory $run -TunnelServiceName $svc
    } else {
        Write-Warning 'Prepare 가 아무것도 설치하지 않았다 — 내릴 것이 없다'
    }
}
"tunnelIndex=$tunIdx ipv6Verdict=$ipv6Verdict baseIdx=$baseIdx"
```

- 세 번 다 `TUNNEL_NOT_REACHABLE` → 서버가 죽었을 가능성이 높다. **여기서 끝낸다.** 다른 설정 파일을 임의로 찾지 않는다.
  - **B-7a 를 근거로 이 규칙을 무르지 않는다.** 흐름 관문이 답 없는 상대에게도 열린다는 것은 위에서 실측했지만, 그것은 기준 인터페이스 쪽 답이다. 터널이 안 살아 있으면 **터널을 지나는 흐름을 잰다는 이 차수의 목적 자체가 없어진다.**
- `ipv6Verdict` 는 `INCONCLUSIVE` 가 나올 것이다(이 회선에 IPv6 없음). IPv6 16사례는 근거와 함께 자동으로 닫힌다(`:1250-1253`).

### 단계 4 — 대상 경로가 터널로 가는지 **확인한 뒤** 지운다

```powershell
# [수정] 지우기 전에 먼저 확인한다. 단계 3 의 ping 은 터널을 지났다는 증거가 아니다
$preIdx = (Find-NetRoute -RemoteIPAddress $target.IPAddressToString | Select-Object -First 1).InterfaceIndex
if ($preIdx -ne $tunIdx) { throw "대상이 터널($tunIdx)이 아니라 $preIdx 로 향한다 — 터널이 경로를 안 심었다. 멈춘다" }

Get-NetRoute -InterfaceIndex $tunIdx -AddressFamily IPv4 -EA SilentlyContinue |
    Where-Object { $_.DestinationPrefix -eq "$($target.IPAddressToString)/32" } |
    Remove-NetRoute -Confirm:$false

$postIdx = (Find-NetRoute -RemoteIPAddress $target.IPAddressToString | Select-Object -First 1).InterfaceIndex
if ($postIdx -ne $baseIdx) { throw "경로를 지운 뒤에도 $postIdx 로 향한다(기대 $baseIdx) — 멈춘다" }
"경로 정리 완료: $preIdx -> $postIdx"
```

### 단계 5 — 관찰 A (정책 걸기 **전**)

> **이 블록도 쪼개지 않는다.** `-Mode Start` 는 pktmon 잡기를 켜 둔 채 끝나고, 이 PC 의 pktmon 거르개를 **전부 지운 상태**로 둔다(`Get-WfpSpikeInterface.ps1` 의 `Invoke-Pktmon` `filter remove` 자리와 `keepCaptureRunning` 표식). 되돌리는 것은 `-Mode Stop` 뿐이다.
> **`-Mode Stop` 은 사례마다 한 번만 돌린다.** §3-0 의 **A-2** 로 갈린다:
> - **(가) A-2 가 `True`** — 되돌리기가 성공하면 Stop 이 `{사례}.capture-state.json` 을 지운다. 그래서 두 번째 Stop 은 `CAPTURE_STATE_MISSING` 으로 **되돌아가고 pktmon 을 한 번도 안 부른다.** 그래도 **한 번만 돌리는 습관은 유지한다.**
> - **(나) A-2 가 `False`** — 두 번째 Stop 은 되돌릴 목록이 이미 지워진 뒤라 **거르개를 못 되살린다.** 이 PC 전체의 pktmon 거르개가 걸린 문제다. 절대로 두 번 돌리지 않는다.
>
> 어느 쪽이든 되돌리기가 **실패**하면 `pktmon-filters-before.json` 과 `{사례}.capture-state.json` 이 **일부러 남는다.** 남아 있으면 "안 끝났다"는 표식이니 지우지 말고 원인을 먼저 본다.

```powershell
$obsA = Join-Path $run 'observation-a'; New-Item -ItemType Directory -Force -Path $obsA | Out-Null
$now  = [DateTimeOffset]::UtcNow.ToString('O')
$chrome = 'C:\Program Files\Google\Chrome\Application\chrome.exe'

$startJson = & "$obs\Get-WfpSpikeInterface.ps1" -Mode Start -VpnInterfaceIndex $tunIdx -BaselineInterfaceIndex $baseIdx `
    -TargetAddress $target -TargetPort 443 -Transport TCP -RunDirectory $obsA -CaseId 'M-017' -PolicyAppliedAtUtc $now
$startJson
# [수정] Start 가 실패하면 뒤 값은 전부 뜻이 없다
if (($startJson | ConvertFrom-Json).status -ne 'OK') { throw "관찰기가 안 떴다 — 멈춘다" }

$flowJson = & "$obs\New-WfpSpikeFlow.ps1" -AppPath $chrome -Transport TCP -IpVersion IPv4 `
    -TargetAddress $target -TargetPort 443 -PolicyAppliedAtUtc $now -RunDirectory $obsA
$flowJson
$flowPid = ($flowJson | ConvertFrom-Json).processId

# [수정] 본run 과 같게 -FlowProcessId 를 넘긴다 · 결과를 받아 observedPath 를 찍는다
$stopJson = & "$obs\Get-WfpSpikeInterface.ps1" -Mode Stop -VpnInterfaceIndex $tunIdx -BaselineInterfaceIndex $baseIdx `
    -TargetAddress $target -TargetPort 443 -Transport TCP -RunDirectory $obsA -CaseId 'M-017' -PolicyAppliedAtUtc $now `
    -FlowProcessId ([uint32]$flowPid)
$stopJson
$observationAPath = [string]($stopJson | ConvertFrom-Json).observedPath
"observationAPath = $observationAPath"     # ← 이 값을 단계 6 에 그대로 쓴다
Test-Path "$obsA\pktmon-filters-before.json"   # False 여야 거르개가 되돌아간 것이다
```

| 관찰 A 결과 | 뜻 | 다음 |
|---|---|---|
| `BASELINE` | 단계 4 가 통했다 | **그대로 진행.** 안 고른 앱 8사례를 잴 수 있다 |
| `VPN` | 터널이 여전히 가져가고 있다 | 단계 4 를 다시 본다. 그래도 `VPN` 이면 안 고른 앱 8사례는 자동으로 `INCONCLUSIVE` 가 된다(`:1256-1259`) |
| `OTHER` | 기준·터널 어느 쪽도 아닌 제3의 인터페이스에서 잡혔다(`:589-599`) | 단계 0 의 "기준 인터페이스 하나만"이 안 지켜진 것이다. **진행하지 않는다.** `OTHER` 를 적으면 `:1256` 이 안 걸러 안 고른 앱 8사례가 근거 없이 `FAIL` 로 채워진다 |
| `UNOBSERVED` | 관찰 수단 문제다 | 사례가 아니라 도구 문제다. `failureReason` 을 보고 원인을 먼저 본다(아래) |

`UNOBSERVED` 일 때 `failureReason` 별 뜻:

| failureReason | 뜻 | 할 일 |
|---|---|---|
| `NO_PACKET_CAPTURED` | 흐름이 정말 없었거나 거르개가 안 맞았다 | 대상 주소·포트를 확인한다 |
| `CAPTURE_BEFORE_POLICY` | `$now` 를 Start 뒤에 잡았다 | `$now` 를 Start **앞**에서 잡는다 (D-2 를 고친 뒤로는 잘 안 난다) |
| `COMPONENT_INDEX_UNREADABLE` | 구성 요소 지도를 못 만들었다 | `pktmon list --json` 이 도는지 본다 |
| `AMBIGUOUS_INTERFACE` | 양쪽 꾸러미 수가 같다 | 기준 인터페이스가 둘이 아닌지 본다 |
| `PKTMON_*` | pktmon 자체가 안 됐다 | 표준 오류의 진단 줄을 본다 |

### 단계 6 — 측정 설정 파일 (저장소 **밖**)

```powershell
@{
  baselineInterfaceIndex = $baseIdx
  selectedAppPath        = 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
  unselectedAppPath      = $chrome
  ipv6Verdict            = $ipv6Verdict         # 단계 3 결과
  observationAPath       = $observationAPath    # [수정] 단계 5 실측값이 변수로 들어온다
  ipv4TargetAddress      = $target.IPAddressToString
  ipv4TargetPort         = 443
  ipv4DnsServer          = $target.IPAddressToString
  queryName              = 'example.com'
} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath "$run\measurement-settings.json" -Encoding utf8
Get-Content -LiteralPath "$run\measurement-settings.json"
```

필수 5칸은 `baselineInterfaceIndex`·`selectedAppPath`·`unselectedAppPath`·`ipv6Verdict`·`observationAPath` 이고, 하나라도 없으면 `MEASUREMENT_SETTINGS_INVALID` 로 막힌다(`:1989-1999`). 두 실행 파일은 2026-08-17 에 존재를 확인했다.

### 단계 7 — LIVE 실행

```powershell
# [수정] 실패하면 이 셸이 닫힐 수 있다(바깥 catch 의 SetShouldExit). 값을 먼저 남긴다
@{ run=$run; svc=$svc; tunIdx=$tunIdx; baseIdx=$baseIdx; target=$target.IPAddressToString; obs=$obs } |
    ConvertTo-Json | Set-Content -LiteralPath "$run\session-state.json" -Encoding utf8

$evidenceRoot = Join-Path $env:LOCALAPPDATA 'VpnRouter\wfp-spike-runs'
$before = @(Get-ChildItem $evidenceRoot -Directory -EA SilentlyContinue | Select-Object -ExpandProperty Name)

& 'C:\dev\vpn_router\scripts\windows\test-wfp-app-routing-spike.ps1' `
    -ApplyLiveWfp `
    -LiveOwnerConfirmation 'APPLY LIVE WFP' `
    -LiveInterfaceIndex $tunIdx `
    -LiveExecutablePath 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe' `
    -LivePackageFamilyName '' `
    -MeasurementSettingsPath "$run\measurement-settings.json"

# [수정] 증거가 쌓인 폴더를 찾아 적는다 — $run 이 아니다
@(Get-ChildItem $evidenceRoot -Directory -EA SilentlyContinue | Where-Object { $_.Name -notin $before }) |
    Select-Object FullName,LastWriteTime
```

- `-LivePackageFamilyName ''` (빈 값)이면 패키지 물음 2개를 건너뛰고 사례 32건만 받는다(`:1952-1976`).
- **`-LiveOwnerConfirmation` 을 명령줄에 적는 것은 사용자 승인의 표현이다.** 저장소 안 코드가 이 값을 채우는 일은 0건이어야 한다(보안 `GR-17`). AI 가 사용자 지시로 입력했다면 **실행 기록에 그 사실을 반드시 남긴다.**
- 측정 예산은 정책 적용 뒤 **20분**이다(`:1263-1266`). 넘긴 사례는 재지 않고 `INCONCLUSIVE` 로 닫힌다.
- 셸이 닫혔으면: 관리자 `pwsh` 를 다시 열고 `Set-Location 'C:\dev\vpn_router'` 뒤
  `$st = Get-Content "$env:LOCALAPPDATA\VpnRouter\wfp-spike-runs\r4-live-plan-a\session-state.json" -Raw | ConvertFrom-Json` 로 값을 되찾아 단계 8 로 간다.

### 단계 8 — 정리와 회복 대조

```powershell
& "$obs\Use-WfpSpikeTunnel.ps1" -Mode Teardown -RunDirectory $run -TunnelServiceName $svc
& "$obs\Get-WfpOwnedPolicyState.ps1" -RunDirectory $run -Label 'after'
& "$obs\Get-WfpThirdPartyState.ps1" -Mode Compare -RunDirectory $run -Label 'after' -BaselinePath "$run\thirdparty-baseline.json"

# 잔여물 확인 — 넷 다 비어 있어야 끝난 것이다
Test-Path "$run\tunnel-installed.json"                      # False
@(Get-Service 'WireGuardTunnel*' -EA SilentlyContinue).Count # 0
@(Get-NetAdapter | Where-Object { $_.InterfaceDescription -like '*WireGuard*' }).Count  # 0
pktmon filter list                                           # 없음
```

`POLICY_STILL_PRESENT` 가 나오면 — §3-0 의 **A-1** 로 갈린다. **어느 쪽이든 사람이 그 자리에서 고른다.**

**(가) A-1 이 `True`** — 한 줄이다. 스위치를 **사람이 직접 적었을 때만** 이 갈래로 들어간다.

```powershell
& "$obs\Use-WfpSpikeTunnel.ps1" -Mode Teardown -StopHarnessFirst -RunDirectory $run -TunnelServiceName $svc
```

**(나) A-1 이 `False`** — 손으로 같은 순서를 밟는다. **정책이 0건인 것을 눈으로 본 뒤에만** 정리로 넘어간다.

```powershell
Get-Process VpnRouter.WfpSpike.Harness -EA SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2
& "$obs\Get-WfpOwnedPolicyState.ps1" -RunDirectory $run -Label 'after-harness-stop'   # 세 개수가 다 0 인지 눈으로 본다
& "$obs\Use-WfpSpikeTunnel.ps1" -Mode Teardown -RunDirectory $run -TunnelServiceName $svc
```

> **이 도구는 터널 서비스를 멈추기만 하고 지우지 않습니다. 되돌리기를 돌렸으면 그 뒤에 정리를 한 번 더 돌리십시오.**
> 즉 `restore-network-dev.ps1` 을 돌렸다면 **그 뒤에 Teardown 을 다시 돌린다.** restore 안에는 `/uninstalltunnelservice` 를 부르는 줄이 **0건**이고 `Get-Service "WireGuardTunnel*" | Stop-Service` 만 있다. **멈추는 것과 지우는 것은 다르다.**

---

## 5. 중단 규칙 (고침)

| 신호 | 즉시 할 일 |
|---|---|
| **인터넷이 끊긴다** | 아래 **비상 복구 ①** 로 간다. 정책이 없어지면 길이 돌아온다. **하네스를 먼저 끝내지 않으면 Teardown 은 반드시 막힌다** |
| 세 번 다 `TUNNEL_NOT_REACHABLE` | 서버가 죽었을 가능성이 높다. 끝낸다. 다른 설정을 찾지 않는다 |
| 단계 4 의 `$preIdx` 가 `$tunIdx` 가 아니다 | 터널이 경로를 안 심었다. 진행하지 않는다 |
| 단계 4 의 `$postIdx` 가 `$baseIdx` 가 아니다 | 경로가 안 지워졌다. 진행하지 않는다 |
| 관찰 A 가 `UNOBSERVED` / `OTHER` | 사례를 채우지 않는다. 원인을 먼저 본다 |
| `ownedPolicyCount` 가 0 이 아닌 채로 끝난다 | `restore-network-dev.ps1` → **그 뒤 Teardown 다시** → 그래도 남으면 **재부팅** (동적 세션이라 재부팅하면 사라진다) |

### 비상 복구 — 네 단계 (사람이 그 자리에서 고른다)

> **읽는 법 세 줄**
> 1. **이 네 단계는 사람이 하나씩 고른다.** 어느 도구도 이 갈래에 스스로 들어가지 않는다. `-StopHarnessFirst` 는 **사람이 명령줄에 직접 적었을 때만** 동작하고, 안 적으면 지금까지의 동작 그대로다. 설정 파일이나 환경 변수로 이 스위치를 켜는 길은 없다.
> 2. **순서를 뒤집지 않는다.** 소유 정책이 0건인 것을 확인하기 **전에** 터널을 내리지 않는다. 정책이 터널 LUID 를 다음 홉으로 쥐고 있어서, 뒤집으면 죽은 주소를 가리키는 정책이 남는다.
> 3. 인터넷을 되돌리는 것은 **①** 이다. ②③④ 는 뒷정리다. 급하면 ① 만 먼저 하고 숨을 고른다.

**① 하네스를 끝내고 · 정책을 다시 세고 · 그 다음 정리한다** — §3-0 의 **A-1** 로 갈린다

**(가) A-1 이 `True`** — 사람이 스위치를 적으면 도구가 이 순서를 대신 지킨다.

```powershell
& "$obs\Use-WfpSpikeTunnel.ps1" -Mode Teardown -StopHarnessFirst -RunDirectory $run -TunnelServiceName $svc
```

**(나) A-1 이 `False`** — 같은 순서를 손으로 밟는다. **세 개수가 다 0 인 것을 눈으로 본 뒤에만** 정리로 넘어간다.

```powershell
Get-Process VpnRouter.WfpSpike.Harness -EA SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2
& "$obs\Get-WfpOwnedPolicyState.ps1" -RunDirectory $run -Label 'after-harness-stop'
& "$obs\Use-WfpSpikeTunnel.ps1" -Mode Teardown -RunDirectory $run -TunnelServiceName $svc
```

**② 결과 한 줄을 읽는다** — 여기서 다음 단계가 갈린다

| `status` / `failureReason` | 뜻 | 다음 |
|---|---|---|
| `OK` / `NONE` | 정책 0건을 확인하고 터널을 내렸다 | ③ 으로 간다 (잔여물만 확인) |
| `ERROR` / `HARNESS_STILL_RUNNING` | 하네스를 끝내려 했는데 아직 살아 있다 | 하네스를 직접 끝낸 뒤 ① 을 다시 고른다. **터널은 아직 안 내려갔다 — 그것이 맞다** |
| `ERROR` / `POLICY_STILL_PRESENT` | 하네스는 없는데 정책·세션이 남았다 | ④ 로 간다 (재부팅) |
| `ERROR` / `POLICY_STATE_UNREADABLE` | 정책을 **못 셌다.** 0건이 아니다 | ④ 로 간다. **못 센 것을 0 으로 읽지 않는다** |
| `ERROR` / `TUNNEL_STOP_FAILED` | 관문은 지났는데 wireguard 가 실패했다 | 표준 오류의 진단 줄을 보고 ③ 으로 간다 |

**③ 남은 것을 훑는다 — 되돌리기 도구**

```powershell
& 'C:\dev\vpn_router\scripts\windows\restore-network-dev.ps1'
```

> **이 도구는 터널 서비스를 멈추기만 하고 지우지 않습니다. 되돌리기를 돌렸으면 그 뒤에 정리를 한 번 더 돌리십시오.**

- 그래서 ③ 을 돌린 뒤에는 **① 을 한 번 더 고른다.** 이 도구에는 `/uninstalltunnelservice` 를 부르는 줄이 0건이다.
- §3-0 의 **A-3** 이 `False` 면 이 도구는 `wfp-spike-runs` **한 뿌리만** 훑는다. 그 밖에 만든 폴더(손 예행 자리 등)는 **훑히지 않으니 손으로 본다.**
- 출력에 "못 읽은 뿌리"가 있으면 그것은 **"잔여물 0건"이 아니라 "못 셌다"** 이다. 그대로 적는다.
- 표식 파일을 손으로 지우는 것은 마지막에 한다: `Remove-Item -LiteralPath "$run\tunnel-installed.json" -Force -EA SilentlyContinue`. **정리가 안 끝났는데 표식만 지우면 "끝났다"는 거짓 자국이 남는다.**

**④ 그래도 정책이 남으면 재부팅한다**

- 소유 정책은 **동적 세션**이라 재부팅하면 사라진다. 재부팅 뒤에는 ① 의 관문이 열리므로 **① 을 다시 고르면 터널까지 깨끗이 내려간다.**
- 재부팅이 이 갈래의 정상 퇴로다. 관문을 손으로 넘기는 것보다 낫다.

> **마지막 수단 (권하지 않는다)**: `& 'C:\Program Files\WireGuard\wireguard.exe' /uninstalltunnelservice $svc` 를 직접 부르는 길이 있다.
> 이것은 **관문을 건너뛴다.** 부르기 전에 `Get-WfpOwnedPolicyState.ps1` 출력에서 `ownedPolicyCount`·`ownerSessionCount`·`harnessProcessCount` 가 **셋 다 0 인 것을 눈으로 본다.**
> 못 셌으면 부르지 않는다 — ④ 로 간다.

---

## 6. 이번 설정으로 잴 수 있는 것 / 없는 것

| 구간 | 사례 | 이번 결과 |
|---|---|---|
| 고른 앱 IPv4 | `M-001`~`M-008` | **실측** (이번 차수가 노리는 것) |
| 안 고른 앱 IPv4 | `M-017`~`M-024` | 관찰 A 가 `BASELINE` 이면 **실측** |
| IPv6 16건 | `M-009`~`M-016`·`M-025`~`M-032` | **`INCONCLUSIVE`** (회선에 IPv6 없음 — 근거 자동 기록) |
| 패키지 32건 | `M-033`~`M-064` | **`NOT_RUN`** (`WfpNativeApi.cs:27` 근거) |

**JSON `verdict` 로 이번 차수를 평가하지 않는다.** `FAIL` 이 한 건이라도 있으면 전체가 `FAIL` 이고, `INCONCLUSIVE` 가 있으면 `PASS` 가 안 나온다. 둘 다 정상이다.

### 아직 남은 약점 — UDP·QUIC·DNS

흐름 발생기는 브라우저에 URL 을 넘겨 흐름을 만든다(`New-WfpSpikeFlow.ps1` URL 갈래). TCP 는 이번에 확인기를 고쳐 실측으로 통과했지만, 나머지 셋은 그대로다.

| 전송 | 넘기는 것 | 위험 |
|---|---|---|
| TCP | `http://<ip>:<port>/` | **낮음 — 이번에 5회 연속 실측 통과** |
| QUIC | `https://<ip>:<port>/` | 높음 — 브라우저는 IP 리터럴에 QUIC 을 잘 안 쓴다 |
| UDP | `udp://<ip>:<port>` | 높음 — 브라우저가 모르는 스킴이다 |
| DNS | `dns://<ip>/<name>` | 높음 — 같은 이유 |

UDP·QUIC·DNS 는 `UNOBSERVED` → `INCONCLUSIVE` 로 닫힐 가능성이 크다. **사례의 실패가 아니라 관찰 수단의 한계다.** 그렇게 나오면 값을 채우지 말고 그대로 기록한다.

> 참고: 이 셋은 흐름 확인 갈래가 달라(`$observedConnection = -not $process.HasExited -or $process.ExitCode -eq 0`) `FLOW_TIMEOUT` 이 안 난다. 즉 흐름 관문은 통과하고 pktmon 단계에서 `NO_PACKET_CAPTURED` 로 닫힐 것이다.

---

## 7. R5 로 넘기는 발견

v1 §7 의 5건에 이번에 나온 것을 더한다.

> **[2026-08-18] R5 가 지금 손대는 자리** — 6·10·11·12·13 이 R5 도구 굳히기의 대상이다.
> 어느 것이 **실제로 들어왔는지**는 이 표가 아니라 **§3-0 확인 블록이 답한다.** 아래 표는 발견 기록이지 완료 기록이 아니다.
>
> | 발견 | R5 대응 | §3-0 의 어느 칸이 답하나 |
> |---|---|---|
> | 6 (회귀 시험 없음) | 고정값 회귀 시험 틀 신설 + push·PR 워크플로 | (칸 없음) `scripts\windows\wfp-observation-tests\Test-WfpObservationFixture.ps1` 이 있는지로 본다 |
> | 10 (되돌리기 뿌리 한 곳) | 뿌리 2곳 + `-AdditionalRunRoot` | **A-3** |
> | 11 (하네스 살아 있으면 Teardown 막힘) | 사람이 고르는 `-StopHarnessFirst` 갈래 | **A-1** |
> | 12 (`git`·`dotnet` 이 폴더를 따라감) | `git -C` + 절대 경로 + 작업 폴더 고정 | **A-4** |
> | 13 (`-Mode Stop` 재실행) | 되돌리기 성공 뒤 상태 파일 삭제 | **A-2** |
>
> 7·8·9 는 R5 에서 **동작을 안 바꾸고 고정값 시험으로 굳히는** 쪽이다. 즉 증상이 사라지는 것이 아니라 **다시 나면 시험이 잡는다.**

| # | 발견 | 근거 |
|---|---|---|
| 1 | 생존 확인이 경로 탈취 뒤에 돈다 | `Use-WfpSpikeTunnel.ps1` 의 `Verify` 안에 있음 |
| 2 | `Prepare` 의 `reachable:false` 는 "죽었다"가 아니라 "안 쟀다"이다 | `:137` 초기값 그대로 나감 |
| 3 | 측정에는 살아 있는 서버가 필요 없을 수 있다 | 판정은 pktmon 이 어느 인터페이스에서 봤는가이다 |
| 4 | 경로 탈취를 절차가 못 막는다 (단계 4 가 사람 손이다) | 이 문서 단계 4 |
| 5 | 기준 인터페이스가 둘일 때를 아무도 안 막는다 | 2026-08-17 실측 |
| **6** | **관찰 도구에 회귀 시험이 없다.** D-1~D-6 은 전부 실기 직전 손 예행으로만 잡혔다. `VpnRouter.Tests` 는 PowerShell 관찰 도구를 한 줄도 안 본다 | `Program.cs` 에 `Get-WfpSpikeInterface`·`pktmon` 언급 0건 |
| **7** | **도구가 창 표시 언어에 묶여 있다.** `etl2txt` 출력 이름표가 번역된다. 로캘 독립 출력 갈래가 pktmon 에 없다 | D-4 |
| **8** | **`pktmon start` 의 `--file-size` 는 CPU 수에 묶인 하한이 있다.** 버퍼 전체보다 작으면 조용히 빈 파일이 된다 | D-1 |
| **9** | **`ConvertFrom-Json` 의 날짜 자동 변환이 시각 비교를 조용히 망가뜨린다.** 같은 무늬가 다른 도구에도 있는지 훑어야 한다 | D-2 |
| **10** | **`restore-network-dev.ps1` 이 훑는 뿌리가 한 곳으로 못 박혀 있다.** 그 밖에서 돈 실행은 복구 대상이 아니다 | `:61` |
| **11** | **`Teardown` 이 하네스가 살아 있으면 반드시 막힌다.** 끊김 대응 순서를 도구가 강제하지 않는다 | `:343-346` vs `:350` |
| **12** | **진입 스크립트가 `git`·`dotnet` 을 부르는 곳의 폴더를 스스로 정하지 않는다.** `build-portable.ps1:307` 은 `git -C` 로 제대로 한다 | `:871`·`:1783`·`:1794` |
| **13** | **`-Mode Stop` 재실행이 이 PC 의 pktmon 거르개를 못 되돌린다.** 상태 파일을 안 지워 두 번째 실행이 그대로 진행된다 | `:399`·`:506`·`:293-296` |

---

## 8. 이 문서가 안 하는 것

- 설정 파일 만들기 — **AI 가 하지 않는다.** 사용자가 만든다(v1 §2). 내용·키·엔드포인트는 어디에도 적지 않는다. **여는 것도 하지 않는다** — 있는지만 본다
- 커밋 — ~~고친 코드 2개 파일과 이 문서는 작업 나무에만 있다~~ **[2026-08-18 정정]** 그 셋은 이미 커밋됐다(§1 「고친 파일」의 정정 줄). 이번 R5 갱신분은 커밋을 이 문서가 정하지 않는다
- `R3-DEC-01`~`05` 결정 — 근거만 모은다
- IPv6 실측 — 이 회선에 없다. 근거와 함께 닫는다
