# Windows WFP 실기 인계 — 안 (가) split-tunnel 재개 절차 (2026-08-17)

> ⚠️ **이 문서의 §4 절차는 더 쓰지 않는다.** 실기 직전 사전 감사에서 관찰 도구 결함 6건과
> 절차 막힘 9건이 나왔다. 고친 절차는 **`docs/windows-wfp-live-run-runbook-v2-2026-08-17.md`** 에 있다.
> 이 문서는 **2026-08-17 중단 기록**(§0·§1)과 **설정 파일 만드는 법**(§2)으로만 읽는다.

> 대상: **새 세션**(앞 대화 문맥 없음). 이 문서 하나로 끝까지 갈 수 있게 적었다.
> 성격: R4 실기 중단 기록 + 재개 절차. **저장소 코드는 한 줄도 안 고쳤다.**
> 앞 문서: `docs/R4-windows-wfp-owner-live-validation-prebrief-2026-08-14.md` · `~/Documents/insight-hub/vpn_router/R4/2026-08-14_03-26_notification_r4-wfp-observation-tooling-and-verdict.md`

## 0. 한 줄 요약

2026-08-17 실기는 **터널을 올린 직후 중단**했다. 시험용 WireGuard 설정이 기본 경로를 통째로 가져갔는데 서버가 응답하지 않아 **PC 전체 인터넷이 약 31분 끊겼다.** WFP 정책은 **한 번도 걸지 않았다.** 정리와 회복 대조까지 끝냈고 잔여물은 0건이다.

재개 방법으로 **안 (가) — 기본 경로를 안 가져가는 split-tunnel 시험용 설정**을 사용자가 채택했다. 이 문서는 그 절차다.

---

## 1. 중단 기록 (2026-08-17)

### 무슨 일이 있었나

| 시각(UTC) | 일 |
|---|---|
| 05:41:15 | 기준선 수집 — 제3자 5종 · WFP 소유 정책 0건 · pktmon 거르개 0건 |
| 05:41:45 | `Use-WfpSpikeTunnel -Mode Prepare` **OK** — 터널 index 54 |
| — | 터널이 기본 경로를 가져감 → **유선·무선 모두 인터넷 끊김** |
| 06:12:35 | 사용자 지시로 중단 · `-Mode Teardown` **OK** |
| 06:14 | 회복 대조 완료 — 잔여물 0건 |

### 왜 유선·무선이 다 끊겼나

실행한 것은 `wireguard.exe /installtunnelservice` 한 줄뿐이다. 기전은 이렇다.

설정에 `AllowedIPs = 0.0.0.0/0` 이 있으면 Windows 가 **기본 경로를 터널 어댑터로 옮긴다.** 이것은 앱별 조치가 아니라 **기계 전체 경로표를 바꾸는 일**이라, 어느 랜카드로 들어왔든 나갈 때는 전부 터널로 간다. 터널 반대편이 응답하지 않으면 전부 허공으로 빠진다.

### macOS 와 왜 다른가

| | macOS | Windows |
|---|---|---|
| 쓰는 것 | `NETransparentProxyProvider` (`TransparentProxyProvider.swift:5`) | WFP 연결 정책 + **실제 터널 인터페이스** |
| 흐름 처리 | 확장 안에서 앱별로 가로챔 | 정책이 "이 앱 흐름을 이 인터페이스 LUID 로" |
| 경로표 | **안 건드림** — `tunnelRemoteAddress: "192.0.2.1"` 은 문서용 가짜 주소(`:21`) | 다음 홉이 될 진짜 인터페이스가 있어야 함 |
| 다른 트래픽 | 영향 0 | 설정에 따라 전부 끌려감 |

macOS 가 독립적인 게 아니라 **macOS 는 애초에 경로표를 안 쓴다.** 프리브리프도 예상은 했다(§8-1: "WireGuard 터널은 보통 기본 경로를 통째로 가져간다").

### 중단 시점 복구 확인 (전부 실측)

