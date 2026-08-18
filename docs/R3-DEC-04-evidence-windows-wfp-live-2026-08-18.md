# R3-DEC-04 근거표와 결정 — Windows 사용자 모드 WFP 앱 라우팅 (2026-08-18)

> 실기 기록: `%LOCALAPPDATA%\VpnRouter\wfp-spike-runs\` 아래 `20260818-110619Z-8ea6080d`(정방향) · `20260818-114242Z-d6ea0286`(역방향) · `r4-cause`(정책 상태 덤프)
> 절차: `docs/windows-wfp-live-run-runbook-v2-2026-08-17.md`
> 앞 시도: 2026-08-10(부분) · 2026-08-17(중단, 31분 끊김) — 둘 다 근거를 못 냈다

## 0. 한 줄

**Windows 사용자 모드 WFP 의 `FwpmConnectionPolicyAdd0` + `NEXT_HOP_INTERFACE` 가 실제 라우팅을 바꾸지 않았다.** 정책·조건·다음 홉이 모두 올바른 상태에서 **양방향으로** 확인했다. 트래픽은 두 번 다 정책이 아니라 경로표를 따랐다.

**결정(§7): 커널 driver 연구로 넘어간다.** — **2026-08-18 조건부 재개됨. §12 를 먼저 읽을 것.**

> **이 문서의 실측 결론은 그대로 유효하다.** 재개는 이 결론을 뒤집는 것이 아니라, 이 실기가 건드리지 않은 **다른 API 표면**(UWP VPN 플러그인의 `VpnChannel.StartWithTrafficFilter`)을 판별 시험 1회로 확인하는 것이다.

---

## 1. 실기 조건 (전부 실측)

| 항목 | 값 |
|---|---|
| 터널 | WireGuard split-tunnel · `AllowedIPs = 1.1.1.1/32` · 터널 index **54** |
| 서버 생존 | 손잡기 **3초** 성공(받은 124바이트) · 터널 너머 ping `OK` |
| 기준 인터페이스 | **8** (Wi-Fi 2) — `Up` 인 어댑터가 이것 하나뿐 |
| 대상 | `1.1.1.1:443` TCP · 고른 앱 `msedge.exe` · 안 고른 앱 `chrome.exe` |
| 소유 정책(시작 전) | **0건** · 세 신호 `AGREE` |
| 제3자 제품 | 5종 관측 · 실행 전후 **무변화** |
| Windows | 26200 · pwsh 7.6.5 |

**서버 설정이 만료돼 있었다.** 옛 설정은 15초 동안 손잡기 요청 592바이트를 보내고 **0바이트**를 받았다. 새로 받은 설정은 **3초 만에 124바이트**를 받았다. 이 확인에 36초가 걸렸고, 같은 조건에서 2026-08-17 은 31분 끊김을 치렀다.

---

## 2. 시험 1 — 정방향 (경로를 지우고, 고른 앱을 터널로 당김)

경로 처리: 터널이 심은 `1.1.1.1/32` 를 **지우기 전에 실제로 터널로 향하는 것을 확인**하고 지웠다(54 → 8).
관찰 A(정책 전): 안 고른 앱이 `BASELINE`(8) · 꾸러미 234 — 터널이 기본 경로를 안 가져갔음이 확인됐다.

| 사례 | 앱 | 기대 | **관측** | 인터페이스 | 꾸러미 | 흐름 |
|---|---|---|---|---|---|---|
| **`M-001`** | **고른 앱(Edge)** | `VPN` | **`BASELINE`** | **8** | 226 | `OK` |
| `M-005` | 고른 앱 + 겹치는 경로 | `VPN` | `UNOBSERVED` | — | 2 | `OK` |
| `M-017` | 안 고른 앱(Chrome) | `BASELINE` | `BASELINE` | 8 | 240 | `OK` |
| `M-021` | 안 고른 앱 + 겹치는 경로 | `BASELINE` | `UNOBSERVED` | — | 3 | `OK` |

꾸러미 수준(`M-001`): 대상으로 가는 105줄의 **출발 주소가 전부 `192.168.1.78`**(랜 주소)이고 **터널(54)에서 잡힌 꾸러미는 0개**.

**이 시험의 약점**: 단계 4 가 터널의 유일한 대상 경로를 지웠으므로, 「정책이 가리킨 인터페이스에 쓸 경로가 없어서 못 골랐다」는 설명이 남았다. 그래서 시험 2 를 했다.

---

## 3. 시험 2 — 역방향 (경로를 살리고, 안 고른 앱을 기준으로 밀어냄)

**약점을 없애는 설계**다. 경로를 지우지 않으므로 정책이 가리키는 인터페이스(8)에는 `1.1.1.1` 로 가는 **멀쩡한 기본 경로가 있다.** 정책이 고를 대상이 실제로 존재한다.

이 실행에서는 이름표의 뜻이 뒤집힌다 — **읽을 때 주의할 것.**

| 하네스 이름표 | 이 실행에서의 뜻 |
|---|---|
| `-LiveInterfaceIndex 8` | 정책이 가리키는 다음 홉 = Wi-Fi(기준) |
| `selectedAppPath` = Chrome | 정책이 **미는** 앱 |
| `VPN` 판정 = 인터페이스 **8** | 정책이 일한 것 |
| `BASELINE` 판정 = 인터페이스 **54** | 경로가 한 것 |

관찰 A(정책 전): Edge 가 `BASELINE`(54) — 경로가 살아 있어 모두가 터널로 가는 상태가 확인됐다.

| 사례 | 앱 | 정책 | 기대 | **관측** | 인터페이스 | 꾸러미 |
|---|---|---|---|---|---|---|
| **`M-001`** | **Chrome** | **→ 8 로 밀어냄** | `VPN`(=8) | **`BASELINE`** | **54** | 32 |
| **`M-005`** | Chrome + 겹치는 경로 | → 8 | `VPN`(=8) | **`BASELINE`** | **54** | 56 |
| `M-017` | Edge (정책 없음) | — | `BASELINE`(=54) | `BASELINE` | 54 | 34 |
| `M-021` | Edge + 겹치는 경로 | — | `BASELINE`(=54) | `BASELINE` | 54 | 51 |

**네 사례 전부 인터페이스 54 로 갔다.** 정책 대상이든 아니든 같다. 흐름은 전부 `OK`.

---

## 4. 정책이 실제로 어떻게 걸렸는가 (실행 중 상태 덤프)

정책이 걸린 순간에 `netsh wfp show state` 를 떠서(5.4MB) 직접 읽었다. 소유 정책 **2** · 세션 **1** · 하네스 **1**.

> 소유 GUID 4개 중 2개만 있는 것은 정상이다. `0601`=DesktopIpv4 · `0602`=DesktopIpv6 는 있고, `0603`·`0604`=Package 는 `-LivePackageFamilyName ''` 로 건너뛰었으므로 없다.

**IPv4 필터 원문**

```
계층      FWPM_CALLOUT_OUTBOUND_NETWORK_CONNECTION_POLICY_LAYER_V4
동작      FWP_ACTION_CALLOUT_TERMINATING
조건      FWPM_CONDITION_ALE_APP_ID = FWP_MATCH_EQUAL
          \device\harddiskvolume3\program files (x86)\microsoft\edge\application\msedge.exe