| 확인 | 결과 |
|---|---|
| 인터넷 | 정상 (ping 1.1.1.1 성공 · DNS 해석 성공) |
| 터널 어댑터·서비스 | 0건 |
| `tunnel-installed.json` (정리 미완 표식) | **없음** = 정리 완료 |
| WFP 소유 정책 | **0건** (`ownedPolicyCount:0` · 세 신호 `AGREE`) |
| pktmon 거르개 | 없음 |
| 제3자 제품 5종 | **전부 무변화** (`unchangedCount:5`) |
| WireGuard 잔여 경로 | 0건 |

> 회복 지문은 `MISMATCH` 로 남았다. 원인은 시험과 무관하다 — 중단 중에 **이더넷(ifIndex 17)이 연결되어** `192.168.1.181/32` · `192.168.1.255/32` 두 경로가 늘었다. 경로를 한 줄씩 대조해 확인했고 WireGuard 잔여물은 없다.
> 기준선 파일: `C:\Users\NetMD\AppData\Local\VpnRouter\r4-live-20260817\`

---

## 2. 사용자가 먼저 해야 하는 것 — split-tunnel 설정 파일 1개

**이것 없이는 재개할 수 없다.** 그리고 **AI 는 이 파일을 만들 수 없다** — 시험 도구는 설정 파일을 열지 않기로 되어 있고(NFR-02 · GR-14), 안에 든 서버 주소·키를 볼 수 없기 때문이다.

기존 `63543_jp_wg.conf` 를 복사해 **새 이름**으로 저장하고 세 군데만 고친다.

| 어디 | 어떻게 | 왜 |
|---|---|---|
| `[Peer]` 의 `AllowedIPs` | `0.0.0.0/0` → **`1.1.1.1/32`** | 기본 경로를 안 가져간다. 이 한 줄이 안 (가)의 전부다 |
| `[Interface]` 의 `DNS = ...` | **줄 통째로 지운다** | 남기면 시스템 DNS 가 터널로 향하는데 그 서버는 `AllowedIPs` 밖이라 DNS 가 통째로 죽는다 |
| `[Interface]` 의 `Address` / `PrivateKey`, `[Peer]` 의 `PublicKey` / `Endpoint` | **그대로 둔다** | 서버 접속에 필요하다 |

**파일 이름 규칙** — 서비스 이름이 곧 파일 이름(확장자 제외)이고 어댑터 별칭도 같은 이름이 된다(`Use-WfpSpikeTunnel.ps1:114-118`). `^[A-Za-z0-9_\-]{1,64}$` 만 쓴다.

권장: `C:\Users\NetMD\Downloads\r4split.conf` → 서비스 이름 `r4split`

> `Table = off` 로 경로 생성을 막는 방법은 **쓰지 않는다.** WireGuard for Windows 가 이 항목을 받는다는 근거를 찾지 못했다. 아래 절차는 경로가 생기는 것을 전제로 하고, 확인에 쓴 뒤 손으로 지운다(단계 4).

### 서버가 살아 있어야 한다

`Verify` 는 터널 너머로 ping 이 되는지 보고 안 되면 `TUNNEL_NOT_REACHABLE` 로 멈춘다(`:274-278`). **2026-08-17 에 끊긴 정황상 이 서버는 죽어 있을 가능성이 높다.** 살아 있는 서버가 없으면 안 (가)도 단계 3 에서 멈춘다 — 다만 이번에는 **끊김 없이** 멈춘다(그게 안 (가)의 핵심이다).

---

## 3. 실행 전 전제 (단계 0)

| 확인 | 명령 | 있어야 할 값 |
|---|---|---|
| 관리자 승격 | `([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole('Administrators')` | `True` |
| BFE 서비스 | `(Get-Service BFE).Status` | `Running` |
| 보호 경로 diff | `git diff --name-only -- macos docs/v0.1.0-release-plan.md artifacts` | **빈 출력** (아니면 자동 게이트가 막는다) |
| 소유 정책 | 단계 2 가 확인 | `ownedPolicyCount:0` |

### ★ 기준 인터페이스를 **하나만** 남긴다

2026-08-17 중단 뒤 **Wi-Fi(8) 와 이더넷(17)이 둘 다 `Up`** 이고 기본 경로가 둘, metric 도 같다. 이 상태로 재면 "기준 인터페이스로 갔다"의 뜻이 흐려지고 `OTHER` 판정이 섞인다.

**둘 중 하나를 끊고 시작한다.** 남긴 쪽 index 가 `baselineInterfaceIndex` 다.

```powershell
Get-NetRoute -DestinationPrefix '0.0.0.0/0' | Select-Object InterfaceIndex, NextHop, RouteMetric
Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object InterfaceIndex, Name
```

---

## 4. 재개 절차 (복사해 붙이는 순서)

아래 `$conf` · `$svc` · `$baseIdx` 세 값만 실제 값으로 바꾸고 순서대로 돌린다.

### 단계 1 — 변수와 실행 폴더

```powershell
$obs     = 'C:\dev\vpn_router\scripts\windows\wfp-observation'
$run     = 'C:\Users\NetMD\AppData\Local\VpnRouter\r4-live-plan-a'
$conf    = 'C:\Users\NetMD\Downloads\r4split.conf'   # ← 단계 2 에서 만든 파일
$svc     = 'r4split'                                  # ← conf 파일 이름(확장자 제외)
$target  = [ipaddress]'1.1.1.1'                       # AllowedIPs 에 넣은 그 주소
$baseIdx = 8                                          # ← 남긴 기준 인터페이스 index
New-Item -ItemType Directory -Force -Path $run | Out-Null
```

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

`ownedPolicyCount` 가 **0 이 아니면 여기서 멈춘다.** 앞 실행 잔여물이므로 `scripts\windows\restore-network-dev.ps1` 을 먼저 돌린다.

### 단계 3 — 터널 올리고 **곧바로** 확인 (실패하면 자동으로 내림)

> **이 블록을 쪼개서 돌리지 않는다.** 2026-08-17 의 31분 끊김이 바로 Prepare 와 Verify 사이가 벌어져 생겼다. 한 덩어리로 붙여 넣으면 실패해도 몇 초 안에 원상복구된다.

```powershell
$tunIdx = $null; $ipv6Verdict = 'INCONCLUSIVE'
$p = & "$obs\Use-WfpSpikeTunnel.ps1" -Mode Prepare -ConfigPath $conf -RunDirectory $run -TunnelServiceName $svc
$p
if (($p | ConvertFrom-Json).status -eq 'OK') {
    $v = & "$obs\Use-WfpSpikeTunnel.ps1" -Mode Verify -RunDirectory $run -TunnelServiceName $svc -ReachabilityAddress $target
    $v
    $vo = $v | ConvertFrom-Json
    if ($vo.status -eq 'OK') { $tunIdx = [int]$vo.tunnelInterfaceIndex; $ipv6Verdict = [string]$vo.ipv6Verdict }
}
if ($null -eq $tunIdx) {
    Write-Warning '터널 확인 실패 — 즉시 내린다'
    & "$obs\Use-WfpSpikeTunnel.ps1" -Mode Teardown -RunDirectory $run -TunnelServiceName $svc
}
"tunnelIndex=$tunIdx ipv6Verdict=$ipv6Verdict"
```

- `TUNNEL_NOT_REACHABLE` → **서버가 죽었다.** 여기서 끝낸다. 다른 설정 파일을 임의로 찾지 않는다(프리브리프 §4-2 단계 2).
- `ipv6Verdict` 는 `INCONCLUSIVE` 가 나올 것이다(이 회선에 IPv6 없음). 그러면 IPv6 16사례는 근거와 함께 자동으로 `INCONCLUSIVE` 로 닫힌다(`test-wfp-app-routing-spike.ps1:1250-1253`).

### 단계 4 — ★ 터널이 심은 대상 경로를 지운다 (안 (가)의 핵심)

`AllowedIPs = 1.1.1.1/32` 는 `1.1.1.1/32` **경로**도 함께 만든다. 그대로 두면 **모든 앱**이 그 주소로 갈 때 터널을 타서, 기본 경로를 가져갔을 때와 똑같이 안 고른 앱을 잴 수 없다.

단계 3 의 ping 이 그 경로로 나가 **서버 생존을 이미 증명했으므로**, 이제 지운다. 그러면 남는 것은 이렇다.

- 안 고른 앱(Chrome) → 평소 경로 → **기준 인터페이스** ✔
- 고른 앱(Edge) → WFP 연결 정책이 다음 홉을 터널로 지정 → **터널** ✔ ← 이것이 이번 시험이 재려는 바로 그것

```powershell
Get-NetRoute -InterfaceIndex $tunIdx -AddressFamily IPv4 -EA SilentlyContinue |
    Where-Object { $_.DestinationPrefix -eq "$($target.IPAddressToString)/32" } |
    Remove-NetRoute -Confirm:$false
# 확인 — 이제 대상 주소가 기준 인터페이스로 향해야 한다
(Find-NetRoute -RemoteIPAddress $target.IPAddressToString | Select-Object -First 1).InterfaceIndex
```

마지막 줄이 **`$baseIdx` 와 같아야** 다음으로 간다. `$tunIdx` 가 나오면 경로가 안 지워진 것이다.

### 단계 5 — 관찰 A (정책 걸기 **전**)

터널이 떠 있고 WFP 정책이 없는 상태에서 **안 고른 앱**이 어디로 나가는지 본다. 이 값 없이 `R3-DEC-04` 근거를 쓰면 잘못된 결론이 올라간다(프리브리프 §8-1).

```powershell
$obsA = Join-Path $run 'observation-a'; New-Item -ItemType Directory -Force -Path $obsA | Out-Null
$now  = [DateTimeOffset]::UtcNow.ToString('O')
$chrome = 'C:\Program Files\Google\Chrome\Application\chrome.exe'
& "$obs\Get-WfpSpikeInterface.ps1" -Mode Start -VpnInterfaceIndex $tunIdx -BaselineInterfaceIndex $baseIdx `
    -TargetAddress $target -TargetPort 443 -Transport TCP -RunDirectory $obsA -CaseId 'M-017' -PolicyAppliedAtUtc $now
& "$obs\New-WfpSpikeFlow.ps1" -AppPath $chrome -Transport TCP -IpVersion IPv4 `
    -TargetAddress $target -TargetPort 443 -PolicyAppliedAtUtc $now -RunDirectory $obsA
& "$obs\Get-WfpSpikeInterface.ps1" -Mode Stop -VpnInterfaceIndex $tunIdx -BaselineInterfaceIndex $baseIdx `
    -TargetAddress $target -TargetPort 443 -Transport TCP -RunDirectory $obsA -CaseId 'M-017' -PolicyAppliedAtUtc $now
```

`observedPath` 값을 그대로 단계 6 의 `observationAPath` 에 적는다. **추측해서 채우지 않는다.**

| 관찰 A 결과 | 뜻 | 다음 |
|---|---|---|
| `BASELINE` | 단계 4 가 통했다 | **그대로 진행.** 안 고른 앱 8사례를 잴 수 있다 |
| `VPN` | 터널이 여전히 가져가고 있다 | 단계 4 를 다시 본다. 그래도 `VPN` 이면 안 고른 앱 8사례는 자동으로 `INCONCLUSIVE` 가 된다(`:1256-1259`) |
| `UNOBSERVED` | pktmon 이 못 봤다 | 사례가 아니라 **관찰 수단 문제**다. 채우지 말고 원인을 먼저 본다 |

### 단계 6 — 측정 설정 파일 (저장소 **밖**)

```powershell
@{
  baselineInterfaceIndex = $baseIdx
  selectedAppPath        = 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
  unselectedAppPath      = $chrome
  ipv6Verdict            = $ipv6Verdict          # 단계 3 결과
  observationAPath       = 'BASELINE'            # ← 단계 5 실측값으로 바꾼다
  ipv4TargetAddress      = $target.IPAddressToString
  ipv4TargetPort         = 443
  ipv4DnsServer          = $target.IPAddressToString
  queryName              = 'example.com'
} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath "$run\measurement-settings.json" -Encoding utf8
```

두 실행 파일은 2026-08-17 에 존재를 확인했다. 필수 5칸은 `baselineInterfaceIndex` · `selectedAppPath` · `unselectedAppPath` · `ipv6Verdict` · `observationAPath` 이고, 하나라도 없으면 `MEASUREMENT_SETTINGS_INVALID` 로 막힌다(`:1989-1999`).

### 단계 7 — LIVE 실행

```powershell
& 'C:\dev\vpn_router\scripts\windows\test-wfp-app-routing-spike.ps1' `
    -ApplyLiveWfp `
    -LiveOwnerConfirmation 'APPLY LIVE WFP' `
    -LiveInterfaceIndex $tunIdx `
    -LiveExecutablePath 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe' `
    -LivePackageFamilyName '' `
    -MeasurementSettingsPath "$run\measurement-settings.json"
```

- `-LivePackageFamilyName ''` (빈 값)이면 패키지 물음 2개를 건너뛰고 사례 32건만 받는다(`:1952-1976`).
- **`-LiveOwnerConfirmation` 을 명령줄에 적는 것은 사용자 승인의 표현이다.** 저장소 안 코드가 이 값을 채우는 일은 0건이어야 한다(보안 `GR-17`). 2026-08-17 에 사용자가 "대신 실행해줘"로 명시 지시했고, 이 문서는 그 지시에 따른 절차다. **실행 기록에 "AI 가 사용자 지시로 입력함"을 반드시 남긴다.**
- 측정 예산은 정책 적용 뒤 **20분**이다(`:1263-1266`). 넘긴 사례는 재지 않고 `INCONCLUSIVE` 로 닫힌다.

### 단계 8 — 정리와 회복 대조

```powershell
& "$obs\Use-WfpSpikeTunnel.ps1" -Mode Teardown -RunDirectory $run -TunnelServiceName $svc
& "$obs\Get-WfpOwnedPolicyState.ps1" -RunDirectory $run -Label 'after'
& "$obs\Get-WfpThirdPartyState.ps1" -Mode Compare -RunDirectory $run -Label 'after' -BaselinePath "$run\thirdparty-baseline.json"
```

`Teardown` 은 **소유 정책 0건을 확인한 뒤에만** 터널을 내린다(순서 잠금). `POLICY_STILL_PRESENT` 가 나오면 터널을 먼저 내리려 하지 말고 `restore-network-dev.ps1` 을 돌린다.

`$run\tunnel-installed.json` 이 **남아 있으면 정리가 안 끝난 것이다.**

---

## 5. 이번 설정으로 잴 수 있는 것 / 없는 것

| 구간 | 사례 | 이번 결과 |
|---|---|---|
| 고른 앱 IPv4 | `M-001`~`M-008` | **실측** (이번 차수가 노리는 것) |
| 안 고른 앱 IPv4 | `M-017`~`M-024` | 관찰 A 가 `BASELINE` 이면 **실측**, `VPN` 이면 `INCONCLUSIVE` |
| IPv6 16건 | `M-009`~`M-016` · `M-025`~`M-032` | **`INCONCLUSIVE`** (회선에 IPv6 없음 — 근거 자동 기록) |
| 패키지 32건 | `M-033`~`M-064` | **`NOT_RUN`** (`WfpNativeApi.cs:27` 근거) |

**JSON `verdict` 로 이번 차수를 평가하지 않는다.** `FAIL` 이 한 건이라도 있으면 전체가 `FAIL` 이고(`OwnerHarnessRunner.cs:194`), `INCONCLUSIVE` 가 있으면 `PASS` 가 안 나온다. 둘 다 정상이다. 성공 기준은 프리브리프 §8-0 표에 있다.

### 미리 알아 둘 약점 — UDP·QUIC·DNS

흐름 발생기는 브라우저에 URL 을 넘겨 흐름을 만든다(`New-WfpSpikeFlow.ps1:224-229`).

| 전송 | 넘기는 것 | 위험 |
|---|---|---|
| TCP | `http://<ip>:<port>/` | 낮음. `Get-NetTCPConnection` 으로 되짚어 확인까지 한다 |
| QUIC | `https://<ip>:<port>/` | **높음** — 브라우저는 IP 리터럴에 QUIC 을 잘 안 쓴다. TLS/TCP 로 내려앉을 수 있다 |
| UDP | `udp://<ip>:<port>` | **높음** — 브라우저가 모르는 스킴이다 |
| DNS | `dns://<ip>/<name>` | **높음** — 같은 이유 |

UDP·QUIC·DNS 는 `UNOBSERVED` → `INCONCLUSIVE` 로 닫힐 가능성이 크다. **이것은 사례의 실패가 아니라 관찰 수단의 한계다.** 그렇게 나오면 값을 채우지 말고 그대로 기록한다. 2026-08-10 실기의 "Edge UDP·QUIC 이 Wi-Fi 로 빠짐"도 같은 뿌리일 수 있다.

---

## 6. 중단 규칙 (실행 중에 판단이 갈리지 않게 미리 고정)

| 신호 | 즉시 할 일 |
|---|---|
| 인터넷이 끊긴다 | **단계 8 Teardown 을 바로 돌린다.** 원인 분석은 그 뒤에 |
| `TUNNEL_NOT_REACHABLE` | 서버가 죽었다. 끝낸다. 다른 설정을 찾지 않는다 |
| 단계 4 확인이 `$tunIdx` 를 낸다 | 경로가 안 지워졌다. 진행하지 않는다 |
| 관찰 A 가 `UNOBSERVED` | 관찰 수단 문제다. 사례를 채우지 않는다 |
| `ownedPolicyCount` 가 0 이 아닌 채로 끝난다 | `restore-network-dev.ps1` → 그래도 남으면 **재부팅**. 동적 세션이라 재부팅하면 반드시 사라진다(프리브리프 §0-2) |

### 비상 복구 (한 줄)

```powershell
& 'C:\Program Files\WireGuard\wireguard.exe' /uninstalltunnelservice r4split
```

그 뒤 `scripts\windows\restore-network-dev.ps1` 을 돌린다.

---

## 7. R5 로 넘기는 발견 (이번에 새로 나온 것)

| # | 발견 | 근거 |
|---|---|---|
| 1 | **생존 확인이 경로 탈취 뒤에 돈다.** `Prepare` 가 터널을 올려 기본 경로를 넘긴 다음에야 `Verify` 가 서버 생존을 잰다. 서버가 죽어 있으면 전면 끊김이 **구조적으로 보장**된다 | `Use-WfpSpikeTunnel.ps1:268-278` 이 `Verify` 안에 있음. 실측: 31분 끊김 |
| 2 | **`Prepare` 의 `reachable:false` 는 "죽었다"가 아니라 "안 쟀다"** 이다. 같은 칸에 두 뜻이 섞여 있어 읽는 사람을 속인다 | `:137` 초기값 그대로 나감 |
| 3 | **측정에는 살아 있는 서버가 필요 없을 수 있다.** 판정은 pktmon 이 어느 인터페이스에서 꾸러미를 봤는가이지 상대가 답했는가가 아니다. 생존 관문이 측정이 요구하는 것보다 엄하다 | `Get-WfpSpikeInterface.ps1` 판정 규칙 |
| 4 | **경로 탈취를 절차가 못 막는다.** 안 (가)의 단계 4(경로 지우기)가 지금은 사람 손이다. 도구로 굳혀야 한다 | 이 문서 단계 4 |
| 5 | **기준 인터페이스가 둘일 때를 아무도 안 막는다.** metric 이 같은 기본 경로 2개면 `baselineInterfaceIndex` 의 뜻이 흐려진다 | 2026-08-17 실측 (Wi-Fi 8 · 이더넷 17 동시 `Up`) |

---

## 8. 이 문서가 안 하는 것

- 저장소 코드 수정 — **0줄.** 위 절차는 전부 기존 스크립트 호출과 명령줄이다
- 설정 파일 내용 기록 — 필드 이름과 바꿀 값만 적었다. 키·엔드포인트는 안 적는다(§5 불변식)
- `R3-DEC-01`~`05` 결정 — 근거만 모은다
- IPv6 실측 — 이 회선에 없다. 근거와 함께 닫는다