컨텍스트   {32458d2e-…-c70601} → FWP_NETWORK_CONNECTION_POLICY_NEXT_HOP_INTERFACE
가중치     10000
```

**다음 홉 LUID 해독**: `14918723538255872` → `IfType=53`(가상) · `NetLuidIndex=32769` → **정확히 `r4split` 터널(index 54)**. 같은 기계의 `VPN Unlimited TAP`(32768) · 이더넷(IfType 6) · Wi-Fi(IfType 71) 어느 것도 아니다.

**쓴 API**: `NativeMethods.cs:19` 이 `FwpmConnectionPolicyAdd0` 을 그대로 호출한다. 손으로 흉내 낸 것이 아니다.

---

## 5. 배제된 가설

| 가설 | 배제 근거 |
|---|---|
| 정책이 안 걸렸다 | 실행 중 상태 덤프에 존재 (소유 정책 2 · 세션 1 · 하네스 1) |
| 잘못된 API 를 썼다 | `FwpmConnectionPolicyAdd0` — Microsoft 문서가 **process-based routing** 용으로 지목한 함수 |
| 앱 신원이 안 맞았다 | `ALE_APP_ID` 가 실행 파일 장치 경로를 정확히 가리킴 |
| 잘못된 인터페이스를 가리켰다 | LUID 해독 결과 정확히 터널(54) |
| 다음 홉에 쓸 경로가 없었다 | **시험 2 에서 경로가 있는데도 안 먹음** |
| 측정 수단이 실패했다 | 여덟 사례 전부 `flowStatus: OK` · 꾸러미 32~240개 관측 |

---

## 6. 문서가 말하는 것

Microsoft 공식 문서:

> **`FWPM_LAYER_OUTBOUND_NETWORK_CONNECTION_POLICY_V4`** — A callout layer where **a WFP filter driver** can inspect an outgoing IPv4 connection and **read/write the routing policy** that was configured for this connection. See `FwpmConnectionPolicyAdd0`.

> **`FwpmConnectionPolicyAdd0`** — allows you to configure more expressive routing policies for outbound connections, and thereby to enable more complex scenarios such as source address-based routing, **process-based routing**, port-based routing, and others.

두 문장을 함께 읽으면 이렇게 읽힌다 — 사용자 모드에서 정책을 **등록**할 수는 있으나, 그 계층에서 정책을 **집행**하는 주체는 커널 모드 filter driver 다. 드라이버가 없으면 등록된 정책이 아무 일도 하지 않는다.

**다만 이것은 문서 문장에서 읽어 낸 해석이지 실측이 아니다.** 확정하려면 커널 드라이버를 만들어 봐야 하고, 그것이 곧 아래 결정이 가리키는 방향이다.

출처: [Filtering layer identifiers](https://learn.microsoft.com/en-us/windows/win32/fwp/management-filtering-layer-identifiers-) · [FwpmConnectionPolicyAdd0](https://learn.microsoft.com/en-us/windows/win32/api/fwpmu/nf-fwpmu-fwpmconnectionpolicyadd0)

---

## 7. 결정 — `R3-DEC-04`

**상태: 2026-08-18 종결 → 같은 날 조건부 재개(REOPENED, 판별 시험 1회 한정).** 아래는 종결 당시 기록이며, 재개 사유와 조건은 §12 에 있다.

**결정: 커널 driver 연구로 넘어간다.**
**결정자: 사용자 · 결정일: 2026-08-18 · 근거: 이 문서 §2~§6**

R4 프리브리프가 "R4·R5 는 근거만 모으고 결정하지 않는다"로 정해 둔 대로, 근거가 갖춰진 이 시점에 사용자가 결정했다.

**함께 닫히는 것**
- 사용자 모드 WFP **연결 정책**(`FwpmConnectionPolicyAdd0`)으로 Windows 앱별 라우팅을 계속 시도하는 갈래는 닫는다
- `R3-DEC-01`(helper·renderer 자동 포함)·`R3-DEC-02`(기존 연결 처리)는 이 결과를 **근거로만** 받는다. 이 경로가 닫혔으므로 그 두 물음은 다시 물어야 한다

**대비**: macOS 는 `NETransparentProxyProvider` 로 같은 제품 목표를 달성했다 (R3, `signedMac` PASS 실행 11 · 통과 11 · 실패 0).

> **2026-08-18 정정**: 종결 당시 여기에 "Windows 는 OS 가 사용자 모드에 같은 수준의 정식 수단을 주지 않는다"고 적었다. **그 문장은 너무 넓었다.** Windows 에는 사용자 모드 VPN 플러그인 플랫폼(`Windows.Networking.Vpn`)이 있고, 거기에는 앱을 실행 파일 경로로 지목하는 `VpnTrafficFilter` 가 있다. 이 실기가 잰 것은 **WFP 연결 정책 하나**이지 "Windows 사용자 모드 전체"가 아니다. 그 수단이 실제로 라우팅을 바꾸는지는 아직 아무도 모른다 — §12 참조.

---

## 8. 이번 실기의 안전 (전부 실측)

| 확인 | 정방향 | 역방향 |
|---|---|---|
| `cleanupOutcome` | `PASS` | `PASS` |
| `beforeAfterFingerprint` | `MATCH` | `MATCH` |
| 소유 WFP 정책(끝난 뒤) | 0건 · 세 신호 `AGREE` | 0건 · `AGREE` |
| 제3자 제품 5종 | 무변화 | 무변화 |
| 터널 서비스 · 어댑터 · pktmon 거르개 | 0 · 0 · 없음 | 0 · 0 · 없음 |
| **인터넷 끊김** | **0** | **0** |
| 걸린 시간 | 3.0분 | 1.4분 |

---

## 9. 이 결과로 평가하면 안 되는 것

**결과 JSON 의 `verdict: FAIL` 을 "측정 실패"로 읽으면 안 된다.** FAIL 이 한 건이라도 있으면 전체가 FAIL 인 설계이고, 여기서 FAIL 은 **"정책 대상 앱이 기대한 인터페이스로 안 갔다는 사실을 측정했다"** 는 뜻이다. 그것이 이 실기가 알고자 한 것이고, 실제로 알아냈다.

못 잰 것들은 전부 근거와 함께 닫혔다 — UDP·QUIC·DNS 는 브라우저로 흐름을 만들 수단이 없고, IPv6 16건은 이 회선에 없고, 패키지 32건은 신원 증명 코드가 아직 없다(`R3-DEC-05` 미결).

---

## 10. 승인 기록 (GR-17)

`-LiveOwnerConfirmation 'APPLY LIVE WFP'` 를 **AI 가 명령줄에 입력했다.** 사용자가 2026-08-18 이 세션에서 명시 승인했다. 저장소 안 코드가 이 값을 채우는 일은 0건이다.

## 11. 이 문서가 안 하는 것

- 커널 driver **설계·구현** — 이 문서는 방향 결정까지다
- `R3-DEC-05`(패키지 신원) 결정 — 미결 유지
- 설정 파일 내용 기록 — 경로와 바꾼 항목 이름만 적었다

---

## 12. 재개 기록 — `R3-DEC-04` (2026-08-18)

**상태 변경**: 종결(CLOSED, "커널 드라이버로 간다") → **조건부 재개(REOPENED, 판별 시험 1회 한정)**
**변경자: 사용자 · 변경일: 2026-08-18**
**전문**: `docs/R3-DEC-04-uwp-vpn-plugin-branch-verdict-2026-08-18.md` (조사 6명 · 적대 반박 3명)

### 12-1. 재개 사유

이 실기가 잰 것은 **WFP 연결 정책**(`FwpmConnectionPolicyAdd0` / `FWPM_LAYER_OUTBOUND_NETWORK_CONNECTION_POLICY_V4`) 하나다. 그와 **무관한 별도 표면**이 확인됐다 — `Windows.Networking.Vpn` (UWP VPN 플러그인 플랫폼)의 `VpnChannel.StartWithTrafficFilter` + `VpnTrafficFilter`.

구조가 다르다. 흐름을 사후에 돌리는 것이 아니라, **채널을 여는 시점에 어떤 앱이 VPN L3 인터페이스에 붙는지를 선언**한다.

**재개는 "구현 재개"가 아니라 "판별 시험 1회 허가"다.**

### 12-2. 이 기계에서 실측한 것

| 확인 | 결과 |
|---|---|
| `windows` 크레이트 0.28 이 필요한 API 를 노출하는가 | **전부 있음** — `StartWithTrafficFilter` · `VpnTrafficFilter` · `VpnTrafficFilterAssignment` · `VpnAppId` · `VpnAppIdType` · `VpnRoutingPolicyType` |
| `VpnAppIdType::FilePath` | 있음 (값 `2`) |
| `VpnRoutingPolicyType` | `SplitRouting=0` · `ForceAllTrafficOverVpn=1` |
| 참조 구현(`luqmana/wireguard-uwp-rs`, 2021-12)이 Rust 1.97.1 로 빌드되는가 | **됨** — 릴리스 3분 22초 · exit 0 · 산출물 3개 |
| 앱별 거르개 패치가 빌드되는가 | **됨** — exit 0 · DLL 626,176 → 650,752 바이트 |
| 앱별 `TrafficFilter` 가 든 플러그인 VPN 프로필을 MDM 없이 만들 수 있는가 | **됨** — 관리자 권한만으로 생성·삭제 확인, 플랫폼이 `msedge.exe` 를 `Type=FilePath` 로 판정 |
| 사이드로드에서 제한 기능(`networkingVpnProvider`)이 부여되는가 | 문서가 명시 허용 · 반박 담당이 깨지 못함 |
| 이 기계의 준비물 | Rust · SDK 26100 · 개발자 모드 **전부 이미 있음**. WDK(`km` 헤더)는 **없음** |

### 12-3. 적대 반박 결과 — **3명 중 3명 REFUTED**

- **【치명】 "허용"과 "재지정"은 다르다.** 문서 언어가 전부 allow 계열이고 redirect 계열이 아니다. Windows 에 앱별 라우팅표가 없고 `VpnRouteAssignment` 에 AppId 칸이 없다. `ForceAllTrafficOverVpn` 이 "터널로 끌어온다"인지 "다른 인터페이스를 못 쓰게 막는다"인지가 결정적 미지수다.
- **【치명】 Microsoft 가 Win32 앱 ID 사용을 만류했다.** `MicrosoftDocs/winrt-api#1798` (2021-03-26 미해결 종료): *"we're able to reproduce a data corruption ... it seems safest to avoid using Win32 appids at all."* 이후 5년간 수정 발표 없음.
- **【치명】 데이터 경로 수명을 Windows 가 쥐고 있다.** `vpnClient` 백그라운드 작업이 2~5분 뒤 조용히 멈춘 보고가 미해결(MS Q&A 264773). Microsoft 자체 Azure VPN Client 도 Windows 11 에서 같은 증상.
- **【강함】 11년간 성공 사례 0건.** Microsoft 공식 UWP VPN 샘플조차 `RoutingPolicyType` 을 한 번도 설정하지 않는다(저장소 전체 0건, 저장소는 archived). GitHub 코드 검색 `VpnTrafficFilter`/`StartWithTrafficFilter` 저장소 0건. VMware Workspace ONE Tunnel 은 2020-01 에 UWP 를 버리고 Win32 로 갈아엎었다.
- **반박이 깨지 못한 것**: 사이드로드 rescap 부여 · 앱 컨테이너 UDP · 26200 배관 생존 · SKU/MDM 게이팅 없음. 전부 문제 없었다.

### 12-4. 재개 조건 (전부 지킨다)

1. 실작업 **4시간 · 달력 1일** 상한. 넘으면 자동 종결.
2. 사전 스냅숏과 검증된 비상 복구를 먼저 만든다.
3. DNS·백신·보안·VPN 제품을 끄는 절차 금지. `pktmon filter remove` 금지.
4. 순서 자물쇠: 끊기 → 프로필 0개 확인 → 패키지 제거 → 인터넷 확인.
5. WireGuard 설정과 개인 키는 **사람이 직접** 다룬다. AI 는 열지도 만들지도 않는다.
6. PFN 거르개와 FilePath 거르개를 한 `VpnTrafficFilterAssignment` 에 **섞지 않는다** (#1798 액세스 위반).
7. `AllowOutbound`/`AllowInbound` 를 **명시적으로 `true`** 로 둔다. 기본값이 문서에 없고, 기본이 `false` 면 조용한 블랙홀이 "거르개가 무시됨"과 똑같이 보인다.

### 12-5. 종료 조건 (셋 중 하나가 관측되면 즉시 판정)

| 관측 | 판정 |
|---|---|
| **③ 성공** — Edge 꾸러미가 터널 ifIndex 에만, Chrome 은 Wi-Fi 8 에 | `R3-DEC-04` 를 "UWP VPN 플러그인 갈래 채택(8시간 안정성 관문 조건부)"으로 개정 |
| **① 거르개 무시** — Edge 가 Wi-Fi 8 로 정상 통신 | 재종결. 사유: 사용자 모드 경로 2종 모두 앱별 재지정 불가로 관측됨 |
| **② 블랙홀** — Edge 가 어느 인터페이스에도 안 나타나고 통신 실패 | 재종결. 사유: 트래픽 거르개는 허용·차단 기계이며 재지정 수단이 아님이 실측됨 |

### 12-6. 재종결 시 기본 후속

커널 갈래로 복귀한다. 단 새로 확인된 **갈래 C — 기존 서명 드라이버 재사용**(WinpkFilter/ndisapi, WinDivert)을 드라이버 자체 작성 이전에 별도 검토한다. WireSock Secure Connect 가 우리 목표와 거의 같은 제품(WireGuard + AllowedApps/DisallowedApps)을 이 방식으로 이미 팔고 있다.

### 12-7. 이 재개로 무효화되지 **않는** 것

**"사용자 모드 WFP 연결 정책은 앱별 트래픽을 재지정하지 못한다"는 §2~§6 의 결론은 그대로 유효하다.** 가설 6개 제거 · 실기 2회 · 꾸러미 잡기 포함. 이번 재개는 그 결론을 뒤집는 것이 아니라 **다른 API 표면**을 보는 것이다.

---

## 13. 갈래 C 종결 — 남의 서명된 드라이버 재사용 (2026-08-18)

**전문**: `docs/R3-DEC-04-driver-reuse-branch-verdict-2026-08-18.md` (조사 렌즈 6 · 적대 반박 2, **2/2 REFUTED**)

### 13-1. 종결 사유 — 한 줄

**앱별 라우팅을 실제로 해내는 드라이버는 전부 소스만 공개되어 있어 우리가 직접 서명해야 하고, 바로 쓸 수 있게 서명된 드라이버는 전부 앱별 라우팅을 못 한다.** 그래서 "남이 서명해 둔 것을 재사용한다"는 전제 자체가 성립하지 않는다.

| 후보 | 라이선스 | 앱별 **라우팅**이 되나 | 판정 |
|---|---|---|---|
| WireSock (`ndiswgc.sys`) | 독점 EULA — 영리 배포 금지 | **됨** | 실격 (라이선스) |
| WinpkFilter (`ndisrd.sys`) | 독점 — 배포 $3,000 / 소스 $9,000 | **안 됨** (드라이버에 앱 개념 없음) | 실격 |
| WinDivert (`WinDivert64.sys`) | LGPLv3 또는 GPLv2 | **안 됨** — 문서 원문: *"For outbound injected packets, the `IfIdx` and `SubIfIdx` fields are currently ignored"* | 기능 미달 |
| Mullvad·Proton·Windscribe `.sys` | **서명된 바이너리 저장소에 LICENSE 파일이 아예 없음** (GitHub API `"license": null`) | 됨 | 실격 (권리 0) |

INF 의 `ManufacturerName` 등 남의 상표 문자열은 Microsoft 카탈로그가 해시한 대상이라 **고치는 순간 서명이 깨진다.**

### 13-2. 서명 관문 — 이건 개발 작업이 아니라 회사 설립 결정이다

Windows 10 1607 이후 Microsoft 가 서명하지 않은 새 커널 드라이버는 적재되지 않는다. 증명 서명(attestation)만으로 충분하지만, 그러려면 **① 검증된 법인 + Entra ID 테넌트 ② D-U-N-S 조회되는 회사 정보 ③ EV 코드 서명 인증서 ④ Partner Center 등록·서약**이 전부 필요하다. EV 인증서는 연 280~900달러이고 2026-02-23 부터 최대 유효기간이 459일로 줄어 **매년 갱신되는 고정비**이며 HSM 보관이 의무다.

**이 저장소는 이미 반대 결정을 기록해 두었다.** `docs/windows-release-hardening.md`: *"The owner chose unsigned distribution because a commercial code-signing certificate is not cost-effective for this release."* 일반 코드 서명 인증서조차 값어치가 없다고 판단한 프로젝트가 **범위 밖 기능** 하나를 위해 그보다 비싼 길을 갈 수는 없다.

### 13-3. 이 기계의 측정값 (재조사 금지)

| 항목 | 값 |
|---|---|
| OS | Windows 11 Pro **10.0.26200** x64 |
| Secure Boot | **꺼짐** |
| HVCI · 메모리 무결성 | **켜짐, 동작 중** (`SecurityServicesRunning=2`) |
| 취약 드라이버 차단 목록 | 켜짐 |
| Smart App Control | 꺼짐 |
| WDK 커널 헤더 | **없음** |
| 이미 적재된 남의 커널 네트워크 드라이버 | Realtek `nt_rtf64` · `wireguard.sys` |

> **경고**: Secure Boot 가 꺼져 있어 이 개발 PC 는 **실제 사용자 PC 보다 관대하다.** 여기서 드라이버가 올라갔다는 사실은 배포 근거가 되지 못한다.

### 13-4. 공짜로 얻은 설계 자산 (이 조사의 진짜 산출물)

나중에 앱별 라우팅을 실제로 만들 때의 출발점이다.

- **올바른 구조**: 사용자 모드에서 `FWPM_CONDITION_ALE_APP_ID` 조건 필터를 심고 provider context 로 IP 를 넘긴 뒤, 커널 callout 이 `ALE_BIND_REDIRECT_V4/V6` · `ALE_CONNECT_REDIRECT_V4/V6` 에서 `localAddressAndPort` 를 **재작성**한다. Windscribe `callout_filter.cpp` · Proton `Callout.cpp` 가 완전한 참고 구현이다.
- **포함 모드는 실제로 있다**: `if (calloutData->isExclude) redirect(localIp) else redirect(vpnIp)`. 방향은 걸림돌이 아니다.
- **막다른 길로 확정된 것** — 터널 인터페이스에서 WFP 로 차단하면 물리 랜카드로 되돌아갈 것이라는 발상은 **틀렸다.** Windows 는 ALE 인가보다 **먼저** 경로 조회로 출구 인터페이스를 정한다. 차단은 폐기일 뿐 재라우팅이 아니다. **이로써 §7 의 "커널로 간다" 결론이 독립적으로 재확인된다.**
- **라우팅 컴파트먼트**(`SetJobCompartmentId`)는 API 가 실재하나 **인터페이스를 다른 컴파트먼트로 옮기는 사용자 모드 API 가 없어** 막힌다.
- **앱별 프록시 실행 인자**(`--proxy-server`)는 가장 싸지만 **UDP·QUIC 이 죽는다.** 하필 YouTube·Netflix 가 이 제품의 대표 규칙이다.
- **드라이버 없이 가능한 유일한 갈래**: Wintun 전체 캡처 + `GetExtendedTcpTable`/`GetExtendedUdpTable` 로 소유 프로세스 판정 + `IP_UNICAST_IF` 로 물리 랜카드 재발신. mihomo·sing-box 가 이 방식이다. **2~4개월 전면 재작성**이고, "나머지 인터넷은 평소 네트워크에 그대로 둔다"는 이 제품의 안전 약속이 성격상 뒤집힌다.

### 13-5. 재개 조건

앱별 라우팅이 정식으로 범위에 들어오면, **첫걸음은 코드가 아니라 서류 결정**이다 — *"이 프로젝트가 법인을 만들고 EV 인증서를 상시 유지할 것인가?"* 아니오면 사용자 모드 TUN 갈래만 남고, 그마저도 **Wintun 0.14.1 이 HVCI 켜진 26200 에서 아직 적재되는지** 2시간 선행 시험을 통과해야 한다.

### 13-6. 명시적으로 하지 않을 것

- EV 코드 서명 인증서 구매 · Partner Center 하드웨어 개발자 등록
- 어떤 `.sys` 파일도 저장소나 릴리스 자산에 넣기 — 특히 `mullvad-split-tunnel.sys` · `ProtonVPN.CalloutDriver.sys` · `windscribesplittunnel.sys` (**라이선스가 아예 없다**)
- WireSock · WinpkFilter 번들 또는 설치 중 내려받기
- 사용자에게 test signing · 메모리 무결성 끄기 · 차단 목록 끄기를 요구하는 모든 방안 (README 의 자체 헌장 위반)
- 네 번째 앱별 라우팅 조사
